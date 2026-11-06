#  YuNet face detector plugin for CompreFace 1.2.0 (OpenCV Zoo ONNX, Apache-2.0)
#
#  Loaded by environment variable:
#      FACE_DETECTION_PLUGIN=yunet.FaceDetector@yunet_2023mar
#  Which resolves to this module:
#      src/services/facescan/plugins/yunet/yunet.py:FaceDetector
#
#  Conforms to the CompreFace FaceDetectorMixin contract:
#      find_faces(img, det_prob_threshold) -> List[BoundingBoxDTO]
#      crop_face(img, box) -> Array3D

import os
import logging
import numpy as np
import cv2
from cached_property import cached_property

from src.services.dto.bounding_box import BoundingBoxDTO
from src.services.facescan.plugins import mixins, base
from src.services.facescan.imgscaler.imgscaler import ImgScaler
from src.services.imgtools.types import Array3D
from src.services.imgtools.proc_img import crop_img, squish_img

logger = logging.getLogger(__name__)

# OpenCV YuNet detect() returns, per face:
#   x, y, w, h, x_re, y_re, x_le, y_le, x_nt, y_nt, x_mr, y_mr, x_ml, y_ml, score
# Map to CompreFace KEYPOINTS_ORDER = left_eye, right_eye, nose, mouth_left, mouth_right
YUNET_LANDMARKS = [
    (6, 7),    # left_eye
    (4, 5),    # right_eye
    (8, 9),    # nose
    (12, 13),  # mouth_left
    (10, 11),  # mouth_right
]

# YuNet default input size; overridden per image via setInputSize.
_YUNET_INPUT_SIZE = (320, 320)


class FaceDetector(mixins.FaceDetectorMixin, base.BasePlugin):
    IMG_LENGTH_LIMIT = 640
    IMAGE_SIZE = 112  # SFace recognizer input size

    @property
    def _weights_dir(self):
        return os.environ.get('FACE_WEIGHTS_DIR', '/opt/face-weights')

    @property
    def _model_path(self):
        name = os.environ.get('FACE_DET_MODEL', 'face_detection_yunet_2023mar.onnx')
        return os.path.join(self._weights_dir, name)

    @cached_property
    def _detector(self):
        if not os.path.exists(self._model_path):
            raise FileNotFoundError(
                f'YuNet ONNX weight not found at {self._model_path}. '
                f'Mount weights into {self._weights_dir} (compose: ./models:/opt/face-weights:ro).')
        # opencv-contrib 4.7 FaceDetectorYN.create signature is positional:
        #   create(model, config, input_size, scoreThreshold, nmsThreshold, topK)
        score = float(os.environ.get('FACE_MIN_DET_SCORE', '0.5'))
        det = cv2.FaceDetectorYN.create(
            self._model_path, "", _YUNET_INPUT_SIZE, score, 0.3, 5000)
        return det

    def crop_face(self, img: Array3D, box: BoundingBoxDTO) -> Array3D:
        # Squish to 112x112 (SFace input). Face alignment via landmarks is a
        # G2 calibration improvement; a centered square crop is sufficient for the PoC.
        return squish_img(crop_img(img, box), (self.IMAGE_SIZE, self.IMAGE_SIZE))

    def find_faces(self, img: Array3D, det_prob_threshold: float = None) -> list:
        if det_prob_threshold is None:
            det_prob_threshold = float(os.environ.get('FACE_MIN_DET_SCORE', '0.5'))
        assert 0 <= det_prob_threshold <= 1

        scaler = ImgScaler(self.IMG_LENGTH_LIMIT)
        scaled = scaler.downscale_img(img)
        h, w = scaled.shape[:2]

        # CompreFace images are RGB; OpenCV DNN operates on BGR.
        bgr = cv2.cvtColor(scaled, cv2.COLOR_RGB2BGR)
        self._detector.setInputSize((w, h))
        _, faces = self._detector.detect(bgr)
        if faces is None:
            faces = []

        boxes = []
        for f in faces:
            score = float(f[14])
            if score < det_prob_threshold:
                continue
            x, y, fw, fh = f[0], f[1], f[2], f[3]
            x_min = int(max(0, round(x)))
            y_min = int(max(0, round(y)))
            x_max = int(min(w, round(x + fw)))
            y_max = int(min(h, round(y + fh)))
            if x_max <= x_min or y_max <= y_min:
                continue
            landmarks = np.array(
                [[f[i], f[j]] for (i, j) in YUNET_LANDMARKS], dtype=float)
            boxes.append(BoundingBoxDTO(
                x_min=x_min, y_min=y_min, x_max=x_max, y_max=y_max,
                probability=score, np_landmarks=landmarks))

        # Map coordinates back to the original (un-scaled) image space.
        return [box.scaled(scaler.upscale_coefficient) for box in boxes]
