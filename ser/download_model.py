"""下载 emotion2vec_plus_large 权重到本地 models/（仅部署准备用，不进镜像）。
运行：python download_model.py
依赖：已 pip install modelscope（宿主 Python）。
"""
from modelscope import snapshot_download

LOCAL_DIR = "d:/work/mediation_platform/mediation-deploy/ser/models"
p = snapshot_download("iic/emotion2vec_plus_large", local_dir=LOCAL_DIR)
print("SAVED", p)
