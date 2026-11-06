#  SFace face recognizer plugin for CompreFace 1.2.0 (OpenCV Zoo ONNX, Apache-2.0)
#
#  Loaded by environment variable:
#      CALCULATION_PLUGIN=sface.Calculator@sface_2021dec
#  Which resolves to this module:
#      src/services/facescan/plugins/sface/sface.py:Calculator
#
#  Conforms to the CompreFace CalculatorMixin contract:
#      calc_embedding(face_img) -> Array1D (128-dim L2-normalized feature)
#
#  The 1:1 comparison itself is performed by CompreFace core (Java side) on the
#  two embeddings; this plugin only extracts the feature. The platform therefore
#  holds no subject gallery and no persisted vectors (SP-3 red line).

import os
import logging
import numpy as np
import cv2
from cached_property import cached_property

from src.services.facescan.plugins import mixins, base

logger = logging.getLogger(__name__)


class Calculator(mixins.CalculatorMixin, base.BasePlugin):
    # ml_models entry: (name, google_drive_id(unused), similarity_coefficients, difference_threshold)
    # CompreFace verification similarity = (tanh((c0 - euclidean_distance) * c1) + 1) / 2
    # SFace features are L2-normalized, so euclidean_distance lies in [0, 2].
    #   c0 = 1.0 (midpoint of the [0, 2] range)
    #   c1 = 5.0  => d=0 -> ~1.0 (same), d=1.4 -> ~0.0 (different)
    # These are PoC defaults; RECALCULATE during G2 threshold calibration on real data.
    ml_models = (
        ('sface_2021dec', '', (1.0, 5.0), 0.4),
    )
    EMBEDDING_SIZE = 128

    @property
    def _weights_dir(self):
        return os.environ.get('FACE_WEIGHTS_DIR', '/opt/face-weights')

    @property
    def _model_path(self):
        name = os.environ.get('FACE_REC_MODEL', 'face_recognition_sface_2021dec.onnx')
        return os.path.join(self._weights_dir, name)

    @cached_property
    def _recognizer(self):
        if not os.path.exists(self._model_path):
            raise FileNotFoundError(
                f'SFace ONNX weight not found at {self._model_path}. '
                f'Mount weights into {self._weights_dir} (compose: ./models:/opt/face-weights:ro).')
        return cv2.FaceRecognizerSF.create(self._model_path, '')

    def calc_embedding(self, face_img: np.ndarray) -> np.ndarray:
        # face_img is the cropped face (RGB). Note: the CompreFace crop pipeline
        # (squish_img -> skimage.transform.resize) yields float64 in [0, 1], so we
        # normalize to uint8 BGR before feeding OpenCV.
        arr = np.asarray(face_img)
        if arr.dtype != np.uint8:
            arr = (arr * 255.0).clip(0, 255).astype(np.uint8)
        bgr = cv2.cvtColor(arr, cv2.COLOR_RGB2BGR)
        # SFace feature extraction on a centered square crop. Face alignment via
        # landmarks is a G2 calibration improvement and can raise 1:1 accuracy.
        feat = self._recognizer.feature(bgr)
        return np.asarray(feat, dtype=np.float64).flatten()
