.PHONY: build run clean test deps

# Build variables
BINARY_NAME=go_server
MAIN_PATH=./cmd/server/main.go
CONFIG_PATH=./config.yaml

# Default target
all: deps build

# Install dependencies
deps:
	go mod tidy
	go mod download

# Build the binary
build:
	go build -o $(BINARY_NAME) $(MAIN_PATH)

# Run the server
run:
	go run $(MAIN_PATH) -config $(CONFIG_PATH)

# Run the server with hot reload
dev:
	air -c .air.toml

# Clean build artifacts
clean:
	go clean
	rm -f $(BINARY_NAME)

# Run tests
test:
	go test -v ./...

# Run tests with coverage
test-coverage:
	go test -v -cover ./...

# Generate protobuf files
proto:
	protoc --go_out=. --go-grpc_out=. proto/*.proto

# Install air for hot reload
install-air:
	go install github.com/cosmtrek/air@latest

# Build for Linux
build-linux:
	CGO_ENABLED=0 GOOS=linux go build -o $(BINARY_NAME)-linux $(MAIN_PATH)

# Build for Windows
build-windows:
	CGO_ENABLED=0 GOOS=windows go build -o $(BINARY_NAME).exe $(MAIN_PATH)

# Build for macOS
build-macos:
	CGO_ENABLED=0 GOOS=darwin go build -o $(BINARY_NAME)-macos $(MAIN_PATH)

# Build for all platforms
build-all: build-linux build-windows build-macos

# Docker build
docker-build:
	docker build -t $(BINARY_NAME) .

# Docker run
docker-run:
	docker run -p 8080:8080 -v $(PWD)/config.yaml:/app/config.yaml $(BINARY_NAME)

# Format code
fmt:
	go fmt ./...

# Vet code
vet:
	go vet ./...

# Lint code
lint:
	golangci-lint run

# Security check
sec:
	gosec ./...

# Help
help:
	@echo "Available targets:"
	@echo "  all          - Install dependencies and build"
	@echo "  deps         - Install dependencies"
	@echo "  build        - Build the binary"
	@echo "  run          - Run the server"
	@echo "  dev          - Run the server with hot reload"
	@echo "  clean        - Clean build artifacts"
	@echo "  test         - Run tests"
	@echo "  test-coverage- Run tests with coverage"
	@echo "  proto        - Generate protobuf files"
	@echo "  install-air  - Install air for hot reload"
	@echo "  build-linux  - Build for Linux"
	@echo "  build-windows- Build for Windows"
	@echo "  build-macos  - Build for macOS"
	@echo "  build-all    - Build for all platforms"
	@echo "  docker-build - Build Docker image"
	@echo "  docker-run   - Run Docker container"
	@echo "  fmt          - Format code"
	@echo "  vet          - Vet code"
	@echo "  lint         - Lint code"
	@echo "  sec          - Security check"
	@echo "  help         - Show this help message"