package logging

import (
	"fmt"
	"io"
	"os"
	"path/filepath"
	"sync"
	"time"

	"github.com/sirupsen/logrus"
)

type Logger struct {
	*logrus.Logger
	throttledLogs map[string]time.Time
	throttleMutex sync.Mutex
}

func NewLogger(level, format, logDir string) *Logger {
	logger := logrus.New()
	
	// Set log level
	switch level {
	case "debug":
		logger.SetLevel(logrus.DebugLevel)
	case "info":
		logger.SetLevel(logrus.InfoLevel)
	case "warn":
		logger.SetLevel(logrus.WarnLevel)
	case "error":
		logger.SetLevel(logrus.ErrorLevel)
	default:
		logger.SetLevel(logrus.InfoLevel)
	}
	
	// Set log format
	if format == "json" {
		logger.SetFormatter(&logrus.JSONFormatter{})
	} else {
		logger.SetFormatter(&logrus.TextFormatter{})
	}
	
	// Set output
	var output io.Writer = os.Stdout
	
	if logDir != "" {
		// Ensure directory exists
		if err := os.MkdirAll(logDir, 0755); err == nil {
			timestamp := time.Now().Format("20060102_150405")
			logFilePath := filepath.Join(logDir, fmt.Sprintf("go_server_%s.log", timestamp))
			file, err := os.OpenFile(logFilePath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
			if err == nil {
				output = io.MultiWriter(os.Stdout, file)
			}
		}
	}
	
	logger.SetOutput(output)
	
	return &Logger{
		Logger:        logger,
		throttledLogs: make(map[string]time.Time),
	}
}

func (l *Logger) InfoThrottled(key string, interval time.Duration, message string, fields logrus.Fields) {
	l.throttleMutex.Lock()
	lastLog, ok := l.throttledLogs[key]
	now := time.Now()
	if ok && now.Sub(lastLog) < interval {
		l.throttleMutex.Unlock()
		return
	}
	l.throttledLogs[key] = now
	l.throttleMutex.Unlock()

	if fields != nil {
		l.WithFields(fields).Info(message)
	} else {
		l.Info(message)
	}
}

func (l *Logger) DebugThrottled(key string, interval time.Duration, message string, fields logrus.Fields) {
	l.throttleMutex.Lock()
	lastLog, ok := l.throttledLogs[key]
	now := time.Now()
	if ok && now.Sub(lastLog) < interval {
		l.throttleMutex.Unlock()
		return
	}
	l.throttledLogs[key] = now
	l.throttleMutex.Unlock()

	if fields != nil {
		l.WithFields(fields).Debug(message)
	} else {
		l.Debug(message)
	}
}

func (l *Logger) WithFields(fields logrus.Fields) *logrus.Entry {
	return l.Logger.WithFields(fields)
}