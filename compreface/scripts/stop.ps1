#Requires -Version 5.1
<#
.SYNOPSIS
    停止 CompreFace 部署件。
.DESCRIPTION
    数据库为宿主已运行的 PostgreSQL（外部，不在 compose 管理内），停止仅影响 CompreFace
    自身的 5 个容器；CompreFace 业务元数据存于该外部 PG 的 compreface 库，stop 不会删除之。
.EXAMPLE
    .\scripts\stop.ps1
#>

$ErrorActionPreference = 'Continue'
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root
$envPath = Join-Path $Root '.env'

Write-Host '===== 停止 CompreFace =====' -ForegroundColor Cyan
& docker compose -f (Join-Path $Root 'docker-compose.yml') --env-file $envPath down
if ($LASTEXITCODE -ne 0) { Write-Host "[fail] docker compose down 退出码 $LASTEXITCODE" -ForegroundColor Red; exit 1 }

Write-Host '[ ok ] 已停止 CompreFace 容器；外部 PostgreSQL 中的 compreface 库数据未被触碰' -ForegroundColor Green
Write-Host '[info] 若需彻底清除 CompreFace 侧管理数据，请按 G3 删除流程在外部 PG 的 compreface 库执行删除，并登记台账' -ForegroundColor Gray
