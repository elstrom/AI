package api

import (
	"encoding/json"
	"fmt"
	"net/http"
	"os"
	"path/filepath"
	"sync"
	"time"
)

// RemoteLogRequest represents incoming log from mobile apps
type RemoteLogRequest struct {
	Source    string `json:"source"`    // "scanai" or "posai"
	Level     string `json:"level"`     // DEBUG, INFO, WARNING, ERROR
	Message   string `json:"message"`   // Log message
	Timestamp string `json:"timestamp"` // ISO8601 timestamp from client
}

// BatchLogRequest represents batch of logs from mobile apps
type BatchLogRequest struct {
	Source string             `json:"source"`
	Logs   []RemoteLogRequest `json:"logs"`
}

// RemoteLogHandler handles remote log requests from mobile apps
type RemoteLogHandler struct {
	scanaiWriter *os.File
	posaiWriter  *os.File
	mu           sync.Mutex
	logDir       string
}

// NewRemoteLogHandler creates a new remote log handler
func NewRemoteLogHandler(logDir string) *RemoteLogHandler {
	handler := &RemoteLogHandler{
		logDir: logDir,
	}

	// Ensure log directory exists
	if err := os.MkdirAll(logDir, 0755); err != nil {
		fmt.Printf("Failed to create log directory: %v\n", err)
	}

	// Open log files
	scanaiPath := filepath.Join(logDir, "scanAI.log")
	posaiPath := filepath.Join(logDir, "posAI.log")

	var err error
	handler.scanaiWriter, err = os.OpenFile(scanaiPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
	if err != nil {
		fmt.Printf("Failed to open scanAI.log: %v\n", err)
	}

	handler.posaiWriter, err = os.OpenFile(posaiPath, os.O_CREATE|os.O_WRONLY|os.O_APPEND, 0666)
	if err != nil {
		fmt.Printf("Failed to open posAI.log: %v\n", err)
	}

	fmt.Printf("Remote log handler initialized. Logs: %s, %s\n", scanaiPath, posaiPath)
	return handler
}

// Close closes the log file handles
func (h *RemoteLogHandler) Close() {
	h.mu.Lock()
	defer h.mu.Unlock()

	if h.scanaiWriter != nil {
		h.scanaiWriter.Close()
	}
	if h.posaiWriter != nil {
		h.posaiWriter.Close()
	}
}

// HandleLog handles incoming log requests (single or batch)
func (h *RemoteLogHandler) HandleLog(w http.ResponseWriter, r *http.Request) {
	// Only accept POST requests
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	// Set CORS headers for mobile apps
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type")

	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}

	// Try to parse as batch first
	var batchReq BatchLogRequest
	decoder := json.NewDecoder(r.Body)
	if err := decoder.Decode(&batchReq); err == nil && len(batchReq.Logs) > 0 {
		// Handle batch logs
		h.handleBatchLogs(batchReq)
		w.WriteHeader(http.StatusOK)
		w.Write([]byte(`{"status":"ok","count":` + fmt.Sprintf("%d", len(batchReq.Logs)) + `}`))
		return
	}

	// Reset body for single log parsing
	r.Body.Close()

	// If not batch, try single log (for backwards compatibility)
	// Note: Body was consumed, so we need to handle this differently
	// For now, return error suggesting batch format
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"ok"}`))
}

// handleBatchLogs processes a batch of logs
func (h *RemoteLogHandler) handleBatchLogs(batch BatchLogRequest) {
	h.mu.Lock()
	defer h.mu.Unlock()

	var writer *os.File
	switch batch.Source {
	case "scanai":
		writer = h.scanaiWriter
	case "posai":
		writer = h.posaiWriter
	default:
		fmt.Printf("Unknown log source: %s\n", batch.Source)
		return
	}

	if writer == nil {
		fmt.Printf("Log writer not available for source: %s\n", batch.Source)
		return
	}

	for _, log := range batch.Logs {
		// Parse client timestamp or use server time
		var timestamp string
		if log.Timestamp != "" {
			timestamp = log.Timestamp
		} else {
			timestamp = time.Now().Format("2006-01-02T15:04:05.000")
		}

		// Format: [TIMESTAMP] [LEVEL] MESSAGE
		logLine := fmt.Sprintf("[%s] [%s] %s\n", timestamp, log.Level, log.Message)
		writer.WriteString(logLine)
	}

	// Flush to disk
	writer.Sync()
}

// HandleSingleLog handles a single log request (alternative endpoint)
func (h *RemoteLogHandler) HandleSingleLog(w http.ResponseWriter, r *http.Request) {
	if r.Method != http.MethodPost {
		http.Error(w, "Method not allowed", http.StatusMethodNotAllowed)
		return
	}

	w.Header().Set("Access-Control-Allow-Origin", "*")

	var logReq RemoteLogRequest
	if err := json.NewDecoder(r.Body).Decode(&logReq); err != nil {
		http.Error(w, "Invalid JSON", http.StatusBadRequest)
		return
	}

	h.writeSingleLog(logReq)
	w.WriteHeader(http.StatusOK)
	w.Write([]byte(`{"status":"ok"}`))
}

// writeSingleLog writes a single log entry
func (h *RemoteLogHandler) writeSingleLog(log RemoteLogRequest) {
	h.mu.Lock()
	defer h.mu.Unlock()

	var writer *os.File
	switch log.Source {
	case "scanai":
		writer = h.scanaiWriter
	case "posai":
		writer = h.posaiWriter
	default:
		return
	}

	if writer == nil {
		return
	}

	var timestamp string
	if log.Timestamp != "" {
		timestamp = log.Timestamp
	} else {
		timestamp = time.Now().Format("2006-01-02T15:04:05.000")
	}

	logLine := fmt.Sprintf("[%s] [%s] %s\n", timestamp, log.Level, log.Message)
	writer.WriteString(logLine)
	writer.Sync()
}
