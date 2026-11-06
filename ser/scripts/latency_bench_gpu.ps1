# latency_bench_gpu.ps1 —— GPU 分支延迟对比（§8.4 门禁取证）
# 与 latency_bench.ps1 同构，仅 base 指向 GPU 反代端口 8023/ser。
# 3 段合成语音（10s/30s/60s）各循环 20 次，记录响应体 latencyMs，算 P50/P95。
# wav 文件名带 PID，避免多实例抢写同一文件导致 BinaryWriter 为 null。

$ErrorActionPreference = 'Continue'
$envFile = 'd:\work\mediation_platform\mediation-deploy\ser\.env'
$key = (Select-String -Path $envFile -Pattern '^SER_API_KEY=(.+)$').Matches.Groups[1].Value.Trim()
$base = 'http://127.0.0.1:8023/ser'
$tmp = 'C:\tmp\serbench'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

function Make-Wav($path, $seconds) {
    $rate = 16000
    $frames = $rate * $seconds
    $fs = [System.IO.File]::Open($path, 'Create')
    try {
        $bw = New-Object System.IO.BinaryWriter($fs)
        try {
            $bw.Write([byte[]][char[]]'RIFF'); $bw.Write([int](36 + $frames * 2))
            $bw.Write([byte[]][char[]]'WAVEfmt ')
            $bw.Write([int]16); $bw.Write([System.Int16]1); $bw.Write([System.Int16]1)
            $bw.Write([int]$rate); $bw.Write([int]($rate * 2))
            $bw.Write([System.Int16]2); $bw.Write([System.Int16]16)
            $bw.Write([byte[]][char[]]'data'); $bw.Write([int]($frames * 2))
            for ($i = 0; $i -lt $frames; $i++) {
                $ampl = [math]::Abs([math]::Sin(2 * [math]::PI * 2 * $i / $rate))
                $v = [int](7000 * $ampl * [math]::Sin(2 * [math]::PI * 440 * $i / $rate))
                if ($v -gt 32767) { $v = 32767 }
                if ($v -lt -32768) { $v = -32768 }
                $bw.Write([System.Int16]$v)
            }
        } finally { if ($bw) { $bw.Dispose() } }
    } finally { $fs.Dispose() }
}

function Bench($seconds, $n) {
    $p = Join-Path $tmp ("gpu_s{0}_{1}.wav" -f $seconds, $PID)
    Make-Wav $p $seconds
    $lat = @()
    for ($k = 1; $k -le $n; $k++) {
        $t0 = Get-Date
        $body = curl.exe -s -F "file=@$p;type=audio/wav" -F "sample_rate=16000" -F "language=zh" -H "X-API-Key: $key" ($base + '/v1/audio/emotion')
        $t1 = Get-Date
        $el = [math]::Round(($t1 - $t0).TotalMilliseconds, 1)
        if ($body -match '"detail"|ser failed|CUDA error') {
            Write-Host ("REQUEST_FAILED (aborting): " + $body)
            exit 1
        }
        $m = [regex]::Match($body, '"latencyMs"\s*:\s*([\d.]+)')
        $l = if ($m.Success) { [double]$m.Groups[1].Value } else { $el }
        $lat += $l
        $st = [regex]::Match($body, '"emotion"\s*:\s*"([^"]+)"')
        Write-Host ("  [{0}/{1}] {2}s el={3}ms lat={4}ms emotion={5}" -f $k, $n, $seconds, $el, $l, $st.Groups[1].Value)
    }
    $sorted = $lat | Sort-Object
    $p50 = $sorted[[math]::Floor(0.50 * $n)]
    $p95 = $sorted[[math]::Ceiling(0.95 * $n) - 1]
    [PSCustomObject]@{
        seconds = $seconds; n = $n
        p50 = [math]::Round($p50, 1); p95 = [math]::Round($p95, 1)
        min = [math]::Round($sorted[0], 1); max = [math]::Round($sorted[-1], 1)
    }
}

Write-Host "=== GPU SER latency bench (20 loops each, port 8023) ==="
$r10 = Bench 10 20
$r30 = Bench 30 20
$r60 = Bench 60 20
Write-Host ""
Write-Host ("{0,-8}{1,-6}{2,-10}{3,-10}{4,-10}{5,-10}" -f 'len(s)', 'n', 'P50(ms)', 'P95(ms)', 'min', 'max')
foreach ($r in @($r10, $r30, $r60)) {
    Write-Host ("{0,-8}{1,-6}{2,-10}{3,-10}{4,-10}{5,-10}" -f $r.seconds, $r.n, $r.p50, $r.p95, $r.min, $r.max)
}
$pass = ($r10.p95 -le 1500) -and ($r30.p95 -le 1500) -and ($r60.p95 -le 1500)
Write-Host ("P95<=1500ms gate: {0}" -f $(if ($pass) { 'PASS' } else { 'FAIL' }))
