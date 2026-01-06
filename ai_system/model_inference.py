import logging
import numpy as np
from typing import Dict, Any, List, Union
from pathlib import Path

# Ultralytics YOLO for TensorRT
try:
    from ultralytics import YOLO
    ULTRALYTICS_AVAILABLE = True
except ImportError:
    ULTRALYTICS_AVAILABLE = False

# ONNX Runtime support
import onnxruntime as ort


class ModelInference:
    """
    Inference backend using Ultralytics YOLO (TensorRT) for GPU and ONNX Runtime for CPU.
    Config-driven architecture following strict parameter centralization rules.
    """
    
    def __init__(self, config_manager: Any):
        """
        Args:
            config_manager: ConfigurationManager instance to retrieve all parameters
        """
        self._config = config_manager
        self._logger = logging.getLogger(__name__)
        self._use_yolo = False
        
        # Get paths from central config
        engine_path_str = self._config.get('model.tensorrt_engine_path')
        onnx_path_str = self._config.get('model.path')
        
        if not onnx_path_str:
            raise ValueError("model.path must be defined in config.json")
            
        self._engine_path = Path(engine_path_str) if engine_path_str else None
        self._onnx_path = Path(onnx_path_str)
        
        # Initialize basic metadata first (needed for warmup)
        self._init_metadata()
        
        # Select Backend (GPU TensorRT via YOLO -> CPU ONNX)
        backend_initialized = False
        
        if ULTRALYTICS_AVAILABLE and self._engine_path and self._engine_path.exists():
            try:
                self._init_yolo(self._engine_path)
                self._use_yolo = True
                self._active_path = self._engine_path
                
                # Warmup to catch dynamic import errors (like tensorrt) or driver issues.
                # This is CRITICAL because YOLO(engine) might succeed but predict() might fail
                # if the tensorrt module is missing but ultralytics is installed.
                self._warmup()
                
                self._logger.info(f"[OK] GPU Backend (Ultralytics): {self._active_path}")
                backend_initialized = True
            except Exception as e:
                self._logger.warning(f"GPU Backend (YOLO/TensorRT) failed during init or warmup: {e}. Falling back to CPU/ONNX.")
                self._use_yolo = False
                # Clean up if partially initialized
                if hasattr(self, '_yolo_model'):
                    del self._yolo_model
        
        if not backend_initialized:
            if not self._onnx_path.exists():
                raise FileNotFoundError(f"ONNX model missing: {self._onnx_path}")
                
            self._init_onnx(self._onnx_path)
            self._active_path = self._onnx_path
            self._use_yolo = False
            
            # Warmup for CPU backend
            try:
                self._warmup()
                self._logger.info(f"[OK] CPU Backend (ONNX): {self._active_path}")
            except Exception as e:
                self._logger.error(f"CPU Backend (ONNX) warmup failed: {e}")
                raise

    def _init_metadata(self):
        """Initialize model metadata from configuration."""
        target_size_str = self._config.get('model.target_size')
        if not target_size_str:
             raise ValueError("model.target_size must be defined in config.json")
             
        w, h = map(int, target_size_str.split(','))
        self._input_shape = (1, 3, h, w)
        self._output_shape = (1, 300, 6) # YOLO11n fixed output shape
        
        # Initialize Info Dictionaries
        self._input_info = {
            'images': {
                'shape': self._input_shape,
                'type': 'float32',
                'name': 'images'
            }
        }
        self._output_info = {
            'output0': {
                'shape': self._output_shape,
                'type': 'float32',
                'name': 'output0'
            }
        }
    
    def _init_yolo(self, engine_path: Path):
        """Initialize YOLO with TensorRT engine."""
        self._logger.info(f"Loading YOLO TensorRT engine from: {engine_path}")
        self._logger.info(f"Engine file size: {engine_path.stat().st_size / 1024 / 1024:.2f} MB")
        
        # Load YOLO model with TensorRT engine
        self._yolo_model = YOLO(str(engine_path), task='detect')
        self._logger.info("YOLO TensorRT engine loaded successfully")
    
    def _init_onnx(self, onnx_path: Path):
        """Standard ONNX Runtime initialization."""
        available = ort.get_available_providers()
        # Prioritize CPU to ensure no license/compatibility issues, 
        # but keep CUDA if explicitly allowed by system state
        providers = ['CPUExecutionProvider']
        if 'CUDAExecutionProvider' in available:
             providers.insert(0, 'CUDAExecutionProvider')
             
        self._session = ort.InferenceSession(str(onnx_path), providers=providers)
        self._onnx_input_name = self._session.get_inputs()[0].name
        self._onnx_output_names = [o.name for o in self._session.get_outputs()]
    
    def _warmup(self):
        """Pre-heat the model to avoid latency on first request."""
        dummy = np.zeros(self._input_shape, dtype=np.float32)
        for _ in range(3):
            self._run_raw_inference(dummy)
    
    def _run_raw_inference(self, input_tensor: np.ndarray) -> np.ndarray:
        """Core inference execution logic."""
        if self._use_yolo:
            # YOLO expects (H, W, C) format, we have (1, C, H, W)
            # Convert: (1, 3, H, W) -> (H, W, 3)
            img = input_tensor[0].transpose(1, 2, 0)  # (C, H, W) -> (H, W, C)
            
            # Denormalize if needed (YOLO expects 0-255)
            if img.max() <= 1.0:
                img = (img * 255).astype(np.uint8)
            else:
                img = img.astype(np.uint8)
            
            # Run YOLO inference
            results = self._yolo_model.predict(img, verbose=False, imgsz=self._input_shape[2])
            
            # Extract raw output in YOLO format
            # YOLO output: boxes in xywh (center x, center y, width, height)
            # We need to convert to xyxy (x1, y1, x2, y2) for postprocessor
            if len(results) > 0 and results[0].boxes is not None:
                boxes = results[0].boxes
                # Convert to our expected format: [x1, y1, x2, y2, conf, class]
                output = np.zeros((1, 300, 6), dtype=np.float32)
                
                num_boxes = min(len(boxes), 300)
                for i in range(num_boxes):
                    box = boxes[i]
                    
                    # Get xywh (center format) from YOLO
                    xywh = box.xywh[0].cpu().numpy()  # [x_center, y_center, w, h]
                    conf = box.conf[0].cpu().numpy()
                    cls = box.cls[0].cpu().numpy()
                    
                    # Convert xywh (center) to xyxy (corners)
                    x_center, y_center, w, h = xywh
                    x1 = x_center - w / 2.0
                    y1 = y_center - h / 2.0
                    x2 = x_center + w / 2.0
                    y2 = y_center + h / 2.0
                    
                    # Store in xyxy format
                    output[0, i, 0] = x1
                    output[0, i, 1] = y1
                    output[0, i, 2] = x2
                    output[0, i, 3] = y2
                    output[0, i, 4] = conf
                    output[0, i, 5] = cls
                
                return output
            else:
                # No detections
                return np.zeros((1, 300, 6), dtype=np.float32)
        else:
            outputs = self._session.run(self._onnx_output_names, {self._onnx_input_name: input_tensor})
            return outputs[0]
    
    def predict(self, input_data: Union[np.ndarray, List[np.ndarray]]) -> List[np.ndarray]:
        """
        Public inference API.
        
        Args:
            input_data: Preprocessed frame in BCHW float32 format
            
        Returns:
            List containing the raw output tensor (1, 300, 6)
        """
        # Ensure single object is handled
        if isinstance(input_data, list):
            input_data = input_data[0]
            
        # Ensure correct type and shape
        if input_data.dtype != np.float32:
            input_data = input_data.astype(np.float32)
            
        if len(input_data.shape) == 3:
            input_data = np.expand_dims(input_data, axis=0)
            
        output = self._run_raw_inference(input_data)
        return [output]
    
    def get_input_info(self) -> Dict[str, Dict[str, Any]]:
        return self._input_info
    
    def get_output_info(self) -> Dict[str, Dict[str, Any]]:
        return self._output_info
    
    def get_model_path(self) -> Path:
        return self._active_path