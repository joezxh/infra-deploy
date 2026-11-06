# emotion2vec_plus_large SER 推理镜像 —— 默认 CPU，可切 GPU（分支 A）
# 构建上下文：mediation-deploy/ser/emotion2vec
#
# 离线能力：
#   * torch/torchaudio 大体积轮子放 wheels/ 则离线安装；目录为空时回退在线 CPU 版
#   * 模型权重在构建期预热烘焙进镜像 /root/.cache/modelscope
#     => 运行期不联网，且不得挂载覆盖该目录的卷
#   * 严禁挂载任何音频卷（spec §9 落盘禁令在部署层的体现）

FROM docker.m.daocloud.io/library/python:3.10-slim

ARG SER_MODEL_ID=iic/emotion2vec_plus_large

ENV DEBIAN_FRONTEND=noninteractive \
    PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple \
    PIP_TRUSTED_HOST=pypi.tuna.tsinghua.edu.cn \
    USE_TF=0 USE_FLAX=0 HF_HUB_OFFLINE=1 \
    SER_MODEL_ID=${SER_MODEL_ID} \
    PYTHONUNBUFFERED=1

RUN sed -i 's#deb.debian.org#mirrors.tuna.tsinghua.edu.cn#g' \
        /etc/apt/sources.list.d/*.sources /etc/apt/sources.list 2>/dev/null || true

RUN apt-get update && apt-get install -y --no-install-recommends \
        ffmpeg libsox-dev libgl1 libglib2.0-0 \
        curl ca-certificates fonts-dejavu-core \
    && rm -rf /var/lib/apt/lists/*

# 1) 优先离线 wheels（含 torch/torchaudio），缺失则在线装 CPU 版
COPY wheels /wheels
RUN if ls /wheels/*.whl >/dev/null 2>&1; then \
        echo "[build] install from offline wheels" \
        && pip install --no-cache-dir /wheels/*.whl; \
    else \
        echo "[build] install torch CPU online" \
        && pip install --no-cache-dir \
             torch==2.3.1 torchaudio==2.3.1 \
             --index-url https://download.pytorch.org/whl/cpu; \
    fi

# 2) 服务栈与推理库
COPY requirements.txt /tmp/requirements.txt
RUN pip install --no-cache-dir -r /tmp/requirements.txt

# 3) 权重不在构建期烘焙：emotion2vec_plus_large 实际约 1.8GB，烘焙会撑大镜像并拖慢
#    §8.4 U4 的 ready 耗时。改为运行时把 mediation-deploy/ser/models 只读挂到 /models
#    （见 docker-compose.yml），app.py 的 get_model() 优先加载 /models；未挂载时回退
#    在线 model id（需联网）。构建期不联网拉权重，离线可构建。

WORKDIR /app
COPY app.py /app/app.py

EXPOSE 8000

HEALTHCHECK --interval=30s --timeout=5s --start-period=120s --retries=3 \
    CMD curl -f http://127.0.0.1:8000/health || exit 1

CMD ["uvicorn", "app:app", "--host", "0.0.0.0", "--port", "8000"]
