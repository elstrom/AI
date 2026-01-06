package response

import (
	"encoding/json"
	"time"
	"github.com/sirupsen/logrus"
	"go_server/internal/logging"
	"go_server/internal/websocket"
	"go_server/internal/renderer"
)

type Response struct {
	Success        bool               `json:"success"`
	Message        string            `json:"message"`
	Results        map[string]float64 `json:"results"`
	ProcessingTime float64           `json:"processing_time"`
	Timestamp      time.Time         `json:"timestamp"`
}

type Handler struct {
	logger      *logging.Logger
	wsServer    *websocket.Server
	renderer    *renderer.Renderer
}

func NewResponseHandler(logger *logging.Logger, wsServer *websocket.Server) *Handler {
	return &Handler{
		logger:   logger,
		wsServer: wsServer,
		renderer: wsServer.GetRenderer(), // We'll add this method to WebSocket server
	}
}

// HandleFrameResponse handles the response from the AI system and sends it back to the smartphone
func (h *Handler) HandleFrameResponse(frameID string, success bool, message string, results map[string]float64, processingTime float64) {
	h.logger.WithFields(logrus.Fields{
		"frame_id":        frameID,
		"success":         success,
		"processing_time": processingTime,
	}).Debug("Handling frame response")
	
	// Create response
	response := Response{
		Success:        success,
		Message:        message,
		Results:        results,
		ProcessingTime: processingTime,
		Timestamp:      time.Now(),
	}
	
	// Convert to JSON
	responseData, err := json.Marshal(response)
	if err != nil {
		h.logger.WithField("error", err).Error("Failed to marshal response")
		return
	}
	
	// Add rendering instructions for the response
	if success {
		// Create instruction to update UI with results
		uiInstruction := renderer.CreateRenderInstruction(
			renderer.InstructionUpdateUI,
			"ui_update_"+frameID,
			map[string]interface{}{
				"results":        results,
				"processing_time": processingTime,
				"message":        message,
			},
		)
		
		// Add instruction to renderer
		h.renderer.AddInstruction(uiInstruction)
	}
	
	// Send response back to smartphone via WebSocket
	h.wsServer.BroadcastResponse(responseData)
	
	h.logger.WithFields(logrus.Fields{
		"frame_id": frameID,
		"size":     len(responseData),
	}).Debug("Response sent to smartphone")
}

// HandleErrorResponse handles error responses
func (h *Handler) HandleErrorResponse(frameID string, err error) {
	h.logger.WithFields(logrus.Fields{
		"frame_id": frameID,
		"error":    err.Error(),
	}).Error("Handling error response")
	
	// Create error response
	response := Response{
		Success:        false,
		Message:        err.Error(),
		Results:        make(map[string]float64),
		ProcessingTime: 0,
		Timestamp:      time.Now(),
	}
	
	// Convert to JSON
	responseData, err := json.Marshal(response)
	if err != nil {
		h.logger.WithField("error", err).Error("Failed to marshal error response")
		return
	}
	
	// Send error response back to smartphone via WebSocket
	h.wsServer.BroadcastResponse(responseData)
	
	h.logger.WithFields(logrus.Fields{
		"frame_id": frameID,
		"size":     len(responseData),
	}).Debug("Error response sent to smartphone")
}

// HandleBatchResponse handles batch frame responses
func (h *Handler) HandleBatchResponse(frameIDs []string, success bool, message string, responses []map[string]float64, totalProcessingTime float64) {
	h.logger.WithFields(logrus.Fields{
		"frame_count":     len(frameIDs),
		"success":         success,
		"processing_time": totalProcessingTime,
	}).Debug("Handling batch response")
	
	// For batch responses, we'll send individual responses for each frame
	for i, frameID := range frameIDs {
		var results map[string]float64
		if i < len(responses) {
			results = responses[i]
		} else {
			results = make(map[string]float64)
		}
		
		h.HandleFrameResponse(frameID, success, message, results, totalProcessingTime/float64(len(frameIDs)))
	}
	
	// Add batch rendering instruction
	if success {
		batchInstruction := renderer.CreateRenderInstruction(
			renderer.InstructionUpdateUI,
			"batch_ui_update_"+frameIDs[0],
			map[string]interface{}{
				"batch":          true,
				"frame_ids":      frameIDs,
				"total_time":     totalProcessingTime,
				"average_time":   totalProcessingTime / float64(len(frameIDs)),
			},
		)
		
		h.renderer.AddInstruction(batchInstruction)
	}
}