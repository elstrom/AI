"""
config.py - Configuration module for ScanAI Database Manager UI

Cross-platform configuration with auto-detection of database path.
"""

import os
import json

# Auto-detect script directory for cross-platform compatibility
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
CONFIG_FILE = os.path.join(SCRIPT_DIR, "ui_config.json")

# Default configuration
DEFAULT_CONFIG = {
    "database": {
        # Relative path from sqlUI folder to database
        "path": os.path.normpath(os.path.join(SCRIPT_DIR, "..", "scanai.db")),
        "recent_connections": []
    },
    "ui": {
        "window_width": 1200,
        "window_height": 800,
        "theme": "default",
        "font_family": "Consolas",
        "font_size": 10,
        "rows_per_page": 50,
        "tail_rows": 10
    },
    "export": {
        "default_format": "txt",
        "include_headers": True,
        "delimiter": "\t"
    }
}


class Config:
    """Configuration manager for the Database UI."""
    
    _instance = None
    _config = None
    
    def __new__(cls):
        if cls._instance is None:
            cls._instance = super().__new__(cls)
            cls._instance._load_config()
        return cls._instance
    
    def _load_config(self):
        """Load configuration from file or create default."""
        if os.path.exists(CONFIG_FILE):
            try:
                with open(CONFIG_FILE, 'r', encoding='utf-8') as f:
                    self._config = json.load(f)
                # Merge with defaults for any missing keys
                self._config = self._merge_defaults(self._config, DEFAULT_CONFIG)
            except Exception as e:
                print(f"Warning: Could not load config file: {e}")
                self._config = DEFAULT_CONFIG.copy()
        else:
            self._config = DEFAULT_CONFIG.copy()
            self._save_config()
    
    def _merge_defaults(self, config, defaults):
        """Recursively merge config with defaults."""
        result = defaults.copy()
        for key, value in config.items():
            if key in result and isinstance(result[key], dict) and isinstance(value, dict):
                result[key] = self._merge_defaults(value, result[key])
            else:
                result[key] = value
        return result
    
    def _save_config(self):
        """Save configuration to file."""
        try:
            with open(CONFIG_FILE, 'w', encoding='utf-8') as f:
                json.dump(self._config, f, indent=2, ensure_ascii=False)
        except Exception as e:
            print(f"Warning: Could not save config file: {e}")
    
    @property
    def db_path(self):
        """Get database path."""
        return self._config["database"]["path"]
    
    @db_path.setter
    def db_path(self, value):
        """Set database path."""
        self._config["database"]["path"] = value
        self._save_config()
    
    @property
    def window_size(self):
        """Get window size as tuple (width, height)."""
        ui = self._config["ui"]
        return (ui["window_width"], ui["window_height"])
    
    @property
    def font(self):
        """Get font settings as tuple (family, size)."""
        ui = self._config["ui"]
        return (ui["font_family"], ui["font_size"])
    
    @property
    def rows_per_page(self):
        """Get rows per page for pagination."""
        return self._config["ui"]["rows_per_page"]
    
    @property
    def tail_rows(self):
        """Get number of rows for tail view."""
        return self._config["ui"]["tail_rows"]
    
    @tail_rows.setter
    def tail_rows(self, value):
        """Set number of rows for tail view."""
        self._config["ui"]["tail_rows"] = value
        self._save_config()
    
    def add_recent_connection(self, path):
        """Add a path to recent connections."""
        recent = self._config["database"]["recent_connections"]
        if path in recent:
            recent.remove(path)
        recent.insert(0, path)
        # Keep only last 5
        self._config["database"]["recent_connections"] = recent[:5]
        self._save_config()
    
    @property
    def recent_connections(self):
        """Get recent database connections."""
        return self._config["database"]["recent_connections"]
    
    def get(self, section, key, default=None):
        """Get a config value."""
        try:
            return self._config[section][key]
        except KeyError:
            return default
    
    def set(self, section, key, value):
        """Set a config value."""
        if section not in self._config:
            self._config[section] = {}
        self._config[section][key] = value
        self._save_config()


# Singleton instance
config = Config()
