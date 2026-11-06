#Requires -Version 7.0
<#
.SYNOPSIS
  SP-6 §0.2 的 G0-a/b/c/d 取证脚本（137 语音网关 embedding 端点）。

.DESCRIPTION
  只发探测请求并生成 Markdown 报告，不修改 137 容器、不写平台配置、
  不置位 VOICEPRINT_POC_PASSED、不产出任何身份结论。
  音频样本在内存中构造、临时文件用完即删；报告只记录状态码与字段形状，不记录向量内容。

.PARAMETER BaseUrl
  137 网关 REST 基址，默认 http://192.168.1.137:8765。
.PARAMETER ApiKey
  G0-d 取证用的真实凭证；不提供时仍会发「无凭证」请求以验证端点是否拒绝裸请求。
.PARAMETER ExpectedDim
  期望的 embedding 维度，默认 192（以实测为准回填 voice.gateway.embedding-dim）。
.PARAMETER AfterRebuild
  137 容器重建后带此开关重跑，用于 G0-b 端点持久化取证。
.PARAMETER OutDir
  报告输出目录，默认脚本所在目录。

.EXAMPLE
  ./g0-probe.ps1 -ApiKey 'real-key' -BaseUrl 'http://192.168.1.137:8765'
  # 重建容器后再跑：
  ./g0-probe.ps1 -ApiKey 'real-key' -AfterRebuild
#>
[CmdletBinding()]
param(
  [string]$BaseUrl = 'http://192.168.1.137:8765',
  [string]$ApiKey = '',
  [int]$ExpectedDim = 192,
  [switch]$AfterRebuild,
  [string]$OutDir = $PSScriptRoot
)

$ErrorActionPreference = 'Continue'
$probeStamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$report = New-Object System.Collections.Generic.List[string]
$result = [ordered]@{
  G0a = '未取证'; G0b = '未取证'; G0c = '未取证'; G0d = '未取证'; Capability = '未取证'
}

function Add-Line([string]$text) { $report.Add($text) | Out-Null }

function New-ProbeWav([string]$path) {
  $sampleRate = 16000
  $seconds = 3
  $frames = $sampleRate * $seconds
  $ms = New-Object System.IO.MemoryStream
  $bw = New-Object System.IO.BinaryWriter($ms)
  $bw.Write([Text.Encoding]::ASCII.GetBytes('RIFF'))
  $bw.Write([int](36 + 2 * $frames))
  $bw.Write([Text.Encoding]::ASCII.GetBytes('WAVEfmt '))
  $bw.Write([int]16); $bw.Write([short]1); $bw.Write([short]1)
  $bw.Write([int]$sampleRate); $bw.Write([int]($sampleRate * 2))
  $bw.Write([short]2); $bw.Write([short]16)
  $bw.Write([Text.Encoding]::ASCII.GetBytes('data'))
  $bw.Write([int](2 * $frames))
  for ($i = 0; $i -lt $frames; $i++) {
    $v = [short]([Math]::Sin(2 * [Math]::PI * 440 * $i / $sampleRate) * 6000)
    $bw.Write($v)
  }
  $bw.Flush()
  [IO.File]::WriteAllBytes($path, $ms.ToArray())
  $bw.Dispose(); $ms.Dispose()
}

function Invoke-Probe([string]$url, [string]$method, [hashtable]$form, [bool]$withAuth) {
  $headers = @{}
  if ($withAuth -and $ApiKey) { $headers['Authorization'] = "Bearer $ApiKey" }
  $args = @{
    Uri = $url; Method = $method; TimeoutSec = 8; SkipHttpErrorCheck = $true; Headers = $headers
  }
  if ($form) { $args['Form'] = $form }
  $sw = [Diagnostics.Stopwatch]::StartNew()
  try {
    $r = Invoke-WebRequest @args
    $sw.Stop()
    return [pscustomobject]@{ Status = [int]$r.StatusCode; Body = [string]$r.Content; Ms = $sw.ElapsedMilliseconds }
  } catch {
    $sw.Stop()
    return [pscustomobject]@{ Status = 0; Body = "REQUEST_FAILED: $($_.Exception.Message)"; Ms = $sw.ElapsedMilliseconds }
  }
}

$tmp = Join-Path ([IO.Path]::GetTempPath()) "vp-g0-$probeStamp.wav"
try {
  New-ProbeWav $tmp
  $form = @{ file = Get-Item $tmp; model = 'qwen3-speaker-embedding'; purpose = 'verify' }

  # ---------- G0-a 端点可达 ----------
  $a = Invoke-Probe "$BaseUrl/v1/audio/embeddings" 'POST' $form $true
  $shapeOk = $false
  $dim = 0
  if ($a.Status -eq 200) {
    try {
      $j = $a.Body | ConvertFrom-Json
      $dim = [int]$j.dim
      $shapeOk = ($j.embedding.Count -eq $dim) -and ($dim -eq $ExpectedDim) -and
                  (-not [string]::IsNullOrWhiteSpace($j.model)) -and ($null -ne $j.quality)
    } catch { $shapeOk = $false }
  }
  $result.G0a = if ($a.Status -eq 200 -and $shapeOk) { '通过' } else { '未通过' }
  Add-Line "## G0-a 端点可达：$($result.G0a)"
  Add-Line "- POST /v1/audio/embeddings → HTTP $($a.Status)，耗时 $($a.Ms) ms"
  Add-Line "- 响应字段形状（不记录向量内容）：dim=$dim，model/quality/embedding 长度校验=$shapeOk"
  if ($a.Status -ne 200) { Add-Line "- 响应体摘要：$($a.Body.Substring(0, [Math]::Min(200, $a.Body.Length)))" }

  # ---------- capability ----------
  $cap = Invoke-Probe "$BaseUrl/v1/audio/embeddings/capability" 'GET' $null $true
  $result.Capability = if ($cap.Status -eq 200) { '通过' } else { '未通过' }
  Add-Line "## capability 探活：$($result.Capability)"
  Add-Line "- GET /v1/audio/embeddings/capability → HTTP $($cap.Status)"

  # ---------- G0-d 鉴权 ----------
  if ($a.Status -eq 200) {
    $d = Invoke-Probe "$BaseUrl/v1/audio/embeddings" 'POST' $form $false
    $result.G0d = if ($d.Status -eq 401 -or $d.Status -eq 403) { '通过' } else { '未通过' }
    Add-Line "## G0-d 鉴权：$($result.G0d)"
    Add-Line "- 不带凭证重发 → HTTP $($d.Status)（判据 401/403；若仍 200 则 G3 不得通过）"
  } else {
    Add-Line '## G0-d 鉴权：不适用（端点不存在，无法验证其鉴权行为）'
  }

  # ---------- G0-c 并发容量 ----------
  if ($a.Status -eq 200) {
    $asrBefore = Invoke-Probe "$BaseUrl/v1/audio/transcriptions" 'POST' $form $true
    $jobs = 1..8 | ForEach-Object -Parallel {
      $f = @{ file = Get-Item $using:tmp; model = 'qwen3-speaker-embedding'; purpose = 'verify' }
      $sw = [Diagnostics.Stopwatch]::StartNew()
      try {
        $r = Invoke-WebRequest -Uri "$using:BaseUrl/v1/audio/embeddings" -Method Post `
          -Form $f -Headers @{ Authorization = "Bearer $using:ApiKey" } `
          -TimeoutSec 8 -SkipHttpErrorCheck
        $sw.Stop()
        [pscustomobject]@{ Status = [int]$r.StatusCode; Ms = $sw.ElapsedMilliseconds }
      } catch {
        $sw.Stop()
        [pscustomobject]@{ Status = 0; Ms = $sw.ElapsedMilliseconds }
      }
    }
    $asrAfter = Invoke-Probe "$BaseUrl/v1/audio/transcriptions" 'POST' $form $true
    $degrade = if ($asrBefore.Ms -gt 0) { [Math]::Round(100.0 * ($asrAfter.Ms - $asrBefore.Ms) / $asrBefore.Ms, 1) } else { 0 }
    $serverErrors = @($jobs | Where-Object { $_.Status -ge 500 }).Count
    $result.G0c = if ($degrade -le 20 -and $serverErrors -eq 0) { '通过' } else { '未通过' }
    Add-Line "## G0-c 并发容量：$($result.G0c)"
    Add-Line "- 8 路并发 embedding：5xx=$serverErrors，ASR 基准 $($asrBefore.Ms) ms → 并发后 $($asrAfter.Ms) ms（劣化 $degrade%）"
    Add-Line '- 判据：ASR P95 劣化 ≤20% 且零 5xx；字幕链路优先，核验请求须走有界队列与熔断'
  } else {
    Add-Line '## G0-c 并发容量：不适用（G0-a 未通过，端点不存在）'
  }

  # ---------- G0-b 持久化 ----------
  if ($AfterRebuild) {
    $b = Invoke-Probe "$BaseUrl/v1/audio/embeddings" 'POST' $form $true
    $result.G0b = if ($b.Status -eq 200) { '通过' } else { '未通过' }
    Add-Line "## G0-b 端点持久化：$($result.G0b)"
    Add-Line "- 容器重建后重发同一请求 → HTTP $($b.Status)（运行时补丁注入在重建后失效即判未通过）"
  } else {
    Add-Line '## G0-b 端点持久化：未取证（须在重建 137 容器后带 -AfterRebuild 重跑本脚本）'
  }
} finally {
  if (Test-Path $tmp) { Remove-Item $tmp -Force }
}

$allPassed = ($result.G0a -eq '通过' -and $result.G0b -eq '通过' -and
              $result.G0c -eq '通过' -and $result.G0d -eq '通过')
Add-Line ''
Add-Line "## 结论：G0 整体$(if ($allPassed) { '通过（仍须 G1/G2/G3 与 T3/T5 书面确认）' } else { '未通过' })"
Add-Line '- 本报告只是取证输出，**不得**据此置位 VOICEPRINT_POC_PASSED，也不改 voiceprint.enabled。'
Add-Line "- 取证时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')；阶段：$(if ($AfterRebuild) { '容器重建后复测' } else { '首次取证' })"

$outFile = Join-Path $OutDir "g0-report-$probeStamp.md"
Add-Line '' | Out-Null
[IO.File]::WriteAllLines($outFile, $report)
Write-Host "报告已写入：$outFile"
Write-Host "G0 整体：$(if ($allPassed) { '通过' } else { '未通过' })（G0-a=$($result.G0a), G0-b=$($result.G0b), G0-c=$($result.G0c), G0-d=$($result.G0d)）"
