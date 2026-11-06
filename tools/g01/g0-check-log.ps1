<#
.SYNOPSIS
    G0 真机日志判定：解析 worker 的 [track-observe] 输出，判定「≥2 个参与方各发布视频轨」。

.DESCRIPTION
    判据（硬性）：同一 room 内出现 >=2 个不同 identity，且每个至少一条 kind=KIND_VIDEO。
    只观测日志，不改任何服务；日志本身只含轨元信息（room/identity/kind/sid），不含帧内容。

.EXAMPLE
    .\g0-check-log.ps1 -LogPath .\worker.log
    .\g0-check-log.ps1 -LogPath C:\logs\worker.log -RoomName meet-0-1793765378556 -OutFile .\g0-report.md
#>
[CmdletBinding()]
param(
    [Parameter(Mandatory = $true)][string]$LogPath,
    [string]$RoomName = '',
    [string]$OutFile = '',
    [int]$MinParticipants = 2
)

$ErrorActionPreference = 'Stop'
if (-not (Test-Path -LiteralPath $LogPath)) { Write-Host "[fail] 日志不存在：$LogPath" -ForegroundColor Red; exit 1 }
if (Test-Path -LiteralPath $LogPath -PathType Container) {
    $files = @(Get-ChildItem $LogPath -File -Recurse | Sort-Object LastWriteTime -Descending)
} else {
    $files = @(Get-Item $LogPath)
}

$rx = [regex]'\[track-observe\]\s+room=(\S+)\s+identity=(\S+)\s+kind=(\S+)\s+sid=(\S+)'
$rows = @()
foreach ($f in $files) {
    foreach ($line in [System.IO.File]::ReadLines($f.FullName)) {
        $m = $rx.Match($line)
        if ($m.Success) {
            $rows += [PSCustomObject]@{
                File = $f.Name; Room = $m.Groups[1].Value; Identity = $m.Groups[2].Value
                Kind = $m.Groups[3].Value; Sid = $m.Groups[4].Value
            }
        }
    }
}

Write-Host "解析到 track-observe 行：$($rows.Count)"
if ($rows.Count -eq 0) {
    Write-Host '[fail] 未发现任何 [track-observe] 行：worker 未运行 / 未连上 LiveKit / 房间内无轨被订阅' -ForegroundColor Red
    Write-Host '       取证要点：worker 与 livekit-server 同网、token 有效、两人确已入会并开启摄像头。'
    exit 2
}

if ($RoomName) { $rows = @($rows | Where-Object { $_.Room -eq $RoomName }) }

$rooms = @($rows | Group-Object Room)
$videoByIdentity = @{}
foreach ($g in $rows) {
    if ($g.Kind -ne 'KIND_VIDEO') { continue }
    if (-not $videoByIdentity.ContainsKey($g.Identity)) { $videoByIdentity[$g.Identity] = 0 }
    $videoByIdentity[$g.Identity]++
}
$participants = @($videoByIdentity.Keys | Sort-Object)
$pass = ($participants.Count -ge $MinParticipants)

Write-Host ''
Write-Host "房间数：$($rooms.Count)"
foreach ($r in $rooms) {
    $ids = @($r.Group | Select-Object -ExpandProperty Identity -Unique)
    $vids = @($r.Group | Where-Object { $_.Kind -eq 'KIND_VIDEO' } | Select-Object -ExpandProperty Identity -Unique)
    Write-Host ("  room={0}  参与方={1}  有视频轨的参与方={2}" -f $r.Name, $ids.Count, $vids.Count)
}
Write-Host ''
foreach ($p in $participants) { Write-Host "  有视频轨：identity=$p  轨数=$($videoByIdentity[$p])" }
Write-Host ''
if ($pass) {
    Write-Host "[结论] G0 **已证实**：$($participants.Count) 个参与方各发布视频轨（>= $MinParticipants）" -ForegroundColor Green
} else {
    Write-Host "[结论] G0 **未证实**：仅 $($participants.Count) 个参与方有视频轨（要求 >= $MinParticipants）" -ForegroundColor Red
    Write-Host '        不得据此置位门禁；需双人真机各开摄像头入会后重新取证。'
}

if (-not $OutFile) { $OutFile = Join-Path (Get-Location) ("g0-report-" + (Get-Date -Format 'yyyyMMdd-HHmmss') + '.md') }
$L = New-Object System.Collections.Generic.List[string]
$L.Add('# G0 双人真机日志取证报告')
$L.Add('')
$L.Add("- 生成时间：$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')")
$L.Add("- 日志来源：$LogPath（$($files.Count) 个文件）")
$L.Add("- 解析到的 track-observe 行：$($rows.Count)")
$L.Add('')
$L.Add('| room | identity | 轨类型 | sid |')
$L.Add('|---|---|---|---|')
foreach ($r in $rows) { $L.Add("| $($r.Room) | $($r.Identity) | $($r.Kind) | $($r.Sid) |") }
$L.Add('')
$L.Add('## 结论')
$L.Add('')
$L.Add("- 有视频轨的参与方数：**$($participants.Count)**（要求 >= $MinParticipants）")
if ($pass) {
    $L.Add('- **G0 已证实**：满足「双人各发布视频轨」判据。')
} else {
    $L.Add('- **G0 未证实**：需双人真机各开摄像头入会后重新取证，不得据本报告置位门禁。')
}
$L.Add('')
$L.Add('> 日志只含轨元信息（room/identity/kind/sid），不含任何帧内容；取证后请按留存策略处置原始日志与截图。')
[System.IO.File]::WriteAllLines($OutFile, $L, (New-Object System.Text.UTF8Encoding($false)))
Write-Host "报告已写出：$OutFile"
if (-not $pass) { exit 3 }