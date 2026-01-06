import logging
import time
import threading
import smtplib
from email.mime.text import MIMEText
from email.mime.multipart import MIMEMultipart
from typing import Dict, Any, Optional, List, Callable
from dataclasses import dataclass
from enum import Enum

from .memory_monitor import MemoryMonitor, MemoryStats, MemoryAlertLevel


class AlertAction(Enum):
    """Enum untuk jenis aksi alert."""
    LOG = 0
    EMAIL = 1
    WEBHOOK = 2
    CUSTOM = 3


@dataclass
class AlertConfig:
    """Data class untuk konfigurasi alert."""
    action: AlertAction
    enabled: bool = True
    cooldown_period: float = 300.0  # 5 minutes
    recipients: Optional[List[str]] = None
    webhook_url: Optional[str] = None
    custom_callback: Optional[Callable[[MemoryStats, MemoryAlertLevel], None]] = None


class MemoryAlertManager:
    """
    Manager untuk menangani alerting penggunaan memori yang tinggi.
    """
    
    def __init__(self, 
                 memory_monitor: MemoryMonitor,
                 email_config: Optional[Dict[str, Any]] = None):
        """
        Initialize MemoryAlertManager.
        
        Args:
            memory_monitor: MemoryMonitor instance
            email_config: Email configuration for sending alerts
                         {
                             'smtp_server': 'smtp.example.com',
                             'smtp_port': 587,
                             'username': 'user@example.com',
                             'password': 'password',
                             'from_addr': 'alerts@example.com'
                         }
        """
        self._logger = logging.getLogger(__name__)
        self._memory_monitor = memory_monitor
        self._email_config = email_config or {}
        
        # Alert configurations
        self._alert_configs: Dict[MemoryAlertLevel, List[AlertConfig]] = {
            MemoryAlertLevel.WARNING: [],
            MemoryAlertLevel.CRITICAL: []
        }
        
        # Last alert timestamps
        self._last_alert_times: Dict[MemoryAlertLevel, float] = {
            MemoryAlertLevel.WARNING: 0.0,
            MemoryAlertLevel.CRITICAL: 0.0
        }
        self._alert_lock = threading.Lock()
        
        # Register alert callback with memory monitor
        self._memory_monitor.add_alert_callback(self._handle_alert)
        
        self._logger.info("MemoryAlertManager initialized")
    
    def add_alert_config(self, 
                        alert_level: MemoryAlertLevel,
                        alert_config: AlertConfig) -> None:
        """
        Add alert configuration.
        
        Args:
            alert_level: Alert level
            alert_config: Alert configuration
        """
        if alert_level not in self._alert_configs:
            raise ValueError(f"Invalid alert level: {alert_level}")
        
        self._alert_configs[alert_level].append(alert_config)
        self._logger.info(f"Added alert config for {alert_level.name} level")
    
    def remove_alert_config(self, 
                           alert_level: MemoryAlertLevel,
                           alert_config: AlertConfig) -> None:
        """
        Remove alert configuration.
        
        Args:
            alert_level: Alert level
            alert_config: Alert configuration to remove
        """
        if alert_level not in self._alert_configs:
            raise ValueError(f"Invalid alert level: {alert_level}")
        
        if alert_config in self._alert_configs[alert_level]:
            self._alert_configs[alert_level].remove(alert_config)
            self._logger.info(f"Removed alert config for {alert_level.name} level")
    
    def add_email_alert(self, 
                       alert_level: MemoryAlertLevel,
                       recipients: List[str],
                       cooldown_period: float = 300.0) -> None:
        """
        Add email alert configuration.
        
        Args:
            alert_level: Alert level
            recipients: List of email recipients
            cooldown_period: Cooldown period in seconds
        """
        alert_config = AlertConfig(
            action=AlertAction.EMAIL,
            recipients=recipients,
            cooldown_period=cooldown_period
        )
        
        self.add_alert_config(alert_level, alert_config)
    
    def add_webhook_alert(self, 
                         alert_level: MemoryAlertLevel,
                         webhook_url: str,
                         cooldown_period: float = 300.0) -> None:
        """
        Add webhook alert configuration.
        
        Args:
            alert_level: Alert level
            webhook_url: Webhook URL
            cooldown_period: Cooldown period in seconds
        """
        alert_config = AlertConfig(
            action=AlertAction.WEBHOOK,
            webhook_url=webhook_url,
            cooldown_period=cooldown_period
        )
        
        self.add_alert_config(alert_level, alert_config)
    
    def add_custom_alert(self, 
                        alert_level: MemoryAlertLevel,
                        callback: Callable[[MemoryStats, MemoryAlertLevel], None],
                        cooldown_period: float = 300.0) -> None:
        """
        Add custom alert configuration.
        
        Args:
            alert_level: Alert level
            callback: Custom callback function
            cooldown_period: Cooldown period in seconds
        """
        alert_config = AlertConfig(
            action=AlertAction.CUSTOM,
            custom_callback=callback,
            cooldown_period=cooldown_period
        )
        
        self.add_alert_config(alert_level, alert_config)
    
    def _handle_alert(self, stats: MemoryStats, alert_level: MemoryAlertLevel) -> None:
        """
        Handle memory alert.
        
        Args:
            stats: Current memory statistics
            alert_level: Alert level
        """
        with self._alert_lock:
            # Check cooldown period
            current_time = time.time()
            last_alert_time = self._last_alert_times[alert_level]
            
            # Get alert configs for this level
            alert_configs = self._alert_configs[alert_level]
            
            for config in alert_configs:
                if not config.enabled:
                    continue
                
                # Check cooldown period
                if current_time - last_alert_time < config.cooldown_period:
                    continue
                
                # Execute alert action
                try:
                    if config.action == AlertAction.LOG:
                        # Log alert is already handled by MemoryMonitor
                        pass
                    
                    elif config.action == AlertAction.EMAIL:
                        self._send_email_alert(stats, alert_level, config)
                    
                    elif config.action == AlertAction.WEBHOOK:
                        self._send_webhook_alert(stats, alert_level, config)
                    
                    elif config.action == AlertAction.CUSTOM and config.custom_callback:
                        config.custom_callback(stats, alert_level)
                    
                    # Update last alert time
                    self._last_alert_times[alert_level] = current_time
                    
                except Exception as e:
                    self._logger.error(f"Error executing alert action: {e}")
    
    def _send_email_alert(self, 
                         stats: MemoryStats, 
                         alert_level: MemoryAlertLevel,
                         config: AlertConfig) -> None:
        """
        Send email alert.
        
        Args:
            stats: Current memory statistics
            alert_level: Alert level
            config: Alert configuration
        """
        if not config.recipients or not self._email_config:
            return
        
        try:
            # Create message
            msg = MIMEMultipart()
            msg['From'] = self._email_config.get('from_addr', 'memory_alert@example.com')
            msg['To'] = ', '.join(config.recipients)
            msg['Subject'] = f"Memory Alert: {alert_level.name} Level"
            
            # Create email body
            body = self._create_email_body(stats, alert_level)
            msg.attach(MIMEText(body, 'html'))
            
            # Send email
            with smtplib.SMTP(
                self._email_config.get('smtp_server', 'smtp.example.com'),
                self._email_config.get('smtp_port', 587)
            ) as server:
                server.starttls()
                server.login(
                    self._email_config.get('username', ''),
                    self._email_config.get('password', '')
                )
                server.send_message(msg)
            
            self._logger.info(f"Email alert sent to {config.recipients}")
            
        except Exception as e:
            self._logger.error(f"Error sending email alert: {e}")
    
    def _send_webhook_alert(self, 
                           stats: MemoryStats, 
                           alert_level: MemoryAlertLevel,
                           config: AlertConfig) -> None:
        """
        Send webhook alert.
        
        Args:
            stats: Current memory statistics
            alert_level: Alert level
            config: Alert configuration
        """
        if not config.webhook_url:
            return
        
        try:
            import requests
            
            # Create webhook payload
            payload = {
                'alert_level': alert_level.name,
                'timestamp': stats.timestamp,
                'memory': {
                    'rss_mb': stats.rss / (1024 * 1024),
                    'vms_mb': stats.vms / (1024 * 1024),
                    'percent': stats.percent,
                    'available_mb': stats.available / (1024 * 1024)
                },
                'gc': {
                    'count0': stats.gc_count0,
                    'count1': stats.gc_count1,
                    'count2': stats.gc_count2,
                    'objects': stats.gc_objects
                }
            }
            
            # Send webhook
            response = requests.post(
                config.webhook_url,
                json=payload,
                timeout=10.0
            )
            
            if response.status_code == 200:
                self._logger.info(f"Webhook alert sent to {config.webhook_url}")
            else:
                self._logger.error(f"Webhook alert failed: {response.status_code} - {response.text}")
                
        except ImportError:
            self._logger.error("requests library is required for webhook alerts")
        except Exception as e:
            self._logger.error(f"Error sending webhook alert: {e}")
    
    def _create_email_body(self, stats: MemoryStats, alert_level: MemoryAlertLevel) -> str:
        """
        Create email body for alert.
        
        Args:
            stats: Current memory statistics
            alert_level: Alert level
            
        Returns:
            Email body as HTML string
        """
        # Format memory values
        rss_mb = stats.rss / (1024 * 1024)
        vms_mb = stats.vms / (1024 * 1024)
        available_mb = stats.available / (1024 * 1024)
        
        # Create HTML body
        html = f"""
        <html>
        <body>
            <h2>Memory Alert: {alert_level.name} Level</h2>
            <p>The system has detected a memory usage alert at level <strong>{alert_level.name}</strong>.</p>
            
            <h3>Memory Statistics</h3>
            <table border="1" cellpadding="5" cellspacing="0">
                <tr>
                    <th>Metric</th>
                    <th>Value</th>
                </tr>
                <tr>
                    <td>Memory Usage</td>
                    <td>{stats.percent:.1f}%</td>
                </tr>
                <tr>
                    <td>Resident Set Size (RSS)</td>
                    <td>{rss_mb:.2f} MB</td>
                </tr>
                <tr>
                    <td>Virtual Memory Size (VMS)</td>
                    <td>{vms_mb:.2f} MB</td>
                </tr>
                <tr>
                    <td>Available Memory</td>
                    <td>{available_mb:.2f} MB</td>
                </tr>
            </table>
            
            <h3>Garbage Collection Statistics</h3>
            <table border="1" cellpadding="5" cellspacing="0">
                <tr>
                    <th>Metric</th>
                    <th>Value</th>
                </tr>
                <tr>
                    <td>Generation 0 Collections</td>
                    <td>{stats.gc_count0}</td>
                </tr>
                <tr>
                    <td>Generation 1 Collections</td>
                    <td>{stats.gc_count1}</td>
                </tr>
                <tr>
                    <td>Generation 2 Collections</td>
                    <td>{stats.gc_count2}</td>
                </tr>
                <tr>
                    <td>Tracked Objects</td>
                    <td>{stats.gc_objects}</td>
                </tr>
            </table>
            
            <p><strong>Timestamp:</strong> {time.strftime('%Y-%m-%d %H:%M:%S', time.localtime(stats.timestamp))}</p>
            
            <p>Please investigate this alert and take appropriate action if necessary.</p>
        </body>
        </html>
        """
        
        return html
    
    def get_alert_configs(self) -> Dict[str, List[Dict[str, Any]]]:
        """
        Get all alert configurations.
        
        Returns:
            Dictionary containing alert configurations
        """
        result = {}
        
        for level, configs in self._alert_configs.items():
            level_configs = []
            for config in configs:
                config_dict = {
                    'action': config.action.name,
                    'enabled': config.enabled,
                    'cooldown_period': config.cooldown_period
                }
                
                if config.recipients:
                    config_dict['recipients'] = config.recipients
                
                if config.webhook_url:
                    config_dict['webhook_url'] = config.webhook_url
                
                level_configs.append(config_dict)
            
            result[level.name] = level_configs
        
        return result
    
    def enable_alert_config(self, 
                           alert_level: MemoryAlertLevel,
                           action: AlertAction) -> None:
        """
        Enable alert configuration.
        
        Args:
            alert_level: Alert level
            action: Alert action
        """
        if alert_level not in self._alert_configs:
            raise ValueError(f"Invalid alert level: {alert_level}")
        
        for config in self._alert_configs[alert_level]:
            if config.action == action:
                config.enabled = True
                self._logger.info(f"Enabled {action.name} alert for {alert_level.name} level")
                return
        
        self._logger.warning(f"No {action.name} alert config found for {alert_level.name} level")
    
    def disable_alert_config(self, 
                            alert_level: MemoryAlertLevel,
                            action: AlertAction) -> None:
        """
        Disable alert configuration.
        
        Args:
            alert_level: Alert level
            action: Alert action
        """
        if alert_level not in self._alert_configs:
            raise ValueError(f"Invalid alert level: {alert_level}")
        
        for config in self._alert_configs[alert_level]:
            if config.action == action:
                config.enabled = False
                self._logger.info(f"Disabled {action.name} alert for {alert_level.name} level")
                return
        
        self._logger.warning(f"No {action.name} alert config found for {alert_level.name} level")