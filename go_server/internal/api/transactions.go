// Package api provides HTTP handlers for the REST API.
package api

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"go_server/internal/database"
	"go_server/internal/logging"
)

// TransactionHandler handles transaction-related HTTP requests.
type TransactionHandler struct {
	db     *database.DB
	logger *logging.Logger
}

// NewTransactionHandler creates a new TransactionHandler.
func NewTransactionHandler(db *database.DB, logger *logging.Logger) *TransactionHandler {
	return &TransactionHandler{
		db:     db,
		logger: logger,
	}
}

// CreateTransactionRequest represents the request body for creating a transaction
type CreateTransactionRequest struct {
	Header database.Transaction      `json:"header"`
	Items  []database.TransactionItem `json:"items"`
}

// ServeHTTP routes requests to the appropriate handler method.
func (h *TransactionHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}

	// Extract path suffix after /transactions
	path := strings.TrimPrefix(r.URL.Path, "/transactions")
	path = strings.TrimPrefix(path, "/")

	// Parse path segments
	segments := strings.Split(path, "/")

	switch r.Method {
	case http.MethodGet:
		if path == "" {
			// Check for date range query
			startDate := r.URL.Query().Get("start")
			endDate := r.URL.Query().Get("end")
			if startDate != "" && endDate != "" {
				h.getTransactionsByDateRange(w, r, startDate, endDate)
			} else {
				h.getAllTransactions(w, r)
			}
		} else if len(segments) == 2 && segments[1] == "items" {
			// GET /transactions/{id}/items
			h.getTransactionItems(w, r, segments[0])
		} else {
			// GET /transactions/{id}
			h.getTransactionByID(w, r, segments[0])
		}
	case http.MethodPost:
		if len(segments) == 2 && segments[1] == "cancel" {
			// POST /transactions/{id}/cancel
			h.cancelTransaction(w, r, segments[0])
		} else {
			// POST /transactions
			h.createTransaction(w, r)
		}
	default:
		http.Error(w, `{"error":"Method not allowed"}`, http.StatusMethodNotAllowed)
	}
}

func (h *TransactionHandler) getAllTransactions(w http.ResponseWriter, r *http.Request) {
	transactions, err := h.db.GetAllTransactions()
	if err != nil {
		h.logger.WithField("error", err).Error("Failed to get transactions")
		http.Error(w, `{"error":"Failed to get transactions"}`, http.StatusInternalServerError)
		return
	}
	if transactions == nil {
		transactions = []database.Transaction{}
	}
	json.NewEncoder(w).Encode(transactions)
}

func (h *TransactionHandler) getTransactionsByDateRange(w http.ResponseWriter, r *http.Request, startDate, endDate string) {
	transactions, err := h.db.GetTransactionsByDateRange(startDate, endDate)
	if err != nil {
		h.logger.WithField("error", err).Error("Failed to get transactions by date range")
		http.Error(w, `{"error":"Failed to get transactions"}`, http.StatusInternalServerError)
		return
	}
	if transactions == nil {
		transactions = []database.Transaction{}
	}
	json.NewEncoder(w).Encode(transactions)
}

func (h *TransactionHandler) getTransactionByID(w http.ResponseWriter, r *http.Request, idStr string) {
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		http.Error(w, `{"error":"Invalid transaction ID"}`, http.StatusBadRequest)
		return
	}

	tx, err := h.db.GetTransactionByID(id)
	if err != nil {
		h.logger.WithField("error", err).Error("Failed to get transaction")
		http.Error(w, `{"error":"Failed to get transaction"}`, http.StatusInternalServerError)
		return
	}
	if tx == nil {
		http.Error(w, `{"error":"Transaction not found"}`, http.StatusNotFound)
		return
	}
	json.NewEncoder(w).Encode(tx)
}

func (h *TransactionHandler) getTransactionItems(w http.ResponseWriter, r *http.Request, idStr string) {
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		http.Error(w, `{"error":"Invalid transaction ID"}`, http.StatusBadRequest)
		return
	}

	items, err := h.db.GetTransactionItems(id)
	if err != nil {
		h.logger.WithField("error", err).Error("Failed to get transaction items")
		http.Error(w, `{"error":"Failed to get transaction items"}`, http.StatusInternalServerError)
		return
	}
	if items == nil {
		items = []database.TransactionItem{}
	}
	json.NewEncoder(w).Encode(items)
}

func (h *TransactionHandler) createTransaction(w http.ResponseWriter, r *http.Request) {
	var req CreateTransactionRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		h.logger.WithField("error", err).Error("Failed to decode transaction request")
		http.Error(w, `{"error":"Invalid request body"}`, http.StatusBadRequest)
		return
	}

	// Validate request
	if len(req.Items) == 0 {
		http.Error(w, `{"error":"Transaction must have at least one item"}`, http.StatusBadRequest)
		return
	}

	// Create transaction in database
	if err := h.db.CreateTransaction(&req.Header, req.Items); err != nil {
		h.logger.WithField("error", err).Error("Failed to create transaction")
		http.Error(w, `{"error":"Failed to create transaction"}`, http.StatusInternalServerError)
		return
	}

	h.logger.WithFields(map[string]interface{}{
		"transaction_id": req.Header.ID,
		"code":           req.Header.Code,
		"total":          req.Header.TotalAmount,
		"items_count":    len(req.Items),
	}).Info("Transaction created successfully")

	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(req.Header)
}

func (h *TransactionHandler) cancelTransaction(w http.ResponseWriter, r *http.Request, idStr string) {
	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		http.Error(w, `{"error":"Invalid transaction ID"}`, http.StatusBadRequest)
		return
	}

	// Get user ID from context/auth (for audit log)
	var userID *int64 = nil

	if err := h.db.CancelTransaction(id, userID); err != nil {
		h.logger.WithField("error", err).Error("Failed to cancel transaction")
		http.Error(w, `{"error":"`+err.Error()+`"}`, http.StatusBadRequest)
		return
	}

	h.logger.WithField("transaction_id", id).Info("Transaction cancelled successfully")
	json.NewEncoder(w).Encode(map[string]string{"message": "Transaction cancelled successfully"})
}
