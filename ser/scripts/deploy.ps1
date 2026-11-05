$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)
if (-not (Test-Path .env)) { throw '请先从 .env.example 复制为 .env 并填写 SER_API_KEY' }
$env:SER_API_KEY = (Select-String -Path .env -Pattern '^SER_API_KEY=(.+)$').Matches.Groups[1].Value
if ([string]::IsNullOrWhiteSpace($env:SER_API_KEY) -or $env:SER_API_KEY -like 'CHANGE_ME*') {
  throw 'SER_API_KEY 未替换为真实随机值'
}
docker compose --env-file .env up -d
Write-Output '已启动；请执行 ./scripts/verify.ps1 完成 U1-U5 取证后再置位门禁'
