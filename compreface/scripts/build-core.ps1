# build-core.ps1 — 构建自定义 compreface-core 镜像（YuNet 检测 + SFace 识别）
#
# 前置：
#   * Docker Desktop 出网正常（必要时清掉系统死代理并重启 Docker Desktop，见 README 故障排查）。
#   * ./models 下已存在 face_detection_yunet_2023mar.onnx 与
#     face_recognition_sface_2021dec.onnx（由 download-weights.ps1 经代理拉取，不入仓）。
#
# 用法：.\scripts\build-core.ps1
#   -ImageTag <tag>   自定义镜像 tag（默认 compreface-core-yunet-sface:1.2.0，须与 .env 的 COMPREFACE_CORE_IMAGE 一致）

param(
    [string]$ImageTag = "compreface-core-yunet-sface:1.2.0"
)

$ErrorActionPreference = "Stop"
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)  # .../compreface
$buildCtx = Join-Path $root "build/core-build"
$dockerfile = Join-Path $buildCtx "Dockerfile"

Write-Host "==> 构建自定义 compreface-core 镜像: $ImageTag"
Write-Host "    构建上下文: $buildCtx"

if (-not (Test-Path $dockerfile)) {
    Write-Error "找不到 Dockerfile: $dockerfile"
    exit 1
}

# 校验权重存在（仅提示，不阻断；缺失时容器启动会因 FileNotFoundError 失败）
$weights = @(
    (Join-Path $root "models/face_detection_yunet_2023mar.onnx"),
    (Join-Path $root "models/face_recognition_sface_2021dec.onnx")
)
foreach ($w in $weights) {
    if (Test-Path $w) {
        Write-Host "    [OK] 权重存在: $w"
    } else {
        Write-Warning "    权重缺失: $w —— 请先运行 download-weights.ps1 或手动放入 ./models"
    }
}

# 清除 daemon 注入的死代理（http.docker.internal:3128），PyPI 改用清华镜像（见 Dockerfile）。
docker build -f $dockerfile -t $ImageTag $buildCtx `
    --build-arg HTTP_PROXY= --build-arg HTTPS_PROXY= `
    --build-arg PIP_INDEX_URL=https://pypi.tuna.tsinghua.edu.cn/simple
if ($LASTEXITCODE -ne 0) {
    Write-Error "docker build 失败，请检查 Docker 出网与镜像源配置（README 故障排查）。"
    exit $LASTEXITCODE
}

Write-Host "==> 构建完成: $ImageTag"
Write-Host "    接下来运行 .\scripts\deploy.ps1 生成 .env 并启动（compose 将引用该镜像）。"
