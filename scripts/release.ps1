# 发版：改版本号 → 提交 → 打 tag → 推送 → GitHub Actions 自动出 Release
# 用法：release.cmd 0.2.0
[CmdletBinding()]
param([Parameter(Position = 0)][string]$Version = '')

$ErrorActionPreference = 'Stop'
# Windows PowerShell 5.1 没有这个变量；PS 7.3+ 需要关掉，避免原生命令非零退出码被当成异常。
if ($null -ne (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue)) {
  $PSNativeCommandUseErrorActionPreference = $false
}

$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

function Get-GitPath {
  $cmd = Get-Command git -ErrorAction SilentlyContinue
  if ($null -ne $cmd) { return $cmd.Source }
  foreach ($candidate in @('C:\Users\admin\.dsh\tools\git\bin\git.exe', 'C:\Program Files\Git\cmd\git.exe')) {
    if (Test-Path $candidate) { return $candidate }
  }
  throw '找不到 git。'
}

function Invoke-Git {
  param([string[]]$GitArgs)
  & $script:git @GitArgs
  if ($LASTEXITCODE -ne 0) { throw ('git ' + ($GitArgs -join ' ') + ' 失败（退出码 ' + $LASTEXITCODE + '）') }
}

function Test-Git {
  param([string[]]$GitArgs)
  & $script:git @GitArgs *> $null
  return ($LASTEXITCODE -eq 0)
}

$script:git = Get-GitPath

if (-not (Test-Path (Join-Path $root '.git'))) {
  Write-Host '[!] 还不是 git 仓库，先跑 setup.cmd。' -ForegroundColor Yellow
  exit 2
}

$pkgPath = Join-Path $root 'package.json'
$raw = [IO.File]::ReadAllText($pkgPath)
$pkg = $raw | ConvertFrom-Json

if ([string]::IsNullOrWhiteSpace($Version)) {
  $Version = Read-Host ('新版本号（当前 ' + $pkg.version + '，例：0.2.0）')
}
$target = $Version.Trim().TrimStart('v')
if ($target -notmatch '^\d+\.\d+\.\d+') {
  throw ('版本号要像 0.2.0 这样，收到：' + $Version)
}

$newRaw = $raw -replace '"version":\s*"[^"]+"', ('"version": "' + $target + '"')
if ($newRaw -ne $raw) {
  [IO.File]::WriteAllText($pkgPath, $newRaw, (New-Object System.Text.UTF8Encoding($false)))
  Write-Host ('[ok] package.json 版本 → ' + $target) -ForegroundColor Green
}

$branch = (& $script:git rev-parse --abbrev-ref HEAD).Trim()
if ($branch -eq '' -or $branch -eq 'HEAD') { $branch = 'main' }

& $script:git add -A
& $script:git diff --cached --quiet
if ($LASTEXITCODE -ne 0) {
  Invoke-Git @('commit', '-m', ('发布 v' + $target))
}

$tag = 'v' + $target
if ((((& $script:git tag -l $tag) | Out-String).Trim()) -ne '') { Invoke-Git @('tag', '-d', $tag) }
Invoke-Git @('tag', '-a', $tag, '-m', ('发布 ' + $tag))
Write-Host ('[ok] 已打 tag：' + $tag) -ForegroundColor Green

Write-Host '[..] 推送分支与 tag …' -ForegroundColor Cyan
Invoke-Git @('push', '-u', 'origin', $branch)
Invoke-Git @('push', 'origin', $tag)

$url = ((& $script:git remote get-url origin).Trim()) -replace '^git@github\.com:', 'https://github.com/'
$web = $url -replace '\.git$', ''
Write-Host '[ok] 推送完成，GitHub Actions 正在打包并创建 Release。' -ForegroundColor Green
if ($web -like 'https://github.com/*') {
  Write-Host ('     发布页：' + $web + '/releases')
}
