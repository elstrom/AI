import logging
import logging.handlers
import os
from pathlib import Path
from datetime import datetime

def setup_logging(log_level=logging.INFO, log_dir=None, log_file_prefix="ai_system"):
    """
    Setup logging configuration for the AI system.
    
    Args:
        log_level: Logging level (default: logging.INFO)
        log_dir: Directory to store log files (default: logs/ in current directory)
        log_file_prefix: Prefix for log file names (default: "ai_system")
    """
    # Create log directory if not exists
    if log_dir is None:
        log_dir = Path("logs")
    else:
        log_dir = Path(log_dir)
    
    log_dir.mkdir(exist_ok=True)
    
    # Create logger
    logger = logging.getLogger()
    logger.setLevel(log_level)
    
    # Clear existing handlers
    logger.handlers.clear()
    
    # Create formatter
    formatter = logging.Formatter(
        '%(asctime)s - %(name)s - %(levelname)s - %(message)s',
        datefmt='%Y-%m-%d %H:%M:%S'
    )
    
    # Create console handler
    console_handler = logging.StreamHandler()
    console_handler.setLevel(log_level)
    console_handler.setFormatter(formatter)
    logger.addHandler(console_handler)
    
    # Create file handler with rotation
    timestamp = datetime.now().strftime("%Y%m%d_%H%M%S")
    log_file = log_dir / f"{log_file_prefix}_{timestamp}.log"
    
    file_handler = logging.handlers.RotatingFileHandler(
        log_file,
        maxBytes=10*1024*1024,  # 10 MB
        backupCount=5
    )
    file_handler.setLevel(log_level)
    file_handler.setFormatter(formatter)
    logger.addHandler(file_handler)
    
    # Create error file handler
    error_log_file = log_dir / f"{log_file_prefix}_errors_{timestamp}.log"
    error_file_handler = logging.handlers.RotatingFileHandler(
        error_log_file,
        maxBytes=5*1024*1024,  # 5 MB
        backupCount=3
    )
    error_file_handler.setLevel(logging.ERROR)
    error_file_handler.setFormatter(formatter)
    logger.addHandler(error_file_handler)
    
    # Log initialization
    logger.info(f"Logging initialized. Log file: {log_file}")
    
    return logger

def get_logger(name):
    """
    Get a logger with the specified name.
    
    Args:
        name: Name of the logger
        
    Returns:
        Logger instance
    """
    return logging.getLogger(name)