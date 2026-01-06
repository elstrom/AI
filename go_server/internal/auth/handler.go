package auth

import (
	"encoding/json"
	"net/http"
	"time"

	"github.com/golang-jwt/jwt/v5"
	"go_server/internal/database"
	"go_server/internal/logging"
	"golang.org/x/crypto/bcrypt"
)

type LoginRequest struct {
	Username string `json:"username"`
	Password string `json:"password"`
	DeviceID string `json:"device_id"`
}

type LoginResponse struct {
	Token    string `json:"token"`
	UserID   int64  `json:"user_id"`
	Username string `json:"username"`
	PlanType string `json:"plan_type"`
	Message  string `json:"message"`
}

type Claims struct {
	UserID   int64  `json:"user_id"`
	Username string `json:"username"`
	DeviceID string `json:"device_id"`
	PlanType string `json:"plan_type"`
	jwt.RegisteredClaims
}

type Handler struct {
	db        *database.DB
	secretKey []byte
	logger    *logging.Logger
}

func NewHandler(db *database.DB, secretKey string, logger *logging.Logger) *Handler {
	return &Handler{
		db:        db,
		secretKey: []byte(secretKey),
		logger:    logger,
	}
}

func (h *Handler) GetSecretKey() []byte {
	return h.secretKey
}

func (h *Handler) Login(w http.ResponseWriter, r *http.Request) {
	w.Header().Set("Content-Type", "application/json")
	w.Header().Set("Access-Control-Allow-Origin", "*")
	w.Header().Set("Access-Control-Allow-Methods", "POST, OPTIONS")
	w.Header().Set("Access-Control-Allow-Headers", "Content-Type, Authorization")

	if r.Method == http.MethodOptions {
		w.WriteHeader(http.StatusOK)
		return
	}

	if r.Method != http.MethodPost {
		http.Error(w, `{"error":"Method not allowed"}`, http.StatusMethodNotAllowed)
		return
	}

	var req LoginRequest
	if err := json.NewDecoder(r.Body).Decode(&req); err != nil {
		http.Error(w, `{"error":"Invalid request body"}`, http.StatusBadRequest)
		return
	}

	// Get user
	user, err := h.db.GetUserByUsername(req.Username)
	if err != nil {
		h.logger.WithField("error", err).Error("Login: Database error looking up user")
		http.Error(w, `{"error":"Database error"}`, http.StatusInternalServerError)
		return
	}
	if user == nil {
		h.logger.WithField("username", req.Username).Warn("Login: User not found")
		http.Error(w, `{"error":"Invalid credentials"}`, http.StatusUnauthorized)
		return
	}

	// Verify password
	err = bcrypt.CompareHashAndPassword([]byte(user.PasswordHash), []byte(req.Password))
	if err != nil {
		h.logger.WithFields(map[string]interface{}{
			"username": req.Username,
			"reason": "Password mismatch",
		}).Warn("Login failed")
		http.Error(w, `{"error":"Invalid credentials"}`, http.StatusUnauthorized)
		return
	}

	h.logger.WithField("username", req.Username).Info("User logged in successfully")

	// Check plan expiration
	if user.PlanExpiredAt != nil && user.PlanExpiredAt.Before(time.Now()) {
		user.PlanType = "expired"
	}

	// Create Token
	expirationTime := time.Now().Add(24 * time.Hour)
	claims := &Claims{
		UserID:   user.ID,
		Username: user.Username,
		DeviceID: req.DeviceID,
		PlanType: user.PlanType,
		RegisteredClaims: jwt.RegisteredClaims{
			ExpiresAt: jwt.NewNumericDate(expirationTime),
			Issuer:    "scanai-server",
		},
	}

	token := jwt.NewWithClaims(jwt.SigningMethodHS256, claims)
	tokenString, err := token.SignedString(h.secretKey)
	if err != nil {
		http.Error(w, `{"error":"Could not generate token"}`, http.StatusInternalServerError)
		return
	}

	resp := LoginResponse{
		Token:    tokenString,
		UserID:   user.ID,
		Username: user.Username,
		PlanType: user.PlanType,
		Message:  "Login successful",
	}

	json.NewEncoder(w).Encode(resp)
}
