# gpu_poc_pipeline.ps1 —— cu128/sm_120 GPU 镜像构建完成后自动起服务、实测 CUDA kernel、跑延迟对比
# 关键：GPU compose 与 CPU 共用 ser/.env，其中 SER_IMAGE/SER_DEVICE/SER_PORT 是 CPU 配置，
#       必须在进程级覆盖，否则 GPU 容器会跑 CPU / 抢 8020-8021 端口。
# 关键：torch 2.6.0+cu124 的 is_available() 为 True 但 sm_120 无 kernel，
#       故 CUDA 校验必须是真实 matmul，而非仅查 is_available()。

$serDir = 'd:\work\mediation_platform\mediation-deploy\ser'
$compose = Join-Path $serDir 'docker-compose.gpu.yml'
$latency = Join-Path $serDir 'scripts\latency_bench_gpu.ps1'
$log = Join-Path $serDir 'gpu_poc_cu128.log'

$env:SER_IMAGE = 'emotion2vec:gpu-cu128'
$env:SER_DEVICE = 'cuda:0'
$env:SER_PORT = '8022'
$env:SER_NGINX_PORT = '8023'
$env:SER_MODEL_ID = 'iic/emotion2vec_plus_large'

function Log($m) { $ts = Get-Date -Format 'HH:mm:ss'; Add-Content -Path $log -Value ("[{0}] {1}" -f $ts, $m) }

Log "=== GPU PoC start (torch cu128 / sm_120, ports 8022/8023) ==="

# 1) 等待 cu128 镜像（新标签，避免 cu124 旧镜像触发抢跑）
$built = $false
for ($i = 0; $i -lt 240; $i++) {
    $img = (docker images -q emotion2vec:gpu-cu128 2>$null)
    if ($img) { Log ("image OK: " + $img); $built = $true; break }
    Start-Sleep -Seconds 15
}
if (-not $built) { Log "TIMEOUT: emotion2vec:gpu-cu128 not built"; exit 1 }

# 2) 清掉旧 GPU 容器后重建
Log "remove stale gpu containers"
docker rm -f emotion2vec-gpu ser-nginx-gpu 2>&1 | ForEach-Object { Log $_ }
Log "docker compose up -d --force-recreate"
docker compose -f $compose up -d --force-recreate 2>&1 | ForEach-Object { Log $_ }

# 3) 等 healthy
$h = $null
for ($i = 0; $i -lt 36; $i++) {
    $h = (docker inspect --format '{{.State.Health.Status}}' emotion2vec-gpu 2>$null)
    if ($h -eq 'healthy') { Log "emotion2vec-gpu healthy"; break }
    Start-Sleep -Seconds 5
}
Log ("health status = " + $h)

# 4) CUDA kernel 实测（真实 matmul，能抓出 sm_120 无 kernel 的问题）
Log "=== CUDA kernel smoke (matmul) ==="
$cuda = (docker exec emotion2vec-gpu python -c "import torch; x=torch.randn(64,64,device='cuda'); print('KERNEL_OK', torch.__version__, (x@x).sum().item())" 2>&1)
Log ("cuda_check: " + ($cuda -join ' '))
if (-not ($cuda -match 'KERNEL_OK')) {
    Log "ERROR: CUDA kernel unusable -> ABORT latency bench (no fake numbers)"
    exit 1
}

# 5) 延迟对比（10/30/60s 各 20 次，走 8023/ser）
Log "=== running latency_bench_gpu.ps1 ==="
$out = & powershell -File $latency 2>&1
$out | ForEach-Object { Log $_ }
Log ("bench exit code = " + $LASTEXITCODE)

Log "=== GPU PoC done ==="
