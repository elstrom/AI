import logging
import time
import numpy as np
import cv2
import grpc
from concurrent import futures
from typing import Dict, Any, List, Optional
from pathlib import Path
from PIL import Image
import io

# TurboJPEG support (optional, falls back to OpenCV if not available)
try:
    from turbojpeg import TurboJPEG, TJPF_BGR
    TURBOJPEG_AVAILABLE = True
    _turbojpeg_instance: Optional[TurboJPEG] = None
except ImportError:
    TURBOJPEG_AVAILABLE = False
    _turbojpeg_instance = None

# Import generated protobuf classes
import sys
import os
sys.path.append(os.path.join(os.path.dirname(__file__), 'proto'))

# Import configuration manager
from .config_manager import ConfigurationManager

try:
    from ai_service_pb2 import (
        FrameRequest, FrameResponse, BatchFrameRequest,
        BatchFrameResponse, ModelInfoResponse, ServerStatsResponse,
        Empty, BBox, Detection, AIResults
    )
    from ai_service_pb2_grpc import AIServiceServicer, add_AIServiceServicer_to_server
except ImportError as e:
    logging.error(f"Failed to import generated protobuf classes: {e}")
    # Jika file protobuf belum di-generate, buat dummy classes
    class FrameRequest:
        def __init__(self):
            self.frame_data = b''
            self.width = 0
            self.height = 0
            self.channels = 0
    
    class FrameResponse:
        def __init__(self):
            self.success = False
            self.message = ""
            self.frame_id = ""
            self.timestamp = ""
            self.processing_time_ms = 0.0
            self.ai_results = None
    
    class BatchFrameRequest:
        def __init__(self):
            self.frames = []
    
    class BatchFrameResponse:
        def __init__(self):
            self.success = False
            self.message = ""
            self.responses = []
            self.total_processing_time = 0.0
    
    class ModelInfoResponse:
        def __init__(self):
            self.success = False
            self.model_path = ""
            self.input_info = {}
            self.output_info = {}
    
    class ServerStatsResponse:
        def __init__(self):
            self.success = False
            self.pool_size = 0
            self.in_use = 0
            self.status = ""
    
    class MemoryStatsResponse:
        def __init__(self):
            self.success = False
            self.memory_percent = 0.0
            self.memory_rss = 0
            self.memory_vms = 0
            self.memory_available = 0
            self.gc_objects = 0
            self.gc_count0 = 0
            self.gc_count1 = 0
            self.gc_count2 = 0
            self.uptime = 0.0
            self.total_gc_calls = 0
            self.total_alerts = 0
            self.max_memory_percent = 0.0
            self.status = ""
    
    class Empty:
        pass
    
    class BBox:
        def __init__(self):
            self.x_min = 0.0
            self.y_min = 0.0
            self.x_max = 0.0
            self.y_max = 0.0
    
    class Detection:
        def __init__(self):
            self.class_name = ""
            self.confidence = 0.0
            self.bbox = BBox()
    
    class AIResults:
        def __init__(self):
            self.detections = []
    
    class AIServiceServicer:
        pass
    
    def add_AIServiceServicer_to_server(server, servant):
        pass

from .frame_processor import FrameProcessor
from .memory_manager import MemoryManager


def _get_turbojpeg() -> Optional['TurboJPEG']:
    """
    Get or create TurboJPEG instance (singleton pattern).
    Supports portable loading from local 'libs' directory.
    """
    global _turbojpeg_instance
    if TURBOJPEG_AVAILABLE and _turbojpeg_instance is None:
        try:
            # 1. Try to find DLL in local 'libs' folder (Portable Mode)
            # This allows copying the project to another machine without installing libjpeg-turbo
            base_path = Path(__file__).parent.parent  # Serv_ScaI root
            local_dll_paths = [
                base_path / "tool" / "libjpeg-turbo64" / "bin" / "turbojpeg.dll",       # Windows
                base_path / "tool" / "libjpeg-turbo64" / "lib" / "libturbojpeg.so",     # Linux (Portable)
                base_path / "tool" / "libjpeg-turbo64" / "lib64" / "libturbojpeg.so",   # Linux (Portable 64-bit)
                base_path / "tool" / "libjpeg-turbo64" / "lib" / "libturbojpeg.dylib",  # macOS
            ]
            
            dll_path = None
            for path in local_dll_paths:
                if path.exists():
                    dll_path = str(path)
                    logging.info(f"Checking local TurboJPEG: Found at {dll_path}")
                    break
            
            if dll_path:
                # Portable mode: Load specific DLL
                logging.info(f"Initializing TurboJPEG in PORTABLE mode from: {dll_path}")
                _turbojpeg_instance = TurboJPEG(lib_path=dll_path)
            else:
                # System mode: Let PyTurboJPEG find it automatically
                logging.info("Initializing TurboJPEG in SYSTEM mode (global install)")
                _turbojpeg_instance = TurboJPEG()
                
        except Exception as e:
            logging.warning(f"Failed to initialize TurboJPEG: {e}")
            logging.warning("System will fallback to OpenCV for decoding.")
            
    return _turbojpeg_instance


class AIService(AIServiceServicer):
    """
    Implementation of AIService for gRPC server.
    Optimized for direct inference without double pooling.
    """
    
    def __init__(self, config_manager: ConfigurationManager):
        """
        Initialize AIService.
        
        Args:
            config_manager: ConfigurationManager instance
        """
        self._logger = logging.getLogger(__name__)
        self._config_manager = config_manager
        
        # Get configuration values
        self._model_path = Path(config_manager.get('model.path', 'Model_train/best.onnx'))
        self._max_workers = config_manager.get('grpc.max_workers', 10)
        pool_size = config_manager.get('model.pool_size', 5)
        
        # Decoder configuration
        self._use_turbojpeg = config_manager.get('decoder.use_turbojpeg', True)
        self._fallback_to_opencv = config_manager.get('decoder.fallback_to_opencv', True)
        
        # Direct inference mode (no double pooling)
        self._direct_inference = config_manager.get('grpc.direct_inference', True)
        
        # Memory monitoring
        enable_memory_monitoring = config_manager.get('memory.enable_monitoring', True)
        
        # Log throttling (per key)
        self._throttled_logs = {}
        self._log_interval = 300.0 # seconds
        
        # Initialize frame processor
        self._frame_processor = FrameProcessor(
            model_path=self._model_path,
            config_manager=config_manager,
            pool_size=pool_size
        )
        
        # Initialize memory manager
        self._memory_manager = None
        if enable_memory_monitoring:
            # Safe handling for log_file config
            log_file_config = config_manager.get('memory.log_file', 'logs/memory.log')
            log_file_path = Path(log_file_config) if log_file_config and str(log_file_config).strip() else None
            
            self._memory_manager = MemoryManager(
                config_manager=config_manager,
                log_file=log_file_path
            )
            
            # Register object pool with memory manager
            if hasattr(self._frame_processor, '_model_pool'):
                self._memory_manager.register_object_pool("model", self._frame_processor._model_pool)
            
            # Register buffer pool with memory manager
            if hasattr(self._frame_processor, '_buffer_pool') and self._frame_processor._buffer_pool:
                self._memory_manager.register_buffer_pool("frame_processor", self._frame_processor._buffer_pool)
        
        # Log initialization info
        decoder_info = "TurboJPEG" if (self._use_turbojpeg and TURBOJPEG_AVAILABLE) else "OpenCV"
        inference_mode = "Direct (no thread pool)" if self._direct_inference else "Thread Pool"
        self._logger.info(f"AIService initialized - Model: {self._model_path}")
        self._logger.info(f"Decoder: {decoder_info}, Inference: {inference_mode}")
        
        # Register callback for configuration changes
        config_manager.add_config_change_callback(self._on_config_changed)
    
    def _log_throttled(self, key: str, level: int, message: str, *args, **kwargs):
        """Log a message only if the interval has passed for the given key."""
        now = time.time()
        last_log = self._throttled_logs.get(key, 0)
        if now - last_log >= self._log_interval:
            self._throttled_logs[key] = now
            self._logger.log(level, message, *args, **kwargs)
    
    def _on_config_changed(self, old_config: Dict[str, Any], new_config: Dict[str, Any]) -> None:
        """
        Callback for configuration changes.
        
        Args:
            old_config: Old configuration
            new_config: New configuration
        """
        # Check if decoder configuration changed
        old_decoder = old_config.get('decoder', {})
        new_decoder = new_config.get('decoder', {})
        
        if old_decoder.get('use_turbojpeg') != new_decoder.get('use_turbojpeg'):
            self._use_turbojpeg = new_decoder.get('use_turbojpeg', True)
            self._logger.info(f"Updated TurboJPEG setting: {self._use_turbojpeg}")
        
        if old_decoder.get('fallback_to_opencv') != new_decoder.get('fallback_to_opencv'):
            self._fallback_to_opencv = new_decoder.get('fallback_to_opencv', True)
            self._logger.info(f"Updated fallback_to_opencv setting: {self._fallback_to_opencv}")
        
        # Check if memory monitoring configuration changed
        old_memory = old_config.get('memory', {})
        new_memory = new_config.get('memory', {})
        
        if old_memory.get('enable_monitoring') != new_memory.get('enable_monitoring'):
            enable_memory_monitoring = new_memory.get('enable_monitoring', True)
            if enable_memory_monitoring and not self._memory_manager:
                self._logger.info("Enabling memory monitoring")
                # Safe handling for log_file config
                log_file_config = new_memory.get('log_file', 'logs/memory.log')
                log_file_path = Path(log_file_config) if log_file_config and str(log_file_config).strip() else None
                
                self._memory_manager = MemoryManager(
                    config_manager=self._config_manager,
                    log_file=log_file_path
                )
                
                # Register object pool with memory manager
                if hasattr(self._frame_processor, '_model_pool'):
                    self._memory_manager.register_object_pool("model", self._frame_processor._model_pool)
                
                # Register buffer pool with memory manager
                if hasattr(self._frame_processor, '_buffer_pool') and self._frame_processor._buffer_pool:
                    self._memory_manager.register_buffer_pool("frame_processor", self._frame_processor._buffer_pool)
            elif not enable_memory_monitoring and self._memory_manager:
                self._logger.info("Disabling memory monitoring")
                self._memory_manager.shutdown()
                self._memory_manager = None
        
        # Check if memory thresholds changed
        if (old_memory.get('warning_threshold') != new_memory.get('warning_threshold') or
            old_memory.get('critical_threshold') != new_memory.get('critical_threshold')):
            if self._memory_manager:
                warning_threshold = new_memory.get('warning_threshold', 70.0)
                critical_threshold = new_memory.get('critical_threshold', 85.0)
                self._memory_manager.set_memory_thresholds(warning_threshold, critical_threshold)
    
    def _decode_jpeg_turbojpeg(self, frame_data: bytes) -> Optional[np.ndarray]:
        """
        Decode JPEG using TurboJPEG (faster than OpenCV).
        
        Args:
            frame_data: JPEG bytes
            
        Returns:
            Decoded frame as BGR numpy array, or None if failed
        """
        if not self._use_turbojpeg or not TURBOJPEG_AVAILABLE:
            return None
        
        jpeg = _get_turbojpeg()
        if jpeg is None:
            return None
        
        try:
            # Decode directly to BGR format (native OpenCV format)
            frame = jpeg.decode(frame_data, pixel_format=TJPF_BGR)
            return frame
        except Exception as e:
            self._logger.debug(f"TurboJPEG decode failed: {e}")
            return None
    
    def _bytes_to_numpy(self, frame_data: bytes, width: int, height: int, channels: int, format: str = 'auto') -> np.ndarray:
        """
        Convert bytes to numpy array.
        Supports: JPEG, PNG, YUV420, and raw RGB/BGR formats.
        Uses TurboJPEG for faster JPEG decoding when available.
        
        Args:
            frame_data: Frame data as bytes
            width: Frame width (0 if unknown)
            height: Frame height (0 if unknown)
            channels: Number of channels
            format: Frame format ('jpeg', 'yuv420', 'rgb', or 'auto' for auto-detection)
            
        Returns:
            Frame as numpy array (BGR format for OpenCV)
        """
        data_len = len(frame_data)
        self._logger.debug(
            f"[DECODE] Input: format={format}, bytes={data_len}, dims={width}x{height}x{channels}"
        )
        
        # EXPLICIT FORMAT DECODING (when client specifies format)
        if format and format != 'auto':
            format_lower = format.lower()
            
            # JPEG format - try TurboJPEG first
            if format_lower == 'jpeg':
                # Try TurboJPEG first (faster)
                frame = self._decode_jpeg_turbojpeg(frame_data)
                if frame is not None:
                    actual_h, actual_w = frame.shape[:2]
                    self._logger.debug(f"[DECODE] ✅ TurboJPEG decoded: {actual_w}x{actual_h}")
                    
                    # Resize if target dimensions provided and differ
                    if width > 0 and height > 0 and (actual_w != width or actual_h != height):
                        self._logger.debug(f"[DECODE] Resizing {actual_w}x{actual_h} -> {width}x{height}")
                        frame = cv2.resize(frame, (width, height))
                    
                    return frame
                
                # Fallback to OpenCV if TurboJPEG failed
                if self._fallback_to_opencv:
                    try:
                        data_array = np.frombuffer(frame_data, dtype=np.uint8)
                        frame = cv2.imdecode(data_array, cv2.IMREAD_COLOR)
                        
                        if frame is not None:
                            actual_h, actual_w = frame.shape[:2]
                            self._logger.debug(f"[DECODE] ✅ OpenCV JPEG decoded: {actual_w}x{actual_h}")
                            
                            # Resize if target dimensions provided and differ
                            if width > 0 and height > 0 and (actual_w != width or actual_h != height):
                                self._logger.debug(f"[DECODE] Resizing {actual_w}x{actual_h} -> {width}x{height}")
                                frame = cv2.resize(frame, (width, height))
                            
                            return frame
                        else:
                            raise ValueError("JPEG decode returned None")
                    except Exception as e:
                        self._logger.error(f"[DECODE] ❌ OpenCV JPEG decode failed: {e}")
                        raise
                else:
                    raise ValueError("TurboJPEG decode failed and fallback is disabled")
            
            # YUV420 format
            elif format_lower == 'yuv420':
                if width <= 0 or height <= 0:
                    raise ValueError(f"YUV420 format requires valid dimensions, got {width}x{height}")
                
                expected_yuv_size = int(width * height * 1.5)
                if data_len != expected_yuv_size:
                    raise ValueError(
                        f"YUV420 size mismatch: expected {expected_yuv_size} bytes, got {data_len}"
                    )
                
                try:
                    yuv_data = np.frombuffer(frame_data, dtype=np.uint8)
                    yuv_frame = yuv_data.reshape((int(height * 1.5), width))
                    frame = cv2.cvtColor(yuv_frame, cv2.COLOR_YUV2BGR_I420)
                    self._logger.debug(f"[DECODE] ✅ YUV420 decoded: {width}x{height}")
                    return frame
                except Exception as e:
                    self._logger.error(f"[DECODE] ❌ YUV420 decode failed: {e}")
                    raise
            
            # Raw RGB format
            elif format_lower == 'rgb':
                if width <= 0 or height <= 0:
                    raise ValueError(f"RGB format requires valid dimensions, got {width}x{height}")
                
                expected_rgb_size = int(width * height * channels)
                if data_len != expected_rgb_size:
                    raise ValueError(
                        f"RGB size mismatch: expected {expected_rgb_size} bytes, got {data_len}"
                    )
                
                try:
                    frame = np.frombuffer(frame_data, dtype=np.uint8)
                    if channels == 1:
                        frame = frame.reshape((height, width))
                    else:
                        frame = frame.reshape((height, width, channels))
                        # Convert RGB to BGR for OpenCV
                        if channels == 3:
                            frame = cv2.cvtColor(frame, cv2.COLOR_RGB2BGR)
                    
                    self._logger.debug(f"[DECODE] ✅ RGB decoded: {width}x{height}x{channels}")
                    return frame
                except Exception as e:
                    self._logger.error(f"[DECODE] ❌ RGB decode failed: {e}")
                    raise
            
            else:
                self._logger.warning(f"[DECODE] Unknown format '{format}', falling back to auto-detection")
        
        # AUTO-DETECTION (fallback when format not specified or unknown)
        self._logger.debug("[DECODE] Using auto-detection...")
        
        # STRATEGY 1: Try TurboJPEG first (fastest for JPEG)
        frame = self._decode_jpeg_turbojpeg(frame_data)
        if frame is not None:
            actual_h, actual_w = frame.shape[:2]
            self._logger.debug(f"[DECODE] ✅ TurboJPEG auto-detected: {actual_w}x{actual_h}")
            
            # Resize if target dimensions provided and differ
            if width > 0 and height > 0 and (actual_w != width or actual_h != height):
                self._logger.debug(f"[DECODE] Resizing {actual_w}x{actual_h} -> {width}x{height}")
                frame = cv2.resize(frame, (width, height))
            
            return frame
        
        # STRATEGY 2: Try OpenCV JPEG/PNG decode
        try:
            data_array = np.frombuffer(frame_data, dtype=np.uint8)
            frame = cv2.imdecode(data_array, cv2.IMREAD_COLOR)
            
            if frame is not None:
                actual_h, actual_w = frame.shape[:2]
                self._logger.debug(
                    f"[DECODE] ✅ OpenCV JPEG/PNG auto-detected: {actual_w}x{actual_h}"
                )
                
                # Resize if target dimensions provided and differ
                if width > 0 and height > 0 and (actual_w != width or actual_h != height):
                    self._logger.debug(f"[DECODE] Resizing {actual_w}x{actual_h} -> {width}x{height}")
                    frame = cv2.resize(frame, (width, height))
                
                return frame
        except Exception as e:
            self._logger.debug(f"[DECODE] OpenCV JPEG/PNG auto-detect failed: {e}")
        
        # STRATEGY 3: Check for YUV420 format (size = w * h * 1.5)
        # YUV420 requires exact dimensions to decode
        if width > 0 and height > 0:
            expected_yuv_size = int(width * height * 1.5)
            expected_raw_size = int(width * height * channels)
            
            if data_len == expected_yuv_size:
                self._logger.debug(f"[DECODE] ✅ YUV420 auto-detected: {width}x{height}")
                try:
                    yuv_data = np.frombuffer(frame_data, dtype=np.uint8)
                    yuv_frame = yuv_data.reshape((int(height * 1.5), width))
                    frame = cv2.cvtColor(yuv_frame, cv2.COLOR_YUV2BGR_I420)
                    self._logger.debug(f"[DECODE] YUV->BGR: shape={frame.shape}")
                    return frame
                except Exception as e:
                    self._logger.error(f"[DECODE] YUV420 auto-detect conversion failed: {e}")
            
            # STRATEGY 4: Raw RGB/BGR format
            elif data_len == expected_raw_size:
                self._logger.debug(f"[DECODE] ✅ Raw format auto-detected: {width}x{height}x{channels}")
                frame = np.frombuffer(frame_data, dtype=np.uint8)
                
                if channels == 1:
                    frame = frame.reshape((height, width))
                else:
                    frame = frame.reshape((height, width, channels))
                
                return frame
        
        # STRATEGY 5: Auto-detect YUV420 from data size (when dims unknown)
        # Common resolutions: 640x360, 1280x720, 1920x1080
        common_resolutions = [
            (640, 360), (1280, 720), (1920, 1080),
            (320, 240), (800, 600), (1024, 768)
        ]
        
        for w, h in common_resolutions:
            if data_len == int(w * h * 1.5):
                self._logger.debug(f"[DECODE] ✅ YUV420 auto-detected by size: {w}x{h}")
                try:
                    yuv_data = np.frombuffer(frame_data, dtype=np.uint8)
                    yuv_frame = yuv_data.reshape((int(h * 1.5), w))
                    frame = cv2.cvtColor(yuv_frame, cv2.COLOR_YUV2BGR_I420)
                    return frame
                except Exception as e:
                    self._logger.debug(f"[DECODE] YUV420 auto-detect failed for {w}x{h}: {e}")
        
        # ALL STRATEGIES FAILED
        self._logger.error(
            f"[DECODE] ❌ All decode strategies failed! "
            f"format={format}, data_len={data_len}, dims={width}x{height}x{channels}"
        )
        raise ValueError(
            f"Failed to decode frame: format={format}, {data_len} bytes, dims={width}x{height}x{channels}. "
            f"Not JPEG/PNG, not YUV420, not raw RGB."
        )
    
    def ProcessFrame(self, request: FrameRequest, context) -> FrameResponse:
        """
        Process a single frame directly (no thread pool overhead).
        
        Args:
            request: FrameRequest containing frame data
            context: gRPC context
            
        Returns:
            FrameResponse containing processing results
        """
        start_time = time.time()
        
        try:
            # Update validation: Allow width/height=0 if data is present (auto-detect)
            if len(request.frame_data) == 0:
                 raise ValueError(f"Invalid frame data: empty")
            
            if (request.width <= 0 or request.height <= 0) and len(request.frame_data) < 100:
                 # Simple heuristic: if dimensions are 0, data must be substantial (imagedata)
                 # 100 bytes is arbitrary small limit for a valid image file
                 raise ValueError(f"Invalid frame: dimensions 0 and data too small ({len(request.frame_data)} bytes)")

            # Log frame metadata
            frame_format = getattr(request, 'format', '') or 'auto'  # Default to 'auto' if not provided
            self._logger.debug(
                f"[FRAME] format={frame_format}, {request.width}x{request.height}, "
                f"{len(request.frame_data)} bytes"
            )
            
            # Convert bytes to numpy array (uses TurboJPEG if available)
            frame = self._bytes_to_numpy(
                request.frame_data,
                request.width,
                request.height,
                request.channels,
                frame_format  # Pass format from client
            )
            
            # DIRECT INFERENCE - No thread pool handover
            # This eliminates context switching overhead
            result = self._frame_processor.process_frame(frame)
            
            # Calculate processing time in milliseconds
            processing_time_ms = (time.time() - start_time) * 1000
            
            # Create response with new format
            response = FrameResponse()
            response.success = True
            response.message = "Frame processed successfully"
            response.processing_time_ms = processing_time_ms
            
            # Map detections to AIResults - ALWAYS create AIResults even if empty
            ai_results = AIResults()  # Always create, even if no detections
            detection_count = 0
            
            if 'detections' in result and isinstance(result['detections'], list):
                for d in result['detections']:
                    if isinstance(d, dict):
                        det = Detection()
                        det.class_name = d.get('class_name', 'unknown')
                        det.confidence = d.get('confidence', 0.0)
                        
                        bbox_data = d.get('bbox', {})
                        bbox = BBox()
                        bbox.x_min = bbox_data.get('x_min', 0.0)
                        bbox.y_min = bbox_data.get('y_min', 0.0)
                        # Convert width/height to x_max/y_max
                        bbox.x_max = bbox_data.get('x_min', 0.0) + bbox_data.get('width', 0.0)
                        bbox.y_max = bbox_data.get('y_min', 0.0) + bbox_data.get('height', 0.0)
                        
                        det.bbox.CopyFrom(bbox)
                        ai_results.detections.append(det)
                        detection_count += 1
                        
                        # Log each detection only if throttled (every 10s per class)
                        self._log_throttled(
                            f"det_{det.class_name}", 
                            logging.INFO,
                            f"[DETECTION] {det.class_name} ({det.confidence:.2f}) at [{bbox.x_min:.3f},{bbox.y_min:.3f},{bbox.x_max:.3f},{bbox.y_max:.3f}]"
                        )
            
            # ALWAYS set ai_results, even if empty
            response.ai_results.CopyFrom(ai_results)
            
            # Only log if there are detections or if processing took long (throttled)
            if detection_count > 0 or processing_time_ms > 1000:
                self._log_throttled(
                    "frame_success",
                    logging.INFO,
                    f"[FRAME] {processing_time_ms:.0f}ms, Detections: {detection_count}"
                )
            
            return response
            
        except Exception as e:
            self._logger.error(f"[FRAME ERROR] Error processing frame: {e}", exc_info=True)
            processing_time_ms = (time.time() - start_time) * 1000
            
            response = FrameResponse()
            response.success = False
            response.message = f"Error processing frame: {str(e)}"
            response.processing_time_ms = processing_time_ms
            
            return response
    
    def ProcessBatchFrames(self, request: BatchFrameRequest, context) -> BatchFrameResponse:
        """
        Process a batch of frames directly.
        
        Args:
            request: BatchFrameRequest containing multiple frames
            context: gRPC context
            
        Returns:
            BatchFrameResponse containing processing results for all frames
        """
        start_time = time.time()
        
        try:
            # Convert all frames to numpy arrays
            frames = []
            for frame_request in request.frames:
                frame = self._bytes_to_numpy(
                    frame_request.frame_data,
                    frame_request.width,
                    frame_request.height,
                    frame_request.channels
                )
                frames.append(frame)
            
            # DIRECT BATCH PROCESSING - No thread pool handover
            results = self._frame_processor.process_batch(frames)
            
            # Calculate total processing time
            total_processing_time = time.time() - start_time
            
            # Create responses for each frame
            responses = []
            for i, result in enumerate(results):
                response = FrameResponse(
                    success=True,
                    message=f"Frame {i} processed successfully",
                    processing_time=total_processing_time / len(frames)  # Average time
                )
                
                # Add results to response
                for key, value in result.items():
                    if isinstance(value, (int, float)):
                        response.results[key] = float(value)
                    elif isinstance(value, list) and len(value) > 0 and isinstance(value[0], (int, float)):
                        # For lists of numbers, take the first value as a simple example
                        response.results[key] = float(value[0])
                
                responses.append(response)
            
            # Create batch response
            batch_response = BatchFrameResponse(
                success=True,
                message=f"Processed {len(frames)} frames successfully",
                responses=responses,
                total_processing_time=total_processing_time
            )
            
            self._logger.debug(f"Batch of {len(frames)} frames processed in {total_processing_time:.4f} seconds")
            return batch_response
            
        except Exception as e:
            self._logger.error(f"Error processing batch frames: {e}")
            return BatchFrameResponse(
                success=False,
                message=f"Error processing batch frames: {str(e)}",
                total_processing_time=time.time() - start_time
            )
    
    def GetModelInfo(self, request: Empty, context) -> ModelInfoResponse:
        """
        Get model information.
        
        Args:
            request: Empty request
            context: gRPC context
            
        Returns:
            ModelInfoResponse containing model information
        """
        try:
            # Get a model from the pool to retrieve its info
            model = self._frame_processor._model_pool.acquire()
            
            try:
                # Get input and output info
                input_info = model.get_input_info()
                output_info = model.get_output_info()
                
                # Convert to string representations
                input_info_str = {name: f"{info['type']}, shape: {info['shape']}" 
                                 for name, info in input_info.items()}
                output_info_str = {name: f"{info['type']}, shape: {info['shape']}" 
                                  for name, info in output_info.items()}
                
                # Create response
                response = ModelInfoResponse(
                    success=True,
                    model_path=str(model.get_model_path()),
                    input_info=input_info_str,
                    output_info=output_info_str
                )
                
                return response
                
            finally:
                # Return model to pool
                self._frame_processor._model_pool.release(model)
                
        except Exception as e:
            self._logger.error(f"Error getting model info: {e}")
            return ModelInfoResponse(
                success=False,
                model_path=str(self._model_path),
                input_info={},
                output_info={}
            )
    
    def GetServerStats(self, request: Empty, context) -> ServerStatsResponse:
        """
        Get server statistics.
        
        Args:
            request: Empty request
            context: gRPC context
            
        Returns:
            ServerStatsResponse containing server statistics
        """
        try:
            # Get model pool stats
            pool_stats = self._frame_processor.get_pool_stats()
            
            # Create status message
            status = f"Server is running. Model pool: {pool_stats['in_use']}/{pool_stats['pool_size']} in use. Direct inference mode: {self._direct_inference}"
            
            # Create response
            response = ServerStatsResponse(
                success=True,
                pool_size=pool_stats["pool_size"],
                in_use=pool_stats["in_use"],
                status=status
            )
            
            return response
            
        except Exception as e:
            self._logger.error(f"Error getting server stats: {e}")
            return ServerStatsResponse(
                success=False,
                pool_size=0,
                in_use=0,
                status=f"Error: {str(e)}"
            )
    
    def shutdown(self):
        """Gracefully shutdown the service."""
        self._logger.info("Shutting down AIService...")
        
        # Shutdown memory manager if enabled
        if self._memory_manager:
            self._logger.info("Shutting down memory manager...")
            self._memory_manager.shutdown()
        
        self._logger.info("AIService shutdown complete")


def serve(config_manager: ConfigurationManager):
    """
    Start the gRPC server.
    
    Args:
        config_manager: ConfigurationManager instance
    """
    # Configure logging
    logging.basicConfig(level=logging.INFO)
    logger = logging.getLogger(__name__)
    
    # Get configuration values
    host = config_manager.get('grpc.host', '[::]')
    port = config_manager.get('grpc.port', 50051)
    max_workers = config_manager.get('grpc.max_workers', 10)
    enable_memory_monitoring = config_manager.get('memory.enable_monitoring', True)
    
    # Create gRPC server
    server = grpc.server(futures.ThreadPoolExecutor(max_workers=max_workers))
    
    # Add AIService to server
    ai_service = AIService(config_manager)
    print(f"DEBUG: Registering AIService instance to gRPC server...")
    add_AIServiceServicer_to_server(ai_service, server)
    print(f"DEBUG: Service registration call completed.")
    
    # Bind server to port
    server.add_insecure_port(f'{host}:{port}')
    
    # Start server
    server.start()
    logger.info(f"Server started on {host}:{port}")
    
    try:
        # Keep server running
        server.wait_for_termination()
    except KeyboardInterrupt:
        logger.info("Server shutting down gracefully")
        
        # Shutdown AIService
        ai_service.shutdown()
        
        # Shutdown configuration manager
        if config_manager:
            logger.info("Shutting down configuration manager...")
            config_manager.shutdown()
        
        # Shutdown gRPC server
        server.stop(5.0)  # 5 seconds grace period
        logger.info("Server shutdown complete")