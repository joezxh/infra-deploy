#Requires -Version 5.1
<#
.SYNOPSIS
    停止 CompreFace 部署件。默认保留命名卷（模型与元数据不重下、不丢管理员账号）。
.PARAMETER Volumes
    连同命名卷一起删除。**危险**：会删除 CompreFace 侧全部管理数据与可能的人脸样例，
    仅在完成数据删除审批、且已按 G3 留档后使用。
.EXAMPLE
    .\scripts\stop.ps1
    .\scripts\stop.ps1 -Volumes
#>
param([switch]$Volumes)

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root
$envPath = Join-Path $Root '.env'

Write-Host '===== 停止 CompreFace =====' -ForegroundColor Cyan
if ($Volumes) {
    Write-Host '[warn] -Volumes 将物理删除 compreface-postgres-data 命名卷' -ForegroundColor Yellow
    & docker compose -f (Join-Path $Root 'docker-compose.yml') --env-file $envPath down -v
} else {
    & docker compose -f (Join-Path $Root 'docker-compose.yml') --env-file $envPath down
}
if ($LASTEXITCODE -ne 0) { Write-Host "[fail] docker compose down 退出码 $LASTEXITCODE" -ForegroundColor Red; exit 1 }

if ($Volumes) {
    Write-Host '[ ok ] 已停止并删除卷；请在 G3 删除流程台账登记时间与操作人' -ForegroundColor Green
} else {
    Write-Host '[ ok ] 已停止；命名卷已保留（CompreFace 管理数据仍在，无需重建应用与服务 key）' -ForegroundColor Green
    Write-Host '[info] 若需彻底清除 CompreFace 侧数据，请走数据删除审批后执行 .\scripts\stop.ps1 -Volumes' -ForegroundColor Gray
}
