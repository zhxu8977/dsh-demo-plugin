# 一条龙连上 GitHub：校验 token → 自动建仓库 → 配远程 → 首次提交 → 推送
# 用法：connect.cmd            （推荐，会提示你粘贴 token）
#       connect.cmd -Token xxx （不推荐：token 会留在命令历史里）
[CmdletBinding()]
param([string]$Token = '', [string]$RepoName = 'dsh-demo-plugin', [switch]$DryRun)

$ErrorActionPreference = 'Stop'
if ($null -ne (Get-Variable -Name PSNativeCommandUseErrorActionPreference -ErrorAction SilentlyContinue)) {
  $PSNativeCommandUseErrorActionPreference = $false
}
try { [Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 } catch { }
$root = Split-Path -Parent $PSScriptRoot
Set-Location $root

# 出错时只给人话，不甩一堆红字堆栈
trap {
  Write-Host ''
  Write-Host ('[x] 出错了：' + $_.Exception.Message) -ForegroundColor Red
  Write-Host '    改好后重新双击 connect.cmd 即可（重复跑是安全的）。' -ForegroundColor DarkGray
  exit 1
}

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
function Read-TokenFromPrompt {
  Write-Host '把 token 粘到这里，然后按回车。' -ForegroundColor Yellow
  Write-Host '（屏幕不会显示任何字符，这是正常的；粘贴用右键或 Ctrl+V）' -ForegroundColor DarkGray
  $secure = Read-Host -Prompt ' token' -AsSecureString
  $bstr = [Runtime.InteropServices.Marshal]::SecureStringToBSTR($secure)
  try { return ([Runtime.InteropServices.Marshal]::PtrToStringBSTR($bstr)).Trim() }
  finally { [Runtime.InteropServices.Marshal]::ZeroFreeBSTR($bstr) }
}
function Get-StoredCredential {
  # 从 Windows 凭据管理器读 git 的 github.com 凭据；读不到就返回 $null（绝不弹窗）
  $nl = [char]10
  $query = 'protocol=https' + $nl + 'host=github.com' + $nl + $nl
  $prevEap = $ErrorActionPreference
  $prevPrompt = $env:GIT_TERMINAL_PROMPT
  $ErrorActionPreference = 'Continue'
  $env:GIT_TERMINAL_PROMPT = '0'
  try {
    $raw = ($query | & $script:git credential fill 2>&1 | Out-String)
  } catch {
    $raw = ''
  } finally {
    $ErrorActionPreference = $prevEap
    $env:GIT_TERMINAL_PROMPT = $prevPrompt
  }
  $password = ($raw -split "\r?\n" | Where-Object { $_ -like 'password=*' } | Select-Object -First 1) -replace '^password=', ''
  $username = ($raw -split "\r?\n" | Where-Object { $_ -like 'username=*' } | Select-Object -First 1) -replace '^username=', ''
  if ([string]::IsNullOrWhiteSpace($password)) { return $null }
  return @{ username = $username; token = $password }
}
$script:git = Get-GitPath

Write-Host ''
Write-Host '=== 连上 GitHub（全自动）===' -ForegroundColor Cyan
Write-Host ''

# ---------- 1. 取凭据：优先用本机已保存的 GitHub 登录 ----------
$fromStore = $false
if ([string]::IsNullOrWhiteSpace($Token)) {
  $stored = Get-StoredCredential
  if ($null -ne $stored) {
    $Token = $stored.token
    $fromStore = $true
    Write-Host ('[ok] 发现本机已保存的 GitHub 登录：' + $stored.username + '（这次不用你输 token）') -ForegroundColor Green
  }
}
if ([string]::IsNullOrWhiteSpace($Token)) {
  Write-Host '本机还没有保存过 GitHub 登录，需要你生成一个 token（只需要一次）。' -ForegroundColor Yellow
  $Token = Read-TokenFromPrompt
}
$Token = $Token.Trim()
if ($Token -eq '') { throw '没有拿到 token，退出。' }
$knownPrefixes = @('ghp_', 'gho_', 'ghu_', 'ghs_', 'github_pat_')
$looksLikeToken = $false
foreach ($prefix in $knownPrefixes) {
  if ($Token.StartsWith($prefix)) { $looksLikeToken = $true }
}
if (-not $looksLikeToken) {
  Write-Host '[!] 这串不像 GitHub token（正常以 ghp_ 开头）。继续试一下…' -ForegroundColor Yellow
}

$headers = @{
  Authorization = 'token ' + $Token
  Accept        = 'application/vnd.github+json'
  'User-Agent'  = 'dsh-demo-plugin-connect'
}

# ---------- 2. 校验登录，取用户名和权限范围 ----------
Write-Host '[..] 正在验证 GitHub 登录 …'
$me = $null
while ($null -eq $me) {
  try {
    $me = Invoke-WebRequest -Uri 'https://api.github.com/user' -Headers $headers -UseBasicParsing -TimeoutSec 30
  } catch {
    $status = $null
    try { $status = $_.Exception.Response.StatusCode.value__ } catch { }
    if ($status -eq 401 -and $fromStore) {
      Write-Host '[!] 本机保存的登录已失效（可能过期或被撤销）。' -ForegroundColor Yellow
      $Token = Read-TokenFromPrompt
      if ([string]::IsNullOrWhiteSpace($Token)) { throw '没有拿到 token，退出。' }
      $fromStore = $false
      $headers.Authorization = 'token ' + $Token
      continue
    }
    if ($status -eq 401) { throw 'token 无效或已过期。请重新生成一个再试。' }
    throw ('连不上 GitHub（' + $_.Exception.Message + '）。可能是网络问题，或者代理没开。')
  }
}
$user = $me.Content | ConvertFrom-Json
$scopes = [string]$me.Headers['X-OAuth-Scopes']
$login = $user.login
Write-Host ('[ok] 已登录：' + $login) -ForegroundColor Green
Write-Host ('     token 权限：' + $(if ([string]::IsNullOrWhiteSpace($scopes)) { '(fine-grained，按仓库授权)' } else { $scopes })) -ForegroundColor DarkGray

$hasRepoScope = ($scopes -match 'repo')
$hasWorkflowScope = ($scopes -match 'workflow')
if (-not $hasRepoScope -and -not [string]::IsNullOrWhiteSpace($scopes)) {
  throw '这个 token 没有 repo 权限，推不了代码。请重新生成并勾上 repo。'
}
if (-not $hasWorkflowScope) {
  Write-Host '[!] token 缺少 workflow 权限：能推代码，但推不上 .github/workflows（流水线跑不起来）。' -ForegroundColor Yellow
  Write-Host '    建议重新生成一个，把 workflow 也勾上。' -ForegroundColor Yellow
}

$email = ('{0}+{1}@users.noreply.github.com' -f $user.id, $login)
Write-Host ('     提交署名：' + $login + ' <' + $email + '>') -ForegroundColor DarkGray

# ---------- 3. 建仓库（已存在就直接用）----------
$repoUrl = 'https://github.com/' + $login + '/' + $RepoName
$remoteUrl = $repoUrl + '.git'
$created = $false
Write-Host ('[..] 检查仓库 ' + $login + '/' + $RepoName + ' …')
$existing = $null
try {
  $existing = Invoke-RestMethod -Uri ('https://api.github.com/repos/' + $login + '/' + $RepoName) -Headers $headers -TimeoutSec 30
} catch { }

if ($DryRun) {
  Write-Host ''
  Write-Host '--- DryRun：只验证，不建仓库、不推送 ---' -ForegroundColor Yellow
  if ($null -ne $existing) {
    Write-Host ('  仓库状态 -> 已存在，会直接复用：' + $existing.html_url)
  } else {
    Write-Host '  仓库状态 -> 还不存在，正式跑时会自动创建'
  }
  Write-Host ('  远端地址 -> ' + $remoteUrl)
  Write-Host ('  提交署名 -> ' + $login + ' <' + $email + '>')
  Write-Host '  推送动作 -> git push -u origin main'
  exit 0
}

if ($null -ne $existing) {
  Write-Host ('[ok] 仓库已存在，直接用它：' + $existing.html_url) -ForegroundColor Green
} else {
  $body = @{
    name        = $RepoName
    description = 'DeepSeek Harness 插件：侧边栏按钮 + 宿主接口 + CI/CD 流水线'
    private     = $false
    auto_init   = $false
  } | ConvertTo-Json
  $created = Invoke-RestMethod -Uri 'https://api.github.com/user/repos' -Headers $headers -Method Post -Body $body -ContentType 'application/json' -TimeoutSec 30
  Write-Host ('[ok] 仓库已创建：' + $created.html_url) -ForegroundColor Green
}

# ---------- 4. 本地 git 配置 ----------
if (-not (Test-Path (Join-Path $root '.git'))) {
  Write-Host '[..] 初始化本地仓库'
  Invoke-Git @('init', '-q', '-b', 'main')
}
Invoke-Git @('config', 'user.name', $login)
Invoke-Git @('config', 'user.email', $email)
Invoke-Git @('config', 'core.quotepath', 'false')
Invoke-Git @('config', 'core.autocrlf', 'false')

$remotes = @(& $script:git remote)
if ($remotes -contains 'origin') {
  Invoke-Git @('remote', 'set-url', 'origin', $remoteUrl)
} else {
  Invoke-Git @('remote', 'add', 'origin', $remoteUrl)
}
Write-Host ('[ok] 远程地址：' + $remoteUrl) -ForegroundColor Green

# ---------- 5. 首次提交 ----------
& $script:git rev-parse --verify --quiet HEAD | Out-Null
if ($LASTEXITCODE -ne 0) {
  Invoke-Git @('add', '-A')
  Invoke-Git @('commit', '-m', '初始化：插件骨架与 CI/CD 流水线')
  Write-Host '[ok] 已创建第一次提交' -ForegroundColor Green
}
& $script:git branch -M main | Out-Null

# ---------- 6. 保存凭据（已保存过就跳过）----------
if (-not $fromStore) {
  $helper = ((& $script:git config --get credential.helper) | Out-String).Trim()
  if ([string]::IsNullOrWhiteSpace($helper)) { & $script:git config --global credential.helper wincred }
  $cred = ('protocol=https{0}host=github.com{0}username={1}{0}password={2}{0}{0}' -f [Environment]::NewLine, $login, $Token)
  $cred | & $script:git credential approve
  Write-Host '[ok] 凭据已保存（以后 push 不再问密码）' -ForegroundColor Green
} else {
  Write-Host '[ok] 沿用本机已保存的登录，不新增任何凭据' -ForegroundColor DarkGray
}

# ---------- 7. 推送 ----------
Write-Host '[..] 推送到 GitHub …' -ForegroundColor Cyan
Invoke-Git @('push', '-u', 'origin', 'main')

Write-Host ''
Write-Host '[ok] 全部完成！' -ForegroundColor Green
Write-Host ('     仓库：  ' + $repoUrl)
Write-Host ('     流水线：' + $repoUrl + '/actions')
Write-Host ''
Write-Host '以后改完代码，双击 push.cmd 就行。' -ForegroundColor Cyan
Write-Host '想发版：release.cmd 0.2.0' -ForegroundColor Cyan
