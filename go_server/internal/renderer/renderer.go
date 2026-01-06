package renderer

import (
	"bytes"
	"compress/gzip"
	"errors"
	"io"
	"sync"
	"time"

	"go_server/internal/logging"
)

// RenderInstructionType defines the type of rendering instruction
type RenderInstructionType string

const (
	// Instruction types for rendering
	InstructionDrawRect    RenderInstructionType = "draw_rect"
	InstructionDrawText    RenderInstructionType = "draw_text"
	InstructionDrawImage   RenderInstructionType = "draw_image"
	InstructionClearScreen RenderInstructionType = "clear_screen"
	InstructionUpdateUI    RenderInstructionType = "update_ui"
	InstructionRenderFrame RenderInstructionType = "render_frame"
)

// RenderInstruction represents a rendering instruction to be sent to the smartphone
type RenderInstruction struct {
	Type       RenderInstructionType `json:"type"`
	ID         string               `json:"id"`
	Parameters map[string]interface{} `json:"parameters"`
	Timestamp  time.Time            `json:"timestamp"`
}

// RenderFrame represents a frame to be rendered on the smartphone
type RenderFrame struct {
	ID          string               `json:"id"`
	Data        []byte               `json:"data"`
	Width       int                  `json:"width"`
	Height      int                  `json:"height"`
	Format      string               `json:"format"`
	Instructions []RenderInstruction  `json:"instructions"`
	Progressive bool                 `json:"progressive"`
	Quality     int                  `json:"quality"`
	Timestamp   time.Time            `json:"timestamp"`
}

// CompressionType defines the compression algorithm to use
type CompressionType string

const (
	CompressionNone CompressionType = "none"
	CompressionGZIP CompressionType = "gzip"
	CompressionLZ4  CompressionType = "lz4"
)

// RendererConfig holds configuration for the renderer
type RendererConfig struct {
	// Compression settings
	CompressionType   CompressionType `yaml:"compression_type"`
	CompressionLevel  int            `yaml:"compression_level"`
	
	// Progressive rendering settings
	EnableProgressive bool   `yaml:"enable_progressive"`
	ProgressiveLevels int    `yaml:"progressive_levels"`
	ProgressiveDelay  int    `yaml:"progressive_delay_ms"` // Delay between progressive levels in ms
	
	// Quality settings
	DefaultQuality     int `yaml:"default_quality"`
	MinQuality         int `yaml:"min_quality"`
	MaxQuality         int `yaml:"max_quality"`
	QualityAdjustment  bool `yaml:"quality_adjustment"`
	
	// Buffer settings
	MaxBufferSize      int `yaml:"max_buffer_size"`
	FlushInterval      int `yaml:"flush_interval_ms"`
}

// Renderer handles offload rendering to smartphone
type Renderer struct {
	config       *RendererConfig
	logger       *logging.Logger
	compressor   Compressor
	instructions chan RenderInstruction
	frames       chan RenderFrame
	buffer       *bytes.Buffer
	mu           sync.Mutex
	stats        *RendererStats
}

// Compressor defines the interface for data compression
type Compressor interface {
	Compress(data []byte) ([]byte, error)
	Decompress(data []byte) ([]byte, error)
}

// GZipCompressor implements gzip compression
type GZipCompressor struct {
	level int
}

// RendererStats holds statistics for the renderer
type RendererStats struct {
	TotalFrames        int64
	CompressedFrames   int64
	ProgressiveFrames  int64
	TotalBytes         int64
	CompressedBytes    int64
	CompressionRatio   float64
	LastProcessingTime time.Duration
	AvgProcessingTime  time.Duration
}

// NewRenderer creates a new renderer instance
func NewRenderer(config *RendererConfig, logger *logging.Logger) *Renderer {
	r := &Renderer{
		config:       config,
		logger:       logger,
		instructions: make(chan RenderInstruction, 100),
		frames:       make(chan RenderFrame, 10),
		buffer:       bytes.NewBuffer(make([]byte, 0, config.MaxBufferSize)),
		stats:        &RendererStats{},
	}
	
	// Initialize compressor based on config
	switch config.CompressionType {
	case CompressionGZIP:
		r.compressor = &GZipCompressor{level: config.CompressionLevel}
	default:
		r.compressor = &NoOpCompressor{}
	}
	
	// Initialize renderer logger
	rendererLogger := NewRendererLogger(logger)
	
	// Start processing frames and instructions
	go r.processInstructions()
	go r.processFrames()
	
	// Log renderer initialization
	rendererLogger.LogRendererInit(config)
	
	return r
}

// AddInstruction adds a rendering instruction to the queue
func (r *Renderer) AddInstruction(instruction RenderInstruction) {
	r.mu.Lock()
	defer r.mu.Unlock()
	
	r.instructions <- instruction
	
	// Initialize renderer logger
	rendererLogger := NewRendererLogger(r.logger)
	rendererLogger.LogInstruction(instruction.Type, instruction.ID)
}

// RenderFrame processes a frame for offload rendering
func (r *Renderer) RenderFrame(frame RenderFrame) error {
	startTime := time.Now()
	
	// Validate frame
	if frame.ID == "" {
		return errors.New("frame ID cannot be empty")
	}
	
	if len(frame.Data) == 0 {
		return errors.New("frame data cannot be empty")
	}
	
	// Apply default quality if not set
	if frame.Quality == 0 {
		frame.Quality = r.config.DefaultQuality
	}
	
	// Ensure quality is within bounds
	if frame.Quality < r.config.MinQuality {
		frame.Quality = r.config.MinQuality
	}
	if frame.Quality > r.config.MaxQuality {
		frame.Quality = r.config.MaxQuality
	}
	
	// Set progressive rendering if enabled
	if r.config.EnableProgressive && !frame.Progressive {
		frame.Progressive = true
	}
	
	// Add frame to processing queue
	r.frames <- frame
	
	// Update stats
	processingTime := time.Since(startTime)
	r.mu.Lock()
	r.stats.TotalFrames++
	r.stats.LastProcessingTime = processingTime
	
	// Calculate average processing time
	if r.stats.TotalFrames > 1 {
		totalTime := r.stats.AvgProcessingTime*time.Duration(r.stats.TotalFrames-1) + processingTime
		r.stats.AvgProcessingTime = totalTime / time.Duration(r.stats.TotalFrames)
	} else {
		r.stats.AvgProcessingTime = processingTime
	}
	r.mu.Unlock()
	
	// Initialize renderer logger
	rendererLogger := NewRendererLogger(r.logger)
	rendererLogger.LogFrameProcessing(frame.ID, frame.Width, frame.Height, processingTime)
	
	return nil
}

// GetStats returns the renderer statistics
func (r *Renderer) GetStats() RendererStats {
	r.mu.Lock()
	defer r.mu.Unlock()
	
	return *r.stats
}

// processInstructions processes rendering instructions
func (r *Renderer) processInstructions() {
	rendererLogger := NewRendererLogger(r.logger)
	
	for instruction := range r.instructions {
		rendererLogger.LogInstruction(instruction.Type, instruction.ID)
		
		// Here we would typically send the instruction to the smartphone
		// For now, we'll just log it
	}
}

// processFrames processes frames for offload rendering
func (r *Renderer) processFrames() {
	rendererLogger := NewRendererLogger(r.logger)
	
	for frame := range r.frames {
		startTime := time.Now()
		
		// Compress frame data if needed
		compressedData := frame.Data
		if r.config.CompressionType != CompressionNone {
			var err error
			compressedData, err = r.compressor.Compress(frame.Data)
			if err != nil {
				rendererLogger.LogError(frame.ID, err, "compression")
				continue
			}
			
			// Update stats
			r.mu.Lock()
			r.stats.CompressedFrames++
			r.stats.TotalBytes += int64(len(frame.Data))
			r.stats.CompressedBytes += int64(len(compressedData))
			if r.stats.TotalBytes > 0 {
				r.stats.CompressionRatio = float64(r.stats.CompressedBytes) / float64(r.stats.TotalBytes)
			}
			r.mu.Unlock()
			
			// Log compression info
			compressionRatio := float64(len(compressedData)) / float64(len(frame.Data))
			rendererLogger.LogCompression(frame.ID, len(frame.Data), len(compressedData), compressionRatio)
		}
		
		// Handle progressive rendering if enabled
		if frame.Progressive {
			r.renderProgressive(frame, compressedData)
		} else {
			// Send frame to smartphone
			r.sendFrameToSmartphone(frame, compressedData)
		}
		
		// Update progressive frame stats
		if frame.Progressive {
			r.mu.Lock()
			r.stats.ProgressiveFrames++
			r.mu.Unlock()
		}
		
		processingTime := time.Since(startTime)
		rendererLogger.LogFrameProcessing(frame.ID, frame.Width, frame.Height, processingTime)
	}
}

// renderProgressive handles progressive rendering
func (r *Renderer) renderProgressive(frame RenderFrame, compressedData []byte) {
	rendererLogger := NewRendererLogger(r.logger)
	rendererLogger.LogProgressiveRendering(frame.ID, r.config.ProgressiveLevels, r.config.ProgressiveDelay)
	
	// Create progressive levels
	for level := 1; level <= r.config.ProgressiveLevels; level++ {
		// Calculate quality for this level
		quality := r.config.MinQuality + (r.config.MaxQuality-r.config.MinQuality)*level/r.config.ProgressiveLevels
		
		// Create progressive frame
		progFrame := frame
		progFrame.Quality = int(quality)
		
		// For simplicity, we're using the same compressed data for all levels
		// In a real implementation, you would generate different quality levels
		r.sendFrameToSmartphone(progFrame, compressedData)
		
		// Delay before sending next level (except for the last one)
		if level < r.config.ProgressiveLevels {
			time.Sleep(time.Duration(r.config.ProgressiveDelay) * time.Millisecond)
		}
	}
}

// sendFrameToSmartphone sends a frame to the smartphone for rendering
func (r *Renderer) sendFrameToSmartphone(frame RenderFrame, data []byte) {
	rendererLogger := NewRendererLogger(r.logger)
	rendererLogger.LogFrameSent(frame.ID, len(data), frame.Quality, len(frame.Instructions))
	
	// Here we would typically send the frame to the smartphone via WebSocket
	// For now, we'll just simulate it by logging
}

// Compress implements the Compressor interface for GZipCompressor
func (g *GZipCompressor) Compress(data []byte) ([]byte, error) {
	var buf bytes.Buffer
	writer, err := gzip.NewWriterLevel(&buf, g.level)
	if err != nil {
		return nil, err
	}
	
	_, err = writer.Write(data)
	if err != nil {
		return nil, err
	}
	
	err = writer.Close()
	if err != nil {
		return nil, err
	}
	
	return buf.Bytes(), nil
}

// Decompress implements the Compressor interface for GZipCompressor
func (g *GZipCompressor) Decompress(data []byte) ([]byte, error) {
	reader, err := gzip.NewReader(bytes.NewReader(data))
	if err != nil {
		return nil, err
	}
	defer reader.Close()
	
	return io.ReadAll(reader)
}

// NoOpCompressor implements a no-op compressor
type NoOpCompressor struct{}

// Compress implements the Compressor interface for NoOpCompressor
func (n *NoOpCompressor) Compress(data []byte) ([]byte, error) {
	return data, nil
}

// Decompress implements the Compressor interface for NoOpCompressor
func (n *NoOpCompressor) Decompress(data []byte) ([]byte, error) {
	return data, nil
}

// CreateRenderInstruction creates a new rendering instruction
func CreateRenderInstruction(instructionType RenderInstructionType, id string, parameters map[string]interface{}) RenderInstruction {
	if parameters == nil {
		parameters = make(map[string]interface{})
	}
	
	return RenderInstruction{
		Type:       instructionType,
		ID:         id,
		Parameters: parameters,
		Timestamp:  time.Now(),
	}
}

// CreateRenderFrame creates a new render frame
func CreateRenderFrame(id string, data []byte, width, height int, format string) RenderFrame {
	return RenderFrame{
		ID:           id,
		Data:         data,
		Width:        width,
		Height:       height,
		Format:       format,
		Instructions: make([]RenderInstruction, 0),
		Progressive:  false,
		Quality:      100,
		Timestamp:    time.Now(),
	}
}