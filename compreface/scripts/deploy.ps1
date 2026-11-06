#Requires -Version 5.1
<#
.SYNOPSIS
    CompreFace 部署件启动脚本（自定义 core：YuNet + SFace）。
.DESCRIPTION
    1. 首次运行自动生成 .env 与随机 API_KEY（数据库复用宿主 postgres/postgres，不随机改）
    2. 校验上线门禁：false 直接放行；true 时必须存在 enable-face-poc.ps1 生成的置位留档
    3. 校验自定义 core 镜像已构建（否则提示先运行 build-core.ps1）
    4. docker compose up -d 并等待核心容器健康
    5. 提示运维通过回环 UI 创建 Face Verification 服务、回填 COMPREFACE_API_KEY
.EXAMPLE
    .\scripts\deploy.ps1
#>

$ErrorActionPreference = 'Continue'   # docker 会把 WARNING 打到 stderr，Stop 模式会误断
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

Write-Host '===== CompreFace 部署件（自定义 core：YuNet + SFace） =====' -ForegroundColor Yellow
Write-Host '[info] 数据库复用宿主 PostgreSQL（postgres/postgres，库名 compreface，经 host.docker.internal:5432）' -ForegroundColor Gray
Write-Host ''

# ---------- 1. .env ----------
$envPath = Join-Path $Root '.env'
if (-not (Test-Path $envPath)) {
    Copy-Item (Join-Path $Root '.env.example') $envPath
    function New-RandomKey($len) {
        $chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789'
        -join (1..$len | ForEach-Object { $chars[(Get-Random -Maximum $chars.Length)] })
    }
    $apiKey = New-RandomKey 40
    $text = Get-Content $envPath -Raw
    # 仅注入随机 API_KEY；PG 凭据沿用 .env.example 的 postgres/postgres
    $text = $text -replace '(?m)^API_KEY=.*$', "API_KEY=$apiKey"
    [System.IO.File]::WriteAllText($envPath, $text, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host '[ ok ] 已生成 .env 与随机 API_KEY（PG 沿用 postgres/postgres；请确认 .env 已被 .gitignore 排除）' -ForegroundColor Green
}

$envLines = Get-Content $envPath
function Get-EnvValue($name) {
    $v = ($envLines | Where-Object { $_ -match "^$name=" } | Select-Object -First 1)
    if (-not $v) { return '' }
    ($v -replace "^$name=", '').Trim()
}

# ---------- 2. 门禁 ----------
$poc = Get-EnvValue 'MEETING_FACE_POC_PASSED'
if ($poc -eq 'true') {
    # 用户人工放行后允许启动，但必须有 enable-face-poc.ps1 生成的置位留档（不放松「留档齐备」纪律）
    $record = Join-Path $Root 'evidence\poc-enablement-record.md'
    if (-not (Test-Path -LiteralPath $record)) {
        Write-Host "[fail] MEETING_FACE_POC_PASSED=true 但缺少置位留档：$record" -ForegroundColor Red
        Write-Host '       请补齐留档，或执行 .\scripts\enable-face-poc.ps1 -Action rollback 回到 fail-closed' -ForegroundColor Red
        exit 1
    }
    Write-Host "[ ok ] 门禁已人工放行，置位留档存在：$record" -ForegroundColor Green
} elseif ($poc -ne 'false') {
    Write-Host "[fail] MEETING_FACE_POC_PASSED=$poc；门禁留档齐备前不得启动部署件" -ForegroundColor Red
    exit 1
}
if (-not (Get-EnvValue 'COMPREFACE_API_KEY')) {
    Write-Host '[warn] COMPREFACE_API_KEY 为空：部署后需访问 http://127.0.0.1:8051/login 创建 Face Verification 服务并回填，再重启 nginx' -ForegroundColor Yellow
}
if (-not (Get-EnvValue 'COMPREFACE_DET_KEY')) {
    Write-Host '[warn] COMPREFACE_DET_KEY 为空：key 与服务类型绑定，另需创建 Face Detection 服务并把 key 回填（detect 接口用它）' -ForegroundColor Yellow
}

# ---------- 2b. 权重清单与哈希（提示，不新建校验体系） ----------
$detModel = Get-EnvValue 'FACE_DET_MODEL'
$recModel = Get-EnvValue 'FACE_REC_MODEL'
$detHash = Get-EnvValue 'FACE_DET_SHA256'
$recHash = Get-EnvValue 'FACE_REC_SHA256'
if (-not $detModel -or -not $recModel -or $detHash -like 'REPLACE*' -or $recHash -like 'REPLACE*' -or -not (Get-EnvValue 'COMPREFACE_CORE_IMAGE')) {
    Write-Host '[warn] 模型权重清单 / SHA256 期望值 / 自定义 core 镜像未就绪，请先运行 verify.ps1 第 0 段确认' -ForegroundColor Yellow
}

# ---------- 3. 自定义 core 镜像校验 ----------
$coreImage = Get-EnvValue 'COMPREFACE_CORE_IMAGE'
$exists = $false
try { & docker image inspect $coreImage 2>$null | Out-Null; $exists = ($LASTEXITCODE -eq 0) } catch { }
if (-not $exists) {
    Write-Host "[warn] 自定义 core 镜像 $coreImage 不存在；尝试自动构建（需 Docker daemon 出网）" -ForegroundColor Yellow
    & docker build -f (Join-Path $Root 'build\core-build\Dockerfile') -t $coreImage (Join-Path $Root 'build\core-build')
    if ($LASTEXITCODE -ne 0) {
        Write-Host "[fail] 自动构建失败；请手动运行 .\scripts\build-core.ps1 并检查 Docker 出网" -ForegroundColor Red
        exit 1
    }
}

# ---------- 4. 拉起 ----------
Write-Host ''
Write-Host '===== docker compose up -d =====' -ForegroundColor Cyan
& docker compose -f (Join-Path $Root 'docker-compose.yml') --env-file $envPath up -d
if ($LASTEXITCODE -ne 0) { Write-Host "[fail] docker compose up 失败，退出码 $LASTEXITCODE" -ForegroundColor Red; exit 1 }

# ---------- 5. 等健康 ----------
function Wait-Healthy($name, $timeoutSec) {
    $deadline = (Get-Date).AddSeconds($timeoutSec)
    while ((Get-Date) -lt $deadline) {
        $state = & docker inspect --format '{{.State.Health.Status}}' $name 2>$null
        if ($LASTEXITCODE -eq 0 -and $state -eq 'healthy') { return $true }
        Start-Sleep -Seconds 5
    }
    return $false
}

Write-Host ''
Write-Host '===== 等待健康（compreface-core / compreface-nginx，最多 900s） =====' -ForegroundColor Cyan
foreach ($c in @('compreface-core', 'compreface-nginx')) {
    if (Wait-Healthy $c 900) { Write-Host "[ ok ] $c healthy" -ForegroundColor Green }
    else { Write-Host "[warn] $c 未达 healthy（检查日志：docker compose logs $c）" -ForegroundColor Yellow }
}

Write-Host ''
Write-Host '===== 后续人工步骤 =====' -ForegroundColor Cyan
Write-Host '1) 访问 http://127.0.0.1:8051/login 注册管理员，创建 **Face Verification** 类型服务'
Write-Host '2) 复制其 x-api-key 回填 .env 的 COMPREFACE_API_KEY，再执行 docker compose up -d 使 nginx 重载'
Write-Host '3) 运行 .\scripts\verify.ps1（含权重 SHA256 比对 + detect/verify 契约），并把实测结论回写 README'
Write-Host '4) 门禁置位/回滚统一用 .\scripts\enable-face-poc.ps1；置位后须补齐真人 G0/G1/G2 报告与 G3 法务/运维留档'
