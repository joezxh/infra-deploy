# SP-4 SER 停止（spec §8.2.8）：保留 -Volumes 开关，本编排默认无命名卷
param([switch]$Volumes)

$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

if ($Volumes) { docker compose --env-file .env down -v }
else { docker compose --env-file .env down }

Write-Output '容器已停止。模型权重烘焙在镜像内，重启无需重新下载；音频与中间向量不落盘、无卷可清。'
Write-Output '提醒：停止 SER 服务后，服务端 /analyze/status 的 ser 行应变为 available=false（§8.4「无静默降级」门禁）。'
