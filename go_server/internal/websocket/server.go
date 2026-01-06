package websocket

import (
	"context"
	"encoding/base64"
	"encoding/json"
	"fmt"
	"net/http"
	"strconv"
	"time"

	// "strings" // Unused

	"github.com/gorilla/websocket"
	"github.com/sirupsen/logrus"
	"github.com/golang-jwt/jwt/v5"
	"go_server/internal/logging"
	"go_server/internal/renderer"
	"go_server/internal/grpc"
	"go_server/internal/database"
	"go_server/proto"
	"net"
	"sync"
	"encoding/binary"
)

const (
	UDPHeaderSize = 12
	MaxUDPBuffer  = 65535
)

type UDPPartialMessage struct {
	Chunks      map[uint16][]byte
	TotalChunks uint16
	LastUpdate  time.Time
}

var upgrader = websocket.Upgrader{
	ReadBufferSize:  1024,
	WriteBufferSize: 1024,
	CheckOrigin: func(r *http.Request) bool {
		return true // Allow all origins for now
	},
	EnableCompression: true,
}

type Frame struct {
	ID      string `json:"id"`
	Token   string `json:"token"` // [NEW] Token field
	Data    []byte `json:"-"` // Will be populated by UnmarshalJSON
	Width   int    `json:"width"`
	Height  int    `json:"height"`
	Format  string `json:"format"`
}

// frameJSON is a helper struct for unmarshaling
type frameJSON struct {
	ID      string `json:"id"`
	Token   string `json:"token"`
	Data    string `json:"data"` // Base64 string from client
	Width   int    `json:"width"`
	Height  int    `json:"height"`
	Format  string `json:"format"`
}

// UnmarshalJSON implements custom JSON unmarshaling to decode base64 data
func (f *Frame) UnmarshalJSON(data []byte) error {
	var fj frameJSON
	if err := json.Unmarshal(data, &fj); err != nil {
		return err
	}
	
	// Decode base64 string to bytes
	decoded, err := base64.StdEncoding.DecodeString(fj.Data)
	if err != nil {
		return fmt.Errorf("failed to decode base64 data: %w", err)
	}
	
	f.ID = fj.ID
	f.Token = fj.Token
	f.Data = decoded
	f.Width = fj.Width
	f.Height = fj.Height
	f.Format = fj.Format
	
	return nil
}

type Server struct {
	logger      *logging.Logger
	connections map[*websocket.Conn]bool
	register    chan *websocket.Conn
	unregister  chan *websocket.Conn
	broadcast   chan []byte

	grpcClient  *grpc.Client     // Single gRPC client (legacy)
	grpcPool    *grpc.ClientPool // gRPC client pool for multi-user (preferred)
	renderer    *renderer.Renderer
	db          *database.DB // Database connection
	secretKey   []byte       // Secret key for JWT
	
	// UDP Reassembly
	udpMutex     sync.Mutex
	udpAssembly  map[uint64]*UDPPartialMessage
	
	// Connection config
	timeoutUserOnline int // Timeout dalam detik untuk menunggu user
	
	// Session Resume: Map SessionID -> Alamat UDP terakhir
	userSessionsMutex sync.RWMutex
	userSessions      map[string]*net.UDPAddr
	writeMutex        sync.Mutex // [NEW] For thread-safe WebSocket writing
}

func NewWebSocketServer(logger *logging.Logger, db *database.DB) *Server {
	return NewWebSocketServerWithGRPCClient(logger, nil, db)
}

// NewWebSocketServerWithGRPCClient creates a new WebSocket server with an optional gRPC client
func NewWebSocketServerWithGRPCClient(logger *logging.Logger, grpcClient *grpc.Client, db *database.DB) *Server {
	// Initialize renderer with config from config file
	// For now, we'll use default values, but in a real implementation,
	// these would come from the config file
	rendererConfig := &renderer.RendererConfig{
		CompressionType:   renderer.CompressionGZIP,
		CompressionLevel:  6,
		EnableProgressive: true,
		ProgressiveLevels: 3,
		ProgressiveDelay:  100,
		DefaultQuality:    80,
		MinQuality:        30,
		MaxQuality:        100,
		QualityAdjustment: true,
		MaxBufferSize:     10 * 1024 * 1024, // 10MB
		FlushInterval:     1000,            // 1 second
	}
	
	return &Server{
		logger:      logger,
		connections: make(map[*websocket.Conn]bool),
		register:    make(chan *websocket.Conn),
		unregister:  make(chan *websocket.Conn),
		broadcast:   make(chan []byte),

		grpcClient:  grpcClient,
		renderer:    renderer.NewRenderer(rendererConfig, logger),
		udpAssembly: make(map[uint64]*UDPPartialMessage),
		db:          db,
	}
}

// NewWebSocketServerWithConfig creates a new WebSocket server with the provided renderer config
func NewWebSocketServerWithConfig(logger *logging.Logger, rendererConfig *renderer.RendererConfig, db *database.DB) *Server {
	return NewWebSocketServerWithConfigAndGRPCClient(logger, rendererConfig, nil, db)
}

// NewWebSocketServerWithConfigAndGRPCClient creates a new WebSocket server with the provided renderer config and gRPC client
func NewWebSocketServerWithConfigAndGRPCClient(logger *logging.Logger, rendererConfig *renderer.RendererConfig, grpcClient *grpc.Client, db *database.DB) *Server {
	return &Server{
		logger:      logger,
		connections: make(map[*websocket.Conn]bool),
		register:    make(chan *websocket.Conn),
		unregister:  make(chan *websocket.Conn),
		broadcast:   make(chan []byte),

		grpcClient:  grpcClient,
		renderer:    renderer.NewRenderer(rendererConfig, logger),
		udpAssembly: make(map[uint64]*UDPPartialMessage),
		db:          db,
	}
}

// NewWebSocketServerWithGRPCPool creates a new WebSocket server with a gRPC client pool for multi-user support
func NewWebSocketServerWithGRPCPool(logger *logging.Logger, rendererConfig *renderer.RendererConfig, grpcPool *grpc.ClientPool, db *database.DB, secretKey string, timeoutUserOnline int) *Server {
	logger.Info("Creating WebSocket server with gRPC client pool for multi-user support")
	
	// Default 30 detik jika tidak diset
	if timeoutUserOnline <= 0 {
		timeoutUserOnline = 30
	}
	
	return &Server{
		logger:            logger,
		connections:       make(map[*websocket.Conn]bool),
		register:          make(chan *websocket.Conn),
		unregister:        make(chan *websocket.Conn),
		broadcast:         make(chan []byte),
		grpcPool:          grpcPool,
		renderer:          renderer.NewRenderer(rendererConfig, logger),
		udpAssembly:       make(map[uint64]*UDPPartialMessage),
		db:                db,
		secretKey:         []byte(secretKey),
		timeoutUserOnline: timeoutUserOnline,
		userSessions:      make(map[string]*net.UDPAddr),
	}
}

func (s *Server) Run() {
	for {
		select {
		case conn := <-s.register:
			s.connections[conn] = true
			s.logger.Info("New WebSocket connection registered")
			
		case conn := <-s.unregister:
			if _, ok := s.connections[conn]; ok {
				delete(s.connections, conn)
				s.logger.Info("WebSocket connection unregistered")
			}
			
		case message := <-s.broadcast:
			for conn := range s.connections {
				s.writeMutex.Lock()
				conn.SetWriteDeadline(time.Now().Add(5 * time.Second))
				err := conn.WriteMessage(websocket.TextMessage, message)
				s.writeMutex.Unlock()
				
				if err != nil {
					s.logger.WithField("error", err).Error("Error broadcasting message")
					conn.Close()
					delete(s.connections, conn)
				}
			}
		}
	}
}

func (s *Server) HandleWebSocket(w http.ResponseWriter, r *http.Request) {
	conn, err := upgrader.Upgrade(w, r, nil)
	if err != nil {
		s.logger.WithField("error", err).Error("Error upgrading connection")
		return
	}
	defer conn.Close()
	
	s.register <- conn
	
	// Set read deadline
	conn.SetReadDeadline(time.Now().Add(time.Duration(s.timeoutUserOnline) * time.Second))
	conn.SetReadLimit(512 * 1024 * 1024) // 512MB
	
	// Set up ping/pong handler
	conn.SetPingHandler(func(appData string) error {
		s.logger.Debug("Received ping from client")
		conn.SetReadDeadline(time.Now().Add(60 * time.Second))
		return nil
	})
	
	// Handle incoming messages
	for {
		messageType, message, err := conn.ReadMessage()
		if err != nil {
			if websocket.IsUnexpectedCloseError(err, websocket.CloseGoingAway, websocket.CloseAbnormalClosure) {
				s.logger.WithField("error", err).Error("Error reading message")
			}
			break
		}

		conn.SetReadDeadline(time.Now().Add(time.Duration(s.timeoutUserOnline) * time.Second))
		
		if messageType == websocket.BinaryMessage {
			// [NEW] Handle Binary messages (Optimized for Online/Ngrok)
			s.logger.Debug("Received binary message over WebSocket")
			s.processBinaryFrame(message, func(resp map[string]interface{}) {
				responseData, _ := json.Marshal(resp)
				
				s.writeMutex.Lock()
				defer s.writeMutex.Unlock()
				
				conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
				err := conn.WriteMessage(websocket.TextMessage, responseData)
				if err != nil {
					s.logger.WithField("error", err).Debug("Failed to send binary response (client likely disconnected)")
				}
			})
			continue
		}

		// Parse frame (JSON format)
		var frame Frame
		err = json.Unmarshal(message, &frame)
		if err != nil {
			s.logger.WithField("error", err).Error("Error parsing frame")
			continue
		}

		// Validate Token
		claims, err := s.validateToken(frame.Token)
		if err != nil {
			s.logger.WithFields(logrus.Fields{
				"frame_id": frame.ID, 
				"error": err.Error(),
			}).Warn("Invalid token in frame")
			
			// Send Unauthorized response
			s.sendErrorResponse(conn, frame.ID, "Unauthorized: " + err.Error())
			continue
		}

		// Validate frame
		if frame.Width <= 0 || frame.Height <= 0 || len(frame.Data) == 0 {
			s.logger.WithFields(logrus.Fields{
				"frame_id": frame.ID, 
				"data_len": len(frame.Data),
			}).Warn("Ignored invalid/empty frame from client")
			continue
		}
		
		s.logger.InfoThrottled("ws_frame_parse", 10*time.Second, "Frame parsed successfully with valid token", logrus.Fields{
			"frame_id":  frame.ID,
			"width":     frame.Width,
			"height":    frame.Height,
			"format":    frame.Format,
			"user_id":   claims["user_id"],
			"username":  claims["username"],
			"device_id": claims["device_id"],
		})
		
		// [NEW] Add import for strconv if not present
		// Check if we have gRPC client or pool
		if s.grpcPool == nil && s.grpcClient == nil {
			s.logger.Warn("No gRPC client/pool available - AI processing will be skipped")
			s.sendErrorResponse(conn, frame.ID, "No gRPC client available")
			continue
		}
		
		// Process frame with gRPC client
		startTime := time.Now()
		
		// Determine number of channels (default to 3 for RGB)
		channels := int32(3)
		if frame.Format == "rgba" {
			channels = 4
		} else if frame.Format == "grayscale" {
			channels = 1
		}
		
		// Call gRPC (prefer pool over single client for multi-user performance)
		var grpcResponse *proto.FrameResponse
		var grpcErr error
		if s.grpcPool != nil {
			grpcResponse, grpcErr = s.grpcPool.ProcessFrame(
				context.Background(),
				frame.Data,
				int32(frame.Width),
				int32(frame.Height),
				channels,
				frame.Format,
			)
		} else {
			grpcResponse, grpcErr = s.grpcClient.ProcessFrame(
				context.Background(),
				frame.Data,
				int32(frame.Width),
				int32(frame.Height),
				channels,
				frame.Format,
			)
		}
		
		if grpcErr != nil {
			s.logger.WithFields(logrus.Fields{
				"frame_id": frame.ID,
				"error": grpcErr.Error(),
			}).Error("Failed to process frame with gRPC client")
			s.sendErrorResponse(conn, frame.ID, "Failed to process frame with AI: " + grpcErr.Error())
			continue
		}
		
		// Log to Database (POS table)
		// Extract numeric user_id
		userIDFloat, ok := claims["user_id"].(float64)
		var userID int64
		if ok {
			userID = int64(userIDFloat)
		} else {
			userID = 0 // Or handle error
		}
		
		// Log scan async
		go func() {
			deviceID, _ := claims["device_id"].(string)
			// For WebSocket, we don't have frameSeq easily, use 0 or parse from ID if possible
			frameSeq := 0
			// Parse frame ID if it's numeric
			if seq, err := strconv.Atoi(frame.ID); err == nil {
				frameSeq = seq
			}
			
			detectionCount := 0
			if grpcResponse.AiResults != nil {
				detectionCount = len(grpcResponse.AiResults.Detections)
			}

			err := s.db.LogScan(userID, deviceID, "", frameSeq, detectionCount, "success")
			if err != nil {
				s.logger.WithField("error", err).Error("Failed to log scan to DB")
			}
		}()
		
		processingTimeMs := time.Since(startTime).Milliseconds()
		
		s.logger.InfoThrottled("ws_frame_grpc", 10*time.Second, "Frame processed with gRPC client", logrus.Fields{
			"frame_id":           frame.ID,
			"grpc_success":       grpcResponse.Success,
			"grpc_message":       grpcResponse.Message,
			"processing_time_ms": processingTimeMs,
		})
		
		// Create response with AI results
		// Prepare AI results manually to avoid omitempty omitting 0.0 values
		var detections []map[string]interface{}
		if grpcResponse.AiResults != nil {
			for _, d := range grpcResponse.AiResults.Detections {
				bboxMap := map[string]interface{}{
					"x_min": d.Bbox.XMin,
					"y_min": d.Bbox.YMin,
					"x_max": d.Bbox.XMax,
					"y_max": d.Bbox.YMax,
				}
				detections = append(detections, map[string]interface{}{
					"class_name": d.ClassName,
					"confidence": d.Confidence,
					"bbox":       bboxMap,
				})
			}
		}

		// Create response with AI results
		response := map[string]interface{}{
			"success":            grpcResponse.Success,
			"message":            grpcResponse.Message,
			"frame_id":           frame.ID,
			"timestamp":          time.Now().Format(time.RFC3339),
			"processing_time_ms": processingTimeMs,
			"ai_results": map[string]interface{}{
				"detections": detections,
			},
			"original_width":  frame.Width,
			"original_height": frame.Height,
		}
		
		responseData, _ := json.Marshal(response)
		
		s.writeMutex.Lock()
		conn.SetWriteDeadline(time.Now().Add(10 * time.Second))
		err = conn.WriteMessage(websocket.TextMessage, responseData)
		s.writeMutex.Unlock()
		
		if err != nil {
			s.logger.WithField("error", err).Debug("Failed to send response over WebSocket")
			break 
		}
	}
	
	s.unregister <- conn
}

func (s *Server) sendErrorResponse(conn *websocket.Conn, frameID string, message string) {
	response := map[string]interface{}{
		"success": false,
		"message": message,
		"frame_id": frameID,
		"timestamp": time.Now().Format(time.RFC3339),
	}
	responseData, _ := json.Marshal(response)
	conn.WriteMessage(websocket.TextMessage, responseData)
}

// validateToken verifies the JWT token
func (s *Server) validateToken(tokenString string) (jwt.MapClaims, error) {
	if tokenString == "" {
		return nil, fmt.Errorf("missing token")
	}
	
	// Parse token
	token, err := jwt.Parse(tokenString, func(token *jwt.Token) (interface{}, error) {
		if _, ok := token.Method.(*jwt.SigningMethodHMAC); !ok {
			return nil, fmt.Errorf("unexpected signing method: %v", token.Header["alg"])
		}
		return s.secretKey, nil
	})

	if err != nil {
		return nil, err
	}

	if claims, ok := token.Claims.(jwt.MapClaims); ok && token.Valid {
		return claims, nil
	}

	return nil, fmt.Errorf("invalid token")
}

func (s *Server) BroadcastResponse(response []byte) {
	s.broadcast <- response
}

// GetRenderer returns the renderer instance
func (s *Server) GetRenderer() *renderer.Renderer {
	return s.renderer
}

// StartUDP starts the UDP server
func (s *Server) StartUDP(port string) {
	addr, err := net.ResolveUDPAddr("udp", ":"+port)
	if err != nil {
		s.logger.WithField("error", err).Fatal("Failed to resolve UDP address")
	}

	conn, err := net.ListenUDP("udp", addr)
	if err != nil {
		s.logger.WithField("error", err).Fatal("Failed to listen on UDP")
	}
	defer conn.Close()

	s.logger.Info("UDP Server listening on " + port)

	buffer := make([]byte, MaxUDPBuffer)
	
	// Cleanup routine for incomplete messages (optimized for 10 concurrent users)
	go func() {
		for {
			time.Sleep(2 * time.Second) // Faster cleanup for multi-user (was 5s)
			s.udpMutex.Lock()
			now := time.Now()
			cleanedCount := 0
			for id, msg := range s.udpAssembly {
				if now.Sub(msg.LastUpdate) > 3*time.Second { // Faster timeout (was 5s)
					delete(s.udpAssembly, id)
					cleanedCount++
				}
			}
			if cleanedCount > 0 {
				s.logger.WithField("cleaned", cleanedCount).Debug("Cleaned stale UDP assemblies")
			}
			s.udpMutex.Unlock()
		}
	}()

	for {
		n, remoteAddr, err := conn.ReadFromUDP(buffer)
		if err != nil {
			s.logger.WithField("error", err).Error("Error reading from UDP")
			continue
		}

		if n < UDPHeaderSize {
			continue
		}

		data := make([]byte, n)
		copy(data, buffer[:n])
		
		msgID := binary.BigEndian.Uint64(data[0:8])
		chunkIdx := binary.BigEndian.Uint16(data[8:10])
		totalChunks := binary.BigEndian.Uint16(data[10:12])
		payload := data[UDPHeaderSize:]

		s.udpMutex.Lock()
		if _, exists := s.udpAssembly[msgID]; !exists {
			s.udpAssembly[msgID] = &UDPPartialMessage{
				Chunks:      make(map[uint16][]byte),
				TotalChunks: totalChunks,
				LastUpdate:  time.Now(),
			}
		}
		
		msg := s.udpAssembly[msgID]
		msg.Chunks[chunkIdx] = payload
		msg.LastUpdate = time.Now()
		
		ready := len(msg.Chunks) == int(msg.TotalChunks)
		var fullData []byte
		
		if ready {
			// Reassemble
			// Calculate size
			size := 0
			for i := uint16(0); i < msg.TotalChunks; i++ {
				if chunk, ok := msg.Chunks[i]; ok {
					size += len(chunk)
				}
			}
			fullData = make([]byte, size)
			offset := 0
			for i := uint16(0); i < msg.TotalChunks; i++ {
				chunk := msg.Chunks[i]
				copy(fullData[offset:], chunk)
				offset += len(chunk)
			}
			delete(s.udpAssembly, msgID)
		}
		s.udpMutex.Unlock()

		if ready {
			go s.processReassembledMessage(fullData, remoteAddr, conn)
		}
	}
}

func (s *Server) processReassembledMessage(message []byte, remoteAddr *net.UDPAddr, conn *net.UDPConn) {
	if len(message) == 0 {
		return
	}

	// Detect format: JSON starts with '{' (byte 123)
	if message[0] == 123 {
		var frame Frame
		err := json.Unmarshal(message, &frame)
		if err != nil {
			s.logger.WithField("error", err).Error("Error parsing UDP frame (JSON)")
			return
		}
		// Treat as a frame and process but we need to send response back
		// Note: This logic is a bit different for JSON over UDP
		// For brevity and logic consistency, we'll use the same processBinaryFrame if it was binary
		// but since it's JSON, we handle it here for now as it was.
		
		// [Existing JSON over UDP logic ...]
		s.logger.Warn("JSON over UDP is deprecated, please use Binary format")
		// (Proceeding with existing logic below)
	}

	// Route to shared processing logic
	s.processBinaryFrame(message, func(resp map[string]interface{}) {
		s.sendUDPResponse(conn, remoteAddr, resp)
	})
}

// processBinaryFrame is the shared core logic for both UDP and WebSocket binary frames
func (s *Server) processBinaryFrame(message []byte, responder func(map[string]interface{})) {
	if len(message) == 0 {
		return
	}

	var frame Frame
	var frameSeq uint64

	// Detect format: JSON starts with '{' (byte 123)
	if message[0] == 123 {
		err := json.Unmarshal(message, &frame)
		if err != nil {
			s.logger.WithField("error", err).Error("Error parsing frame (JSON)")
			return
		}
		// Try to parse frameSeq from frame.ID if JSON
		if seq, err := strconv.ParseUint(frame.ID, 10, 64); err == nil {
			frameSeq = seq
		}
	} else {
		// Binary Format (Updated to match Flutter client protocol):
		// [TokenLen(1)] + [Token] + [SessionIdLen(1)] + [SessionId] + [FrameSeq(8)] + [Width(4)] + [Height(4)] + [FormatLen(1)] + [Format] + [ImageBytes]
		if len(message) < 2 {
			return 
		}

		offset := 0
		
		// Read Token
		tokenLen := int(message[offset])
		offset++
		if len(message) < offset + tokenLen {
			s.logger.Warn("Malformed binary packet: too short for token")
			return
		}
		frame.Token = string(message[offset : offset+tokenLen])
		offset += tokenLen
		
		// Read SessionId length
		if len(message) < offset + 1 {
			return
		}
		sessionIdLen := int(message[offset])
		offset++
		if len(message) < offset + sessionIdLen {
			return
		}
		// Skip sessionId as we use the responder callback for routing
		offset += sessionIdLen
		
		// Read FrameSeq (8 bytes, big-endian)
		if len(message) < offset + 8 {
			return
		}
		frameSeq = uint64(message[offset])<<56 | uint64(message[offset+1])<<48 | 
			uint64(message[offset+2])<<40 | uint64(message[offset+3])<<32 |
			uint64(message[offset+4])<<24 | uint64(message[offset+5])<<16 | 
			uint64(message[offset+6])<<8 | uint64(message[offset+7])
		offset += 8
		
		// Read Width (4 bytes, big-endian)
		if len(message) < offset + 4 {
			return
		}
		width := int32(message[offset])<<24 | int32(message[offset+1])<<16 | int32(message[offset+2])<<8 | int32(message[offset+3])
		offset += 4
		
		// Read Height (4 bytes, big-endian)
		if len(message) < offset + 4 {
			return
		}
		height := int32(message[offset])<<24 | int32(message[offset+1])<<16 | int32(message[offset+2])<<8 | int32(message[offset+3])
		offset += 4
		
		// Read Format
		if len(message) < offset + 1 {
			return
		}
		formatLen := int(message[offset])
		offset++
		if len(message) < offset + formatLen {
			return
		}
		format := string(message[offset : offset+formatLen])
		offset += formatLen
		
		// Image data
		frame.Data = message[offset:]
		frame.ID = fmt.Sprintf("%d", frameSeq)
		frame.Format = format
		frame.Width = int(width)
		frame.Height = int(height)
	}

	// Validate Token
	claims, err := s.validateToken(frame.Token)
	if err != nil {
		s.logger.WithFields(logrus.Fields{
			"frame_id": frame.ID, 
			"error": err.Error(),
		}).Warn("Invalid token in binary frame")
		
		responder(map[string]interface{}{
			"success": false,
			"message": "Unauthorized: " + err.Error(),
			"frame_id": frame.ID,
		})
		return
	}

	// Validate frame data
	if len(frame.Data) == 0 {
		return
	}
	
	s.logger.InfoThrottled("core_frame_process", 10*time.Second, "Processing Binary Frame Core", logrus.Fields{
		"frame_id": frame.ID,
		"user_id":  claims["user_id"],
		"format":   frame.Format,
		"size":     len(frame.Data),
	})

	// Check if we have gRPC client or pool
	if s.grpcPool == nil && s.grpcClient == nil {
		responder(map[string]interface{}{
			"success": false,
			"message": "No gRPC client available",
			"frame_id": frame.ID,
		})
		return
	}
	
	// Call gRPC
	channels := int32(3)
	if frame.Format == "rgba" {
		channels = 4
	}
	
	var grpcResponse *proto.FrameResponse
	var grpcErr error
	if s.grpcPool != nil {
		grpcResponse, grpcErr = s.grpcPool.ProcessFrame(
			context.Background(),
			frame.Data,
			int32(frame.Width),
			int32(frame.Height),
			channels,
			frame.Format,
		)
	} else {
		grpcResponse, grpcErr = s.grpcClient.ProcessFrame(
			context.Background(),
			frame.Data,
			int32(frame.Width),
			int32(frame.Height),
			channels,
			frame.Format,
		)
	}
	
	if grpcErr != nil {
		responder(map[string]interface{}{
			"success": false,
			"message": "AI Error: " + grpcErr.Error(),
			"frame_id": frame.ID,
		})
		return
	}

	// Log to Database (POS table)
	userIDFloat, ok := claims["user_id"].(float64)
	var userID int64
	if ok {
		userID = int64(userIDFloat)
	}
	
	// Log scan asynchronously
	go func() {
		deviceID, _ := claims["device_id"].(string)
		
		detectionCount := 0
		if grpcResponse.AiResults != nil {
			detectionCount = len(grpcResponse.AiResults.Detections)
		}

		err := s.db.LogScan(userID, deviceID, "", int(frameSeq), detectionCount, "success")
		if err != nil {
			s.logger.WithField("error", err).Error("Failed to log scan to DB")
		}
	}()
	
	// Prepare AI results
	var detections []map[string]interface{}
	if grpcResponse.AiResults != nil {
		for _, d := range grpcResponse.AiResults.Detections {
			bboxMap := map[string]interface{}{
				"x_min": d.Bbox.XMin,
				"y_min": d.Bbox.YMin,
				"x_max": d.Bbox.XMax,
				"y_max": d.Bbox.YMax,
			}
			detections = append(detections, map[string]interface{}{
				"class_name": d.ClassName,
				"confidence": d.Confidence,
				"bbox":       bboxMap,
			})
		}
	}

	// Responder call
	responder(map[string]interface{}{
		"success":         grpcResponse.Success,
		"message":         grpcResponse.Message,
		"frame_id":        frame.ID,
		"frame_sequence":  frameSeq,
		"ai_results": map[string]interface{}{
			"detections": detections,
		},
		"original_width":  frame.Width,
		"original_height": frame.Height,
	})
}

func (s *Server) sendUDPResponse(conn *net.UDPConn, addr *net.UDPAddr, data interface{}) {
	jsonBytes, err := json.Marshal(data)
	if err != nil {
		return
	}
	
	// Chunking response
	// Using same protocol: MsgID(0 for response? Or random), ChunkIdx, Total
	// Client doesn't strictly check MsgID for correlation in my simple implementation, just reassembles whatever comes.
	// But giving it a random ID is better.
	
	msgID := uint64(time.Now().UnixNano())
	chunkSize := 1400
	totalLen := len(jsonBytes)
	totalChunks := uint16((totalLen + chunkSize - 1) / chunkSize)
	
	for i := uint16(0); i < totalChunks; i++ {
		start := int(i) * chunkSize
		end := start + chunkSize
		if end > totalLen {
			end = totalLen
		}
		
		chunkPayload := jsonBytes[start:end]
		
		packet := make([]byte, 12+len(chunkPayload))
		binary.BigEndian.PutUint64(packet[0:8], msgID)
		binary.BigEndian.PutUint16(packet[8:10], i)
		binary.BigEndian.PutUint16(packet[10:12], totalChunks)
		copy(packet[12:], chunkPayload)
		
		conn.WriteToUDP(packet, addr)
	}
}