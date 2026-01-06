package main

import (
	"context"
	"encoding/json"
	"flag"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"syscall"
	"time"

	"go_server/internal/api"
	"go_server/internal/auth"
	"go_server/internal/config"
	"go_server/internal/database"
	"go_server/internal/grpc"
	"go_server/internal/logging"
	"go_server/internal/preprocessor"
	"go_server/internal/renderer"
	"go_server/internal/response"
	"go_server/internal/websocket"
)

func main() {
	// Parse command line flags
	configPath := flag.String("config", "../config.json", "Path to configuration file")
	flag.Parse()
	
	// Load configuration
	cfg, err := config.LoadConfig(*configPath)
	if err != nil {
		panic("Failed to load configuration: " + err.Error())
	}
	
	// Initialize logger
	logDir := cfg.Logging.Directory
	if logDir != "" && !filepath.IsAbs(logDir) {
		logDir = filepath.Join("..", logDir)
	}
	logger := logging.NewLogger(cfg.Logging.Level, cfg.Logging.Format, logDir)
	logger.Info("Starting Go server")
	
	// Initialize Database [NEW]
	dbPath := cfg.Database.Path
	db, err := database.NewDatabase(dbPath)
	if err != nil {
		logger.WithField("error", err).Fatal("Failed to connect to database")
	}
	defer db.Close()
	

	// Initialize API Handlers
	authHandler := auth.NewHandler(db, cfg.Auth.SecretKey, logger)
	categoryHandler := api.NewCategoryHandler(db, logger, cfg.Auth.SecretKey)
	productHandler := api.NewProductHandler(db, logger, cfg.Auth.SecretKey)
	transactionHandler := api.NewTransactionHandler(db, logger)

	// Initialize Remote Log Handler for mobile app logs
	remoteLogHandler := api.NewRemoteLogHandler(logDir)
	defer remoteLogHandler.Close()


	// Initialize gRPC client pool with retry logic
	// Using pool for multi-user concurrent support (10 users)
	grpcAddr := cfg.GRPC.Host + ":" + cfg.GRPC.Port
	const grpcPoolSize = 3 // 3 connections for load balancing with 10 users
	logger.WithFields(map[string]interface{}{
		"grpc_address": grpcAddr,
		"pool_size":    grpcPoolSize,
	}).Info("Creating gRPC client pool for multi-user support")
	
	var grpcPool *grpc.ClientPool
	
	// Try to connect to the gRPC server with a timeout
	connectCtx, cancel := context.WithTimeout(context.Background(), 60*time.Second)
	defer cancel()
	
	// Channel to signal successful connection
	connected := make(chan bool, 1)
	
	// Try to connect in a goroutine
	go func() {
		var err error
		grpcPool, err = grpc.NewClientPool(grpcAddr, grpcPoolSize, logger)
		if err != nil {
			logger.WithField("error", err).Error("Failed to create gRPC client pool")
			connected <- false
			return
		}
		connected <- true
	}()
	
	// Wait for connection or timeout
	select {
	case success := <-connected:
		if !success {
			logger.Fatal("Failed to connect to gRPC server pool")
		}
	case <-connectCtx.Done():
		logger.Error("Timeout while connecting to gRPC server")
		// Don't exit immediately, try to continue without gRPC pool
		grpcPool = nil
	}
	
	// Defer closing the gRPC pool if it was created
	if grpcPool != nil {
		defer grpcPool.Close()
		logger.WithField("pool_size", grpcPool.Size()).Info("gRPC client pool connected successfully")
	} else {
		logger.Warn("Continuing without gRPC client pool - some functionality may be limited")
	}
	
	// Initialize frame preprocessor
	_ = preprocessor.NewFramePreprocessor(logger)
	

	
	// Initialize WebSocket server with renderer config
	var compressionType renderer.CompressionType
	switch cfg.Renderer.CompressionType {
	case "gzip":
		compressionType = renderer.CompressionGZIP
	case "lz4":
		compressionType = renderer.CompressionLZ4
	default:
		compressionType = renderer.CompressionNone
	}
	
	rendererConfig := &renderer.RendererConfig{
		CompressionType:   compressionType,
		CompressionLevel:  cfg.Renderer.CompressionLevel,
		EnableProgressive: cfg.Renderer.EnableProgressive,
		ProgressiveLevels: cfg.Renderer.ProgressiveLevels,
		ProgressiveDelay:  cfg.Renderer.ProgressiveDelay,
		DefaultQuality:    cfg.Renderer.DefaultQuality,
		MinQuality:        cfg.Renderer.MinQuality,
		MaxQuality:        cfg.Renderer.MaxQuality,
		QualityAdjustment: cfg.Renderer.QualityAdjustment,
		MaxBufferSize:     cfg.Renderer.MaxBufferSize,
		FlushInterval:     cfg.Renderer.FlushInterval,
	}
	
	// Create WebSocket server with gRPC pool for multi-user performance
	wsServer := websocket.NewWebSocketServerWithGRPCPool(logger, rendererConfig, grpcPool, db, cfg.Auth.SecretKey, cfg.Connection.TimeoutUserOnline)
	
	// Initialize response handler
	_ = response.NewResponseHandler(logger, wsServer)
	
	// Start WebSocket server in a goroutine
	go wsServer.Run()

	// Start UDP Server
	go wsServer.StartUDP(cfg.Server.Port)
	
	// Set up HTTP server
	mux := http.NewServeMux()
	mux.HandleFunc(cfg.WebSocket.Path, wsServer.HandleWebSocket)
	
	// Register Login Handler [NEW]
	mux.HandleFunc("/login", authHandler.Login)
	
	// Register API Routes
	// Categories
	mux.Handle("/categories", categoryHandler)
	mux.Handle("/categories/", categoryHandler)
	
	// Products
	mux.Handle("/products", productHandler)
	mux.Handle("/products/", productHandler)
	
	// Transactions
	mux.Handle("/transactions", transactionHandler)
	mux.Handle("/transactions/", transactionHandler)

	// Add health check endpoint
	mux.HandleFunc("/health", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte("OK"))
	})
	
	// Add metrics endpoint
	mux.HandleFunc("/metrics", func(w http.ResponseWriter, r *http.Request) {
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status": "running"}`))
	})

	// Add remote log endpoint for mobile apps (ScanAI & PosAI)
	mux.HandleFunc("/remote-log", remoteLogHandler.HandleLog)

	
	// Add renderer stats endpoint
	mux.HandleFunc("/renderer-stats", func(w http.ResponseWriter, r *http.Request) {
		renderer := wsServer.GetRenderer()
		stats := renderer.GetStats()
		
		w.Header().Set("Content-Type", "application/json")
		json.NewEncoder(w).Encode(stats)
	})
	
	serverAddr := cfg.Server.Host + ":" + cfg.Server.Port
	server := &http.Server{
		Addr:    serverAddr,
		Handler: mux,
	}
	
	// Start HTTP server in a goroutine
	go func() {
		logger.WithField("address", serverAddr).Info("Starting HTTP server")
		if err := server.ListenAndServe(); err != nil && err != http.ErrServerClosed {
			logger.WithField("error", err).Fatal("Failed to start HTTP server")
		}
	}()
	
	// Set up graceful shutdown
	quit := make(chan os.Signal, 1)
	signal.Notify(quit, syscall.SIGINT, syscall.SIGTERM)
	<-quit
	
	logger.Info("Shutting down server...")
	
	// Create a deadline for shutdown
	ctx, cancel := context.WithTimeout(context.Background(), 30*time.Second)
	defer cancel()
	
	// Shutdown HTTP server
	if err := server.Shutdown(ctx); err != nil {
		logger.WithField("error", err).Error("Failed to shutdown HTTP server gracefully")
	}
	
	logger.Info("Server stopped")
}