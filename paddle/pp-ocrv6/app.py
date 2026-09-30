"""PP-OCRv6 (Medium 34.5M) 文本识别服务 —— CPU 推理，零显存占用。

端点
----
GET  /health  -> {"status":"ok","gpu_available":false,"model":"PP-OCRv6_medium","ready":true}
POST /ocr     (multipart: image=<file>)  -> 见下方返回结构
POST /api/ocr 与 /ocr 等价，兼容既有 Java PaddleOcrClient 契约。

返回结构
--------
{
  "status": "success",
  "data": [{"text": "识别到的全部文本（按行以换行符拼接）"}],   # 兼容旧客户端
  "lines": [                                                  # 逐行明细
    {"text": "纯臻营养护发素", "score": 0.9999, "box": [52, 4, 160, 20]}
  ],
  "count": 34
}

两个必须保留的修复（详见 ../../README.md 故障排查）
--------------------------------------------------
1. paddlepaddle 3.3.0 CPU 上，PP-OCRv6_medium_det 走 oneDNN(PIR) 会抛
   NotImplementedError: ConvertPirAttribute2RuntimeAttribute not support
   [pir::ArrayAttribute<pir::DoubleAttribute>] (onednn_instruction.cc:116)
   => 必须 enable_mkldnn=False（环境变量 OCR_ENABLE_MKLDNN 控制，默认关闭）。
2. 结果字段在 result[i].json["res"] 内（rec_texts / rec_scores / rec_boxes），
   不在 result[i].json 顶层。
"""
import asyncio
import os
import threading
from io import BytesIO
from typing import Any, Dict, List, Optional

import numpy as np
import uvicorn
from fastapi import FastAPI, File, HTTPException, UploadFile
from PIL import Image

app = FastAPI(title="PP-OCRv6 (Medium) OCR Service", version="1.0.0")

MODEL_NAME = os.environ.get("OCR_MODEL", "PP-OCRv6_medium")
# 见文件头说明 (1)：默认关闭 oneDNN，否则 PP-OCRv6 det 模型在 paddle 3.3.0 CPU 下崩溃
ENABLE_MKLDNN = os.environ.get("OCR_ENABLE_MKLDNN", "false").strip().lower() in (
    "1",
    "true",
    "yes",
    "on",
)
CPU_THREADS = int(os.environ.get("OCR_CPU_THREADS", "10"))

_lock = threading.Lock()
_ocr_model = None


def _str2bool(v: Optional[str], default: bool) -> bool:
    if v is None:
        return default
    return v.strip().lower() in ("1", "true", "yes", "on")


def get_ocr():
    """惰性加载 PP-OCRv6（默认即 Medium 34.5M 服务端高精度模型）。"""
    global _ocr_model
    if _ocr_model is None:
        with _lock:
            if _ocr_model is None:
                from paddleocr import PaddleOCR

                _ocr_model = PaddleOCR(
                    enable_mkldnn=ENABLE_MKLDNN,
                    cpu_threads=CPU_THREADS,
                    device="cpu",
                )
    return _ocr_model


def _decode_image(data: bytes) -> np.ndarray:
    """字节流转 RGB numpy 数组（paddlex 管道最稳的输入形式）。"""
    try:
        img = Image.open(BytesIO(data))
        if img.mode != "RGB":
            img = img.convert("RGB")
        return np.array(img)
    except Exception as e:  # 非图片/损坏文件
        raise HTTPException(status_code=400, detail=f"invalid image: {e}")


def _extract(res: Dict[str, Any]) -> List[Dict[str, Any]]:
    """从 result[i].json['res'] 提取逐行文本/置信度/框。"""
    texts = res.get("rec_texts") or []
    scores = res.get("rec_scores") or []
    boxes = res.get("rec_boxes") or res.get("dt_polys") or []
    lines: List[Dict[str, Any]] = []
    for i, t in enumerate(texts):
        score = float(scores[i]) if i < len(scores) else None
        box = boxes[i] if i < len(boxes) else None
        lines.append({"text": str(t), "score": score, "box": box})
    return lines


def _run_ocr(data: bytes) -> Dict[str, Any]:
    img = _decode_image(data)
    ocr = get_ocr()
    result = ocr.predict(img)

    lines: List[Dict[str, Any]] = []
    for r in result:
        j = r.json if hasattr(r, "json") else r
        if not isinstance(j, dict):
            continue
        res = j.get("res", j)  # 见文件头说明 (2)
        if isinstance(res, dict):
            lines.extend(_extract(res))

    full_text = "\n".join(line["text"] for line in lines).strip()
    return {
        "status": "success",
        # 兼容旧客户端：data 数组内单元素承载全文
        "data": [{"text": full_text}],
        "lines": lines,
        "count": len(lines),
    }


@app.get("/health")
def health():
    return {
        "status": "ok",
        "gpu_available": False,
        "model": MODEL_NAME,
        "ready": _ocr_model is not None,
    }


@app.post("/ocr")
async def ocr(image: UploadFile = File(...)):
    data = await image.read()
    if not data:
        raise HTTPException(status_code=400, detail="empty image")
    try:
        # 同步推理放入线程池，避免阻塞事件循环
        return await asyncio.to_thread(_run_ocr, data)
    except HTTPException:
        raise
    except Exception as e:
        raise HTTPException(status_code=500, detail=f"ocr failed: {e}")


@app.post("/api/ocr")
async def api_ocr(image: UploadFile = File(...)):
    """与 /ocr 等价，兼容既有客户端路径。"""
    return await ocr(image)


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8000")))
