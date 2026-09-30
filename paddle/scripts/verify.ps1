#Requires -Version 5.1
<#
.SYNOPSIS
    PaddleOCR(PP-OCRv6) 部署冒烟测试：
      1. Nginx 存活
      2. 无 API Key 调用应被拒（401）
      3. PP-OCRv6 图片识别返回文本（经 Nginx）
.EXAMPLE
    .\scripts\verify.ps1
#>

$Root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
Set-Location $Root

$envFile = Get-Content ".env" -ErrorAction SilentlyContinue
if (-not $envFile) { Write-Host "[fail] 缺少 .env，请先运行 deploy.ps1" -ForegroundColor Red; exit 1 }
function Get-EnvValue($name) { (($envFile | Where-Object { $_ -match "^$name=" }) -replace "^$name=", '').Trim() }

$apiKey    = Get-EnvValue 'API_KEY'
$nginxPort = Get-EnvValue 'NGINX_HTTP_PORT'; if (-not $nginxPort) { $nginxPort = '80' }
$base      = "http://127.0.0.1:$nginxPort"
$sample    = Join-Path $Root 'samples\test-ocr.png'

$pass = 0; $fail = 0
function Assert($name, $cond, $detail) {
    if ($cond) { Write-Host ("[ pass ] {0}  {1}" -f $name, $detail) -ForegroundColor Green; $script:pass++ }
    else       { Write-Host ("[ FAIL ] {0}  {1}" -f $name, $detail) -ForegroundColor Red;   $script:fail++ }
}

Write-Host "===== 1. Nginx 存活 =====" -ForegroundColor Cyan
try {
    $h = Invoke-RestMethod -Uri "$base/nginx-health" -TimeoutSec 10
    Assert 'nginx-health' ($h.status -eq 'ok') ($h | ConvertTo-Json -Compress)
} catch { Assert 'nginx-health' $false $_.Exception.Message }

Write-Host ""
Write-Host "===== 2. 无 API Key 应返回 401 =====" -ForegroundColor Cyan
try {
    $r = Invoke-WebRequest -Uri "$base/ocr/v6/health" -TimeoutSec 10
    Assert 'auth-401' $false "期望 401，实际 $($r.StatusCode)"
} catch {
    $code = $_.Exception.Response.StatusCode.value__
    Assert 'auth-401' ($code -eq 401) "实际 HTTP $code"
}

if (-not (Test-Path $sample)) {
    Write-Host ""
    Write-Host "[skip] 缺少样例图片 $sample，跳过 OCR 用例" -ForegroundColor Yellow
} else {
    Write-Host ""
    Write-Host "===== 3. PP-OCRv6 图片识别 =====" -ForegroundColor Cyan
    try {
        # Windows PowerShell 5.1 不支持 Invoke-RestMethod -Form，改用 curl.exe（Windows 自带）
        $raw = & curl.exe -s -w "`n%{http_code}" -H "X-API-Key: $apiKey" `
              -F "image=@$sample" "$base/ocr/v6/ocr" 2>$null
        $lines = $raw -split "`n"
        $code  = $lines[-1]
        $body  = ($lines | Select-Object -SkipLast 1) -join "`n"
        if ($code -ne '200') { Assert 'ocr-v6' $false "HTTP $code"; break }
        $r = $body | ConvertFrom-Json
        $text = $r.data[0].text
        Assert 'ocr-v6' ($r.count -gt 0 -or $text.Length -gt 0) ("count=$($r.count), 首行=$(($text -split "`n" | Select-Object -First 1))")
    } catch { Assert 'ocr-v6' $false $_.Exception.Message }
}

Write-Host ""
Write-Host "===== 汇总：pass=$pass fail=$fail =====" -ForegroundColor $(if ($fail -eq 0) { 'Green' } else { 'Red' })
if ($fail -gt 0) { exit 1 }
