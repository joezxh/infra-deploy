# SP-4 SER 部署（spec §8.2.8）
# docker 会把 WARNING 打到 stderr：不能用 Stop 模式误判，改用 Continue + 显式 $LASTEXITCODE
$ErrorActionPreference = 'Continue'
Set-Location (Split-Path -Parent $PSScriptRoot)

function Assert-LastExit([string]$step) {
  if ($LASTEXITCODE -ne 0) { throw "步骤失败: $step (exit=$LASTEXITCODE)" }
}

if (-not (Test-Path .env)) {
  Copy-Item .env.example .env
  $key = (-join (1..3 | ForEach-Object { [guid]::NewGuid().ToString('N') })).Substring(0, 40)
  $text = (Get-Content .env -Raw -Encoding UTF8)
  $text = $text -replace '(?m)^API_KEY=.*$', "API_KEY=$key"
  $text = $text -replace '(?m)^SER_API_KEY=.*$', "SER_API_KEY=$key"
  [System.IO.File]::WriteAllText((Join-Path (Get-Location) '.env'), $text,
    (New-Object System.Text.UTF8Encoding($false)))
  Write-Output '已生成 .env 与随机 40 位 API_KEY；请留档到密钥管理，切勿提交 .env'
}

$env:SER_API_KEY = (Select-String -Path .env -Pattern '^SER_API_KEY=(.+)$').Matches.Groups[1].Value
if ([string]::IsNullOrWhiteSpace($env:SER_API_KEY) -or $env:SER_API_KEY -like 'change-me*') {
  throw 'SER_API_KEY 未替换为真实随机值'
}

docker compose --env-file .env up -d --build
Assert-LastExit 'docker compose up -d --build'

# 300M 模型首次加载比 OCR 慢，健康窗口取 900s
$deadline = (Get-Date).AddSeconds(900)
$healthy = $false
while ((Get-Date) -lt $deadline) {
  $state = (& docker inspect --format '{{.State.Health.Status}}' emotion2vec 2>$null | Out-String).Trim()
  if ($LASTEXITCODE -eq 0 -and $state -eq 'healthy') { $healthy = $true; break }
  Start-Sleep -Seconds 10
}
if (-not $healthy) { throw 'emotion2vec 900s 内未 healthy；不要置位任何门禁开关' }

Write-Output '容器已启动且 healthy。下一步：执行 ./scripts/verify.ps1 完成 U1–U5 取证并回填 README。'
Write-Output '门禁纪律：U1–U5 未回写、§8.4 六条 PoC 未通过、许可未留档前，MEETING_SER_ENABLED 与 MEETING_SER_POC_PASSED 恒 false。'
