#Requires -Version 5.1
<#
.SYNOPSIS
    查看 PaddleOCR 各服务状态与最近日志。
.EXAMPLE
    .\scripts\status.ps1
    .\scripts\status.ps1 -Logs pp-ocrv6
#>
param([string]$Logs)

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

if ($Logs) {
    docker compose logs --tail 100 -f $Logs
    return
}

Write-Host "=========== 容器状态 ===========" -ForegroundColor Cyan
docker compose ps

Write-Host ""
Write-Host "=========== 直连健康检查（127.0.0.1，绕过 Nginx） ===========" -ForegroundColor Cyan
$envFile = Get-Content ".env" -ErrorAction SilentlyContinue
function Get-EnvValue($name) {
    ($envFile | Where-Object { $_ -match "^$name=" }) -replace "^$name=", ''
}
$ocrv6Port = Get-EnvValue 'OCRV6_PORT'; if (-not $ocrv6Port) { $ocrv6Port = '8011' }
$nginxPort = Get-EnvValue 'NGINX_HTTP_PORT'; if (-not $nginxPort) { $nginxPort = '80' }

foreach ($t in @(
    @{ Name = 'pp-ocrv6'; Url = "http://127.0.0.1:$ocrv6Port/health" },
    @{ Name = 'nginx';     Url = "http://127.0.0.1:$nginxPort/nginx-health" }
)) {
    try {
        $r = Invoke-RestMethod -Uri $t.Url -TimeoutSec 8
        Write-Host ("  {0,-18} OK   {1}" -f $t.Name, ($r | ConvertTo-Json -Compress))
    } catch {
        Write-Host ("  {0,-18} DOWN {1}" -f $t.Name, $_.Exception.Message) -ForegroundColor Yellow
    }
}

Write-Host ""
Write-Host "=========== 资源占用（pp-ocrv6 为 CPU 推理） ===========" -ForegroundColor Cyan
docker stats --no-stream --format "table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}" 2>$null
