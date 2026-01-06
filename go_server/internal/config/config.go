package config

import (
	"encoding/json"
	"log"
	"os"
)

type Config struct {
	Server struct {
		Host string `json:"host"`
		Port string `json:"port"`
	} `json:"server"`
	
	WebSocket struct {
		Path string `json:"path"`
	} `json:"websocket"`
	
	Database struct {
		Path string `json:"path"`
	} `json:"database"`

	Auth struct {
		SecretKey string `json:"secret_key"`
	} `json:"auth"`

	Connection struct {
		TimeoutUserOnline int `json:"timeout_user_online"`
	} `json:"connection"`
	
	GRPC struct {
		Host string `json:"host"`
		Port string `json:"port"`
	} `json:"grpc"`
	
	Logging struct {
		Level     string `json:"level"`
		Format    string `json:"format"`
		Directory string `json:"directory"`
	} `json:"logging"`
	
	FrameSkip struct {
		BaseSkipRatio          float64 `json:"base_skip_ratio"`
		MaxSkipRatio           float64 `json:"max_skip_ratio"`
		DifferenceThreshold    float64 `json:"difference_threshold"`
		MotionThreshold        float64 `json:"motion_threshold"`
		MotionWindowSize       int     `json:"motion_window_size"`
		SystemLoadThreshold    float64 `json:"system_load_threshold"`
		SystemLoadCheckInterval int   `json:"system_load_check_interval"`
	} `json:"frame_skip"`
	
	Renderer struct {
		CompressionType   string `json:"compression_type"`
		CompressionLevel  int    `json:"compression_level"`
		EnableProgressive bool   `json:"enable_progressive"`
		ProgressiveLevels int    `json:"progressive_levels"`
		ProgressiveDelay  int    `json:"progressive_delay_ms"`
		DefaultQuality    int    `json:"default_quality"`
		MinQuality        int    `json:"min_quality"`
		MaxQuality        int    `json:"max_quality"`
		QualityAdjustment bool   `json:"quality_adjustment"`
		MaxBufferSize     int    `json:"max_buffer_size"`
		FlushInterval     int    `json:"flush_interval_ms"`
	} `json:"renderer"`
}

func LoadConfig(configPath string) (*Config, error) {
	var config Config
	
	data, err := os.ReadFile(configPath)
	if err != nil {
		log.Printf("Error reading config file: %v", err)
		return nil, err
	}
	
	err = json.Unmarshal(data, &config)
	if err != nil {
		log.Printf("Error parsing config file: %v", err)
		return nil, err
	}
	
	return &config, nil
}