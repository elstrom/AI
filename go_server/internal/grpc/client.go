package grpc

import (
	"context"
	"time"
	"fmt"
	"google.golang.org/grpc"
	"google.golang.org/grpc/credentials/insecure"
	"go_server/proto"
	"go_server/internal/logging"
	"github.com/sirupsen/logrus"
)

type Client struct {
	conn       *grpc.ClientConn
	client     proto.AIServiceClient
	logger     *logging.Logger
	serverAddr string
}

func NewGRPCClient(serverAddr string, logger *logging.Logger) (*Client, error) {
	// Set up a connection to the server with retry logic
	conn, err := connectWithRetry(serverAddr, logger)
	if err != nil {
		logger.WithField("error", err).Error("Failed to connect to gRPC server after retries")
		return nil, fmt.Errorf("failed to connect to gRPC server: %v", err)
	}

	// Create a client
	client := proto.NewAIServiceClient(conn)

	return &Client{
		conn:       conn,
		client:     client,
		logger:     logger,
		serverAddr: serverAddr,
	}, nil
}

// connectWithRetry attempts to connect to the gRPC server with exponential backoff
func connectWithRetry(serverAddr string, logger *logging.Logger) (*grpc.ClientConn, error) {
	const (
		maxRetries      = 10
		initialBackoff  = 1 * time.Second
		maxBackoff      = 30 * time.Second
		backoffFactor   = 2.0
	)

	var lastErr error
	backoff := initialBackoff

	for attempt := 1; attempt <= maxRetries; attempt++ {
		logger.WithFields(logrus.Fields{
			"attempt": attempt,
			"max_retries": maxRetries,
			"backoff": backoff,
		}).Info("Attempting to connect to gRPC server")

		conn, err := grpc.Dial(serverAddr, grpc.WithTransportCredentials(insecure.NewCredentials()))
		if err == nil {
			// Test the connection with a simple health check
			ctx, cancel := context.WithTimeout(context.Background(), 5*time.Second)
			defer cancel()
			
			client := proto.NewAIServiceClient(conn)
			_, err = client.GetModelInfo(ctx, &proto.Empty{})
			if err == nil {
				logger.Info("Successfully connected to gRPC server")
				return conn, nil
			}
			
			// If the health check failed, close the connection
			conn.Close()
			logger.WithField("error", err).Warn("gRPC connection established but health check failed")
		} else {
			logger.WithField("error", err).Warn("Failed to connect to gRPC server")
		}

		lastErr = err
		
		// If this is the last attempt, don't wait
		if attempt == maxRetries {
			break
		}

		// Wait with exponential backoff
		logger.WithField("backoff", backoff).Info("Waiting before retry...")
		time.Sleep(backoff)
		
		// Increase the backoff for the next attempt
		backoff = time.Duration(float64(backoff) * backoffFactor)
		if backoff > maxBackoff {
			backoff = maxBackoff
		}
	}

	return nil, fmt.Errorf("failed to connect to gRPC server after %d attempts, last error: %v", maxRetries, lastErr)
}

func (c *Client) Close() error {
	if c.conn != nil {
		return c.conn.Close()
	}
	return nil
}

func (c *Client) ProcessFrame(ctx context.Context, frameData []byte, width, height, channels int32, format string) (*proto.FrameResponse, error) {
	c.logger.Debug("Sending frame to AI system")
	
	req := &proto.FrameRequest{
		FrameData: frameData,
		Width:     width,
		Height:    height,
		Channels:  channels,
		Format:    format,
	}
	
	resp, err := c.client.ProcessFrame(ctx, req)
	if err != nil {
		c.logger.WithField("error", err).Error("Failed to process frame")
		return nil, fmt.Errorf("failed to process frame: %v", err)
	}
	
	c.logger.WithFields(logrus.Fields{
		"success": resp.Success,
		"message": resp.Message,
		"processing_time": resp.ProcessingTimeMs,
	}).Debug("Received response from AI system")
	
	return resp, nil
}

func (c *Client) ProcessBatchFrames(ctx context.Context, frames []*proto.FrameRequest) (*proto.BatchFrameResponse, error) {
	c.logger.WithField("frame_count", len(frames)).Debug("Sending batch frames to AI system")
	
	// Create request
	req := &proto.BatchFrameRequest{
		Frames: frames,
	}
	
	// Call RPC
	ctx, cancel := context.WithTimeout(ctx, 60*time.Second)
	defer cancel()
	
	resp, err := c.client.ProcessBatchFrames(ctx, req)
	if err != nil {
		c.logger.WithField("error", err).Error("Failed to process batch frames")
		return nil, fmt.Errorf("failed to process batch frames: %v", err)
	}
	
	c.logger.WithFields(logrus.Fields{
		"success": resp.Success,
		"message": resp.Message,
		"total_processing_time": resp.TotalProcessingTime,
	}).Debug("Received batch response from AI system")
	
	return resp, nil
}

func (c *Client) GetModelInfo(ctx context.Context) (*proto.ModelInfoResponse, error) {
	c.logger.Debug("Getting model info from AI system")
	
	// Create request
	req := &proto.Empty{}
	
	// Call RPC
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	
	resp, err := c.client.GetModelInfo(ctx, req)
	if err != nil {
		c.logger.WithField("error", err).Error("Failed to get model info")
		return nil, fmt.Errorf("failed to get model info: %v", err)
	}
	
	c.logger.WithFields(logrus.Fields{
		"success": resp.Success,
		"model_path": resp.ModelPath,
	}).Debug("Received model info from AI system")
	
	return resp, nil
}

func (c *Client) GetServerStats(ctx context.Context) (*proto.ServerStatsResponse, error) {
	c.logger.Debug("Getting server stats from AI system")
	
	// Create request
	req := &proto.Empty{}
	
	// Call RPC
	ctx, cancel := context.WithTimeout(ctx, 10*time.Second)
	defer cancel()
	
	resp, err := c.client.GetServerStats(ctx, req)
	if err != nil {
		c.logger.WithField("error", err).Error("Failed to get server stats")
		return nil, fmt.Errorf("failed to get server stats: %v", err)
	}
	
	c.logger.WithFields(logrus.Fields{
		"success": resp.Success,
		"pool_size": resp.PoolSize,
		"in_use": resp.InUse,
		"status": resp.Status,
	}).Debug("Received server stats from AI system")
	
	return resp, nil
}