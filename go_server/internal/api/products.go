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

// ProductHandler handles product-related HTTP requests.
type ProductHandler struct {
	db        *database.DB
	logger    *logging.Logger
	secretKey []byte
}

// NewProductHandler creates a new ProductHandler.
func NewProductHandler(db *database.DB, logger *logging.Logger, secretKey string) *ProductHandler {
	return &ProductHandler{
		db:        db,
		logger:    logger,
		secretKey: []byte(secretKey),
	}
}

// ServeHTTP routes requests to the appropriate handler method.
func (h *ProductHandler) ServeHTTP(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "GET, POST, PUT, DELETE, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}

	// Extract path suffix after /products
	path := strings.TrimPrefix(r.URL.Path, "/products")
	path = strings.TrimPrefix(path, "/")

	switch r.Method {
	case http.MethodGet:
		if path == "" {
			// Check for name query parameter
			name := r.URL.Query().Get("name")
			if name != "" {
				h.searchByName(w, r, name)
			} else {
				h.getAllProducts(w, r)
			}
		} else {
			h.getProductByID(w, r, path)
		}
	case http.MethodPost:
		h.createProduct(w, r)
	case http.MethodPut:
		h.updateProduct(w, r, path)
	case http.MethodDelete:
		h.deleteProduct(w, r, path)
	default:
		http.Error(w, `{"error":"Method not allowed"}`, http.StatusMethodNotAllowed)
	}
}

func (h *ProductHandler) getAllProducts(w http.ResponseWriter, r *http.Request) {
	userID, err := auth.GetUserIDFromRequest(r, h.secretKey)
	if err != nil {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	products, err := h.db.GetAllProducts(userID)
	if err != nil {
		h.logger.WithField("error", err).Error("Failed to get products")
		http.Error(w, `{"error":"Failed to get products"}`, http.StatusInternalServerError)
		return
	}
	if products == nil {
		products = []database.Product{}
	}
	json.NewEncoder(w).Encode(products)
}

func (h *ProductHandler) getProductByID(w http.ResponseWriter, r *http.Request, idStr string) {
	userID, err := auth.GetUserIDFromRequest(r, h.secretKey)
	if err != nil {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		http.Error(w, `{"error":"Invalid product ID"}`, http.StatusBadRequest)
		return
	}

	product, err := h.db.GetProductByID(id, userID)
	if err != nil {
		h.logger.WithField("error", err).Error("Failed to get product")
		http.Error(w, `{"error":"Failed to get product"}`, http.StatusInternalServerError)
		return
	}
	if product == nil {
		http.Error(w, `{"error":"Product not found"}`, http.StatusNotFound)
		return
	}
	json.NewEncoder(w).Encode(product)
}

func (h *ProductHandler) searchByName(w http.ResponseWriter, r *http.Request, name string) {
	userID, err := auth.GetUserIDFromRequest(r, h.secretKey)
	if err != nil {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	products, err := h.db.SearchProductsByName(name, userID)
	if err != nil {
		h.logger.WithField("error", err).Error("Failed to search products")
		http.Error(w, `{"error":"Failed to search products"}`, http.StatusInternalServerError)
		return
	}
	if products == nil {
		products = []database.Product{}
	}
	json.NewEncoder(w).Encode(products)
}

func (h *ProductHandler) createProduct(w http.ResponseWriter, r *http.Request) {
	userID, err := auth.GetUserIDFromRequest(r, h.secretKey)
	if err != nil {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	var product database.Product
	if err := json.NewDecoder(r.Body).Decode(&product); err != nil {
		http.Error(w, `{"error":"Invalid request body"}`, http.StatusBadRequest)
		return
	}

	// Validate required fields
	if product.Name == "" {
		http.Error(w, `{"error":"Product name is required"}`, http.StatusBadRequest)
		return
	}
	if product.CategoryID == 0 {
		product.CategoryID = 1 // Default category
	}
	
	product.UserID = userID // Assign to logged in user

	id, err := h.db.CreateProduct(&product)
	if err != nil {
		h.logger.WithField("error", err).Error("Failed to create product")
		http.Error(w, `{"error":"Failed to create product"}`, http.StatusInternalServerError)
		return
	}

	product.ID = id
	w.WriteHeader(http.StatusCreated)
	json.NewEncoder(w).Encode(product)
}

func (h *ProductHandler) updateProduct(w http.ResponseWriter, r *http.Request, idStr string) {
	userID, err := auth.GetUserIDFromRequest(r, h.secretKey)
	if err != nil {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		http.Error(w, `{"error":"Invalid product ID"}`, http.StatusBadRequest)
		return
	}

	var product database.Product
	if err := json.NewDecoder(r.Body).Decode(&product); err != nil {
		http.Error(w, `{"error":"Invalid request body"}`, http.StatusBadRequest)
		return
	}
	product.ID = id
	product.UserID = userID // Ensure updating right user's product

	if err := h.db.UpdateProduct(&product); err != nil {
		h.logger.WithField("error", err).Error("Failed to update product")
		if err.Error() == "product not found or unauthorized" {
			http.Error(w, `{"error":"Product not found"}`, http.StatusNotFound)
		} else {
			http.Error(w, `{"error":"Failed to update product"}`, http.StatusInternalServerError)
		}
		return
	}

	json.NewEncoder(w).Encode(product)
}

func (h *ProductHandler) deleteProduct(w http.ResponseWriter, r *http.Request, idStr string) {
	userID, err := auth.GetUserIDFromRequest(r, h.secretKey)
	if err != nil {
		http.Error(w, `{"error":"Unauthorized"}`, http.StatusUnauthorized)
		return
	}

	id, err := strconv.ParseInt(idStr, 10, 64)
	if err != nil {
		http.Error(w, `{"error":"Invalid product ID"}`, http.StatusBadRequest)
		return
	}

	if err := h.db.DeleteProduct(id, userID); err != nil {
		h.logger.WithField("error", err).Error("Failed to delete product")
		if err.Error() == "product not found or unauthorized" {
			http.Error(w, `{"error":"Product not found"}`, http.StatusNotFound)
		} else {
			http.Error(w, `{"error":"Failed to delete product"}`, http.StatusInternalServerError)
		}
		return
	}

	w.WriteHeader(http.StatusNoContent)
}
