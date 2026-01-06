#!/usr/bin/env python3
import subprocess
import sys

def install_dependencies():
    """
    Install only the necessary dependencies used in this server project.
    Version numbers are omitted to install the latest versions.
    """
    dependencies = [
        "onnxruntime",       # AI model inference
        "grpcio",            # gRPC core
        "grpcio-tools",      # gRPC tools for proto generation
        "numpy",             # Numerical processing
        "opencv-python",     # Image processing (OpenCV)
        "pillow",            # Image processing (PIL)
        "PyTurboJPEG",       # High-performance JPEG decoding
        "psutil",            # Process and system utility monitoring
        "pyyaml",            # YAML configuration support
        "requests",          # HTTP client for health checks
        "websocket-client"   # WebSocket client for health checks
    ]

    print("🚀 Starting dependency installation...")
    print(f"📦 Packages to install: {', '.join(dependencies)}")
    print("-" * 50)

    for package in dependencies:
        print(f"📥 Installing {package}...")
        try:
            subprocess.check_call([sys.executable, "-m", "pip", "install", package])
            print(f"✅ {package} installed successfully.")
        except subprocess.CalledProcessError as e:
            print(f"❌ Failed to install {package}. Error: {e}")
            continue

    print("-" * 50)
    print("✨ Installation process completed!")
    print("💡 Tip: If you have an NVIDIA GPU, you might want to replace 'onnxruntime' with 'onnxruntime-gpu' for better performance.")

if __name__ == "__main__":
    install_dependencies()
