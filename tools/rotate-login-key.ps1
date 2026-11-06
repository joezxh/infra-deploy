<#
.SYNOPSIS
    登录密码 RSA 密钥轮换助手（C00 整改配套）。

.DESCRIPTION
    四步轮换（前后端协同，配合 uaa 重启）：
      1) node rotate-login-key.ps1 -Action status    # 查看当前状态
      2) （重启 uaa，使新私钥生效；新旧私钥并存）
      3) node rotate-login-key.ps1 -Action switch    # 前端公钥切到新公钥（dev server 会热更新）
      4）node rotate-login-key.ps1 -Action verify    # 登录冒烟（新公钥 → 新私钥）
      5) node rotate-login-key.ps1 -Action retire    # 退役旧私钥（仅留 2048 位那把）
      6) （再次重启 uaa）→ 再 verify

    顺序要点：先重启 uaa 再切前端；先切前端再退役旧私钥。任何一步失败都可原地重跑，
    不会破坏可用性（轮换窗口内新旧私钥并存）。

.EXAMPLE
    node rotate-login-key.ps1 -Action status
#>
param(
    [ValidateSet('status', 'switch', 'retire', 'verify')][string]$Action = 'status',
    [string]$DeployRoot = 'd:/work/mediation_platform/mediation-deploy',
    [string]$WebRoot = 'd:/work/mediation_platform/mediation-web',
    [string]$LoginBase = 'http://127.0.0.1:8080/admin-api/uaa/auth/login',
    [string]$TenantId = '1',
    [string]$User = 'admin',
    [string]$Pass = 'admin123'
)

$ErrorActionPreference = 'Stop'
$privFile = Join-Path $DeployRoot 'secrets\uaa-login-rsa-private.key'
$pubFile = Join-Path $DeployRoot 'secrets\uaa-login-rsa-public.key'
$jsFile = Join-Path $WebRoot 'src\utils\jsencrypt.ts'
$envFile = Join-Path $WebRoot '.env.development'

function Get-PrivKeys {
    if (-not (Test-Path $privFile)) { throw "私钥文件不存在：$privFile" }
    $out = @()
    foreach ($l in [System.IO.File]::ReadAllLines($privFile)) {
        $t = $l.Trim()
        if (-not $t -or $t.StartsWith('#')) { continue }
        $out += $t
    }
    return $out
}

function Get-NewPub {
    if (-not (Test-Path $pubFile)) { throw "公钥文件不存在：$pubFile" }
    return ([System.IO.File]::ReadAllText($pubFile)).Trim()
}

function Test-FrontendHasNewPub {
    # 源码里公钥按 64 字符切片，故前 48 字符必然完整落在第一片内 —— 用子串判定即可，
    # 避免跨语句正则匹配（.NET 与 JS 行为差异大，易吞掉后续代码）
    $pub = Get-NewPub
    $needle = $pub.Substring(0, [Math]::Min(48, $pub.Length))
    if (-not (Test-Path $jsFile)) { return $false }
    return ([System.IO.File]::ReadAllText($jsFile)).Contains($needle)
}

function Test-KeyMatchesNewPub {
    param([string]$KeyB64, [string]$PubB64)
    $out = & node -e "try{const c=require('crypto');const k=c.createPrivateKey({key:Buffer.from(process.argv[1],'base64'),format:'der',type:'pkcs8'});const p=c.createPublicKey({key:Buffer.from(process.argv[2],'base64'),format:'der',type:'spki'});const e=c.publicEncrypt({key:p,padding:c.constants.RSA_PKCS1_PADDING},Buffer.from('probe'));const d=c.privateDecrypt({key:k,padding:c.constants.RSA_PKCS1_PADDING},e);process.stdout.write(d.toString());}catch(e){process.stdout.write('');}" $KeyB64 $PubB64
    return ($out -eq 'probe')
}

function Split-B64 {
    param([string]$B64, [int]$Width = 64)
    $parts = @()
    for ($i = 0; $i -lt $B64.Length; $i += $Width) {
        $parts += $B64.Substring($i, [Math]::Min($Width, $B64.Length - $i))
    }
    return $parts
}

function Show-Status {
    $keys = Get-PrivKeys
    $newPub = Get-NewPub
    Write-Host "私钥文件：$privFile"
    Write-Host "私钥把数：$($keys.Count)"
    foreach ($k in $keys) {
        $bits = & node -e "try{const c=require('crypto');const k=c.createPrivateKey({key:Buffer.from(process.argv[1],'base64'),format:'der',type:'pkcs8'});process.stdout.write(String(k.asymmetricKeyDetails.modulusLength));}catch(e){process.stdout.write('?');}" $k
        $match = Test-KeyMatchesNewPub -KeyB64 $k -PubB64 $newPub
        Write-Host "  - base64 长度 $($k.Length)，RSA 位数 $bits，与新公钥配对=$match"
    }
    $frontSwitched = Test-FrontendHasNewPub
    Write-Host "新公钥长度：$($newPub.Length)"
    Write-Host "前端是否已用新公钥：$frontSwitched"
    Write-Host ""
    Write-Host '下一步：'
    if ($keys.Count -gt 1 -and -not $frontSwitched) {
        Write-Host '  1) 重启 uaa（加载新私钥，新旧并存）'
        Write-Host '  2) node rotate-login-key.ps1 -Action switch'
        Write-Host '  3) node rotate-login-key.ps1 -Action verify'
        Write-Host '  4) node rotate-login-key.ps1 -Action retire → 再重启 uaa → 再 verify'
    } elseif ($frontSwitched -and $keys.Count -gt 1) {
        Write-Host '  1) node rotate-login-key.ps1 -Action verify   （确认新公钥链路可用）'
        Write-Host '  2) node rotate-login-key.ps1 -Action retire → 重启 uaa → 再 verify'
    } else {
        Write-Host '  当前状态已收敛（单私钥 + 前端新公钥）。'
    }
}
function Switch-Frontend {
    $pub = Get-NewPub
    # 用 node 完成替换：JS 与 .NET 正则行为不同，且 .NET 侧极易跨语句吞掉后续代码
    $tmpJs = Join-Path $env:TEMP 'rotate-front-key.js'
    $jsCode = @'
const fs = require('fs');
const file = process.argv[2], pub = process.argv[3];
let t = fs.readFileSync(file, 'utf8');
const rx = /const DEFAULT_PUBLIC_KEY\s*=\s*((?:\s*'(?:[A-Za-z0-9+/=]|\\n)*'\s*\+?\s*)+?);/;
if (!rx.test(t)) { console.log('NO_MATCH'); process.exit(1); }
const parts = pub.match(/.{1,64}/g) || [];
const body = parts.map(p => "  '" + p + "' +").join('\n').replace(/ \+\s*$/, '');
const block = 'const DEFAULT_PUBLIC_KEY =\n' + body + ';';
fs.writeFileSync(file, t.replace(rx, block), 'utf8');
console.log('OK');
'@
    [System.IO.File]::WriteAllText($tmpJs, $jsCode, (New-Object System.Text.UTF8Encoding($false)))
    $out = & node $tmpJs $jsFile $pub
    Remove-Item $tmpJs -ErrorAction SilentlyContinue
    if ("$out" -notmatch 'OK') { throw "前端公钥替换失败：$out" }
    Write-Host "已更新：$jsFile 的 DEFAULT_PUBLIC_KEY"

    if (Test-Path $envFile) {
        $e = [System.IO.File]::ReadAllText($envFile)
        $pem = 'VITE_LOGIN_RSA_PUBLIC_KEY="-----BEGIN PUBLIC KEY-----\n' + $pub + '\n-----END PUBLIC KEY-----"'
        $lines = $e -split "`r?`n"
        $hit = $false
        for ($i = 0; $i -lt $lines.Count; $i++) {
            if ($lines[$i] -match '^\s*#?\s*VITE_LOGIN_RSA_PUBLIC_KEY=') { $lines[$i] = $pem; $hit = $true }
        }
        if (-not $hit) { $lines += $pem }
        [System.IO.File]::WriteAllText($envFile, ($lines -join "`n"), (New-Object System.Text.UTF8Encoding($false)))
        Write-Host "已更新：$envFile 的 VITE_LOGIN_RSA_PUBLIC_KEY"
    }
    Write-Host '前端公钥已切换为新公钥。若 dev server 在运行，Vite 会热更新；生产需重新构建发布。'
}

function Retire-OldKeys {
    $keys = Get-PrivKeys
    if ($keys.Count -le 1) { Write-Host '私钥文件已只有一把，无需退役'; return }
    $newPub = Get-NewPub
    # 依据「能否用该私钥解开新公钥的密文」判断保留哪把：能解的保留（2048 位新私钥）
    $keep = @()
    foreach ($k in $keys) {
        $probe = & node -e "const c=require('crypto');const k=c.createPrivateKey({key:Buffer.from(process.argv[1],'base64'),format:'der',type:'pkcs8'});const p=c.createPublicKey({key:Buffer.from(process.argv[2],'base64'),format:'der',type:'spki'});const e=c.publicEncrypt({key:p,padding:c.constants.RSA_PKCS1_PADDING},Buffer.from('probe'));const d=c.privateDecrypt({key:k,padding:c.constants.RSA_PKCS1_PADDING},e);process.stdout.write(d.toString());" $k $newPub 2>$null
        if ($probe -eq 'probe') { $keep += $k } else { Write-Host "退役一把旧私钥（长度 $($k.Length)，与新公钥不配对）" }
    }
    if ($keep.Count -ne 1) { throw "退役判定异常：保留 $($keep.Count) 把，预期 1 把；请人工检查 $privFile" }
    $content = @(
        '# 登录密码 RSA 私钥（仅服务端持有）',
        '# 【安全红线】严禁入库、严禁进前端 bundle、严禁进镜像。',
        '# 轮换记录：2026-11-05 升级到 2048 位（旧的 1024 位已退役）。',
        '# 每行一把私钥（# 注释），轮换窗口内可多把并存。',
        $keep[0],
        ''
    ) -join "`n"
    [System.IO.File]::WriteAllText($privFile, $content, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host "已退役旧私钥，保留 1 把（长度 $($keep[0].Length)）。请重启 uaa 使其生效。"
}

function Verify-Login {
    $pub = Get-NewPub
    $enc = & node -e "const c=require('crypto');const k='-----BEGIN PUBLIC KEY-----\n'+process.argv[1]+'\n-----END PUBLIC KEY-----';console.log(c.publicEncrypt({key:k,padding:c.constants.RSA_PKCS1_PADDING},Buffer.from(process.argv[2])).toString('base64'))" $pub $Pass
    if (-not $enc) { throw '密码加密失败' }
    $body = @{ username = $User; password = $enc } | ConvertTo-Json
    try {
        $r = Invoke-RestMethod -Method Post -Uri $LoginBase -ContentType 'application/json' -Headers @{ 'tenant-id' = $TenantId } -Body $body -TimeoutSec 20
        Write-Host "登录 HTTP 成功，code=$($r.code)"
        if ($r.code -eq 0) { Write-Host '[verify] 登录通过：新公钥 → uaa 新私钥 解密链路正常' -ForegroundColor Green; return }
        Write-Host "[verify] 登录失败：$($r.msg)" -ForegroundColor Red
    } catch {
        Write-Host "[verify] 请求异常：$($_.Exception.Message)" -ForegroundColor Red
    }
}

switch ($Action) {
    'status' { Show-Status }
    'switch' { Switch-Frontend }
    'retire' { Retire-OldKeys }
    'verify' { Verify-Login }
}