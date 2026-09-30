# PP-OCRv6 (Medium 34.5M) 文本识别镜像 —— CPU 推理，自包含可离线复现
# 构建上下文：mediation-deploy/paddle/pp-ocrv6 目录（compose 已设置 context: ./pp-ocrv6）
#
# 离线能力：
#   * paddlepaddle 3.3.0 (184MB) 由 pp-ocrv6/wheels/ 下的轮子离线安装；
#     若删除 wheels/*.whl 会自动回退在线安装 paddlepaddle==3.3.0。
#   * PP-OCRv6 模型权重在构建期预热并烘焙进镜像 /root/.paddlex/official_models，
#     运行期不再联网下载 => 不要给容器挂载覆盖 /root/.paddlex 的卷。

FROM docker.m.daocloud.io/library/python:3.10-slim

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_INDEX_URL=https://pypi.org/simple \
    PIP_EXTRA_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple \
    PIP_TRUSTED_HOST="pypi.tuna.tsinghua.edu.cn pypi.org" \
    PADDLE_PDX_MODEL_SOURCE=modelscope \
    PADDLE_PDX_DISABLE_MODEL_SOURCE_CHECK=True \
    PYTHONUNBUFFERED=1

# 国内 apt 源加速
RUN sed -i 's#deb.debian.org#mirrors.tuna.tsinghua.edu.cn#g' \
        /etc/apt/sources.list.d/*.sources /etc/apt/sources.list 2>/dev/null || true

RUN apt-get update && apt-get install -y --no-install-recommends \
        libgl1 libglib2.0-0 libsm6 libxext6 libxrender1 libgomp1 \
        fonts-dejavu-core fonts-liberation curl ca-certificates \
    && rm -rf /var/lib/apt/lists/*

# 1) paddlepaddle CPU 3.3.0 —— 优先离线轮子，缺失时回退在线安装
COPY wheels /wheels
RUN if ls /wheels/*.whl >/dev/null 2>&1; then \
        echo "[build] install paddlepaddle from offline wheel" \
        && pip install --no-cache-dir /wheels/*.whl; \
    else \
        echo "[build] install paddlepaddle online" \
        && pip install --no-cache-dir paddlepaddle==3.3.0; \
    fi

# 2) 上层依赖 + 服务栈
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# 3) 构建期预热 PP-OCRv6 权重（顺便暴露 oneDNN 兼容性问题，见 app.py 文件头）
#    注意：必须 enable_mkldnn=False，否则预热阶段就会崩
RUN python -c "from paddleocr import PaddleOCR; PaddleOCR(enable_mkldnn=False, device='cpu')"

WORKDIR /app
COPY app.py /app/app.py

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=20s --retries=3 \
    CMD curl -f http://localhost:8000/health || exit 1

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
