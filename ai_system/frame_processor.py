import logging
import numpy as np
import cv2
from typing import Optional, Dict, Any, Tuple, List, Union
from pathlib import Path
from .model_inference import ModelInference
from .object_pool import ObjectPool
from .config_manager import ConfigurationManager


class FrameProcessor:
    """
    Kelas untuk memproses frame dari smartphone menggunakan model AI.
    Optimized with vectorized post-processing for better performance.
    """
    
    def __init__(self,
                 model_path: Path,
                 config_manager: ConfigurationManager,
                 pool_size: Optional[int] = None,
                 target_size: Optional[Tuple[int, int]] = None,
                 normalize: Optional[bool] = None):
        """
        Inisialisasi FrameProcessor.
        
        Args:
            model_path: Path ke file model ONNX
            config_manager: ConfigurationManager instance
            pool_size: Jumlah model instance dalam pool (from config if not provided)
            target_size: Ukuran target untuk resize frame (width, height) (from config if not provided)
            normalize: Apakah akan melakukan normalisasi pixel (from config if not provided)
        """
        self._logger = logging.getLogger(__name__)
        self._config_manager = config_manager
        
        # Get configuration values with fallbacks to parameters
        # ALL values should come from config.json for easy debugging
        self._pool_size = pool_size or config_manager.get('model.pool_size', 5)
        
        # Target size - MUST match model training size (check model metadata)
        self._target_size = target_size or self._parse_target_size(
            config_manager.get('model.target_size')
        )
        if not self._target_size:
            raise ValueError("model.target_size must be specified in config.json")
        
        self._normalize = normalize if normalize is not None else config_manager.get('model.normalize', True)
        
        # Buat pool untuk model inference
        self._model_pool = ObjectPool(
            create_object=lambda: ModelInference(config_manager),
            max_size=self._pool_size,
            reset_object=self._reset_model
        )
        
        # Class names from config
        self._class_names = config_manager.get('model.class_names', [])
        if not self._class_names:
            self._logger.warning("model.class_names not specified in config, using indices")

        self._logger.info(f"FrameProcessor initialized with model: {model_path}")
        self._logger.info(f"Target size: {self._target_size}, Normalize: {self._normalize}")
        self._logger.info(f"Class names: {self._class_names}")

        # Register callback for configuration changes
        config_manager.add_config_change_callback(self._on_config_changed)
    
    def _parse_target_size(self, size_config: Optional[Union[str, List[int], Tuple[int, int]]]) -> Optional[Tuple[int, int]]:
        """
        Parse target size from configuration.
        
        Args:
            size_config: Target size configuration (string, list, or tuple)
            
        Returns:
            Target size as tuple or None
        """
        if size_config is None:
            return None
        
        if isinstance(size_config, str):
            # Parse from string format "width,height"
            try:
                parts = size_config.split(',')
                if len(parts) == 2:
                    return (int(parts[0]), int(parts[1]))
            except ValueError:
                self._logger.warning(f"Invalid target size format: {size_config}")
                return None
        
        elif isinstance(size_config, (list, tuple)) and len(size_config) == 2:
            # Use as is if it's a list or tuple of 2 elements
            try:
                return (int(size_config[0]), int(size_config[1]))
            except (ValueError, IndexError):
                self._logger.warning(f"Invalid target size values: {size_config}")
                return None
        
        else:
            self._logger.warning(f"Unsupported target size format: {size_config}")
            return None
    
    def _on_config_changed(self, old_config: Dict[str, Any], new_config: Dict[str, Any]) -> None:
        """
        Callback for configuration changes.
        
        Args:
            old_config: Old configuration
            new_config: New configuration
        """
        # Check if model configuration changed
        old_model = old_config.get('model', {})
        new_model = new_config.get('model', {})
        
        if old_model.get('normalize') != new_model.get('normalize'):
            new_normalize = new_model.get('normalize')
            if new_normalize is not None:
                self._normalize = bool(new_normalize)
                self._logger.info(f"Updated normalize setting: {self._normalize}")
        
        if old_model.get('target_size') != new_model.get('target_size'):
            new_target_size = self._parse_target_size(new_model.get('target_size'))
            if new_target_size is not None:
                self._target_size = new_target_size
                self._logger.info(f"Updated target size: {self._target_size}")
    
    def _reset_model(self, model: ModelInference) -> None:
        """
        Reset model instance (jika diperlukan).
        
        Args:
            model: Instance model yang akan direset
        """
        # Tidak ada reset khusus yang diperlukan untuk ModelInference
        pass
    
    def preprocess_frame(self, frame: np.ndarray) -> np.ndarray:
        """
        Preprocess frame sebelum inferensi.
        
        Args:
            frame: Frame yang akan dipreprocess
            
        Returns:
            Frame yang sudah dipreprocess
        """
        # Check for empty frame
        if frame is None or frame.size == 0:
            raise ValueError("Empty frame provided to preprocess_frame")

        self._logger.debug(f"[PREPROCESS] Input: shape={frame.shape}, dtype={frame.dtype}")

        # Konversi ke RGB jika BGR
        if len(frame.shape) == 3 and frame.shape[2] == 3:
            frame = cv2.cvtColor(frame, cv2.COLOR_BGR2RGB)
            self._logger.debug(f"[PREPROCESS] After BGR->RGB: shape={frame.shape}")
        
        # Resize frame jika target_size disediakan
        if self._target_size:
            original_shape = frame.shape
            frame = cv2.resize(frame, self._target_size)
            self._logger.debug(
                f"[PREPROCESS] After resize {original_shape[:2]} -> {self._target_size}: "
                f"shape={frame.shape}"
            )
        
        # Normalisasi pixel jika diperlukan
        if self._normalize:
            frame = frame.astype(np.float32) / 255.0
            self._logger.debug(
                f"[PREPROCESS] After normalize: dtype={frame.dtype}, "
                f"range=[{frame.min():.3f}, {frame.max():.3f}]"
            )
        
        # Transpose HWC ke CHW (Channels First) untuk ONNX
        frame = np.transpose(frame, (2, 0, 1))
        self._logger.debug(f"[PREPROCESS] After transpose HWC->CHW: shape={frame.shape}")

        # Tambahkan batch dimension
        frame = np.expand_dims(frame, axis=0)
        self._logger.debug(f"[PREPROCESS] After add batch dim: shape={frame.shape}")
        
        return frame
    
    
    def postprocess_output(self, output: List[np.ndarray], original_shape: tuple = None) -> Dict[str, Any]:
        """
        Postprocess output dari model YOLO11n dengan NMS built-in.
        VECTORIZED VERSION - Uses NumPy matrix operations for speed.
        
        Model output format: (1, 300, 6)
        Each detection: [x1, y1, x2, y2, confidence, class_id]
        
        IMPORTANT: Model outputs bbox in MODEL INPUT coordinates (320x320),
        but we need to map them back to ORIGINAL aspect ratio!
        
        Args:
            output: Output dari model
            original_shape: Original frame shape (H, W, C) before resize
            
        Returns:
            Dictionary berisi hasil detections (identical JSON format to before)
        """
        result = {"detections": []}
        
        try:
            if not output or len(output) == 0:
                return result
            
            # Model output: (1, 300, 6)
            # Format: [x1, y1, x2, y2, confidence, class_id]
            pred = output[0]
            
            self._logger.debug(f"[POSTPROCESS] Raw output shape: {pred.shape}")
            
            # Remove batch dimension
            if len(pred.shape) == 3:
                pred = pred[0]  # (300, 6)
            
            self._logger.debug(f"[POSTPROCESS] After remove batch: {pred.shape}")
            
            # Get confidence threshold
            conf_threshold = self._config_manager.get('model.conf_threshold', 0.25)
            
            # VECTORIZED: Filter by confidence (index 4 is confidence)
            confidences = pred[:, 4]
            mask = confidences > conf_threshold
            valid_detections = pred[mask]
            
            self._logger.debug(
                f"[POSTPROCESS] Conf threshold: {conf_threshold}, "
                f"Valid detections: {len(valid_detections)}/{len(pred)}"
            )
            
            if len(valid_detections) == 0:
                return result
            
            # Get model input size
            model_w, model_h = 320.0, 320.0
            if self._target_size:
                model_w, model_h = float(self._target_size[0]), float(self._target_size[1])
            
            # Get ORIGINAL frame dimensions
            if original_shape is not None:
                orig_h, orig_w = float(original_shape[0]), float(original_shape[1])
            else:
                # Fallback to model input size (will be wrong!)
                orig_w, orig_h = model_w, model_h
                self._logger.warning(
                    f"[POSTPROCESS] No original_shape provided, using model input size "
                    f"{orig_w}x{orig_h} - bbox may be incorrect!"
                )
            
            # VECTORIZED: Calculate scale factors
            scale_x = orig_w / model_w
            scale_y = orig_h / model_h
            
            self._logger.debug(
                f"[POSTPROCESS] Scaling: model {model_w}x{model_h} -> "
                f"original {orig_w}x{orig_h}, scale_x={scale_x:.2f}, scale_y={scale_y:.2f}"
            )
            
            # VECTORIZED: Extract all columns at once
            x1_all = valid_detections[:, 0]
            y1_all = valid_detections[:, 1]
            x2_all = valid_detections[:, 2]
            y2_all = valid_detections[:, 3]
            conf_all = valid_detections[:, 4]
            class_id_all = valid_detections[:, 5].astype(np.int32)
            
            # VECTORIZED: Scale bbox from model coordinates to original frame coordinates
            x1_scaled = x1_all * scale_x
            y1_scaled = y1_all * scale_y
            x2_scaled = x2_all * scale_x
            y2_scaled = y2_all * scale_y
            
            # VECTORIZED: Convert to x, y, w, h
            x_all = x1_scaled
            y_all = y1_scaled
            w_all = x2_scaled - x1_scaled
            h_all = y2_scaled - y1_scaled
            
            # VECTORIZED: Normalize to 0-1 using original frame dimensions
            norm_x = np.clip(x_all / orig_w, 0.0, 1.0)
            norm_y = np.clip(y_all / orig_h, 0.0, 1.0)
            norm_w = np.clip(w_all / orig_w, 0.0, 1.0)
            norm_h = np.clip(h_all / orig_h, 0.0, 1.0)
            
            # Apply clockwise rotation if enabled (for portrait mode clients)
            rotate_clockwise = self._config_manager.get('model.rotate_bbox_clockwise', False)
            if rotate_clockwise:
                # VECTORIZED: Rotate 90° clockwise: (x, y, w, h) -> (y, 1-x-w, h, w)
                # This transforms from landscape to portrait orientation
                final_x = norm_y.copy()
                final_y = 1.0 - norm_x - norm_w
                final_w = norm_h.copy()
                final_h = norm_w.copy()
                
                self._logger.debug("[POSTPROCESS] Applied clockwise rotation to all bboxes")
            else:
                final_x = norm_x
                final_y = norm_y
                final_w = norm_w
                final_h = norm_h
            
            # Build detections list (still need loop for dict creation, but math is vectorized)
            detections = []
            num_detections = len(valid_detections)
            
            for i in range(num_detections):
                class_idx = class_id_all[i]
                class_name = self._class_names[class_idx] if class_idx < len(self._class_names) else str(class_idx)
                
                detections.append({
                    "class_name": class_name,
                    "confidence": float(conf_all[i]),
                    "bbox": {
                        "x_min": float(final_x[i]),
                        "y_min": float(final_y[i]),
                        "width": float(final_w[i]),
                        "height": float(final_h[i])
                    }
                })
            
            result["detections"] = detections
            
            self._logger.debug(f"[POSTPROCESS] Returned {num_detections} detections")
            
        except Exception as e:
            self._logger.error(f"Error in postprocess: {e}", exc_info=True)
        
        return result
    
    def process_frame(self, frame: np.ndarray) -> Dict[str, Any]:
        """
        Proses frame menggunakan model AI.
        
        Args:
            frame: Frame yang akan diproses
            
        Returns:
            Dictionary berisi hasil inferensi
        """
        # Store original frame shape for bbox normalization
        original_shape = frame.shape
        
        # Preprocess frame
        processed_frame = self.preprocess_frame(frame)
        
        # Dapatkan model dari pool
        model = self._model_pool.acquire()
        
        try:
            # Lakukan inferensi
            output = model.predict(processed_frame)
            
            # Postprocess output with original frame shape for correct normalization
            result = self.postprocess_output(output, original_shape=original_shape)
            
            self._logger.debug("Frame processed successfully")
            return result
            
        except Exception as e:
            self._logger.error(f"Error processing frame: {e}")
            raise
        finally:
            # Kembalikan model ke pool
            self._model_pool.release(model)
    
    def process_batch(self, frames: List[np.ndarray]) -> List[Dict[str, Any]]:
        """
        Proses batch frame menggunakan model AI.
        
        Args:
            frames: List frame yang akan diproses
            
        Returns:
            List berisi hasil inferensi untuk setiap frame
        """
        results = []
        
        for frame in frames:
            result = self.process_frame(frame)
            results.append(result)
        
        self._logger.debug(f"Processed batch of {len(frames)} frames")
        return results

    def get_pool_stats(self) -> Dict[str, int]:
        """
        Mendapatkan statistik pool.
        
        Returns:
            Dictionary berisi statistik pool
        """
        return {
            "pool_size": self._model_pool.size(),
            "in_use": self._model_pool.in_use_count()
        }
    
    def set_target_size(self, target_size: Tuple[int, int]) -> None:
        """
        Mengatur ukuran target untuk resize frame.
        
        Args:
            target_size: Ukuran target (width, height)
        """
        self._target_size = target_size
        self._logger.info(f"Target size set to {target_size}")
    
    def set_normalize(self, normalize: bool) -> None:
        """
        Mengatur apakah akan melakukan normalisasi pixel.
        
        Args:
            normalize: True untuk normalisasi, False untuk tidak
        """
        self._normalize = normalize
        self._logger.info(f"Normalize set to {normalize}")