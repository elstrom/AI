package grpc

import (
	"context"
	"fmt"
	"sync"
	"sync/atomic"

	"github.com/sirupsen/logrus"
	"go_server/internal/logging"
	"go_server/proto"
)

// ClientPool manages a pool of gRPC clients for load balancing
// This is crucial for handling 10+ concurrent users
type ClientPool struct {
	clients    []*Client
	size       int
	counter    uint64 // For round-robin distribution
	mu         sync.RWMutex
	logger     *logging.Logger
	serverAddr string
}

// NewClientPool creates a new pool of gRPC clients
// poolSize should be at least 2-3 for 10 concurrent users
func NewClientPool(serverAddr string, poolSize int, logger *logging.Logger) (*ClientPool, error) {
	if poolSize < 1 {
		poolSize = 3 // Default pool size for multi-user scenario
	}

	pool := &ClientPool{
		clients:    make([]*Client, 0, poolSize),
		size:       poolSize,
		logger:     logger,
		serverAddr: serverAddr,
	}

	logger.WithFields(logrus.Fields{
		"pool_size":   poolSize,
		"server_addr": serverAddr,
	}).Info("Creating gRPC client pool for multi-user support")

	// Create initial clients
	for i := 0; i < poolSize; i++ {
		client, err := NewGRPCClient(serverAddr, logger)
		if err != nil {
			// Close already created clients on failure
			pool.Close()
			return nil, fmt.Errorf("failed to create gRPC client %d/%d: %v", i+1, poolSize, err)
		}
		pool.clients = append(pool.clients, client)
		logger.WithField("client_index", i).Debug("Created gRPC client for pool")
	}

	logger.WithField("pool_size", len(pool.clients)).Info("gRPC client pool created successfully")
	return pool, nil
}

// getNextClient returns the next client using round-robin selection
func (p *ClientPool) getNextClient() *Client {
	p.mu.RLock()
	defer p.mu.RUnlock()

	if len(p.clients) == 0 {
		return nil
	}

	// Atomic increment and modulo for round-robin
	idx := atomic.AddUint64(&p.counter, 1) % uint64(len(p.clients))
	return p.clients[idx]
}

// ProcessFrame distributes frame processing across pool clients
func (p *ClientPool) ProcessFrame(ctx context.Context, frameData []byte, width, height, channels int32, format string) (*proto.FrameResponse, error) {
	client := p.getNextClient()
	if client == nil {
		return nil, fmt.Errorf("no gRPC clients available in pool")
	}

	return client.ProcessFrame(ctx, frameData, width, height, channels, format)
}

// ProcessBatchFrames distributes batch processing across pool clients
func (p *ClientPool) ProcessBatchFrames(ctx context.Context, frames []*proto.FrameRequest) (*proto.BatchFrameResponse, error) {
	client := p.getNextClient()
	if client == nil {
		return nil, fmt.Errorf("no gRPC clients available in pool")
	}

	return client.ProcessBatchFrames(ctx, frames)
}

// GetModelInfo gets model info from any available client
func (p *ClientPool) GetModelInfo(ctx context.Context) (*proto.ModelInfoResponse, error) {
	client := p.getNextClient()
	if client == nil {
		return nil, fmt.Errorf("no gRPC clients available in pool")
	}

	return client.GetModelInfo(ctx)
}

// GetServerStats gets server stats from any available client
func (p *ClientPool) GetServerStats(ctx context.Context) (*proto.ServerStatsResponse, error) {
	client := p.getNextClient()
	if client == nil {
		return nil, fmt.Errorf("no gRPC clients available in pool")
	}

	return client.GetServerStats(ctx)
}

// Close closes all clients in the pool
func (p *ClientPool) Close() error {
	p.mu.Lock()
	defer p.mu.Unlock()

	var lastErr error
	for i, client := range p.clients {
		if client != nil {
			if err := client.Close(); err != nil {
				p.logger.WithFields(logrus.Fields{
					"client_index": i,
					"error":        err,
				}).Error("Failed to close gRPC client")
				lastErr = err
			}
		}
	}
	p.clients = nil
	return lastErr
}

// Size returns the current pool size
func (p *ClientPool) Size() int {
	p.mu.RLock()
	defer p.mu.RUnlock()
	return len(p.clients)
}

// Stats returns pool statistics
func (p *ClientPool) Stats() map[string]interface{} {
	p.mu.RLock()
	defer p.mu.RUnlock()

	return map[string]interface{}{
		"pool_size":      len(p.clients),
		"total_requests": atomic.LoadUint64(&p.counter),
		"server_addr":    p.serverAddr,
	}
}
