# 把本插件装进 DeepSeek Harness 的 desktop profile（软链接方式，改代码即时生效，重启应用后加载）
# 用法：install.cmd           安装
#       install.cmd -Uninstall 卸载
#       install.cmd -DryRun    只看会改什么，不动文件
[CmdletBinding()]
param([switch]$Uninstall, [switch]$DryRun, [string]$ProfileDir = '')

$ErrorActionPreference = 'Stop'
$root = $PSCommandPath | Split-Path -Parent
Set-Location $root

if ([string]::IsNullOrWhiteSpace($ProfileDir)) {
  $dshHome = $env:DSH_HOME
  if ([string]::IsNullOrWhiteSpace($dshHome)) { $dshHome = Join-Path $env:USERPROFILE '.dsh' }
  $ProfileDir = Join-Path $dshHome 'profiles\desktop'
}
$pkgPath = Join-Path $ProfileDir 'package.json'
if (-not (Test-Path $pkgPath)) { throw ('找不到 profile 配置：' + $pkgPath) }

$name = (Get-Content (Join-Path $root 'package.json') -Raw -Encoding UTF8 | ConvertFrom-Json).name
$linkPath = Join-Path $ProfileDir ('node_modules\' + $name)
$linkTarget = $root.Replace('\', '/')

$pkg = Get-Content $pkgPath -Raw -Encoding UTF8 | ConvertFrom-Json
if ($null -eq $pkg.dependencies) { $pkg | Add-Member -NotePropertyName dependencies -NotePropertyValue ([pscustomobject]@{}) }
if ($null -eq $pkg.dsh) { $pkg | Add-Member -NotePropertyName dsh -NotePropertyValue ([pscustomobject]@{ profile = [pscustomobject]@{ bundles = @() } }) }

if ($Uninstall) {
  if ($pkg.dependencies.PSObject.Properties.Name -contains $name) {
    $pkg.dependencies.PSObject.Properties.Remove($name)
  }
  $pkg.dsh.profile.bundles = @($pkg.dsh.profile.bundles | Where-Object { $_ -ne $name })
  Write-Host ('[..] 从 profile 移除：' + $name) -ForegroundColor Cyan
} else {
  if ($pkg.dependencies.PSObject.Properties.Name -contains $name) {
    $pkg.dependencies.$name = 'link:' + $linkTarget
  } else {
    $pkg.dependencies | Add-Member -NotePropertyName $name -NotePropertyValue ('link:' + $linkTarget)
  }
  if (@($pkg.dsh.profile.bundles) -notcontains $name) {
    $pkg.dsh.profile.bundles = @($pkg.dsh.profile.bundles) + $name
  }
  Write-Host ('[..] 写入 profile 依赖与 bundles：' + $name) -ForegroundColor Cyan
}

$json = ($pkg | ConvertTo-Json -Depth 32) + "`n"

if ($DryRun) {
  Write-Host '--- DryRun：下面是改完后的 profile/package.json 片段 ---' -ForegroundColor Yellow
  Write-Host ('link: ' + $linkPath + '  ->  ' + $root)
  Write-Host ('dependencies.' + $name + ' = link:' + $linkTarget)
  Write-Host '--- 没有写入任何文件 ---' -ForegroundColor Yellow
  exit 0
}

$stamp = Get-Date -Format 'yyyyMMdd-HHmmss'
$backup = $pkgPath + '.bak-' + $stamp
$serial = 1
while (Test-Path $backup) { $backup = $pkgPath + '.bak-' + $stamp + '-' + $serial; $serial++ }
Copy-Item $pkgPath $backup -Force
Write-Host ('[ok] 已备份：' + $backup) -ForegroundColor DarkGray
[IO.File]::WriteAllText($pkgPath, $json, (New-Object System.Text.UTF8Encoding($false)))

if (Test-Path $linkPath) { [IO.Directory]::Delete($linkPath) }
if (-not $Uninstall) {
  New-Item -ItemType Junction -Path $linkPath -Target $root | Out-Null
  Write-Host ('[ok] 已建立软链接：' + $linkPath) -ForegroundColor Green
} else {
  Write-Host '[ok] 软链接已删除' -ForegroundColor Green
}

Write-Host ''
Write-Host '完成。重启 DeepSeek Harness 后生效。' -ForegroundColor Cyan
