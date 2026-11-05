Set-Location (Split-Path -Parent $PSScriptRoot)
docker compose ps
Write-Output '--- /health ---'
try { Invoke-RestMethod -Uri 'http://127.0.0.1:8020/health' -TimeoutSec 3 | ConvertTo-Json -Compress }
catch { Write-Output "health 不可达: $($_.Exception.Message)" }
