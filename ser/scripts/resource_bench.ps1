# resource_bench.ps1 —— §8.4 资源挤占门禁取证（分支 B，SER_TORCH_THREADS=8）
# 制造 2 并发持续推理，采样 SER 与同机 CPU 推理服务（CompreFace）的 CPU%，观察是否饥饿。
# 注意：app.py 为单并发门，2 个并发请求会在 SER 侧排队，故峰值 CPU ≈ 单并发满载。
#       本机无 pp-ocrv6 OCR 容器（在 192.168.40.30），以同机 CompreFace-api 作 CPU 占用参照；
#       门禁最终判定须在部署机（与 OCR 同机）复测。

$ErrorActionPreference = 'Continue'
$envFile = 'd:\work\mediation_platform\mediation-deploy\ser\.env'
$key = (Select-String -Path $envFile -Pattern '^SER_API_KEY=(.+)$').Matches.Groups[1].Value.Trim()
$base = 'http://127.0.0.1:8020/ser'
$tmp = 'C:\tmp\serbench'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

# 生成 10s 负载 wav（440Hz + 调幅包络）
$rate = 16000; $frames = $rate * 10
$fs = [System.IO.File]::Open((Join-Path $tmp 'load.wav'), 'Create')
$bw = New-Object System.IO.BinaryWriter($fs)
$bw.Write([byte[]][char[]]'RIFF'); $bw.Write([int](36 + $frames * 2))
$bw.Write([byte[]][char[]]'WAVEfmt ')
$bw.Write([int]16); $bw.Write([System.Int16]1); $bw.Write([System.Int16]1)
$bw.Write([int]$rate); $bw.Write([int]($rate * 2))
$bw.Write([System.Int16]2); $bw.Write([System.Int16]16)
$bw.Write([byte[]][char[]]'data'); $bw.Write([int]($frames * 2))
for ($i = 0; $i -lt $frames; $i++) {
    $env = [math]::Abs([math]::Sin(2 * [math]::PI * 2 * $i / $rate))
    $v = [int](7000 * $env * [math]::Sin(2 * [math]::PI * 440 * $i / $rate))
    if ($v -gt 32767) { $v = 32767 }
    if ($v -lt -32768) { $v = -32768 }
    $bw.Write([System.Int16]$v)
}
$bw.Dispose(); $fs.Dispose()

# 负载进程脚本
$loadCmd = @"
`$key='$key'; `$base='$base'; `$wav='$(Join-Path $tmp 'load.wav')'
for(`$i=0;`$i -lt 300;`$i++){
  curl.exe -s -F "file=@`$wav;type=audio/wav" -F "sample_rate=16000" -F "language=zh" -H "X-API-Key: `$key" (`$base+'/v1/audio/emotion') | Out-Null
}
"@
$loadFile = Join-Path $tmp 'load.ps1'
Set-Content -Path $loadFile -Value $loadCmd -Encoding UTF8

$p1 = Start-Process -FilePath powershell -ArgumentList '-File', $loadFile -NoNewWindow -PassThru
$p2 = Start-Process -FilePath powershell -ArgumentList '-File', $loadFile -NoNewWindow -PassThru
Write-Host ("loaders pid={0},{1}; sampling 30s (SER + CompreFace-api)..." -f $p1.Id, $p2.Id)

$serPeak = 0.0; $cfPeak = 0.0
for ($s = 0; $s -lt 30; $s++) {
    $st = docker stats --no-stream --format '{{.Name}} {{.CPUPerc}}' emotion2vec compreface-api 2>$null
    foreach ($line in $st) {
        if ($line -match 'emotion2vec\s+([\d.]+)%') { $c = [double]$Matches[1]; if ($c -gt $serPeak) { $serPeak = $c } }
        if ($line -match 'compreface-api\s+([\d.]+)%') { $c = [double]$Matches[1]; if ($c -gt $cfPeak) { $cfPeak = $c } }
    }
    Write-Host ("[{0}s] {1}" -f $s, ($st -join ' | '))
    Start-Sleep -Seconds 1
}
$p1, $p2 | Stop-Process -Force -ErrorAction SilentlyContinue
Write-Host ""
Write-Host ("SER peak CPU%  = {0}" -f [math]::Round($serPeak, 1))
Write-Host ("CompreFace peak CPU% = {0} (idle 参照；本机无 pp-ocrv6 OCR 同机)" -f [math]::Round($cfPeak, 1))
Write-Host "判定：SER 单并发门串行处理，2 并发请求排队；峰值 CPU 应 < 单核 100%*8 线程，"
Write-Host "      且不应长期打满整机致同机 OCR/CompreFace 饥饿。部署机需与 pp-ocrv6 同机复测最终判定。"
