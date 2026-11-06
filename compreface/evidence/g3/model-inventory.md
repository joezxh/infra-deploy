# G3-1 模型名与版本清单（已坐实）

素材来源：`mediation-deploy/compreface/guide.md` §1.3、`.env.example` 的 SHA256 期望值、
`build/core-build/Dockerfile`、`scripts/verify.ps1` 第 0 段离线校验（9/9 通过）。

| 角色 | 模型 | 版本 / 权重文件 | 大小 | SHA256 | 许可 | 加载方式 |
|---|---|---|---|---|---|---|
| 人脸检测 | YuNet（OpenCV Zoo） | `face_detection_yunet_2023mar.onnx`（2023mar） | 227 KB | `8F2383E4DD3CFBB4553EA8718107FC0423210DC964F9F4280604804ED2552FA4` | Apache-2.0（OpenCV 系） | `cv2.FaceDetectorYN`，插件 `yunet.FaceDetector@yunet_2023mar` |
| 识别 / 1:1 特征 | SFace（OpenCV Zoo） | `face_recognition_sface_2021dec.onnx`（2021dec） | 37 MB | `0BA9FBFA01B5270C96627C4EF784DA859931E02F04419C829E83484087C34E79` | Apache-2.0（OpenCV 系） | `cv2.FaceRecognizerSF`，128 维 L2 归一化，插件 `sface.Calculator@sface_2021dec` |

**运行时**

- 自定义镜像 `compreface-core-yunet-sface:1.2.0`，基于官方 `exadel/compreface-core:1.2.0`。
- `opencv-contrib-python-headless==4.9.0.80`（提供 `FaceDetectorYN` / `FaceRecognizerSF`）。
- 权重以只读方式挂载 `./models` → 容器内 `/opt/face-weights`；`EXTRA_PLUGINS` 已置空，
  不加载 landmarks/agegender/mask/pose 等属性类插件。
- 选择器：`FACE_DETECTION_PLUGIN` / `CALCULATION_PLUGIN` 环境变量。
- 相似度由 CompreFace api 侧按欧氏距离换算（`/status` 的 `similarity_coefficients=[1.0, 5.0]`），
  与论文余弦口径不同；阈值必须按帧域 G2 标定。

**校验命令**

```powershell
.\scripts\verify.ps1        # 第 0 段离线比对两份 .onnx 的 SHA256
```

**待补**：权重许可全文快照与训练数据集许可条款见 `license-three-layer.md`；
本清单只证明「部署实际用了什么」，不证明全部合规。
