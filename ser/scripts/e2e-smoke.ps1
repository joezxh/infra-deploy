# e2e-smoke.ps1 —— §10.4 / §8.4 人检一致率取数工具（影子模式）
# 对一批真实会议音频片段批量调用 SER，输出 emotion/confidence/latency 到 CSV，
# 供真人听记对照，计算「声学标签 vs 人工听记」一致率（门禁 ≥70%）。
#
# 用法：
#   .\e2e-smoke.ps1 -WavDir "D:\meeting\segments" -OutCsv "D:\meeting\ser_shadow.csv"
#   .\e2e-smoke.ps1 -WavDir "D:\meeting\segments" -BaseUrl "http://127.0.0.1:8023/ser"   # GPU 分支 A
# 说明：
#   - 每段 .wav 视为一个会议片段；脚本只取 SER 标签，不替代人工判断。
#   - 真人需对每段独立听记「愤怒/焦虑/激动/平静/威胁」之一，与 CSV 的 emotion 比对，
#     统计一致段数 / 总段数 ≥ 0.70 即门禁通过。
#   - 本机无 LiveKit 拉流与 JWT，故不实现七步中的实时拉流；仅做离线片段批量取数。
#   - §8.4 人检门禁的「影子模式 2 场真实调解会」需在阶段 3/4 由真人执行对照。

param(
    [string]$WavDir,
    [string]$OutCsv = 'C:\tmp\ser_shadow.csv',
    [string]$BaseUrl = 'http://127.0.0.1:8020/ser'
)

$ErrorActionPreference = 'Stop'
if (-not $WavDir -or -not (Test-Path $WavDir)) {
    Write-Host "ERROR: -WavDir 必须指向含 .wav 片段的目录（当前='$WavDir'）"
    exit 1
}
$envFile = 'd:\work\mediation_platform\mediation-deploy\ser\.env'
$key = (Select-String -Path $envFile -Pattern '^SER_API_KEY=(.+)$').Matches.Groups[1].Value.Trim()
$base = $BaseUrl

$wavs = Get-ChildItem -Path $WavDir -Filter '*.wav' | Sort-Object Name
if ($wavs.Count -eq 0) { Write-Host "ERROR: $WavDir 下无 .wav"; exit 1 }
Write-Host ("found {0} wav segments" -f $wavs.Count)

$rows = @()
foreach ($w in $wavs) {
    $t0 = Get-Date
    $body = curl.exe -s -F ("file=@{0};type=audio/wav" -f $w.FullName) -F "sample_rate=16000" -F "language=zh" -H "X-API-Key: $key" ($base + '/v1/audio/emotion')
    $t1 = Get-Date
    $el = [math]::Round(($t1 - $t0).TotalMilliseconds, 1)
    $emo = ([regex]::Match($body, '"emotion"\s*:\s*"([^"]+)"')).Groups[1].Value
    $conf = ([regex]::Match($body, '"confidence"\s*:\s*([\d.]+)')).Groups[1].Value
    $lat = ([regex]::Match($body, '"latencyMs"\s*:\s*([\d.]+)')).Groups[1].Value
    $raw = ([regex]::Match($body, '"rawLabel"\s*:\s*"([^"]+)"')).Groups[1].Value
    Write-Host ("{0} -> emotion={1} conf={2} lat={3}ms raw={4}" -f $w.Name, $emo, $conf, $lat, $raw)
    $rows += [PSCustomObject]@{
        file       = $w.Name
        emotion    = $emo
        confidence = $conf
        latencyMs  = $lat
        rawLabel   = $raw
        humanLabel = ''   # 真人听记填此处
    }
}
$rows | Export-Csv -Path $OutCsv -NoTypeInformation -Encoding UTF8
Write-Host ("CSV written: {0} (humanLabel 列留空，供真人填后算一致率)" -f $OutCsv)
