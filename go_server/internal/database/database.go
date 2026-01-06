package database

import (
	"database/sql"
	"encoding/json"
	"fmt"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

// DB represents a database connection
type DB struct {
	conn *sql.DB
}

// ============================================================
// MODELS
// ============================================================

// Category represents a product category
type Category struct {
	ID       int64  `json:"id"`
	UserID   int64  `json:"user_id"`
	Name     string `json:"name"`
	IsActive int    `json:"is_active"`
}

// Product represents a product in the database
type Product struct {
	ID         int64     `json:"id"`
	UserID     int64     `json:"user_id"`
	Name       string    `json:"name"`
	SKU        *string   `json:"sku,omitempty"`
	CategoryID int64     `json:"category_id"`
	Price      float64   `json:"price"`
	IsActive   int       `json:"is_active"`
	CreatedAt  time.Time `json:"created_at"`
	UpdatedAt  time.Time `json:"updated_at"`
}

// User represents a user in the database
type User struct {
	ID            int64      `json:"id"`
	Username      string     `json:"username"`
	PasswordHash  string     `json:"-"`
	DeviceID      *string    `json:"device_id,omitempty"`
	PlanType      string     `json:"plan_type"`
	PlanExpiredAt *time.Time `json:"plan_expired_at,omitempty"`
	CreatedAt     time.Time  `json:"created_at"`
}

// Transaction represents a transaction header
type Transaction struct {
	ID            int64     `json:"id"`
	Code          string    `json:"code"`
	Date          time.Time `json:"date"`
	Status        string    `json:"status"`
	Subtotal      float64   `json:"subtotal"`
	DiscountTotal float64   `json:"discount_total"`
	TaxTotal      float64   `json:"tax_total"`
	TotalAmount   float64   `json:"total_amount"`
	PaidAmount    float64   `json:"paid_amount"`
	ChangeAmount  float64   `json:"change_amount"`
	PaymentMethod string    `json:"payment_method"`
	UserID        *int64    `json:"user_id,omitempty"`
}

// UnmarshalJSON implements custom unmarshaling for Transaction to handle various time formats
func (t *Transaction) UnmarshalJSON(data []byte) error {
	type Alias Transaction
	aux := &struct {
		Date interface{} `json:"date"`
		*Alias
	}{
		Alias: (*Alias)(t),
	}

	if err := json.Unmarshal(data, &aux); err != nil {
		return err
	}

	switch v := aux.Date.(type) {
	case string:
		if v == "" {
			t.Date = time.Time{}
			return nil
		}
		// Try various formats
		formats := []string{
			time.RFC3339,
			"2006-01-02T15:04:05.999999",
			"2006-01-02 15:04:05",
			"2006-01-02T15:04:05",
		}
		var err error
		var parsed time.Time
		for _, f := range formats {
			parsed, err = time.Parse(f, strings.Trim(v, "\""))
			if err == nil {
				t.Date = parsed
				return nil
			}
		}
		return fmt.Errorf("failed to parse date %q: %w", v, err)
	case nil:
		t.Date = time.Time{}
		return nil
	default:
		// If it's already a time.Time (shouldn't happen with json.Unmarshal into interface{} but safe anyway)
		return nil
	}
}

// TransactionItem represents a transaction line item
type TransactionItem struct {
	ID            int64   `json:"id,omitempty"`
	TransactionID int64   `json:"transaction_id"`
	ProductID     *int64  `json:"product_id,omitempty"`
	ItemName      string  `json:"item_name"`
	Price         float64 `json:"price"`
	Qty           int     `json:"qty"`
	SubTotal      float64 `json:"sub_total"`
	Total         float64 `json:"total"`
}

// CashMovement represents a cash flow record
type CashMovement struct {
	ID            int64     `json:"id"`
	TransactionID int64     `json:"transaction_id"`
	Amount        float64   `json:"amount"`
	PaymentMethod string    `json:"payment_method"`
	CreatedAt     time.Time `json:"created_at"`
}

// StockSale represents stock deduction from a sale
type StockSale struct {
	ID            int64     `json:"id"`
	ProductID     int64     `json:"product_id"`
	TransactionID int64     `json:"transaction_id"`
	Qty           int       `json:"qty"`
	CreatedAt     time.Time `json:"created_at"`
}

// AIModel represents an AI model configuration
type AIModel struct {
	ID        int64     `json:"id"`
	Name      string    `json:"name"`
	Version   *string   `json:"version,omitempty"`
	Labels    string    `json:"labels"`
	IsActive  int       `json:"is_active"`
	CreatedAt time.Time `json:"created_at"`
}

// AuditLog represents an audit trail entry
type AuditLog struct {
	ID            int64     `json:"id"`
	UserID        *int64    `json:"user_id,omitempty"`
	Entity        string    `json:"entity"`
	Action        string    `json:"action"`
	ChangedFields *string   `json:"changed_fields,omitempty"`
	CreatedAt     time.Time `json:"created_at"`
}

// ============================================================
// DATABASE CONNECTION
// ============================================================

// NewDatabase creates a new database connection
func NewDatabase(dbPath string) (*DB, error) {
	conn, err := sql.Open("sqlite", dbPath)
	if err != nil {
		return nil, fmt.Errorf("failed to open database: %w", err)
	}

	// SQLite-specific optimizations for concurrency
	conn.SetMaxOpenConns(1) // Single writer, best for SQLite to avoid locking
	conn.SetMaxIdleConns(1)
	conn.SetConnMaxLifetime(time.Hour)

	if err := conn.Ping(); err != nil {
		return nil, fmt.Errorf("failed to ping database: %w", err)
	}

	// Enable foreign keys
	if _, err := conn.Exec("PRAGMA foreign_keys = ON"); err != nil {
		return nil, fmt.Errorf("failed to enable foreign keys: %w", err)
	}

	// Enable WAL (Write-Ahead Logging) mode
	if _, err := conn.Exec("PRAGMA journal_mode = WAL"); err != nil {
		return nil, fmt.Errorf("failed to enable WAL: %w", err)
	}

	// Set busy timeout to 5 seconds
	if _, err := conn.Exec("PRAGMA busy_timeout = 5000"); err != nil {
		return nil, fmt.Errorf("failed to set busy timeout: %w", err)
	}

	// Set synchronous to NORMAL for better performance with WAL
	if _, err := conn.Exec("PRAGMA synchronous = NORMAL"); err != nil {
		return nil, fmt.Errorf("failed to set synchronous mode: %w", err)
	}

	db := &DB{conn: conn}
	
	// Run migrations
	if err := db.MigrateSchemas(); err != nil {
		return nil, fmt.Errorf("failed to migrate schemas: %w", err)
	}

	return db, nil
}

// MigrateSchemas checks and updates database schema
func (db *DB) MigrateSchemas() error {
	// 1. Add user_id to categories
	var colCount int
	err := db.conn.QueryRow("SELECT count(*) FROM pragma_table_info('categories') WHERE name='user_id'").Scan(&colCount)
	if err != nil {
		// Table might not exist yet if fresh install, or other error.
		// If table doesn't exist, we skip migration as it will be created by other means?
		// No, usually tables are created by some init script. But seeing there is no CREATE TABLE here,
		// we assume tables exist. If error, we return it.
		// However, for robustness, if table doesn't exist, this query might fail or return 0.
		// Assuming tables exist as per previous context.
		return fmt.Errorf("failed to check categories schema: %w", err)
	}
	
	if colCount == 0 {
		// Add column
		if _, err := db.conn.Exec("ALTER TABLE categories ADD COLUMN user_id INTEGER DEFAULT 1"); err != nil {
			return fmt.Errorf("failed to add user_id to categories: %w", err)
		}
		// Update existing rows (redundant with DEFAULT but safe)
		if _, err := db.conn.Exec("UPDATE categories SET user_id = 1 WHERE user_id IS NULL"); err != nil {
			return fmt.Errorf("failed to update existing categories: %w", err)
		}
	}

	// 2. Add user_id to products
	err = db.conn.QueryRow("SELECT count(*) FROM pragma_table_info('products') WHERE name='user_id'").Scan(&colCount)
	if err != nil {
		return fmt.Errorf("failed to check products schema: %w", err)
	}
	
	if colCount == 0 {
		// Add column
		if _, err := db.conn.Exec("ALTER TABLE products ADD COLUMN user_id INTEGER DEFAULT 1"); err != nil {
			return fmt.Errorf("failed to add user_id to products: %w", err)
		}
		// Update existing rows
		if _, err := db.conn.Exec("UPDATE products SET user_id = 1 WHERE user_id IS NULL"); err != nil {
			return fmt.Errorf("failed to update existing products: %w", err)
		}
	}
	
	return nil
}

// Close closes the database connection
func (db *DB) Close() error {
	return db.conn.Close()
}

// ============================================================
// USER METHODS
// ============================================================

// GetUserByUsername retrieves a user by username
func (db *DB) GetUserByUsername(username string) (*User, error) {
	query := `SELECT id, username, password_hash, device_id, plan_type, plan_expired_at, created_at FROM users WHERE username = ?`
	row := db.conn.QueryRow(query, username)

	var user User
	var createdAtStr string
	var deviceID, planExpiredAt sql.NullString

	err := row.Scan(&user.ID, &user.Username, &user.PasswordHash, &deviceID, &user.PlanType, &planExpiredAt, &createdAtStr)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("failed to scan user: %w", err)
	}

	if deviceID.Valid {
		user.DeviceID = &deviceID.String
	}
	user.CreatedAt, _ = time.Parse("2006-01-02 15:04:05", createdAtStr)
	if planExpiredAt.Valid {
		t, _ := time.Parse("2006-01-02 15:04:05", planExpiredAt.String)
		user.PlanExpiredAt = &t
	}

	return &user, nil
}

// CreateUser creates a new user
func (db *DB) CreateUser(user *User) (int64, error) {
	query := `INSERT INTO users (username, password_hash, device_id, plan_type) VALUES (?, ?, ?, ?)`
	result, err := db.conn.Exec(query, user.Username, user.PasswordHash, user.DeviceID, user.PlanType)
	if err != nil {
		return 0, fmt.Errorf("failed to create user: %w", err)
	}
	return result.LastInsertId()
}

// ============================================================
// CATEGORY METHODS
// ============================================================

// GetAllCategories retrieves all active categories for a specific user
func (db *DB) GetAllCategories(userID int64) ([]Category, error) {
	query := `SELECT id, user_id, name, is_active FROM categories WHERE is_active = 1 AND (user_id = ? OR user_id = 1)`
	rows, err := db.conn.Query(query, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to query categories: %w", err)
	}
	defer rows.Close()

	var categories []Category
	for rows.Next() {
		var c Category
		if err := rows.Scan(&c.ID, &c.UserID, &c.Name, &c.IsActive); err != nil {
			return nil, fmt.Errorf("failed to scan category: %w", err)
		}
		categories = append(categories, c)
	}
	return categories, nil
}

// GetCategoryByID retrieves a category by ID and UserID (or admin)
func (db *DB) GetCategoryByID(id, userID int64) (*Category, error) {
	query := `SELECT id, user_id, name, is_active FROM categories WHERE id = ? AND (user_id = ? OR user_id = 1)`
	row := db.conn.QueryRow(query, id, userID)

	var c Category
	err := row.Scan(&c.ID, &c.UserID, &c.Name, &c.IsActive)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("failed to scan category: %w", err)
	}
	return &c, nil
}

// CreateCategory creates a new category
func (db *DB) CreateCategory(c *Category) (int64, error) {
	query := `INSERT INTO categories (user_id, name, is_active) VALUES (?, ?, ?)`
	result, err := db.conn.Exec(query, c.UserID, c.Name, 1)
	if err != nil {
		return 0, fmt.Errorf("failed to create category: %w", err)
	}
	return result.LastInsertId()
}

// UpdateCategory updates an existing category
func (db *DB) UpdateCategory(c *Category) error {
	query := `UPDATE categories SET name = ?, is_active = ? WHERE id = ? AND user_id = ?`
	result, err := db.conn.Exec(query, c.Name, c.IsActive, c.ID, c.UserID)
	if err != nil {
		return fmt.Errorf("failed to update category: %w", err)
	}
	rows, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if rows == 0 {
		return fmt.Errorf("category not found or unauthorized")
	}
	return nil
}

// DeleteCategory soft-deletes a category
func (db *DB) DeleteCategory(id, userID int64) error {
	query := `UPDATE categories SET is_active = 0 WHERE id = ? AND user_id = ?`
	result, err := db.conn.Exec(query, id, userID)
	if err != nil {
		return fmt.Errorf("failed to delete category: %w", err)
	}
	rows, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if rows == 0 {
		return fmt.Errorf("category not found or unauthorized")
	}
	return nil
}

// ============================================================
// PRODUCT METHODS
// ============================================================

// GetAllProducts retrieves all active products for a user
func (db *DB) GetAllProducts(userID int64) ([]Product, error) {
	query := `SELECT id, user_id, name, sku, category_id, price, is_active, created_at, updated_at FROM products WHERE is_active = 1 AND (user_id = ? OR user_id = 1)`
	rows, err := db.conn.Query(query, userID)
	if err != nil {
		return nil, fmt.Errorf("failed to query products: %w", err)
	}
	defer rows.Close()

	var products []Product
	for rows.Next() {
		var p Product
		var createdAtStr, updatedAtStr string
		var sku sql.NullString
		if err := rows.Scan(&p.ID, &p.UserID, &p.Name, &sku, &p.CategoryID, &p.Price, &p.IsActive, &createdAtStr, &updatedAtStr); err != nil {
			return nil, fmt.Errorf("failed to scan product: %w", err)
		}
		if sku.Valid {
			p.SKU = &sku.String
		}
		p.CreatedAt, _ = time.Parse("2006-01-02 15:04:05", createdAtStr)
		p.UpdatedAt, _ = time.Parse("2006-01-02 15:04:05", updatedAtStr)
		products = append(products, p)
	}
	return products, nil
}

// GetProductByID retrieves a product by ID
func (db *DB) GetProductByID(id, userID int64) (*Product, error) {
	query := `SELECT id, user_id, name, sku, category_id, price, is_active, created_at, updated_at FROM products WHERE id = ? AND (user_id = ? OR user_id = 1)`
	row := db.conn.QueryRow(query, id, userID)

	var p Product
	var createdAtStr, updatedAtStr string
	var sku sql.NullString
	err := row.Scan(&p.ID, &p.UserID, &p.Name, &sku, &p.CategoryID, &p.Price, &p.IsActive, &createdAtStr, &updatedAtStr)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("failed to scan product: %w", err)
	}
	if sku.Valid {
		p.SKU = &sku.String
	}
	p.CreatedAt, _ = time.Parse("2006-01-02 15:04:05", createdAtStr)
	p.UpdatedAt, _ = time.Parse("2006-01-02 15:04:05", updatedAtStr)
	return &p, nil
}

// GetProductByName retrieves a product by exact name
func (db *DB) GetProductByName(name string, userID int64) (*Product, error) {
	query := `SELECT id, user_id, name, sku, category_id, price, is_active, created_at, updated_at FROM products WHERE name = ? AND is_active = 1 AND (user_id = ? OR user_id = 1)`
	row := db.conn.QueryRow(query, name, userID)

	var p Product
	var createdAtStr, updatedAtStr string
	var sku sql.NullString
	err := row.Scan(&p.ID, &p.UserID, &p.Name, &sku, &p.CategoryID, &p.Price, &p.IsActive, &createdAtStr, &updatedAtStr)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("failed to scan product: %w", err)
	}
	if sku.Valid {
		p.SKU = &sku.String
	}
	p.CreatedAt, _ = time.Parse("2006-01-02 15:04:05", createdAtStr)
	p.UpdatedAt, _ = time.Parse("2006-01-02 15:04:05", updatedAtStr)
	return &p, nil
}

// SearchProductsByName searches products by name pattern
func (db *DB) SearchProductsByName(name string, userID int64) ([]Product, error) {
	query := `SELECT id, user_id, name, sku, category_id, price, is_active, created_at, updated_at FROM products WHERE name LIKE ? AND is_active = 1 AND (user_id = ? OR user_id = 1)`
	rows, err := db.conn.Query(query, "%"+name+"%", userID)
	if err != nil {
		return nil, fmt.Errorf("failed to search products: %w", err)
	}
	defer rows.Close()

	var products []Product
	for rows.Next() {
		var p Product
		var createdAtStr, updatedAtStr string
		var sku sql.NullString
		if err := rows.Scan(&p.ID, &p.UserID, &p.Name, &sku, &p.CategoryID, &p.Price, &p.IsActive, &createdAtStr, &updatedAtStr); err != nil {
			return nil, fmt.Errorf("failed to scan product: %w", err)
		}
		if sku.Valid {
			p.SKU = &sku.String
		}
		p.CreatedAt, _ = time.Parse("2006-01-02 15:04:05", createdAtStr)
		p.UpdatedAt, _ = time.Parse("2006-01-02 15:04:05", updatedAtStr)
		products = append(products, p)
	}
	return products, nil
}

// CreateProduct creates a new product
func (db *DB) CreateProduct(p *Product) (int64, error) {
	query := `INSERT INTO products (user_id, name, sku, category_id, price, is_active, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?)`
	now := time.Now().Format("2006-01-02 15:04:05")
	result, err := db.conn.Exec(query, p.UserID, p.Name, p.SKU, p.CategoryID, p.Price, 1, now, now)
	if err != nil {
		return 0, fmt.Errorf("failed to create product: %w", err)
	}
	return result.LastInsertId()
}

// UpdateProduct updates an existing product
func (db *DB) UpdateProduct(p *Product) error {
	query := `UPDATE products SET name = ?, sku = ?, category_id = ?, price = ?, is_active = ?, updated_at = ? WHERE id = ? AND user_id = ?`
	now := time.Now().Format("2006-01-02 15:04:05")
	result, err := db.conn.Exec(query, p.Name, p.SKU, p.CategoryID, p.Price, p.IsActive, now, p.ID, p.UserID)
	if err != nil {
		return fmt.Errorf("failed to update product: %w", err)
	}
	rows, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if rows == 0 {
		return fmt.Errorf("product not found or unauthorized")
	}
	return nil
}

// DeleteProduct soft-deletes a product
func (db *DB) DeleteProduct(id, userID int64) error {
	query := `UPDATE products SET is_active = 0, updated_at = ? WHERE id = ? AND user_id = ?`
	now := time.Now().Format("2006-01-02 15:04:05")
	result, err := db.conn.Exec(query, now, id, userID)
	if err != nil {
		return fmt.Errorf("failed to delete product: %w", err)
	}
	rows, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if rows == 0 {
		return fmt.Errorf("product not found or unauthorized")
	}
	return nil
}

// ============================================================
// TRANSACTION METHODS
// ============================================================

// generateTransactionCode generates a unique transaction code
func (db *DB) generateTransactionCode() string {
	now := time.Now()
	return fmt.Sprintf("TRX%s%03d", now.Format("20060102150405"), now.Nanosecond()%1000)
}

// GetAllTransactions retrieves all transactions
func (db *DB) GetAllTransactions() ([]Transaction, error) {
	query := `SELECT id, code, date, status, subtotal, discount_total, tax_total, total_amount, paid_amount, change_amount, payment_method, user_id 
			  FROM transactions ORDER BY date DESC`
	rows, err := db.conn.Query(query)
	if err != nil {
		return nil, fmt.Errorf("failed to query transactions: %w", err)
	}
	defer rows.Close()

	var transactions []Transaction
	for rows.Next() {
		var t Transaction
		var dateStr string
		var userID sql.NullInt64
		if err := rows.Scan(&t.ID, &t.Code, &dateStr, &t.Status, &t.Subtotal, &t.DiscountTotal, &t.TaxTotal, &t.TotalAmount, &t.PaidAmount, &t.ChangeAmount, &t.PaymentMethod, &userID); err != nil {
			return nil, fmt.Errorf("failed to scan transaction: %w", err)
		}
		t.Date, _ = time.Parse("2006-01-02 15:04:05", dateStr)
		if userID.Valid {
			t.UserID = &userID.Int64
		}
		transactions = append(transactions, t)
	}
	return transactions, nil
}

// GetTransactionsByDateRange retrieves transactions within a date range
func (db *DB) GetTransactionsByDateRange(startDate, endDate string) ([]Transaction, error) {
	query := `SELECT id, code, date, status, subtotal, discount_total, tax_total, total_amount, paid_amount, change_amount, payment_method, user_id 
			  FROM transactions WHERE date BETWEEN ? AND ? ORDER BY date DESC`
	rows, err := db.conn.Query(query, startDate, endDate)
	if err != nil {
		return nil, fmt.Errorf("failed to query transactions: %w", err)
	}
	defer rows.Close()

	var transactions []Transaction
	for rows.Next() {
		var t Transaction
		var dateStr string
		var userID sql.NullInt64
		if err := rows.Scan(&t.ID, &t.Code, &dateStr, &t.Status, &t.Subtotal, &t.DiscountTotal, &t.TaxTotal, &t.TotalAmount, &t.PaidAmount, &t.ChangeAmount, &t.PaymentMethod, &userID); err != nil {
			return nil, fmt.Errorf("failed to scan transaction: %w", err)
		}
		t.Date, _ = time.Parse("2006-01-02 15:04:05", dateStr)
		if userID.Valid {
			t.UserID = &userID.Int64
		}
		transactions = append(transactions, t)
	}
	return transactions, nil
}

// GetTransactionByID retrieves a transaction by ID
func (db *DB) GetTransactionByID(txID int64) (*Transaction, error) {
	query := `SELECT id, code, date, status, subtotal, discount_total, tax_total, total_amount, paid_amount, change_amount, payment_method, user_id 
			  FROM transactions WHERE id = ?`
	row := db.conn.QueryRow(query, txID)

	var t Transaction
	var dateStr string
	var userID sql.NullInt64
	err := row.Scan(&t.ID, &t.Code, &dateStr, &t.Status, &t.Subtotal, &t.DiscountTotal, &t.TaxTotal, &t.TotalAmount, &t.PaidAmount, &t.ChangeAmount, &t.PaymentMethod, &userID)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, fmt.Errorf("failed to scan transaction: %w", err)
	}
	t.Date, _ = time.Parse("2006-01-02 15:04:05", dateStr)
	if userID.Valid {
		t.UserID = &userID.Int64
	}
	return &t, nil
}

// GetTransactionItems retrieves items for a transaction
func (db *DB) GetTransactionItems(txID int64) ([]TransactionItem, error) {
	query := `SELECT id, transaction_id, product_id, item_name, price, qty, sub_total, total FROM transaction_items WHERE transaction_id = ?`
	rows, err := db.conn.Query(query, txID)
	if err != nil {
		return nil, fmt.Errorf("failed to query transaction items: %w", err)
	}
	defer rows.Close()

	var items []TransactionItem
	for rows.Next() {
		var item TransactionItem
		var productID sql.NullInt64
		if err := rows.Scan(&item.ID, &item.TransactionID, &productID, &item.ItemName, &item.Price, &item.Qty, &item.SubTotal, &item.Total); err != nil {
			return nil, fmt.Errorf("failed to scan transaction item: %w", err)
		}
		if productID.Valid {
			item.ProductID = &productID.Int64
		}
		items = append(items, item)
	}
	return items, nil
}

// CreateTransaction creates a new transaction with items
func (db *DB) CreateTransaction(header *Transaction, items []TransactionItem) error {
	tx, err := db.conn.Begin()
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	// Generate transaction code
	header.Code = db.generateTransactionCode()
	txDate := header.Date
	if txDate.IsZero() {
		txDate = time.Now()
	}

	// Insert transaction header
	headerQuery := `INSERT INTO transactions (code, date, status, subtotal, discount_total, tax_total, total_amount, paid_amount, change_amount, payment_method, user_id) 
					VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)`
	result, err := tx.Exec(headerQuery, header.Code, txDate.Format("2006-01-02 15:04:05"), "COMPLETED", header.Subtotal, header.DiscountTotal, header.TaxTotal, header.TotalAmount, header.PaidAmount, header.ChangeAmount, header.PaymentMethod, header.UserID)
	if err != nil {
		return fmt.Errorf("failed to insert transaction header: %w", err)
	}

	transactionID, err := result.LastInsertId()
	if err != nil {
		return fmt.Errorf("failed to get transaction ID: %w", err)
	}
	header.ID = transactionID

	// Insert transaction items
	itemQuery := `INSERT INTO transaction_items (transaction_id, product_id, item_name, price, qty, sub_total, total) VALUES (?, ?, ?, ?, ?, ?, ?)`
	for _, item := range items {
		_, err = tx.Exec(itemQuery, transactionID, item.ProductID, item.ItemName, item.Price, item.Qty, item.SubTotal, item.Total)
		if err != nil {
			return fmt.Errorf("failed to insert transaction item: %w", err)
		}

		// Record stock sale if product_id exists
		if item.ProductID != nil {
			stockQuery := `INSERT INTO stock_sales (product_id, transaction_id, qty) VALUES (?, ?, ?)`
			_, err = tx.Exec(stockQuery, *item.ProductID, transactionID, item.Qty)
			if err != nil {
				return fmt.Errorf("failed to insert stock sale: %w", err)
			}
		}
	}

	// Record cash movement
	cashQuery := `INSERT INTO cash_movements (transaction_id, amount, payment_method) VALUES (?, ?, ?)`
	_, err = tx.Exec(cashQuery, transactionID, header.TotalAmount, header.PaymentMethod)
	if err != nil {
		return fmt.Errorf("failed to insert cash movement: %w", err)
	}

	return tx.Commit()
}

// CancelTransaction cancels a transaction and reverts all related records
func (db *DB) CancelTransaction(txID int64, userID *int64) error {
	tx, err := db.conn.Begin()
	if err != nil {
		return fmt.Errorf("failed to begin transaction: %w", err)
	}
	defer tx.Rollback()

	// Get transaction to verify it exists and is not already cancelled
	var status string
	err = tx.QueryRow("SELECT status FROM transactions WHERE id = ?", txID).Scan(&status)
	if err == sql.ErrNoRows {
		return fmt.Errorf("transaction not found")
	}
	if err != nil {
		return fmt.Errorf("failed to get transaction: %w", err)
	}
	if status == "CANCELLED" {
		return fmt.Errorf("transaction already cancelled")
	}

	// Delete cash movements
	_, err = tx.Exec("DELETE FROM cash_movements WHERE transaction_id = ?", txID)
	if err != nil {
		return fmt.Errorf("failed to delete cash movements: %w", err)
	}

	// Delete stock sales
	_, err = tx.Exec("DELETE FROM stock_sales WHERE transaction_id = ?", txID)
	if err != nil {
		return fmt.Errorf("failed to delete stock sales: %w", err)
	}

	// Update transaction status
	_, err = tx.Exec("UPDATE transactions SET status = 'CANCELLED' WHERE id = ?", txID)
	if err != nil {
		return fmt.Errorf("failed to update transaction status: %w", err)
	}

	// Log the cancellation
	auditQuery := `INSERT INTO audit_logs (user_id, entity, action, changed_fields) VALUES (?, ?, ?, ?)`
	changedFields := fmt.Sprintf(`{"transaction_id":%d,"previous_status":"%s"}`, txID, status)
	_, err = tx.Exec(auditQuery, userID, "transactions", "CANCEL", changedFields)
	if err != nil {
		return fmt.Errorf("failed to insert audit log: %w", err)
	}

	return tx.Commit()
}

// ============================================================
// AUDIT LOG METHODS
// ============================================================

// LogAudit creates an audit log entry
func (db *DB) LogAudit(userID *int64, entity, action, changedFields string) error {
	query := `INSERT INTO audit_logs (user_id, entity, action, changed_fields) VALUES (?, ?, ?, ?)`
	_, err := db.conn.Exec(query, userID, entity, action, changedFields)
	if err != nil {
		return fmt.Errorf("failed to insert audit log: %w", err)
	}
	return nil
}

// LogScan logs an AI scan event
func (db *DB) LogScan(userID int64, deviceID, sessionID string, frameSeq, detectionCount int, status string) error {
	query := `INSERT INTO scans (user_id, device_id, session_id, frame_seq, detection_count, status) VALUES (?, ?, ?, ?, ?, ?)`
	var uID *int64
	if userID > 0 {
		uID = &userID
	}
	_, err := db.conn.Exec(query, uID, deviceID, sessionID, frameSeq, detectionCount, status)
	if err != nil {
		return fmt.Errorf("failed to insert scan log: %w", err)
	}
	return nil
}
