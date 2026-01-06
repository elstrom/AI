#!/usr/bin/env python3
"""
Main entry point for the AI System.
"""

import logging
import signal
import sys
from pathlib import Path

# Add the ai_system package to the path
sys.path.insert(0, str(Path(__file__).parent))

from ai_system.logging_config import setup_logging
from ai_system.grpc_server import serve
from ai_system.config_manager import ConfigurationManager

def signal_handler(sig, frame):
    """Handle interrupt signal."""
    print("\nShutting down server...")
    sys.exit(0)

def main():
    """Main function to start the AI system."""
    # Set up signal handler
    signal.signal(signal.SIGINT, signal_handler)
    
    # Configuration file path
    config_path = Path("config.json")
    
    # Initialize configuration manager
    config_manager = ConfigurationManager(
        config_path=config_path,
        enable_hot_reload=True
    )
    
    # Set up logging
    log_level = getattr(logging, config_manager.get('logging.level', 'INFO'))
    log_dir = config_manager.get('logging.directory', 'logs')
    setup_logging(log_level=log_level, log_dir=log_dir)
    logger = logging.getLogger(__name__)
    
    # Check if model exists
    model_path = Path(config_manager.get('model.path', 'Model_train/best.onnx'))
    if not model_path.exists():
        logger.error(f"Model file not found: {model_path}")
        sys.exit(1)
    
    # Log startup information
    logger.info("Starting AI System with Object Pooling, TurboJPEG Decoder, and Direct Inference")
    logger.info(f"Configuration: {config_path}")
    logger.info(f"Hot reload: {'enabled' if config_manager.get('hot_reload.enabled', True) else 'disabled'}")
    logger.info(f"TurboJPEG: {'enabled' if config_manager.get('decoder.use_turbojpeg', True) else 'disabled'}")
    logger.info(f"Direct inference: {'enabled' if config_manager.get('grpc.direct_inference', True) else 'disabled'}")
    
    try:
        # Start the gRPC server
        serve(config_manager)
    except KeyboardInterrupt:
        logger.info("Server stopped by user")
    except Exception as e:
        logger.error(f"Server error: {e}")
        sys.exit(1)
    finally:
        # Shutdown configuration manager
        config_manager.shutdown()

if __name__ == "__main__":
    main()