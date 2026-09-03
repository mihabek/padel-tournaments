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

# Run a native command quietly; PowerShell 5.1 would otherwise turn its stderr into a terminating error.
function Quiet([scriptblock]$sb) {
  $old = $ErrorActionPreference; $ErrorActionPreference = 'Continue'
  try { & $sb 2>&1 | Out-Null } finally { $ErrorActionPreference = $old }
  return $LASTEXITCODE
}

if ((Quiet { & $gh auth status }) -ne 0) { throw 'Not logged in. Run "gh auth login" first, then re-run this script.' }
$owner = (& $gh api user -q .login).Trim()
$branch = (git rev-parse --abbrev-ref HEAD).Trim()

$exists = (Quiet { & $gh repo view "$owner/$RepoName" }) -eq 0

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
$rc = Quiet { & $gh api -X POST "repos/$owner/$RepoName/pages" -f build_type=legacy -f "source[branch]=$branch" -f 'source[path]=/' }
if ($rc -ne 0) {
  $rc = Quiet { & $gh api -X PUT "repos/$owner/$RepoName/pages" -f build_type=legacy -f "source[branch]=$branch" -f 'source[path]=/' }
}
if ($rc -ne 0) { Write-Warning 'Could not enable Pages via API. Enable it in the repository Settings > Pages (branch main, folder /).' }
$url = "https://$owner.github.io/$RepoName/"
Write-Host ''
Write-Host "Site: $url  (first deploy takes a minute or two)"
Write-Host "Repo: https://github.com/$owner/$RepoName"
Write-Host 'The daily refresh workflow needs Actions enabled with write permission (Settings > Actions > General > Workflow permissions: Read and write).'
