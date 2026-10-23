# dsh-demo-plugin —— 一键提交并推送
# 用法：push.cmd            用默认说明（时间戳）
#       push.cmd "改了啥"   自定义提交说明
[CmdletBinding()]
param([Parameter(ValueFromRemainingArguments = $true)][string[]]$Message = @())

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
  Write-Host '[!] 这个目录还不是 git 仓库。' -ForegroundColor Yellow
  Write-Host '    先跑一次 setup.cmd 做首次配置。' -ForegroundColor Yellow
  exit 2
}

$text = ''
if ($null -ne $Message -and $Message.Count -gt 0) { $text = ($Message -join ' ').Trim() }
if ($text -eq '') { $text = '更新 ' + (Get-Date -Format 'yyyy-MM-dd HH:mm') }

Invoke-Git @('add', '-A')

& $script:git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
  Write-Host '没有改动，不用提交。' -ForegroundColor DarkGray
} else {
  Invoke-Git @('commit', '-m', $text)
  Write-Host ('[ok] 已提交：' + $text) -ForegroundColor Green
}

$remotes = @(& $script:git remote)
if (-not ($remotes -contains 'origin')) {
  Write-Host '[!] 还没配远程仓库。先跑 setup.cmd。' -ForegroundColor Yellow
  exit 3
}

$branch = (& $script:git rev-parse --abbrev-ref HEAD).Trim()
if ($branch -eq '' -or $branch -eq 'HEAD') { $branch = 'main' }

Write-Host ('[..] 推送到 origin/' + $branch + ' …') -ForegroundColor Cyan
Invoke-Git @('push', '-u', 'origin', $branch)

$url = ((& $script:git remote get-url origin).Trim()) -replace '^git@github\.com:', 'https://github.com/'
$web = $url -replace '\.git$', ''
Write-Host '[ok] 推送完成。' -ForegroundColor Green
if ($web -like 'https://github.com/*') {
  Write-Host ('     仓库：  ' + $web)
  Write-Host ('     流水线：' + $web + '/actions')
}
