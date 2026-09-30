#Requires -Version 5.1
<#
.SYNOPSIS
    停止并移除 PaddleOCR 相关容器（保留镜像与 .env，便于再次启动）。
    加 -Volumes 会额外删除匿名卷（模型缓存会丢失，需重新下载）。
#>
param([switch]$Volumes)

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

$args = @('compose', 'down', '--remove-orphans')
if ($Volumes) { $args += '-v' }

Write-Host "[stop] docker $($args -join ' ')" -ForegroundColor Cyan
docker @args
if ($LASTEXITCODE -eq 0) { Write-Host "[  ok  ] 已停止" -ForegroundColor Green }
else { Write-Host "[ fail ] 停止失败" -ForegroundColor Red; exit 1 }
