// Package api provides HTTP handlers for the REST API.
package api

import (
	"encoding/json"
	"net/http"
	"strconv"
	"strings"

	"go_server/internal/auth"
	"go_server/internal/database"
	"go_server/internal/logging"
)

// CategoryHandler handles category-related HTTP requests.
type CategoryHandler struct {
	db        *database.DB
	logger    *logging.Logger
	secretKey []byte
}

// NewCategoryHandler creates a new CategoryHandler.
func NewCategoryHandler(db *database.DB, logger *logging.Logger, secretKey string) *CategoryHandler {
	return &CategoryHandler{
		db:        db,
		logger:    logger,
		secretKey: []byte(secretKey),
	}
}

// ServeHTTP routes requests to the appropriate handler method.
func (h *CategoryHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}

	// Extract path suffix after /categories
	path := strings.TrimPrefix(r.URL.Path, "/categories")
	path = strings.TrimPrefix(path, "/")

	switch r.Method {
	case http.MethodGet:
		if path == "" {
			h.getAllCategories(w, r)
		} else {
			h.getCategoryByID(w, r, path)
		}
	case http.MethodPost:
		h.createCategory(w, r)
	case http.MethodPut:
		h.updateCategory(w, r, path)
	case http.MethodDelete:
		h.deleteCategory(w, r, path)
	default:
		http.Error(w, `{"error":"Method not allowed"}`, http.StatusMethodNotAllowed)
	}
}

func (h *CategoryHandler) getAllCategories(w http.ResponseWriter, r *http.Request) {
	userID, err := auth.GetUserIDFromRequest(r, h.secretKey)
	if err != nil {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	categories, err := h.db.GetAllCategories(userID)
	if err != nil {
		h.logger.WithField("error", err).Error("Failed to get categories")
		http.Error(w, `{"error":"Failed to get categories"}`, http.StatusInternalServerError)
		return
	}
	if categories == nil {
		categories = []database.Category{}
	}
	json.NewEncoder(w).Encode(categories)
}

func (h *CategoryHandler) getCategoryByID(w http.ResponseWriter, r *http.Request, idStr string) {
	userID, err := auth.GetUserIDFromRequest(r, h.secretKey)
	if err != nil {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		http.Error(w, `{"error":"Invalid category ID"}`, http.StatusBadRequest)
		return
	}

	category, err := h.db.GetCategoryByID(id, userID)
	if err != nil {
		h.logger.WithField("error", err).Error("Failed to get category")
		http.Error(w, `{"error":"Failed to get category"}`, http.StatusInternalServerError)
		return
	}
	if category == nil {
		http.Error(w, `{"error":"Category not found"}`, http.StatusNotFound)
		return
	}
	json.NewEncoder(w).Encode(category)
}

func (h *CategoryHandler) createCategory(w http.ResponseWriter, r *http.Request) {
	userID, err := auth.GetUserIDFromRequest(r, h.secretKey)
	if err != nil {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	var category database.Category
	if err := json.NewDecoder(r.Body).Decode(&category); err != nil {
		http.Error(w, `{"error":"Invalid request body"}`, http.StatusBadRequest)
		return
	}

	// Validate required fields
	if category.Name == "" {
		http.Error(w, `{"error":"Category name is required"}`, http.StatusBadRequest)
		return
	}

	category.UserID = userID // Assign to logged in user

	id, err := h.db.CreateCategory(&category)
	if err != nil {
		h.logger.WithField("error", err).Error("Failed to create category")
		http.Error(w, `{"error":"Failed to create category"}`, http.StatusInternalServerError)
		return
	}

	category.ID = id
	category.IsActive = 1
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(category)
}

func (h *CategoryHandler) updateCategory(w http.ResponseWriter, r *http.Request, idStr string) {
	userID, err := auth.GetUserIDFromRequest(r, h.secretKey)
	if err != nil {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		http.Error(w, `{"error":"Invalid category ID"}`, http.StatusBadRequest)
		return
	}

	var category database.Category
	if err := json.NewDecoder(r.Body).Decode(&category); err != nil {
		http.Error(w, `{"error":"Invalid request body"}`, http.StatusBadRequest)
		return
	}
	category.ID = id
	category.UserID = userID

	if err := h.db.UpdateCategory(&category); err != nil {
		h.logger.WithField("error", err).Error("Failed to update category")
		if err.Error() == "category not found or unauthorized" {
			http.Error(w, `{"error":"Category not found"}`, http.StatusNotFound)
		} else {
			http.Error(w, `{"error":"Failed to update category"}`, http.StatusInternalServerError)
		}
		return
	}

	json.NewEncoder(w).Encode(category)
}

func (h *CategoryHandler) deleteCategory(w http.ResponseWriter, r *http.Request, idStr string) {
	userID, err := auth.GetUserIDFromRequest(r, h.secretKey)
	if err != nil {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		http.Error(w, `{"error":"Invalid category ID"}`, http.StatusBadRequest)
		return
	}

	if err := h.db.DeleteCategory(id, userID); err != nil {
		h.logger.WithField("error", err).Error("Failed to delete category")
		if err.Error() == "category not found or unauthorized" {
			http.Error(w, `{"error":"Category not found"}`, http.StatusNotFound)
		} else {
			http.Error(w, `{"error":"Failed to delete category"}`, http.StatusInternalServerError)
		}
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
