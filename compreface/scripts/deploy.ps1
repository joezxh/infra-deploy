#Requires -Version 5.1
<#
.SYNOPSIS
    CompreFace 部署件启动脚本（**本轮未实测，仅供内网门禁验证，不得直接投产**）。
.DESCRIPTION
    1. 首次运行自动生成 .env 与随机密钥（API_KEY / PG_PASSWORD）
    2. 校验上线门禁开关仍为 false
    3. docker compose up -d 并等待各容器健康
    4. 提示运维通过回环 UI 创建 Face Verification 服务、回填 COMPREFACE_API_KEY
.EXAMPLE
    .\scripts\deploy.ps1
#>

$ErrorActionPreference = 'Continue'   # docker 会把 WARNING 打到 stderr，Stop 模式会误断
$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

Write-Host '===== CompreFace 部署件（未实测 / 不接业务链路） =====' -ForegroundColor Yellow
Write-Host '[warn] 本编排骨架的镜像 tag、环境变量与 REST 路径尚未与官方 compose 核对。' -ForegroundColor Yellow
Write-Host '[warn] G0-G3 门禁未过前，平台侧 video.available 必须为 false。' -ForegroundColor Yellow
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
    $pgPass = New-RandomKey 32
    $text = Get-Content $envPath -Raw
    $text = $text -replace '(?m)^API_KEY=.*$', "API_KEY=$apiKey"
    $text = $text -replace '(?m)^PG_PASSWORD=.*$', "PG_PASSWORD=$pgPass"
    [System.IO.File]::WriteAllText($envPath, $text, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host '[ ok ] 已生成 .env 与随机密钥（请确认 .env 已被 .gitignore 排除）' -ForegroundColor Green
}

$envLines = Get-Content $envPath
function Get-EnvValue($name) {
    $v = ($envLines | Where-Object { $_ -match "^$name=" } | Select-Object -First 1)
    if (-not $v) { return '' }
    ($v -replace "^$name=", '').Trim()
}

# ---------- 2. 门禁 ----------
$poc = Get-EnvValue 'MEETING_FACE_POC_PASSED'
if ($poc -ne 'false') {
    Write-Host "[fail] MEETING_FACE_POC_PASSED=$poc；门禁留档齐备前不得启动部署件" -ForegroundColor Red
    exit 1
}
if (-not (Get-EnvValue 'COMPREFACE_API_KEY')) {
    Write-Host '[warn] COMPREFACE_API_KEY 为空：部署后需访问 http://127.0.0.1:8051/login 创建 Face Verification 服务并回填，再重启 nginx' -ForegroundColor Yellow
}

# ---------- 3. 拉起 ----------
Write-Host ''
Write-Host '===== docker compose up -d =====' -ForegroundColor Cyan
& docker compose -f (Join-Path $Root 'docker-compose.yml') --env-file $envPath up -d
if ($LASTEXITCODE -ne 0) { Write-Host "[fail] docker compose up 失败，退出码 $LASTEXITCODE" -ForegroundColor Red; exit 1 }

# ---------- 4. 等健康 ----------
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
Write-Host '===== 等待健康（5 容器 + nginx，最多 900s） =====' -ForegroundColor Cyan
foreach ($c in @('compreface-postgres-db', 'compreface-core', 'compreface-nginx')) {
    if (Wait-Healthy $c 900) { Write-Host "[ ok ] $c healthy" -ForegroundColor Green }
    else { Write-Host "[warn] $c 未达 healthy（镜像/变量待与官方 compose 核对）" -ForegroundColor Yellow }
}

Write-Host ''
Write-Host '===== 后续人工步骤 =====' -ForegroundColor Cyan
Write-Host '1) 访问 http://127.0.0.1:8051/login 注册管理员，创建 **Face Verification** 类型服务'
Write-Host '2) 复制其 x-api-key 回填 .env 的 COMPREFACE_API_KEY，再执行 docker compose up -d 使 nginx 重载'
Write-Host '3) 运行 .\scripts\verify.ps1 做四段式验证，并把实测结论回写 README「实测留档」'
Write-Host '4) 未回写前保持 MEETING_FACE_POC_PASSED=false，平台侧不得置 video.available=true'
