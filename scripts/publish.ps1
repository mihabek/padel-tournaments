#requires -Version 5.1
<#
.SYNOPSIS
  One-time publish to GitHub Pages using the GitHub CLI (gh).
  Creates a public repository, pushes the current branch and enables Pages from the main branch root.
.EXAMPLE
  gh auth login            # once, in your own terminal
  powershell -ExecutionPolicy Bypass -File scripts\publish.ps1
#>
param(
  [string]$RepoName = 'padel-tournaments',
  [switch]$Private
)
$ErrorActionPreference = 'Stop'
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
$Root = Split-Path -Parent $ScriptDir
Set-Location $Root

$gh = Get-Command gh -ErrorAction SilentlyContinue
if (-not $gh) { $candidate = 'C:\Program Files\GitHub CLI\gh.exe'; if (Test-Path $candidate) { $gh = $candidate } else { throw 'GitHub CLI (gh) not found. Install it with: winget install GitHub.cli' } } else { $gh = $gh.Source }

& $gh auth status 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) { throw 'Not logged in. Run "gh auth login" first, then re-run this script.' }
$owner = (& $gh api user -q .login).Trim()
$branch = (git rev-parse --abbrev-ref HEAD).Trim()

$exists = $false
& $gh repo view "$owner/$RepoName" 2>&1 | Out-Null
if ($LASTEXITCODE -eq 0) { $exists = $true }

if (-not $exists) {
  $vis = if ($Private) { '--private' } else { '--public' }
  Write-Host "Creating $owner/$RepoName ($vis) and pushing $branch..."
  & $gh repo create $RepoName $vis --source . --remote origin --push --description 'Upcoming official padel tournaments in Estonia, Latvia, Finland and FIP Bronze worldwide'
  if ($LASTEXITCODE -ne 0) { throw 'gh repo create failed' }
} else {
  if (-not (git remote | Select-String -Quiet '^origin$')) { git remote add origin "https://github.com/$owner/$RepoName.git" }
  Write-Host "Pushing $branch to $owner/$RepoName..."
  git push -u origin $branch
  if ($LASTEXITCODE -ne 0) { throw 'git push failed' }
}

Write-Host 'Enabling GitHub Pages (branch root)...'
& $gh api -X POST "repos/$owner/$RepoName/pages" -f build_type=legacy -f "source[branch]=$branch" -f 'source[path]=/' 2>&1 | Out-Null
if ($LASTEXITCODE -ne 0) {
  & $gh api -X PUT "repos/$owner/$RepoName/pages" -f build_type=legacy -f "source[branch]=$branch" -f 'source[path]=/' 2>&1 | Out-Null
}
$url = "https://$owner.github.io/$RepoName/"
Write-Host ''
Write-Host "Site: $url  (first deploy takes a minute or two)"
Write-Host "Repo: https://github.com/$owner/$RepoName"
Write-Host 'The daily refresh workflow needs Actions enabled with write permission (Settings > Actions > General > Workflow permissions: Read and write).'
