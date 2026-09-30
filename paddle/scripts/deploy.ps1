#Requires -Version 5.1
<#
.SYNOPSIS
    PaddleOCR 一键部署：PP-OCRv6 (CPU) + Nginx 反代鉴权。

.DESCRIPTION
    1. 检查 docker / nvidia runtime
    2. 首次运行自动生成 .env（随机 API_KEY）
    3. 构建 PP-OCRv6 镜像
    4. docker compose up -d 并等待 pp-ocrv6 健康
    5. 打印调用示例

.EXAMPLE
    .\scripts\deploy.ps1
#>

# 用 Continue + 显式检查 $LASTEXITCODE：docker 等原生命令会往 stderr 输出 WARNING，
# 在 Stop 模式下会被 PowerShell 当成终止错误（即使已 2>$null）。
$ErrorActionPreference = 'Continue'

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

function Write-Step { param($m) Write-Host "[deploy] $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "[  ok  ] $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "[ warn ] $m" -ForegroundColor Yellow }
function Write-Fail { param($m) Write-Host "[ fail ] $m" -ForegroundColor Red }

function Wait-Healthy {
    param([string]$Container, [int]$Timeout = 600)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt $Timeout) {
        $st = docker inspect --format '{{.State.Health.Status}}' $Container 2>$null
        if ($LASTEXITCODE -eq 0 -and $st -eq 'healthy') { return $true }
        if ($st -eq 'unhealthy') { return $false }
        Start-Sleep -Seconds 5
    }
    return $false
}

# ---------- 1. 环境检查 ----------
Write-Step "检查 docker ..."
if (-not (Get-Command docker -ErrorAction SilentlyContinue)) { Write-Fail "未找到 docker，请先安装 Docker Desktop"; exit 1 }
try { docker version --format '{{.Server.Version}}' | Out-Null } catch { Write-Fail "docker daemon 未运行"; exit 1 }
Write-Ok "docker 可用"

# ---------- 2. .env ----------
if (-not (Test-Path ".env")) {
    Copy-Item ".env.example" ".env"
    $key = -join ((48..57 + 65..90 + 97..122) | Get-Random -Count 40 | ForEach-Object { [char]$_ })
    (Get-Content ".env") -replace '^API_KEY=.*', "API_KEY=$key" | Set-Content ".env"
    Write-Ok "已生成 .env 并写入随机 API_KEY"
} else { Write-Ok ".env 已存在" }

$apiKey = ((Get-Content ".env" | Where-Object { $_ -match '^API_KEY=' }) -replace '^API_KEY=', '').Trim()
$nginxPort = ((Get-Content ".env" | Where-Object { $_ -match '^NGINX_HTTP_PORT=' }) -replace '^NGINX_HTTP_PORT=', '').Trim()
if (-not $nginxPort) { $nginxPort = '80' }

# ---------- 3. 启动 ----------
Write-Step "启动服务（首次会构建 PP-OCRv6 镜像，耗时较长）..."
docker compose up -d --build pp-ocrv6 nginx
if ($LASTEXITCODE -ne 0) { Write-Fail "docker compose up 失败"; exit 1 }
Write-Ok "容器已创建"

# ---------- 4. 等待健康 ----------
Write-Step "等待 pp-ocrv6 就绪 ..."
if (Wait-Healthy -Container 'pp-ocrv6' -Timeout 600) { Write-Ok "pp-ocrv6 healthy" }
else { Write-Warn "pp-ocrv6 尚未 healthy（可能仍在加载模型），请稍后用 scripts\status.ps1 复查" }

# ---------- 5. 汇总 ----------
Write-Host ""
Write-Host "=============== 部署完成 ===============" -ForegroundColor Green
Write-Host "Nginx 入口 : http://localhost:$nginxPort"
Write-Host "API Key    : $apiKey"
Write-Host ""
Write-Host "健康检查："
Write-Host "  curl http://localhost:$nginxPort/nginx-health"
Write-Host "PP-OCRv6 文本识别："
Write-Host "  curl -H \"X-API-Key: $apiKey\" -F image=@samples\test-ocr.png http://localhost:$nginxPort/ocr/v6/ocr"
Write-Host ""
Write-Host "冒烟测试： .\scripts\verify.ps1"
