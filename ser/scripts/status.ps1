# SP-4 SER 状态诊断（spec §8.2.8）
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

function Env-Value([string]$name, [string]$fallback) {
  if (Test-Path .env) {
    $hit = Select-String -Path .env -Pattern "^$name=(.+)$"
    if ($hit) { return $hit.Matches.Groups[1].Value.Trim() }
  }
  return $fallback
}

$nginxPort = Env-Value 'SER_NGINX_PORT' '8020'
$corePort = Env-Value 'SER_PORT' '8021'

docker compose --env-file .env ps

Write-Output "--- 模型容器 /health (127.0.0.1:$corePort) ---"
try { Invoke-RestMethod -Uri "http://127.0.0.1:$corePort/health" -TimeoutSec 5 | ConvertTo-Json -Compress }
catch { Write-Output "模型容器探活失败: $($_.Exception.Message)" }

Write-Output "--- nginx 免鉴权探针 (127.0.0.1:$nginxPort/ser-nginx-health) ---"
try { Invoke-RestMethod -Uri "http://127.0.0.1:$nginxPort/ser-nginx-health" -TimeoutSec 5 | ConvertTo-Json -Compress }
catch { Write-Output "nginx 探针失败: $($_.Exception.Message)" }

# 分支 B 与 OCR 同为 CPU：这是判断 SER 是否挤占 OCR_CPU_THREADS 的唯一手段
Write-Output '--- 容器资源占用 ---'
docker stats --no-stream emotion2vec ser-nginx
