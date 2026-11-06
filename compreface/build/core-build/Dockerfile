# 自定义 compreface-core：注入 YuNet 检测 + SFace 识别插件
#
# 基于官方 exadel/compreface-core:1.2.0（仅 core 重建；api/admin/fe 复用官方镜像）。
# 设计要点：
#   * 官方镜像自带的 opencv-python 4.4.0.46 不含 contrib 的 FaceDetectorYN /
#     FaceRecognizerSF，替换为 opencv-contrib-python-headless（自带 ONNX 推理后端，
#     无需额外 onnxruntime 依赖）。
#   * 权重文件由 compose 以只读卷挂到 /opt/face-weights，不烘焙进镜像。
#   * 插件代码在基础镜像构建（含 build-time 的 setup.py / Google Drive 下载）之后
#     才注入，因此不会触发任何模型下载；运行期直接从挂载路径加载 ONNX。

FROM exadel/compreface-core:1.2.0

# 替换 opencv 为 contrib 版本（提供 cv2.FaceDetectorYN / cv2.FaceRecognizerSF）
# 走清华 PyPI 镜像，避免依赖宿主/daemon 的死代理桥接（http.docker.internal:3128）。
# build 阶段通过 --build-arg HTTP_PROXY= HTTPS_PROXY= 清除 daemon 注入的代理。
RUN pip uninstall -y opencv-python opencv-contrib-python 2>/dev/null; \
    pip install --no-cache-dir -i https://pypi.tuna.tsinghua.edu.cn/simple \
        numpy==1.23.5 opencv-contrib-python-headless==4.9.0.80

# 注入 YuNet 检测 + SFace 识别插件（包名.yunet/yunet.py:FaceDetector 等）
COPY yunet /app/ml/src/services/facescan/plugins/yunet
COPY sface /app/ml/src/services/facescan/plugins/sface

# 将 EXTRA_PLUGINS 的进程内默认值改为空串：
# core 的 get_env 对「空串」会回退默认值（landmarks/agegender/mask/pose），
# 仅靠环境变量留空挡不住；SP-3 只允许检测 + 1:1，不产出任何属性类插件。
# 置空后仍可用 EXTRA_PLUGINS 环境变量按需追加插件。
RUN sed -i "s|get_env_split('EXTRA_PLUGINS', 'facenet.LandmarksDetector,agegender.AgeDetector,agegender.GenderDetector,facenet.facemask.MaskDetector,facenet.PoseEstimator')|get_env_split('EXTRA_PLUGINS', '')|" \
    /app/ml/src/constants.py

# 默认插件（可由 docker-compose 环境变量覆盖）
ENV FACE_DETECTION_PLUGIN=yunet.FaceDetector@yunet_2023mar \
    CALCULATION_PLUGIN=sface.Calculator@sface_2021dec \
    EXTRA_PLUGINS=""

WORKDIR /app/ml
