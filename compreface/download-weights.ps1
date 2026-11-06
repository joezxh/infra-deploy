# 下载 YuNet + SFace ONNX 权重（OpenCV Zoo，Apache-2.0）到 ./models
# 墙内通过 ghproxy.net 镜像 GitHub raw 仓库获取。
$ErrorActionPreference = 'Stop'
$base = 'https://ghproxy.net/https://raw.githubusercontent.com/opencv/opencv_zoo/master/models'
$dest = Join-Path $PSScriptRoot 'models'
New-Item -ItemType Directory -Force -Path $dest | Out-Null

$items = @(
  @{ file = 'face_detection_yunet_2023mar.onnx';  path = 'face_detection_yunet/face_detection_yunet_2023mar.onnx' },
  @{ file = 'face_recognition_sface_2021dec.onnx'; path = 'face_recognition_sface/face_recognition_sface_2021dec.onnx' }
)

foreach ($it in $items) {
  $url = "$base/$($it.path)"
  $out = Join-Path $dest $it.file
  if (Test-Path $out) { Write-Host "skip $($it.file)"; continue }
  Write-Host "download $($it.file) <- $url"
  curl.exe -L -o $out $url
  if (-not (Test-Path $out) -or (Get-Item $out).Length -lt 100KB) {
    Write-Error "download failed or too small: $($it.file)"
  }
}

Write-Host "`nSHA256 (回填到 .env 的 FACE_DET_SHA256 / FACE_REC_SHA256):"
Get-FileHash -Algorithm SHA256 (Join-Path $dest '*.onnx') | ForEach-Object { Write-Host "$($_.Hash)  $($_.Path)" }
