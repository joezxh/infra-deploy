Set-Location (Split-Path -Parent $PSScriptRoot)
docker compose down
Write-Output '容器已停止；本部署件无命名卷（音频不落盘）'
