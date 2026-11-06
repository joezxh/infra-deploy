"""emotion2vec_plus_large SER 服务（SP-4 设计 §4.2 契约的实现件，§8.2.5）。

端点
----
GET  /health  -> {"status":"ok","gpu_available":<bool>,"model":"<自报>",
                  "ready":<bool>,"persistence":false,"labels_supported":[...]}
POST /v1/audio/emotion (multipart: file=<wav 16k 单声道 int16>, sample_rate, language)
             -> {"emotion":"anger","confidence":0.68,"model":"...","latencyMs":412,
                 "rawLabel":"angry","scores":{...}}
             -> 400 音频非法 / 409 拒分类或静音 / 429 并发满 / 500 推理失败 / 502 返回体异常

三条刻意的设计
--------------
1. 不落盘：入参字节直接解码为 ndarray。若实测发现本版本 funasr 的 generate
   不接受数组而必须给路径（U1），只允许写 /dev/shm（内存盘）且 finally 删除，
   绝禁写持久卷。
2. 不静默降级：`other`/`unknown`、未知标签、全静音一律非 2xx，而不是回 `calm`。
   worker 侧收到非 2xx 即计一次 failure，连续达阈触发断路（§4.3 / §5.5）。
3. 单并发门：SER_MAX_INFLIGHT 满时 429，而不是排队——转录链路宁可丢一段情感，
   不可把字幕拖慢。

实测待办（spec §8.2.9 U1/U2，禁止当作已知）
-------------------------------------------
`funasr.AutoModel.generate` 是否直接收 ndarray、参数名 `fs` 还是 `sampling_rate`、
返回体 `labels` 的字面量形态，均须在 PoC 当场实测并回写本目录 README；
实装与此处的官方口径不一致时，**只允许改本文件**，不得改平台侧契约。
"""
from __future__ import annotations

import asyncio
import os
import re
import threading
import time
from io import BytesIO

import numpy as np
import uvicorn
from fastapi import FastAPI, File, Form, HTTPException, UploadFile

app = FastAPI(title="emotion2vec SER Service", version="1.0.0")

MODEL_ID = os.environ.get("SER_MODEL_ID", "iic/emotion2vec_plus_large")
DEVICE = os.environ.get("SER_DEVICE", "cpu")
MAX_INFLIGHT = int(os.environ.get("SER_MAX_INFLIGHT", "2"))
THREADS = int(os.environ.get("SER_TORCH_THREADS", "8"))
# 静音判据：PoC 门禁要求 3s 全静音不得回 200 calm；数值为设计值，实测后回写 README
SILENCE_RMS_FLOOR = float(os.environ.get("SER_SILENCE_RMS_FLOOR", "0.0001"))

# 官方 9 类 -> 平台 5 类（spec §8.2.4，与 worker 的 SER_EMOTIONS 同源）
LABEL_MAP = {
    "neutral": "calm", "happy": "calm",
    "fearful": "anxious", "sad": "anxious",
    "surprised": "agitated", "disgusted": "agitated",
    "angry": "anger",
}
# 模型主动拒分类：实测 emotion2vec_plus_large 输出标签集为
# {angry, happy, neutral, sad, unk}（U2 实测，非设计假设的 9 类），
# `unk` 即"无法分类"，与 `unknown`/`other` 同属拒分类，不得当成 calm
REJECT = {"other", "unknown", "unk"}

_lock = threading.Lock()
_sem = threading.Semaphore(MAX_INFLIGHT)
_model = None
_labels = None


def get_model():
    """惰性加载 + 双重检查锁；加载失败直接抛，绝不返回假模型。

    优先用本地挂载的权重目录（SER_MODEL_LOCAL_DIR，默认 /models，由 docker-compose
    把 mediation-deploy/ser/models 只读挂入）；缺失时回退在线 model id（需联网）。
    emotion2vec_plus_large 实际权重约 1.8GB，故不烘焙进镜像，改用运行时挂载。
    """
    global _model, _labels
    if _model is None:
        with _lock:
            if _model is None:
                import torch
                torch.set_num_threads(THREADS)
                from funasr import AutoModel
                local = os.environ.get("SER_MODEL_LOCAL_DIR", "/models")
                if os.path.isdir(local) and os.path.exists(os.path.join(local, "model.pt")):
                    model_path = local
                    print(f"[ser] loading local weights from {local}")
                else:
                    model_path = MODEL_ID
                    print(f"[ser] local weights absent, loading model id {MODEL_ID}")
                _model = AutoModel(model=model_path, device=DEVICE, disable_update=True)
                # 取模型自报标签表，不自行写死拼写变体
                _labels = getattr(getattr(_model, "model", None), "labels", None)
    return _model


def _norm(label: str) -> str:
    """容错取字母标签（U2 实测：emotion2vec_plus_large 真实标签形如 `难过/sad`
    中文/英文、`0: angry` 序号前缀、`<>` 包裹符）。统一取到可映射的英文 token。
    """
    s = re.sub(r"[<|>]", "", str(label)).strip().lower()
    if "/" in s:                      # 中文/英文 -> 取英文段
        s = s.split("/")[-1].strip()
    return s.split(":", 1)[-1].strip() if ":" in s else s


def _decode(data: bytes, rate: int) -> np.ndarray:
    """wav 字节 -> float32 单声道数组（不写磁盘）。"""
    if not data:
        raise HTTPException(status_code=400, detail="empty audio")
    try:
        import soundfile as sf
        arr, sr = sf.read(BytesIO(data), dtype="float32", always_2d=False)
    except Exception as exc:
        raise HTTPException(status_code=400, detail=f"invalid audio: {exc}")
    if arr.ndim > 1:
        arr = arr.mean(axis=1)
    if int(sr) != int(rate):
        raise HTTPException(status_code=400,
                            detail=f"sample_rate mismatch: got {sr}, want {rate}")
    if arr.size == 0:
        raise HTTPException(status_code=400, detail="empty pcm frames")
    return arr


def _run(data: bytes, rate: int) -> dict:
    if not _sem.acquire(blocking=False):
        raise HTTPException(status_code=429, detail="ser busy, retry later")
    try:
        audio = _decode(data, rate)
        # §8.4「拒分类行为」门禁：静音不是「平静」，不得回 200 calm
        rms = float(np.sqrt(np.mean(np.square(audio, dtype=np.float64))))
        if rms < SILENCE_RMS_FLOOR:
            raise HTTPException(status_code=409, detail="silent audio: refused classification")

        model = get_model()
        t0 = time.monotonic()
        # U1：若实测本版本必须传文件路径，只允许 /dev/shm + finally 删除（见文件头）
        res = model.generate(input=audio, fs=rate, sampling_rate=rate,
                             granularity="utterance", extract_embedding=False)
        first = (res[0] if isinstance(res, list) and res else res) or {}
        scores = first.get("scores") or first.get("emotion_scores") or []
        labels = first.get("labels") or _labels or []
        if not scores or len(scores) != len(labels):
            raise HTTPException(status_code=502,
                                detail=f"unexpected result shape: keys={list(first)[:8]}")
        idx = int(np.argmax(np.asarray(scores, dtype=np.float32)))
        raw = _norm(labels[idx])
        conf = round(float(scores[idx]), 4)
        if raw in REJECT:
            # 409 而不是 200：让 worker 计失败，不写标签（§5.5 失败语义）
            raise HTTPException(status_code=409,
                                detail=f"model refused classification: {raw}")
        emotion = LABEL_MAP.get(raw)
        if emotion is None:
            # 标签表与映射不一致 => 暴露而不是猜一个（与 asr_provider 的 raise 同源）
            raise HTTPException(status_code=502, detail=f"unmapped label: {raw!r}")
        return {"emotion": emotion, "confidence": conf, "model": MODEL_ID,
                "rawLabel": raw, "latencyMs": int((time.monotonic() - t0) * 1000),
                "scores": {_norm(k): round(float(v), 4) for k, v in zip(labels, scores)}}
    except HTTPException:
        raise
    except Exception as exc:
        raise HTTPException(status_code=500, detail=f"ser failed: {exc}")
    finally:
        _sem.release()


@app.get("/health")
def health():
    import torch
    return {"status": "ok",
            "gpu_available": bool(torch.cuda.is_available()),
            "device": DEVICE, "model": MODEL_ID,
            "ready": _model is not None,
            "persistence": False,  # 服务侧不得具备任何持久化（§9）
            "labels_supported": sorted(LABEL_MAP) + sorted(REJECT),
            "max_inflight": MAX_INFLIGHT}


@app.post("/v1/audio/emotion")
async def emotion(file: UploadFile = File(...),
                  sample_rate: int = Form(16000),
                  language: str = Form("zh")):
    return await asyncio.to_thread(_run, await file.read(), sample_rate)


if __name__ == "__main__":
    uvicorn.run(app, host="0.0.0.0", port=int(os.environ.get("PORT", "8000")))
