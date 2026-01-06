package frameskip

import (
	"image"
	"image/color"
	"math"
	"runtime"
	"sync"
	"time"

	"go_server/internal/logging"
	"github.com/sirupsen/logrus"
)

// FrameSkipperConfig holds configuration for the frame skipper
type FrameSkipperConfig struct {
	// Base skip ratio (0.0 to 1.0)
	BaseSkipRatio float64 `yaml:"base_skip_ratio"`
	
	// Maximum skip ratio under heavy load (0.0 to 1.0)
	MaxSkipRatio float64 `yaml:"max_skip_ratio"`
	
	// Threshold for frame difference (0.0 to 1.0)
	DifferenceThreshold float64 `yaml:"difference_threshold"`
	
	// Threshold for motion detection (0.0 to 1.0)
	MotionThreshold float64 `yaml:"motion_threshold"`
	
	// Window size for motion detection (in frames)
	MotionWindowSize int `yaml:"motion_window_size"`
	
	// System load threshold to trigger adaptive skipping (0.0 to 1.0)
	SystemLoadThreshold float64 `yaml:"system_load_threshold"`
	
	// Interval for system load check (in milliseconds)
	SystemLoadCheckInterval int `yaml:"system_load_check_interval"`
}

// FrameSkipper manages frame skipping logic
type FrameSkipper struct {
	config       *FrameSkipperConfig
	logger       *logging.Logger
	currentRatio float64
	lastFrame    *image.RGBA
	frameHistory []*image.RGBA
	skipCount    int
	totalCount   int
	mu           sync.Mutex
	lastLoadCheck time.Time
	systemLoad   float64
}

// NewFrameSkipper creates a new frame skipper
func NewFrameSkipper(config *FrameSkipperConfig, logger *logging.Logger) *FrameSkipper {
	return &FrameSkipper{
		config:       config,
		logger:       logger,
		currentRatio: config.BaseSkipRatio,
		frameHistory: make([]*image.RGBA, 0),
		lastLoadCheck: time.Now(),
	}
}

// ShouldSkip determines if a frame should be skipped
func (fs *FrameSkipper) ShouldSkip(frameData []byte, width, height int) (bool, string) {
	fs.mu.Lock()
	defer fs.mu.Unlock()
	
	fs.totalCount++
	
	// Check system load periodically
	fs.checkSystemLoad()
	
	// Adjust skip ratio based on system load
	fs.adjustSkipRatio()
	
	// Convert byte data to image
	img, err := fs.bytesToImage(frameData, width, height)
	if err != nil {
		fs.logger.WithField("error", err).Error("Failed to convert bytes to image")
		return false, "conversion_error"
	}
	
	// Check if frame should be skipped based on difference
	if fs.lastFrame != nil {
		diff := fs.calculateDifference(img, fs.lastFrame)
		if diff < fs.config.DifferenceThreshold {
			fs.skipCount++
			fs.logger.WithFields(logrus.Fields{
			"skip_reason": "low_difference",
			"difference":  diff,
			"threshold":   fs.config.DifferenceThreshold,
			"skip_ratio":  fs.currentRatio,
		}).Debug("Skipping frame due to low difference")
			return true, "low_difference"
		}
		
		// Check motion level
		motion := fs.calculateMotion(img)
		if motion < fs.config.MotionThreshold {
			fs.skipCount++
			fs.logger.WithFields(logrus.Fields{
			"skip_reason": "low_motion",
			"motion":      motion,
			"threshold":   fs.config.MotionThreshold,
			"skip_ratio":  fs.currentRatio,
		}).Debug("Skipping frame due to low motion")
			return true, "low_motion"
		}
	}
	
	// Apply skip ratio
	if fs.currentRatio > 0 && fs.totalCount%int(1/fs.currentRatio) != 0 {
		fs.skipCount++
		fs.logger.WithFields(logrus.Fields{
		"skip_reason": "ratio",
		"skip_ratio":  fs.currentRatio,
	}).Debug("Skipping frame based on ratio")
		return true, "ratio"
	}
	
	// Update frame history
	fs.updateFrameHistory(img)
	fs.lastFrame = img
	
	return false, ""
}

// GetStats returns frame skipping statistics
func (fs *FrameSkipper) GetStats() (int, int, float64) {
	fs.mu.Lock()
	defer fs.mu.Unlock()
	
	skipRatio := 0.0
	if fs.totalCount > 0 {
		skipRatio = float64(fs.skipCount) / float64(fs.totalCount)
	}
	
	return fs.skipCount, fs.totalCount, skipRatio
}

// ResetStats resets the frame skipping statistics
func (fs *FrameSkipper) ResetStats() {
	fs.mu.Lock()
	defer fs.mu.Unlock()
	
	fs.skipCount = 0
	fs.totalCount = 0
}

// checkSystemLoad checks the current system load
func (fs *FrameSkipper) checkSystemLoad() {
	now := time.Now()
	if now.Sub(fs.lastLoadCheck).Milliseconds() < int64(fs.config.SystemLoadCheckInterval) {
		return
	}
	
	fs.lastLoadCheck = now
	
	// Get system load
	var m runtime.MemStats
	runtime.ReadMemStats(&m)
	
	// Calculate system load based on memory usage and goroutines
	memLoad := float64(m.Alloc) / float64(m.Sys)
	cpuLoad := float64(runtime.NumGoroutine()) / 1000.0 // Assuming 1000 goroutines as 100% load
	
	// Combine loads (can be adjusted based on requirements)
	fs.systemLoad = (memLoad + cpuLoad) / 2.0
	
	fs.logger.WithFields(logrus.Fields{
		"mem_load":    memLoad,
		"cpu_load":    cpuLoad,
		"system_load": fs.systemLoad,
	}).Debug("System load check")
}

// adjustSkipRatio adjusts the skip ratio based on system load
func (fs *FrameSkipper) adjustSkipRatio() {
	if fs.systemLoad > fs.config.SystemLoadThreshold {
		// Increase skip ratio based on system load
		loadFactor := (fs.systemLoad - fs.config.SystemLoadThreshold) / (1.0 - fs.config.SystemLoadThreshold)
		fs.currentRatio = fs.config.BaseSkipRatio + (fs.config.MaxSkipRatio-fs.config.BaseSkipRatio)*loadFactor
		
		// Clamp to max skip ratio
		if fs.currentRatio > fs.config.MaxSkipRatio {
			fs.currentRatio = fs.config.MaxSkipRatio
		}
	} else {
		// Gradually return to base skip ratio
		fs.currentRatio = fs.config.BaseSkipRatio
	}
	
	fs.logger.WithFields(logrus.Fields{
		"system_load":      fs.systemLoad,
		"load_threshold":   fs.config.SystemLoadThreshold,
		"current_ratio":    fs.currentRatio,
		"base_skip_ratio":  fs.config.BaseSkipRatio,
		"max_skip_ratio":   fs.config.MaxSkipRatio,
	}).Debug("Adjusted skip ratio")
}

// bytesToImage converts byte data to image.Image
func (fs *FrameSkipper) bytesToImage(data []byte, width, height int) (*image.RGBA, error) {
	img := image.NewRGBA(image.Rect(0, 0, width, height))
	
	// Assuming data is in RGBA format
	for y := 0; y < height; y++ {
		for x := 0; x < width; x++ {
			idx := (y*width + x) * 4
			if idx+3 < len(data) {
				r := data[idx]
				g := data[idx+1]
				b := data[idx+2]
				a := data[idx+3]
				img.Set(x, y, color.RGBA{r, g, b, a})
			}
		}
	}
	
	return img, nil
}

// calculateDifference calculates the difference between two frames
func (fs *FrameSkipper) calculateDifference(img1, img2 *image.RGBA) float64 {
	bounds := img1.Bounds()
	totalDiff := 0.0
	pixelCount := 0
	
	for y := bounds.Min.Y; y < bounds.Max.Y; y++ {
		for x := bounds.Min.X; x < bounds.Max.X; x++ {
			r1, g1, b1, _ := img1.At(x, y).RGBA()
			r2, g2, b2, _ := img2.At(x, y).RGBA()
			
			// Calculate Euclidean distance in RGB space
			diff := math.Sqrt(
				math.Pow(float64(r1-r2)/65535.0, 2) +
				math.Pow(float64(g1-g2)/65535.0, 2) +
				math.Pow(float64(b1-b2)/65535.0, 2))
			
			totalDiff += diff
			pixelCount++
		}
	}
	
	// Normalize to 0-1 range
	if pixelCount > 0 {
		return totalDiff / float64(pixelCount)
	}
	return 0.0
}

// calculateMotion calculates the motion level based on frame history
func (fs *FrameSkipper) calculateMotion(img *image.RGBA) float64 {
	if len(fs.frameHistory) == 0 {
		return 1.0 // No history, assume high motion
	}
	
	// Calculate motion as average difference with recent frames
	totalMotion := 0.0
	count := 0
	
	historySize := len(fs.frameHistory)
	if historySize > fs.config.MotionWindowSize {
		historySize = fs.config.MotionWindowSize
	}
	
	for i := len(fs.frameHistory) - historySize; i < len(fs.frameHistory); i++ {
		diff := fs.calculateDifference(img, fs.frameHistory[i])
		totalMotion += diff
		count++
	}
	
	if count > 0 {
		return totalMotion / float64(count)
	}
	return 0.0
}

// updateFrameHistory updates the frame history
func (fs *FrameSkipper) updateFrameHistory(img *image.RGBA) {
	// Add current frame to history
	fs.frameHistory = append(fs.frameHistory, img)
	
	// Keep only the last N frames
	maxHistory := fs.config.MotionWindowSize * 2
	if len(fs.frameHistory) > maxHistory {
		fs.frameHistory = fs.frameHistory[len(fs.frameHistory)-maxHistory:]
	}
}