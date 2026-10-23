# 首次配置：把本目录变成 git 仓库，并连上你的 GitHub 空仓库
# 用法：setup.cmd
#       setup.cmd -User zhangsan -Email me@example.com -RepoUrl https://github.com/zhangsan/dsh-demo-plugin.git
[CmdletBinding()]
param([string]$User, [string]$Email, [string]$RepoUrl)

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
  & $script:git @GitArgs | Out-Null
  return ($LASTEXITCODE -eq 0)
}

$script:git = Get-GitPath

Write-Host '=== dsh-demo-plugin 首次配置 ===' -ForegroundColor Cyan

if (-not (Test-Path (Join-Path $root '.git'))) {
  Write-Host '[..] 初始化 git 仓库（分支 main）'
  & $script:git init -q -b main
  if ($LASTEXITCODE -ne 0) { throw 'git init 失败：本机 git 版本可能太旧，请手动执行 git init -b main' }
  Write-Host '[ok] 仓库已初始化' -ForegroundColor Green
}

if ([string]::IsNullOrWhiteSpace($User)) {
  $User = (Read-Host 'GitHub 用户名（英文，例：zhangsan）').Trim()
}
if ([string]::IsNullOrWhiteSpace($Email)) {
  $Email = (Read-Host 'GitHub 邮箱（登录 GitHub 那个）').Trim()
}
if ([string]::IsNullOrWhiteSpace($RepoUrl)) {
  $RepoUrl = (Read-Host '仓库地址（例：https://github.com/zhangsan/dsh-demo-plugin.git）').Trim()
}

Invoke-Git @('config', 'user.name', $User)
Invoke-Git @('config', 'user.email', $Email)
Invoke-Git @('config', 'core.quotepath', 'false')
Invoke-Git @('config', 'core.autocrlf', 'false')

# 首次 push 免密：优先用 Git Credential Manager；没有的话第一次会问一次 token
& $script:git config credential.helper manager
if ($LASTEXITCODE -ne 0) {
  Write-Host '（提示）本机没装 Git Credential Manager：第一次 push 会问你密码，' -ForegroundColor DarkGray
  Write-Host '        密码处粘贴 Personal Access Token（不是登录密码）。' -ForegroundColor DarkGray
}

$remotes = @(& $script:git remote)
if ($remotes -contains 'origin') {
  Invoke-Git @('remote', 'set-url', 'origin', $RepoUrl)
} else {
  Invoke-Git @('remote', 'add', 'origin', $RepoUrl)
}
Write-Host ('[ok] 远程仓库：' + $RepoUrl) -ForegroundColor Green

if (-not (Test-Git @('rev-parse', '--verify', '--quiet', 'HEAD'))) {
  Invoke-Git @('add', '-A')
  Invoke-Git @('commit', '-m', '初始化：插件骨架与 CI/CD 流水线')
  Write-Host '[ok] 已创建第一次提交' -ForegroundColor Green
}

& $script:git branch -M main

Write-Host ''
Write-Host '配置完成。下一步：双击 push.cmd 把代码推上去。' -ForegroundColor Cyan
Write-Host '（第一次推送如果要密码，粘贴 GitHub 的 Personal Access Token）' -ForegroundColor DarkGray
