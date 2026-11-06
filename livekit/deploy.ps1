#Requires -Version 5.1
<#
.SYNOPSIS
    矛盾纠纷调解平台 - LiveKit 视频会议服务部署（Windows / Docker Desktop）。

.DESCRIPTION
    start   生成 .env、按 .env 渲染 livekit.yaml、检查端口冲突、启动 Redis + LiveKit、等待就绪
    stop    停止容器（保留数据卷）
    down    移除容器（保留数据卷）
    restart 重新渲染配置并强制重建容器（改完 .env 用这个）
    status  容器状态 + HTTP 存活
    verify  部署冒烟：容器 / HTTP / 端口 / --node-ip / Redis / 密钥一致性
    logs    跟随 livekit-server 日志
    genkeys 生成新密钥对（只打印，不自动改写 .env）

.EXAMPLE
    .\deploy.ps1
    .\deploy.ps1 -Action verify
    .\deploy.ps1 -Action genkeys
#>
param(
    [ValidateSet('start','stop','down','restart','status','verify','logs','genkeys','help')]
    [string]$Action = 'start'
)

# docker 等原生命令会把 WARNING 写 stderr，Stop 模式下会被误判为终止错误
$ErrorActionPreference = 'Continue'

$Root = Split-Path -Parent $MyInvocation.MyCommand.Path
Set-Location $Root

$EnvFile     = Join-Path $Root '.env'
$EnvSample   = Join-Path $Root '.env.example'
$Template    = Join-Path $Root 'livekit.yaml.template'
$Config      = Join-Path $Root 'livekit.yaml'
$ComposeFile = Join-Path $Root 'docker-compose.yml'

function Write-Step { param($m) Write-Host "[deploy] $m" -ForegroundColor Cyan }
function Write-Ok   { param($m) Write-Host "[  ok  ] $m" -ForegroundColor Green }
function Write-Warn { param($m) Write-Host "[ warn ] $m" -ForegroundColor Yellow }
function Write-Fail { param($m) Write-Host "[ fail ] $m" -ForegroundColor Red }

function Show-Usage {
    Write-Host @'
用法: .\deploy.ps1 [-Action start|stop|down|restart|status|verify|logs|genkeys|help]

  start    默认。生成 .env / 渲染 livekit.yaml / 起 Redis + LiveKit
  restart  改动 .env（密钥、node-ip、Redis 地址）后必须用它，会强制重建容器
  verify   冒烟：GET / 返回 200、ports 输出、--node-ip、Redis PONG、密钥一致
  genkeys  生成 >=32 位密钥对，手动写入 .env 并同步 ai-server / livekit-worker

注意：7880/7881/7882 已被本机 mwb-livekit 占用时，start 会拒绝启动。
'@
}

# ---------------- Docker / Compose ----------------
$script:ComposeV2 = $true

function Invoke-Compose {
    param([string[]]$ComposeArgs)
    if ($script:ComposeV2) { & docker compose @ComposeArgs | Out-Host }
    else                   { & docker-compose @ComposeArgs | Out-Host }
    return $LASTEXITCODE
}

function Init-Compose {
    if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
        Write-Fail '未找到 docker，请先安装 Docker Desktop'; exit 1
    }
    & docker version --format '{{.Server.Version}}' 2>$null | Out-Null
    if ($LASTEXITCODE -ne 0) { Write-Fail 'docker daemon 未运行'; exit 1 }

    & docker compose version 2>$null | Out-Null
    if ($LASTEXITCODE -eq 0) { $script:ComposeV2 = $true }
    elseif (Get-Command docker-compose -ErrorAction SilentlyContinue) { $script:ComposeV2 = $false }
    else { Write-Fail '未找到 docker compose / docker-compose'; exit 1 }

    $rc = Invoke-Compose @('-f', $ComposeFile, 'config', '-q')
    if ($rc -ne 0) { Write-Fail 'docker-compose.yml 语法检查失败'; exit 1 }
}

# ---------------- .env ----------------
function Ensure-Env {
    if (-not (Test-Path -LiteralPath $EnvFile)) {
        if (-not (Test-Path -LiteralPath $EnvSample)) { Write-Fail '缺少 .env.example'; exit 1 }
        Copy-Item -LiteralPath $EnvSample -Destination $EnvFile
        Write-Warn '已由 .env.example 生成 .env；跨机部署请先改 LIVEKIT_NODE_IP 再执行 start'
    }
}

function Import-DotEnv {
    param([string]$Path)
    $vars = @{}
    foreach ($line in (Get-Content -LiteralPath $Path -Encoding UTF8)) {
        if ($line -match '^\s*([A-Za-z_][A-Za-z0-9_]*)\s*=\s*(.*)$') {
            $vars[$Matches[1]] = $Matches[2].Trim()
        }
    }
    return $vars
}

function Get-Val {
    param([hashtable]$H, [string]$K, [string]$D)
    if ($H.ContainsKey($K) -and -not [string]::IsNullOrWhiteSpace([string]$H[$K])) {
        return ([string]$H[$K]).Trim()
    }
    return $D
}

function Get-EffectiveConfig {
    Ensure-Env
    $h = Import-DotEnv -Path $EnvFile
    $cfg = @{
        LIVEKIT_IMAGE            = Get-Val $h 'LIVEKIT_IMAGE'            'crpi-c762f77rjuytqer9.cn-hangzhou.personal.cr.aliyuncs.com/llm-basic/base/livekit-server:v1.13.11'
        LIVEKIT_NODE_IP          = Get-Val $h 'LIVEKIT_NODE_IP'          '127.0.0.1'
        LIVEKIT_API_KEY          = Get-Val $h 'LIVEKIT_API_KEY'          'devkey'
        LIVEKIT_API_SECRET       = Get-Val $h 'LIVEKIT_API_SECRET'       'secret'
        REDIS_MODE               = Get-Val $h 'REDIS_MODE'               'internal'
        REDIS_IMAGE              = Get-Val $h 'REDIS_IMAGE'              'docker.m.daocloud.io/library/redis:7.4-alpine'
        LIVEKIT_REDIS_ADDRESS    = Get-Val $h 'LIVEKIT_REDIS_ADDRESS'    'redis:6379'
        LIVEKIT_REDIS_PASSWORD   = Get-Val $h 'LIVEKIT_REDIS_PASSWORD'   'mediation_livekit_redis'
        LIVEKIT_CONTAINER_NAME   = Get-Val $h 'LIVEKIT_CONTAINER_NAME'   'mediation-livekit'
        REDIS_CONTAINER_NAME     = Get-Val $h 'REDIS_CONTAINER_NAME'     'mediation-livekit-redis'
    }
    if ($cfg['REDIS_MODE'] -notin @('internal', 'external')) {
        Write-Fail "REDIS_MODE 只能是 internal / external，当前=$($cfg['REDIS_MODE'])"; exit 1
    }
    if ($cfg['REDIS_MODE'] -eq 'internal') {
        $cfg['LIVEKIT_REDIS_ADDRESS'] = 'redis:6379'
    }
    elseif ($cfg['LIVEKIT_REDIS_ADDRESS'] -eq 'redis:6379') {
        Write-Fail 'REDIS_MODE=external 时必须把 LIVEKIT_REDIS_ADDRESS 改成外部 Redis 地址'; exit 1
    }
    if (($cfg['LIVEKIT_API_KEY'] + $cfg['LIVEKIT_API_SECRET']) -match '"') {
        Write-Fail '密钥不能包含双引号（会破坏渲染出的 YAML）'; exit 1
    }
    return $cfg
}

# ---------------- 渲染 livekit.yaml ----------------
function Render-Config {
    param([hashtable]$Cfg)
    if (-not (Test-Path -LiteralPath $Template)) { Write-Fail '缺少 livekit.yaml.template'; exit 1 }

    $text = [System.IO.File]::ReadAllText($Template, [System.Text.Encoding]::UTF8)
    foreach ($k in @('LIVEKIT_API_KEY','LIVEKIT_API_SECRET','LIVEKIT_REDIS_ADDRESS','LIVEKIT_REDIS_PASSWORD')) {
        $text = $text.Replace(('@' + $k + '@'), [string]$Cfg[$k])
    }
    if ($text -match '@[A-Z][A-Z0-9_]*@') {
        Write-Fail "模板存在未替换占位符：$($Matches[0])"; exit 1
    }
    # UTF-8 无 BOM：LiveKit 的 Go YAML 解析器不接受 BOM
    [System.IO.File]::WriteAllText($Config, $text, (New-Object System.Text.UTF8Encoding($false)))
    Write-Ok '已渲染 livekit.yaml（含明文密钥，请勿提交到版本库）'
}

# ---------------- 前置检查 / 等待 ----------------
function Test-PortConflict {
    param([hashtable]$Cfg)
    $lines = @(docker ps --format '{{.Names}}|{{.Ports}}' 2>$null)
    $self  = [regex]::Escape([string]$Cfg['LIVEKIT_CONTAINER_NAME'])
    $busy  = @($lines | Where-Object { $_ -match ':7880->|:7881->|:7882->' -and $_ -notmatch "^$self\|" })
    if ($busy.Count -gt 0) {
        foreach ($l in $busy) { Write-Host "    $l" -ForegroundColor Yellow }
        Write-Fail '7880/7881/7882 已被其它容器占用（本机已有 mwb-livekit 时会命中）'
        Write-Host '  复用现有实例：把 ai-server 的 LIVEKIT_* 指向它；或先 docker stop mwb-livekit 再部署。' -ForegroundColor Yellow
        exit 1
    }
}

function Get-HttpCode {
    $raw = & curl.exe -s -o NUL -w '%{http_code}' --max-time 3 'http://127.0.0.1:7880/' 2>$null
    if ($LASTEXITCODE -ne 0) { return '000' }
    return ([string]$raw).Trim()
}

function Wait-Ready {
    param([string]$Container)
    for ($i = 1; $i -le 30; $i++) {
        if ((Get-HttpCode) -eq '200') { Write-Ok 'LiveKit 信令存活（GET / => 200）'; return $true }
        Start-Sleep -Seconds 1
    }
    Write-Fail '30s 内 GET http://127.0.0.1:7880/ 未返回 200'
    Write-Host "  排查： docker logs $Container" -ForegroundColor Yellow
    return $false
}

function Wait-RedisHealthy {
    param([string]$Container)
    $sw = [Diagnostics.Stopwatch]::StartNew()
    while ($sw.Elapsed.TotalSeconds -lt 60) {
        $st = ([string](docker inspect --format '{{.State.Health.Status}}' $Container 2>$null)).Trim()
        if ($LASTEXITCODE -eq 0 -and $st -eq 'healthy')   { return $true }
        if ($LASTEXITCODE -eq 0 -and $st -eq 'unhealthy') { return $false }
        Start-Sleep -Seconds 2
    }
    return $false
}

# ---------------- 动作 ----------------
function Start-Deployment {
    param([switch]$ForceRecreate)
    $cfg = Get-EffectiveConfig
    Render-Config -Cfg $cfg
    Test-PortConflict -Cfg $cfg

    Write-Step "镜像：$($cfg['LIVEKIT_IMAGE'])"
    if ($cfg['REDIS_MODE'] -eq 'internal') {
        Write-Step ("启动内置 Redis: {0}, 地址 {1}" -f $cfg['REDIS_CONTAINER_NAME'], $cfg['LIVEKIT_REDIS_ADDRESS'])
        $rc = Invoke-Compose @('-f', $ComposeFile, 'up', '-d', 'redis')
        if ($rc -ne 0) { Write-Fail 'Redis 启动失败'; exit 1 }
        if (-not (Wait-RedisHealthy -Container $cfg['REDIS_CONTAINER_NAME'])) {
            Write-Fail '内置 Redis 未 healthy；查看 docker logs 后重试'; exit 1
        }
        Write-Ok 'Redis healthy'
    }
    else {
        Write-Step "REDIS_MODE=external：跳过内置 Redis，server 将连 $($cfg['LIVEKIT_REDIS_ADDRESS'])"
    }

    $upArgs = @('-f', $ComposeFile, 'up', '-d')
    if ($ForceRecreate) { $upArgs += '--force-recreate' }
    $upArgs += 'livekit-server'
    Write-Step "启动 LiveKit Server（--node-ip $($cfg['LIVEKIT_NODE_IP'])）"
    $rc = Invoke-Compose $upArgs
    if ($rc -ne 0) { Write-Fail 'LiveKit 启动失败'; exit 1 }
    if (-not (Wait-Ready -Container $cfg['LIVEKIT_CONTAINER_NAME'])) { exit 1 }
    Show-Summary -Cfg $cfg
}

function Show-Summary {
    param([hashtable]$Cfg)
    $ip = $Cfg['LIVEKIT_NODE_IP']
    Write-Host ''
    Write-Host '================ 部署完成 ================' -ForegroundColor Green
    Write-Host "信令(浏览器) : ws://$ip:7880"
    Write-Host "API(服务端)  : http://$ip:7880"
    Write-Host "API Key      : $($Cfg['LIVEKIT_API_KEY'])   (Secret 见 .env)"
    Write-Host "容器 / 网络  : $($Cfg['LIVEKIT_CONTAINER_NAME']) / mediation-livekit-net"
    Write-Host ''
    Write-Host 'ai-server 需配置（application.yaml 的 livekit.*）：' -ForegroundColor Cyan
    Write-Host "  LIVEKIT_SERVER_URL=ws://$ip:7880"
    Write-Host "  LIVEKIT_API_URL=http://$ip:7880"
    Write-Host "  LIVEKIT_API_KEY=$($Cfg['LIVEKIT_API_KEY'])"
    Write-Host '  LIVEKIT_API_SECRET=<与 .env 完全一致>'
    Write-Host 'livekit-worker 需：LIVEKIT_URL / LIVEKIT_API_KEY / LIVEKIT_API_SECRET，并加入 mediation-livekit-net'
    Write-Host ''
    if ($ip -eq '127.0.0.1' -or $ip -eq 'localhost') {
        Write-Warn 'node-ip 为回环：仅本机浏览器可用；跨机部署必须改 .env 的 LIVEKIT_NODE_IP'
    }
    if ($Cfg['LIVEKIT_API_KEY'] -eq 'devkey') {
        Write-Warn '仍为默认密钥 devkey/secret；生产请执行 -Action genkeys 并同步后端'
    }
    Write-Host '冒烟验证： .\deploy.ps1 -Action verify'
}

function Verify-Deployment {
    $cfg = Get-EffectiveConfig
    $script:pass = 0
    $script:fail = 0
    function Assert {
        param([string]$Name, [bool]$Cond, [string]$Detail)
        if ($Cond) { Write-Host ("[ pass ] {0}  {1}" -f $Name, $Detail) -ForegroundColor Green; $script:pass++ }
        else       { Write-Host ("[ FAIL ] {0}  {1}" -f $Name, $Detail) -ForegroundColor Red;   $script:fail++ }
    }

    $ctr   = $Cfg['LIVEKIT_CONTAINER_NAME']
    $state = ([string](docker inspect --format '{{.State.Status}}' $ctr 2>$null)).Trim()
    Assert '容器运行' ($state -eq 'running') $state

    # 同端口若跑着别的 LiveKit（例如本机 mwb-livekit），HTTP 200 不能算本部署件存活
    $selfRunning = @(docker ps --format '{{.Names}}' 2>$null | Where-Object { $_ -eq $ctr }).Count -gt 0
    $code = Get-HttpCode
    Assert 'GET / => 200' ($code -eq '200' -and $selfRunning) "HTTP $code (本项目容器运行中=$selfRunning)"

    $ports = [string](docker exec $ctr /livekit-server ports --config /etc/lk/config.yaml 2>$null | Out-String)
    Assert '端口 7880/7881/7882' ($ports -match '7880' -and $ports -match '7881' -and $ports -match '7882') `
        (($ports -replace "`r?`n", ' ').Trim())

    $cmd = [string](docker inspect --format '{{json .Config.Cmd}}' $ctr 2>$null | Out-String)
    Assert '--node-ip 已生效' ($cmd -match '--node-ip') $cmd.Trim()

    if ($cfg['REDIS_MODE'] -eq 'internal') {
        $pong = [string](docker exec $cfg['REDIS_CONTAINER_NAME'] redis-cli -a $cfg['LIVEKIT_REDIS_PASSWORD'] ping 2>$null | Out-String)
        Assert 'Redis PONG' ($pong -match 'PONG') $pong.Trim()
    }
    else {
        Write-Warn 'REDIS_MODE=external：跳过容器内 ping，请确认 server 已连上外部 Redis'
    }

    if (Test-Path -LiteralPath $Config) {
        $rendered = [System.IO.File]::ReadAllText($Config, [System.Text.Encoding]::UTF8)
        $expected = '"' + $cfg['LIVEKIT_API_KEY'] + '": "' + $cfg['LIVEKIT_API_SECRET'] + '"'
        Assert '密钥与 .env 一致' ($rendered.Contains($expected)) 'livekit.yaml keys'
    }
    else { Assert '密钥与 .env 一致' $false '缺少生成物 livekit.yaml' }

    $ps = [string](docker ps --format '{{.Names}}|{{.Ports}}' 2>$null | Where-Object { $_ -match ("^" + [regex]::Escape($ctr) + "\|") } | Out-String)
    Assert 'UDP 7881 已映射' ($ps -match '7881/udp') $ps.Trim()

    Write-Host ''
    Write-Host "===== 汇总：pass=$($script:pass) fail=$($script:fail) =====" -ForegroundColor $(if ($script:fail -eq 0) { 'Green' } else { 'Red' })
    if ($script:fail -gt 0) { exit 1 }
}

function New-Keys {
    $cfg = Get-EffectiveConfig
    Write-Step "用 $($cfg['LIVEKIT_IMAGE']) 生成密钥对 ..."
    $out = @(& docker run --rm --entrypoint /livekit-server $cfg['LIVEKIT_IMAGE'] generate-keys 2>$null)
    if ($LASTEXITCODE -ne 0) { Write-Fail 'generate-keys 失败（镜像是否已拉取？）'; exit 1 }

    $keyLine    = @($out | Where-Object { $_ -match '^API Key:' })[0]
    $secretLine = @($out | Where-Object { $_ -match '^API Secret:' })[0]
    if (-not $keyLine -or -not $secretLine) { Write-Fail '无法解析 generate-keys 输出'; exit 1 }
    $key    = ($keyLine    -replace '^API Key:\s*',    '').Trim()
    $secret = ($secretLine -replace '^API Secret:\s*', '').Trim()

    Write-Host ''
    Write-Host "LIVEKIT_API_KEY=$key"    -ForegroundColor Green
    Write-Host "LIVEKIT_API_SECRET=$secret" -ForegroundColor Green
    Write-Host ''
    Write-Warn '本命令不改写 .env：请手动替换两行，并同步 ai-server 的 LIVEKIT_API_KEY / LIVEKIT_API_SECRET 与 livekit-worker'
    Write-Host  '       然后执行 .\deploy.ps1 -Action restart 使新密钥生效' -ForegroundColor Yellow
}

# ---------------- 主流程 ----------------
if ($Action -eq 'help') { Show-Usage; exit 0 }
Init-Compose

switch ($Action) {
    'start'   { Start-Deployment }
    'restart' { Start-Deployment -ForceRecreate }
    'stop'    {
        $rc = Invoke-Compose @('-f', $ComposeFile, 'stop')
        if ($rc -ne 0) { exit 1 }
        Write-Ok '已停止容器（数据卷保留）'
    }
    'down'    {
        $rc = Invoke-Compose @('-f', $ComposeFile, 'down')
        if ($rc -ne 0) { exit 1 }
        Write-Ok '已移除容器（数据卷 redis_data 保留，如需清空用 docker volume rm mediation-livekit_redis_data）'
    }
    'status'  {
        Invoke-Compose @('-f', $ComposeFile, 'ps') | Out-Null
        $code = Get-HttpCode
        if ($code -eq '200') { Write-Ok 'GET / => 200（信令存活）' }
        else                 { Write-Warn "GET / => $code（未就绪）" }
        $cfg = Get-EffectiveConfig
        Write-Host "配置：node-ip=$($cfg['LIVEKIT_NODE_IP'])  redis=$($cfg['LIVEKIT_REDIS_ADDRESS'])  key=$($cfg['LIVEKIT_API_KEY'])"
    }
    'verify'  { Verify-Deployment }
    'logs'    { Invoke-Compose @('-f', $ComposeFile, 'logs', '-f', 'livekit-server') | Out-Null }
    'genkeys' { New-Keys }
}
