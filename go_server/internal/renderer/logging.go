package renderer

import (
	"encoding/json"
	"time"

	"go_server/internal/logging"
	"github.com/sirupsen/logrus"
)

// RendererLogger handles logging specific to offload rendering
type RendererLogger struct {
	logger *logging.Logger
}

// NewRendererLogger creates a new renderer logger
func NewRendererLogger(logger *logging.Logger) *RendererLogger {
	return &RendererLogger{
		logger: logger,
	}
}

// LogFrameProcessing logs frame processing information
func (rl *RendererLogger) LogFrameProcessing(frameID string, width, height int, processingTime time.Duration) {
	rl.logger.WithFields(logrus.Fields{
		"frame_id":        frameID,
		"width":           width,
		"height":          height,
		"processing_time": processingTime,
		"component":       "renderer",
		"event":           "frame_processing",
	}).Debug("Frame processed for offload rendering")
}

// LogCompression logs compression information
func (rl *RendererLogger) LogCompression(frameID string, originalSize, compressedSize int, compressionRatio float64) {
	rl.logger.WithFields(logrus.Fields{
		"frame_id":          frameID,
		"original_size":     originalSize,
		"compressed_size":   compressedSize,
		"compression_ratio": compressionRatio,
		"component":         "renderer",
		"event":            "compression",
	}).Debug("Frame data compressed")
}

// LogProgressiveRendering logs progressive rendering information
func (rl *RendererLogger) LogProgressiveRendering(frameID string, levels int, delay int) {
	rl.logger.WithFields(logrus.Fields{
		"frame_id":    frameID,
		"levels":      levels,
		"delay_ms":    delay,
		"component":   "renderer",
		"event":       "progressive_rendering",
	}).Debug("Progressive rendering started")
}

// LogInstruction logs rendering instruction information
func (rl *RendererLogger) LogInstruction(instructionType RenderInstructionType, instructionID string) {
	rl.logger.WithFields(logrus.Fields{
		"instruction_type": instructionType,
		"instruction_id":   instructionID,
		"component":        "renderer",
		"event":           "instruction",
	}).Debug("Rendering instruction processed")
}

// LogError logs error information
func (rl *RendererLogger) LogError(frameID string, err error, context string) {
	rl.logger.WithFields(logrus.Fields{
		"frame_id":  frameID,
		"error":     err.Error(),
		"context":   context,
		"component": "renderer",
		"event":     "error",
	}).Error("Error in renderer")
}

// LogStats logs renderer statistics
func (rl *RendererLogger) LogStats(stats RendererStats) {
	rl.logger.WithFields(logrus.Fields{
		"total_frames":       stats.TotalFrames,
		"compressed_frames":  stats.CompressedFrames,
		"progressive_frames": stats.ProgressiveFrames,
		"total_bytes":        stats.TotalBytes,
		"compressed_bytes":   stats.CompressedBytes,
		"compression_ratio":  stats.CompressionRatio,
		"last_processing_time": stats.LastProcessingTime,
		"avg_processing_time":  stats.AvgProcessingTime,
		"component":         "renderer",
		"event":            "stats",
	}).Info("Renderer statistics")
}

// LogFrameSent logs when a frame is sent to the smartphone
func (rl *RendererLogger) LogFrameSent(frameID string, dataSize int, quality int, instructionCount int) {
	rl.logger.WithFields(logrus.Fields{
		"frame_id":        frameID,
		"data_size":       dataSize,
		"quality":         quality,
		"instructions":    instructionCount,
		"component":       "renderer",
		"event":           "frame_sent",
	}).Debug("Frame sent to smartphone for rendering")
}

// LogRendererInit logs renderer initialization
func (rl *RendererLogger) LogRendererInit(config *RendererConfig) {
	rl.logger.WithFields(logrus.Fields{
		"compression_type":  config.CompressionType,
		"compression_level": config.CompressionLevel,
		"progressive":       config.EnableProgressive,
		"progressive_levels": config.ProgressiveLevels,
		"progressive_delay":  config.ProgressiveDelay,
		"default_quality":    config.DefaultQuality,
		"min_quality":        config.MinQuality,
		"max_quality":        config.MaxQuality,
		"quality_adjustment": config.QualityAdjustment,
		"max_buffer_size":    config.MaxBufferSize,
		"flush_interval":     config.FlushInterval,
		"component":          "renderer",
		"event":             "init",
	}).Info("Renderer initialized")
}

// LogQualityAdjustment logs quality adjustment information
func (rl *RendererLogger) LogQualityAdjustment(frameID string, oldQuality, newQuality int) {
	rl.logger.WithFields(logrus.Fields{
		"frame_id":     frameID,
		"old_quality":  oldQuality,
		"new_quality":  newQuality,
		"component":    "renderer",
		"event":        "quality_adjustment",
	}).Debug("Quality adjusted for frame")
}

// LogBufferFlush logs buffer flush information
func (rl *RendererLogger) LogBufferFlush(bufferSize int, flushTime time.Duration) {
	rl.logger.WithFields(logrus.Fields{
		"buffer_size":  bufferSize,
		"flush_time":   flushTime,
		"component":    "renderer",
		"event":        "buffer_flush",
	}).Debug("Renderer buffer flushed")
}

// LogInstructionQueue logs instruction queue information
func (rl *RendererLogger) LogInstructionQueue(queueSize int) {
	rl.logger.WithFields(logrus.Fields{
		"queue_size":  queueSize,
		"component":   "renderer",
		"event":       "instruction_queue",
	}).Debug("Instruction queue status")
}

// LogFrameQueue logs frame queue information
func (rl *RendererLogger) LogFrameQueue(queueSize int) {
	rl.logger.WithFields(logrus.Fields{
		"queue_size":  queueSize,
		"component":   "renderer",
		"event":       "frame_queue",
	}).Debug("Frame queue status")
}

// LogSystemLoad logs system load information
func (rl *RendererLogger) LogSystemLoad(load float64, threshold float64) {
	rl.logger.WithFields(logrus.Fields{
		"load":       load,
		"threshold":  threshold,
		"component":  "renderer",
		"event":      "system_load",
	}).Debug("System load check")
}

// LogBandwidthUsage logs bandwidth usage information
func (rl *RendererLogger) LogBandwidthUsage(bytesSent int, duration time.Duration) {
	bandwidth := float64(bytesSent) / duration.Seconds() / 1024.0 // KB/s
	rl.logger.WithFields(logrus.Fields{
		"bytes_sent":  bytesSent,
		"duration":    duration,
		"bandwidth":   bandwidth,
		"component":   "renderer",
		"event":       "bandwidth_usage",
	}).Info("Bandwidth usage")
}

// LogSmartphoneResponse logs smartphone response information
func (rl *RendererLogger) LogSmartphoneResponse(frameID string, responseTime time.Duration, success bool) {
	rl.logger.WithFields(logrus.Fields{
		"frame_id":      frameID,
		"response_time": responseTime,
		"success":       success,
		"component":     "renderer",
		"event":         "smartphone_response",
	}).Debug("Smartphone response received")
}

// LogDetailedStats logs detailed renderer statistics in JSON format
func (rl *RendererLogger) LogDetailedStats(stats RendererStats) {
	statsJSON, err := json.Marshal(stats)
	if err != nil {
		rl.logger.WithField("error", err).Error("Failed to marshal renderer stats")
		return
	}
	
	rl.logger.WithFields(logrus.Fields{
		"stats_json": string(statsJSON),
		"component":  "renderer",
		"event":      "detailed_stats",
	}).Info("Detailed renderer statistics")
}