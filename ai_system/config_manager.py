import logging
import os
import json
import yaml
from typing import Dict, Any, Optional, Union, Callable
from pathlib import Path
from threading import Lock
import time
import threading


class ConfigurationManager:
    """
    Centralized Configuration Manager for managing system configuration.
    Supports loading from JSON/YAML files, validation, hot reload, and logging.
    """
    
    def __init__(self, 
                 config_path: Optional[Union[str, Path]] = None,
                 default_config: Optional[Dict[str, Any]] = None,
                 enable_hot_reload: bool = True,
                 hot_reload_interval: float = 5.0):
        """
        Initialize ConfigurationManager.
        
        Args:
            config_path: Path to configuration file (JSON/YAML)
            default_config: Default configuration values
            enable_hot_reload: Whether to enable hot reload of configuration
            hot_reload_interval: Interval in seconds for checking configuration changes
        """
        self._logger = logging.getLogger(__name__)
        self._config_path = Path(config_path) if config_path else None
        self._config: Dict[str, Any] = default_config or {}
        self._enable_hot_reload = enable_hot_reload
        self._hot_reload_interval = hot_reload_interval
        self._config_lock = Lock()
        self._last_modified = 0
        self._validation_schema: Optional[Dict[str, Any]] = None
        self._validation_callback: Optional[Callable[[Dict[str, Any]], bool]] = None
        self._config_change_callbacks: list = []
        self._hot_reload_thread: Optional[threading.Thread] = None
        self._shutdown_flag = False
        
        # Load initial configuration
        if self._config_path and self._config_path.exists():
            self._load_config()
        
        # Start hot reload if enabled
        if self._enable_hot_reload:
            self._start_hot_reload()
        
        self._logger.info("ConfigurationManager initialized")
    
    def _load_config(self) -> None:
        """
        Load configuration from file.
        """
        if not self._config_path or not self._config_path.exists():
            self._logger.warning(f"Configuration file not found: {self._config_path}")
            return
        
        try:
            with self._config_lock:
                # Get last modified time
                last_modified = self._config_path.stat().st_mtime
                
                # Skip if file hasn't been modified
                if last_modified <= self._last_modified:
                    return
                
                # Load configuration based on file extension
                file_ext = self._config_path.suffix.lower()
                
                with open(self._config_path, 'r') as f:
                    if file_ext == '.json':
                        new_config = json.load(f)
                    elif file_ext in ['.yaml', '.yml']:
                        new_config = yaml.safe_load(f)
                    else:
                        raise ValueError(f"Unsupported configuration file format: {file_ext}")
                
                # Validate configuration if validation is set up
                if self._validation_schema or self._validation_callback:
                    if not self._validate_config(new_config):
                        self._logger.error("Configuration validation failed")
                        return
                
                # Update configuration
                old_config = self._config.copy()
                self._config.update(new_config)
                self._last_modified = last_modified
                
                # Log configuration change
                self._logger.info(f"Configuration loaded from {self._config_path}")
                
                # Notify callbacks
                self._notify_config_change_callbacks(old_config, self._config)
                
        except Exception as e:
            self._logger.error(f"Error loading configuration: {e}")
    
    def _validate_config(self, config: Dict[str, Any]) -> bool:
        """
        Validate configuration against schema or using custom validation callback.
        
        Args:
            config: Configuration to validate
            
        Returns:
            True if valid, False otherwise
        """
        # Custom validation callback takes precedence
        if self._validation_callback:
            try:
                return self._validation_callback(config)
            except Exception as e:
                self._logger.error(f"Configuration validation callback error: {e}")
                return False
        
        # Schema-based validation (basic implementation)
        if self._validation_schema:
            try:
                # This is a simple implementation - in a real-world scenario,
                # you might want to use a proper schema validation library
                for key, schema in self._validation_schema.items():
                    if key in config:
                        value = config[key]
                        expected_type = schema.get('type')
                        required = schema.get('required', False)
                        
                        if required and value is None:
                            self._logger.error(f"Required configuration key missing: {key}")
                            return False
                        
                        if expected_type and not isinstance(value, expected_type):
                            self._logger.error(f"Configuration key {key} should be {expected_type}, got {type(value)}")
                            return False
                
                return True
            except Exception as e:
                self._logger.error(f"Configuration schema validation error: {e}")
                return False
        
        # No validation, assume valid
        return True
    
    def _notify_config_change_callbacks(self, old_config: Dict[str, Any], new_config: Dict[str, Any]) -> None:
        """
        Notify all registered callbacks about configuration changes.
        
        Args:
            old_config: Old configuration
            new_config: New configuration
        """
        for callback in self._config_change_callbacks:
            try:
                callback(old_config, new_config)
            except Exception as e:
                self._logger.error(f"Error in configuration change callback: {e}")
    
    def _start_hot_reload(self) -> None:
        """
        Start hot reload thread.
        """
        if self._hot_reload_thread and self._hot_reload_thread.is_alive():
            return
        
        self._shutdown_flag = False
        self._hot_reload_thread = threading.Thread(target=self._hot_reload_loop, daemon=True)
        self._hot_reload_thread.start()
        self._logger.info("Hot reload thread started")
    
    def _hot_reload_loop(self) -> None:
        """
        Hot reload loop that periodically checks for configuration changes.
        """
        while not self._shutdown_flag:
            try:
                self._load_config()
                time.sleep(self._hot_reload_interval)
            except Exception as e:
                self._logger.error(f"Error in hot reload loop: {e}")
                time.sleep(self._hot_reload_interval)
    
    def _stop_hot_reload(self) -> None:
        """
        Stop hot reload thread.
        """
        self._shutdown_flag = True
        if self._hot_reload_thread and self._hot_reload_thread.is_alive():
            self._hot_reload_thread.join(timeout=2.0)
        self._logger.info("Hot reload thread stopped")
    
    def get(self, key: str, default: Any = None) -> Any:
        """
        Get configuration value by key.
        
        Args:
            key: Configuration key (supports dot notation, e.g., 'thread_pool.max_workers')
            default: Default value if key not found
            
        Returns:
            Configuration value or default
        """
        with self._config_lock:
            keys = key.split('.')
            value = self._config
            
            for k in keys:
                if isinstance(value, dict) and k in value:
                    value = value[k]
                else:
                    return default
            
            return value
    
    def set(self, key: str, value: Any, persist: bool = False) -> None:
        """
        Set configuration value.
        
        Args:
            key: Configuration key (supports dot notation)
            value: Configuration value
            persist: Whether to persist the change to file
        """
        with self._config_lock:
            keys = key.split('.')
            config = self._config
            
            # Navigate to parent of the target key
            for k in keys[:-1]:
                if k not in config:
                    config[k] = {}
                config = config[k]
            
            # Get old value for logging
            old_value = config.get(keys[-1])
            
            # Set new value
            config[keys[-1]] = value
            
            # Log change
            self._logger.info(f"Configuration changed: {key} = {value} (was: {old_value})")
            
            # Persist to file if requested
            if persist and self._config_path:
                self._save_config()
            
            # Notify callbacks
            self._notify_config_change_callbacks(
                {key: old_value}, 
                {key: value}
            )
    
    def _save_config(self) -> None:
        """
        Save current configuration to file.
        """
        if not self._config_path:
            self._logger.warning("No configuration file path set, cannot save configuration")
            return
        
        try:
            # Create directory if it doesn't exist
            self._config_path.parent.mkdir(parents=True, exist_ok=True)
            
            # Save based on file extension
            file_ext = self._config_path.suffix.lower()
            
            with open(self._config_path, 'w') as f:
                if file_ext == '.json':
                    json.dump(self._config, f, indent=2)
                elif file_ext in ['.yaml', '.yml']:
                    yaml.dump(self._config, f, default_flow_style=False)
                else:
                    raise ValueError(f"Unsupported configuration file format: {file_ext}")
            
            # Update last modified time
            self._last_modified = self._config_path.stat().st_mtime
            
            self._logger.info(f"Configuration saved to {self._config_path}")
        except Exception as e:
            self._logger.error(f"Error saving configuration: {e}")
    
    def get_all(self) -> Dict[str, Any]:
        """
        Get a copy of the entire configuration.
        
        Returns:
            Copy of the configuration dictionary
        """
        with self._config_lock:
            return self._config.copy()
    
    def set_validation_schema(self, schema: Dict[str, Any]) -> None:
        """
        Set configuration validation schema.
        
        Args:
            schema: Validation schema dictionary
        """
        self._validation_schema = schema
        self._logger.info("Configuration validation schema set")
    
    def set_validation_callback(self, callback: Callable[[Dict[str, Any]], bool]) -> None:
        """
        Set custom configuration validation callback.
        
        Args:
            callback: Validation callback function
        """
        self._validation_callback = callback
        self._logger.info("Configuration validation callback set")
    
    def add_config_change_callback(self, callback: Callable[[Dict[str, Any], Dict[str, Any]], None]) -> None:
        """
        Add callback to be called when configuration changes.
        
        Args:
            callback: Callback function that takes old_config and new_config
        """
        self._config_change_callbacks.append(callback)
        self._logger.info("Configuration change callback added")
    
    def remove_config_change_callback(self, callback: Callable[[Dict[str, Any], Dict[str, Any]], None]) -> None:
        """
        Remove configuration change callback.
        
        Args:
            callback: Callback function to remove
        """
        if callback in self._config_change_callbacks:
            self._config_change_callbacks.remove(callback)
            self._logger.info("Configuration change callback removed")
    
    def reload(self) -> None:
        """
        Manually reload configuration from file.
        """
        self._load_config()
    
    def shutdown(self) -> None:
        """
        Shutdown the configuration manager.
        """
        if self._enable_hot_reload:
            self._stop_hot_reload()
        self._logger.info("ConfigurationManager shutdown")