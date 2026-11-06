# resource_bench_gpu.ps1 —— §8.4 资源门禁取证（GPU 分支 A，2 并发持续推理）
# 采样：宿主 nvidia-smi（全局显存/利用率）+ docker stats（SER CPU/MEM）+ 容器 torch mem_get_info（WSL 视角）
# 背景：WSL2 下宿主 `nvidia-smi --query-compute-apps` 看不到容器 CUDA 进程（[Not Found]/[N/A]），
#       故以「全局 memory.used 增量（相对模型加载后基线）」+「容器 mem_get_info」交叉验证 SER 显存峰值。
# 注意：宿主侧还有 LM Studio / explorer 等占用显存（基线约 2176 MiB），SER 占用按增量算，不按绝对值算。
# 负载：2 个并发 loader 循环 POST 60s wav 到 8023/ser；app.py 的 SER_MAX_INFLIGHT=2。

$ErrorActionPreference = 'Continue'
$serDir = 'd:\work\mediation_platform\mediation-deploy\ser'
$envFile = Join-Path $serDir '.env'
$key = (Select-String -Path $envFile -Pattern '^SER_API_KEY=(.+)$').Matches.Groups[1].Value.Trim()
$base = 'http://127.0.0.1:8023/ser'
$tmp = 'C:\tmp\serbench'
$log = Join-Path $serDir 'gpu_resource_bench.log'
New-Item -ItemType Directory -Force -Path $tmp | Out-Null

function Log($m) {
    $ts = Get-Date -Format 'HH:mm:ss'
    Write-Host ("[{0}] {1}" -f $ts, $m)
    Add-Content -Path $log -Value ("[{0}] {1}" -f $ts, $m)
}

function Get-GpuSample {
    $r = nvidia-smi --query-gpu=memory.used,memory.total,utilization.gpu,utilization.memory --format=csv,noheader,nounits 2>$null
    $line = ($r | Select-Object -First 1)
    if (-not $line) { return $null }
    $p = $line -split '\s*,\s*'
    [PSCustomObject]@{
        UsedMB  = [double]$p[0]
        TotalMB = [double]$p[1]
        GpuUtil = [double]$p[2]
        MemUtil = [double]$p[3]
    }
}

function Get-ContainerMem {
    $r = docker exec emotion2vec-gpu python -c "import torch; f,t=torch.cuda.mem_get_info(); print('%d %d' % ((t-f)//1048576, t//1048576))" 2>$null
    if ($r -match '^\s*(\d+)\s+(\d+)') {
        [PSCustomObject]@{ UsedMB = [double]$Matches[1]; TotalMB = [double]$Matches[2] }
    } else { $null }
}

# 60s 负载 wav（不存在则生成）
$wav = Join-Path $tmp 'gpu_s60.wav'
if (-not (Test-Path $wav)) {
    $rate = 16000; $frames = $rate * 60
    $fs = [System.IO.File]::Open($wav, 'Create')
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

Log "=== GPU resource bench start (2 concurrent, 60s wav, port 8023) ==="

# 1) idle 基线（容器 healthy 时）
$idle = @()
for ($i = 0; $i -lt 3; $i++) { $s = Get-GpuSample; if ($s) { $idle += $s }; Start-Sleep -Milliseconds 400 }
$idleUsed = ($idle | Measure-Object -Property UsedMB -Average).Average
$cmIdle = Get-ContainerMem
Log ("idle baseline: hostUsed={0}MB total={1}MB | containerView used={2}MB/{3}MB" -f `
    [math]::Round($idleUsed, 0), ($idle | Select-Object -First 1).TotalMB, $(if ($cmIdle) { $cmIdle.UsedMB } else { 'N/A' }), $(if ($cmIdle) { $cmIdle.TotalMB } else { 'N/A' }))

# 2) 预热：触发模型加载 + CUDA 初始化（首请求可能 ~60s）
Log "warmup request (model load + CUDA init)..."
$t0 = Get-Date
$warm = curl.exe -s --max-time 180 -w ' HTTP=%{http_code}' -F "file=@$wav;type=audio/wav" -F "sample_rate=16000" -F "language=zh" -H "X-API-Key: $key" ($base + '/v1/audio/emotion') 2>&1
Log ("warmup: {0}ms http={1} emotion={2}" -f [math]::Round(((Get-Date) - $t0).TotalMilliseconds, 0), `
    ([regex]::Match($warm, 'HTTP=(\d+)')).Groups[1].Value, ([regex]::Match($warm, '"emotion"\s*:\s*"([^"]+)"')).Groups[1].Value)

# 3) 模型加载后基线（SER 显存增量的计算基准）
Start-Sleep -Seconds 2
$loaded = @()
for ($i = 0; $i -lt 3; $i++) { $s = Get-GpuSample; if ($s) { $loaded += $s }; Start-Sleep -Milliseconds 400 }
$loadedUsed = ($loaded | Measure-Object -Property UsedMB -Average).Average
$cmLoaded = Get-ContainerMem
Log ("loaded baseline: hostUsed={0}MB | containerView used={1}MB/{2}MB" -f `
    [math]::Round($loadedUsed, 0), $(if ($cmLoaded) { $cmLoaded.UsedMB } else { 'N/A' }), $(if ($cmLoaded) { $cmLoaded.TotalMB } else { 'N/A' }))

# 4) 启动 2 个并发 loader
$stamp = Get-Date -Format 'HHmmss'
$loadFiles = @()
$loaders = @()
for ($n = 1; $n -le 2; $n++) {
    $outFile = Join-Path $tmp ("gpurload_{0}_{1}.log" -f $stamp, $n)
    $loadFiles += $outFile
    $loadCmd = @"
`$key = '$key'; `$base = '$base'; `$wav = '$wav'; `$out = '$outFile'
for (`$i = 0; `$i -lt 300; `$i++) {
    `$r = curl.exe -s --max-time 60 -w ' HTTP=%{http_code}' -F "file=@`$wav;type=audio/wav" -F "sample_rate=16000" -F "language=zh" -H "X-API-Key: `$key" (`$base + '/v1/audio/emotion') 2>&1
    `$http = ([regex]::Match(`$r, 'HTTP=(\d+)')).Groups[1].Value
    `$lat  = ([regex]::Match(`$r, '"latencyMs"\s*:\s*([\d.]+)')).Groups[1].Value
    Add-Content -Path `$out -Value ("http=`$http lat=`$lat")
}
"@
    $lf = Join-Path $tmp ("gpurload_{0}_{1}.ps1" -f $stamp, $n)
    Set-Content -Path $lf -Value $loadCmd -Encoding UTF8
    $loaders += (Start-Process -FilePath powershell -ArgumentList '-File', $lf -NoNewWindow -PassThru)
}
Log ("loaders started: {0}" -f (($loaders | ForEach-Object { $_.Id }) -join ','))

# 5) 采样 30s：nvidia-smi 每轮 1 次 + docker stats 每轮 1 次
$peakUsed = 0.0; $peakGpuUtil = 0.0; $peakMemUtil = 0.0
$peakSerCpu = 0.0; $peakCfCpu = 0.0; $peakSerMem = ''
$samples = 0
for ($s = 0; $s -lt 30; $s++) {
    $g = Get-GpuSample
    if ($g) {
        $samples++
        if ($g.UsedMB -gt $peakUsed) { $peakUsed = $g.UsedMB }
        if ($g.GpuUtil -gt $peakGpuUtil) { $peakGpuUtil = $g.GpuUtil }
        if ($g.MemUtil -gt $peakMemUtil) { $peakMemUtil = $g.MemUtil }
    }
    $st = docker stats --no-stream --format '{{.Name}} {{.CPUPerc}} {{.MemUsage}}' emotion2vec-gpu compreface-api 2>$null
    foreach ($line in $st) {
        if ($line -match 'emotion2vec-gpu\s+([\d.]+)%\s+(\S+)') {
            $c = [double]$Matches[1]; if ($c -gt $peakSerCpu) { $peakSerCpu = $c; $peakSerMem = $Matches[2] }
        }
        if ($line -match 'compreface-api\s+([\d.]+)%') {
            $c = [double]$Matches[1]; if ($c -gt $peakCfCpu) { $peakCfCpu = $c }
        }
    }
    Log ("[{0,2}s] vram={1}MB gpuUtil={2}% memUtil={3}% | {4}" -f $s, $(if ($g) { [math]::Round($g.UsedMB, 0) } else { 'N/A' }), `
        $(if ($g) { $g.GpuUtil } else { 'N/A' }), $(if ($g) { $g.MemUtil } else { 'N/A' }), ($st -join ' | '))
    Start-Sleep -Milliseconds 500
}

# 6) 停负载、冷却后复测
$loaders | Stop-Process -Force -ErrorAction SilentlyContinue
Start-Sleep -Seconds 5
$cmAfter = Get-ContainerMem
$after = Get-GpuSample
Log ("cooled: hostUsed={0}MB | containerView used={1}MB" -f $(if ($after) { [math]::Round($after.UsedMB, 0) } else { 'N/A' }), $(if ($cmAfter) { $cmAfter.UsedMB } else { 'N/A' }))

# 7) 统计请求成功率
$totalReq = 0; $okReq = 0; $badReq = 0
foreach ($f in $loadFiles) {
    if (Test-Path $f) {
        $lines = Get-Content -Encoding UTF8 $f
        $totalReq += $lines.Count
        $okReq += ($lines | Where-Object { $_ -match 'http=200' }).Count
        $badReq += ($lines | Where-Object { $_ -match 'http=(?!200)\d+' -or $_ -notmatch 'http=' }).Count
    }
}

# 8) 汇总
$totalMB = ($loaded | Select-Object -First 1).TotalMB
$serDelta = $peakUsed - $loadedUsed
$freeMB = $totalMB - $peakUsed
Log ""
Log "================ SUMMARY ================"
Log ("samples                 = {0}" -f $samples)
Log ("VRAM total              = {0} MB" -f [math]::Round($totalMB, 0))
Log ("VRAM idle baseline      = {0} MB (含宿主 LM Studio/explorer 等)" -f [math]::Round($idleUsed, 0))
Log ("VRAM loaded baseline    = {0} MB (模型已加载)" -f [math]::Round($loadedUsed, 0))
Log ("VRAM peak (2 并发)      = {0} MB" -f [math]::Round($peakUsed, 0))
Log ("SER VRAM increment      = {0} MB (peak - loaded)" -f [math]::Round($serDelta, 0))
Log ("VRAM headroom at peak   = {0} MB ({1}% of total)" -f [math]::Round($freeMB, 0), [math]::Round(100 * $freeMB / $totalMB, 1))
Log ("container view used     = {0} MB idle / {1} MB loaded / {2} MB cooled" -f `
    $(if ($cmIdle) { $cmIdle.UsedMB } else { 'N/A' }), $(if ($cmLoaded) { $cmLoaded.UsedMB } else { 'N/A' }), $(if ($cmAfter) { $cmAfter.UsedMB } else { 'N/A' }))
Log ("GPU util peak           = {0} %" -f $peakGpuUtil)
Log ("mem util peak           = {0} %" -f $peakMemUtil)
Log ("SER CPU peak            = {0} % (mem {1})" -f [math]::Round($peakSerCpu, 1), $peakSerMem)
Log ("CompreFace CPU peak     = {0} % (同机 CPU 服务参照)" -f [math]::Round($peakCfCpu, 1))
Log ("requests                = {0} total / {1} http200 / {2} non-200-or-error" -f $totalReq, $okReq, $badReq)
Log "========================================="
Log "=== GPU resource bench done ==="
