#Requires -Version 5.1
<#
.SYNOPSIS
    CompreFace 部署件状态与探活（未实测环境下的诊断入口）。
.EXAMPLE
    .\scripts\status.ps1
#>

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

$envPath = Join-Path $Root '.env'
if (-not (Test-Path $envPath)) { Write-Host '[fail] 缺少 .env，请先运行 deploy.ps1' -ForegroundColor Red; exit 1 }
$envLines = Get-Content $envPath
function Get-EnvValue($name) {
    $v = ($envLines | Where-Object { $_ -match "^$name=" } | Select-Object -First 1)
    if (-not $v) { return '' }
    ($v -replace "^$name=", '').Trim()
}
$nginxPort = Get-EnvValue 'COMPREFACE_NGINX_PORT'; if (-not $nginxPort) { $nginxPort = '8050' }
$uiPort = Get-EnvValue 'COMPREFACE_UI_PORT'; if (-not $uiPort) { $uiPort = '8051' }
$apiKey = Get-EnvValue 'API_KEY'

Write-Host '===== 1. 容器状态 =====' -ForegroundColor Cyan
& docker compose -f (Join-Path $Root 'docker-compose.yml') --env-file $envPath ps
if ($LASTEXITCODE -ne 0) { Write-Host "[warn] docker compose ps 退出码 $LASTEXITCODE" -ForegroundColor Yellow }

Write-Host ''
Write-Host '===== 2. 外层 nginx 探针 =====' -ForegroundColor Cyan
try {
    $h = Invoke-RestMethod -Uri "http://127.0.0.1:$nginxPort/face-nginx-health" -TimeoutSec 10
    Write-Host ("[ ok ] {0}" -f ($h | ConvertTo-Json -Compress)) -ForegroundColor Green
} catch { Write-Host "[fail] nginx 探针不可达：$($_.Exception.Message)" -ForegroundColor Red }

Write-Host ''
Write-Host '===== 3. 业务级探活（带 X-API-Key 的 detection 请求，需样例图） =====' -ForegroundColor Cyan
$sample = Join-Path $Root 'samples\face.jpg'
if (-not (Test-Path $sample)) {
    Write-Host "[skip] 缺少 $sample；业务级探活请运行 verify.ps1" -ForegroundColor Yellow
} else {
    $raw = & curl.exe -s -w "`n%{http_code}" -H "X-API-Key: $apiKey" `
          -F "file=@$sample" "http://127.0.0.1:$nginxPort/face/api/v1/detection/detect" 2>$null
    Write-Host ("[info] {0}" -f ($raw -join ' ')) -ForegroundColor Gray
}

Write-Host ''
Write-Host '===== 4. 回环 UI（仅运维，不对外） =====' -ForegroundColor Cyan
Write-Host "http://127.0.0.1:$uiPort/login"

Write-Host ''
Write-Host '===== 5. 资源占用 =====' -ForegroundColor Cyan
& docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}"
