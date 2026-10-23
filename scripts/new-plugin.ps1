# 用本插件当模板，生成一个新插件目录
# 用法：new-plugin.cmd dsh-my-plugin
[CmdletBinding()]
param([Parameter(Position = 0, Mandatory = $true)][string]$Name, [string]$Target = '')

$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent $PSScriptRoot
if ($Name -notmatch '^[a-z][a-z0-9-]{2,}$') {
  throw ('名字用小写英文 + 连字符，例：dsh-my-plugin，收到：' + $Name)
}
if ([string]::IsNullOrWhiteSpace($Target)) { $Target = Join-Path (Split-Path -Parent $root) $Name }
if (Test-Path $Target) { throw ('目标已存在：' + $Target + '（换个名字或先删掉）') }

$skip = @('.git', 'dist', 'node_modules')
New-Item -ItemType Directory -Path $Target | Out-Null
Get-ChildItem $root -Force | Where-Object { $skip -notcontains $_.Name } |
  Copy-Item -Destination $Target -Recurse -Force

$shortId = $Name -replace '^dsh-', ''
$textFiles = Get-ChildItem $Target -Recurse -File | Where-Object {
  @('.js', '.json', '.yml', '.md', '.ps1', '.cmd', '.txt') -contains $_.Extension
}
foreach ($file in $textFiles) {
  $raw = [IO.File]::ReadAllText($file.FullName)
  $new = $raw.Replace('dsh-demo-plugin', $Name).Replace('id: demo-plugin', ('id: ' + $shortId))
  if ($new -eq $raw) { continue }
  $utf8Bom = ($file.Extension -eq '.ps1')
  [IO.File]::WriteAllText($file.FullName, $new, (New-Object System.Text.UTF8Encoding($utf8Bom)))
}

Write-Host ('[ok] 新插件已生成：' + $Target) -ForegroundColor Green
Write-Host ''
Write-Host '下一步：' -ForegroundColor Cyan
Write-Host ('  1) 改 ' + $Target + '\lib\index.js 的接口和 lib\client.js 的界面')
Write-Host '  2) 在 GitHub 建一个新空仓库'
Write-Host ('  3) 进目录跑 setup.cmd，完成首次配置')
