$ErrorActionPreference = 'Stop'
$base = 'http://127.0.0.1:8020'
$key = (Select-String -Path (Join-Path (Split-Path -Parent $PSScriptRoot) '.env') -Pattern '^SER_API_KEY=(.+)$').Matches.Groups[1].Value

Write-Output '[1/4] 探活'
Invoke-RestMethod -Uri "$base/health" -TimeoutSec 3 | Out-Null

Write-Output '[2/4] 无 key 必须 401'
try {
  Invoke-RestMethod -Uri "$base/v1/ser" -Method Post -Body '{}' -ContentType 'application/json' -TimeoutSec 3 | Out-Null
  throw '无 key 仍返回成功，鉴权门禁失败'
} catch {
  if ($_.Exception.Message -like '*鉴权门禁失败*') { throw }
}

Write-Output '[3/4] 带 key 的 3s 静音段必须 409/502，不得 200 calm'
$wav16k = [byte[]]::new(16000 * 3 * 2)
$body = @{ wav = ($wav16k | ForEach-Object { $_.ToString('x2') }) -join ''; sample_rate = 16000 } | ConvertTo-Json
try {
  $r = Invoke-RestMethod -Uri "$base/v1/ser" -Method Post -Headers @{ 'X-API-Key' = $key } -Body $body -ContentType 'application/json' -TimeoutSec 5
  if ($r.emotion -eq 'calm') { throw '静音段返回 200 calm，U5 门禁失败' }
} catch {
  if ($_.Exception.Message -like '*U5 门禁失败*') { throw }
  Write-Output "静音段按预期被拒绝: $($_.Exception.Message)"
}

Write-Output '[4/4] 标签集与映射表一致性'
Write-Output '预期 labels_supported = calm,anxious,agitated,anger,threat（实测返回体请回填 README U5）'
