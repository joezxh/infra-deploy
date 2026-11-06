# SP-4 SER 契约验证（spec §8.2.8 / §10.4 / §8.4）
# Windows PowerShell 5.1 的 Invoke-RestMethod 不支持 -Form，必须用 curl.exe -F。
# 本脚本只做「契约是否成立」的验证，**不会**替人回填 U1–U5 实测值。
$ErrorActionPreference = 'Stop'
Set-Location (Split-Path -Parent $PSScriptRoot)

function Env-Value([string]$name, [string]$fallback) {
  $hit = Select-String -Path .env -Pattern "^$name=(.+)$"
  if ($hit) { return $hit.Matches.Groups[1].Value.Trim() }
  return $fallback
}

$port = Env-Value 'SER_NGINX_PORT' '8020'
$key = Env-Value 'SER_API_KEY' ''
if ([string]::IsNullOrWhiteSpace($key) -or $key -like 'change-me*') {
  throw 'SER_API_KEY 未替换为真实随机值'
}
$base = "http://127.0.0.1:$port"
$expected = @('calm', 'anxious', 'agitated', 'anger', 'threat')

# 宿主临时取证 wav：仅在 scripts/.tmp 生存，finally 删除；服务侧与容器内不落盘
$tmpDir = Join-Path $PSScriptRoot '.tmp'
New-Item -ItemType Directory -Force -Path $tmpDir | Out-Null
$toneWav = Join-Path $tmpDir 'tone.wav'
$silentWav = Join-Path $tmpDir 'silent.wav'
$outFile = Join-Path $tmpDir 'response.json'

function New-Wav16k([string]$path, [int]$seconds, [bool]$withTone) {
  $frames = 16000 * $seconds
  $fs = [System.IO.File]::Open($path, [System.IO.FileMode]::Create)
  $bw = New-Object System.IO.BinaryWriter($fs)
  try {
    $bw.Write([byte[]][char[]]'RIFF')
    $bw.Write([int](36 + $frames * 2))
    $bw.Write([byte[]][char[]]'WAVEfmt ')
    $bw.Write([int]16); $bw.Write([System.Int16]1); $bw.Write([System.Int16]1)
    $bw.Write([int]16000); $bw.Write([int]32000)
    $bw.Write([System.Int16]2); $bw.Write([System.Int16]16)
    $bw.Write([byte[]][char[]]'data'); $bw.Write([int]($frames * 2))
    for ($i = 0; $i -lt $frames; $i++) {
      $v = 0
      if ($withTone) { $v = [int](8000 * [math]::Sin(2 * [math]::PI * 440 * $i / 16000)) }
      $bw.Write([System.Int16]$v)
    }
  } finally { $bw.Dispose(); $fs.Dispose() }
}

function Invoke-Ser([string]$wav, [bool]$withKey) {
  $args = @('-s', '-o', $outFile, '-w', '%{http_code}', '-X', 'POST',
    '-F', "file=@$wav;type=audio/wav", '-F', 'sample_rate=16000', '-F', 'language=zh')
  if ($withKey) { $args += @('-H', "X-API-Key: $key") }
  $args += "$base/ser/v1/audio/emotion"
  $code = (& curl.exe @args | Out-String).Trim()
  $body = if (Test-Path $outFile) { Get-Content $outFile -Raw -Encoding UTF8 } else { '' }
  return @{ Code = $code; Body = $body }
}

try {
  Write-Output '[1/5] nginx 免鉴权探针'
  $probe = Invoke-RestMethod -Uri "$base/ser-nginx-health" -TimeoutSec 5
  if ($probe.status -ne 'ok') { throw 'nginx 探针未返回 ok' }

  Write-Output '[2/5] 带 key 的 /ser/health 必须可用，且 labels_supported 与映射表一致'
  $health = Invoke-RestMethod -Uri "$base/ser/health" -Headers @{ 'X-API-Key' = $key } -TimeoutSec 5
  $labels = @($health.labels_supported | ForEach-Object {
    ($_ -replace '[<|>]', '' -replace '^\d+:\s*', '').Trim().ToLower()
  })
  foreach ($official in @('neutral', 'happy', 'fearful', 'sad', 'surprised', 'disgusted', 'angry', 'other', 'unknown')) {
    if ($labels -notcontains $official) { throw "labels_supported 缺少官方标签 $official（U2 门禁失败）" }
  }
  if ($health.persistence -ne $false) { throw '服务自报存在持久化，违反 §9 落盘禁令' }

  Write-Output '[3/5] 无 key 必须 401'
  New-Wav16k $toneWav 3 $true
  $noKey = Invoke-Ser $toneWav $false
  if ($noKey.Code -ne '401') { throw "无 key 返回 $($noKey.Code)，鉴权门禁失败" }

  Write-Output '[4/5] 真 wav 正向：200 且 emotion 落在五值内'
  $ok = Invoke-Ser $toneWav $true
  if ($ok.Code -ne '200') { throw "正向请求返回 $($ok.Code)：$($ok.Body)" }
  $result = $ok.Body | ConvertFrom-Json
  if ($expected -notcontains $result.emotion) { throw "emotion 非法: $($result.emotion)" }
  Write-Output "  实测 emotion=$($result.emotion) model=$($result.model) latencyMs=$($result.latencyMs)（数据请人工回填 README U3/U4）"

  Write-Output '[5/5] 3s 全静音必须 409/502，绝不能 200 calm'
  New-Wav16k $silentWav 3 $false
  $silent = Invoke-Ser $silentWav $true
  if ($silent.Code -eq '200') {
    $s = $silent.Body | ConvertFrom-Json
    if ($s.emotion -eq 'calm') { throw '静音段返回 200 calm，§8.4 拒分类门禁失败' }
    throw "静音段返回 200（emotion=$($s.emotion)），§8.4 拒分类门禁失败"
  }
  if ($silent.Code -notin @('409', '502')) { throw "静音段返回 $($silent.Code)，期望 409/502" }
  Write-Output "  静音按预期被拒绝: HTTP $($silent.Code)"

  Write-Output '契约验证通过。U1–U5 实测值仍需人工按 spec §8.2.9 / §8.4 回填 README；未回写前不得置位门禁开关。'
} finally {
  Remove-Item -Force -ErrorAction SilentlyContinue $toneWav, $silentWav, $outFile
}
