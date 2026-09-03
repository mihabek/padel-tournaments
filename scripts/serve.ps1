#requires -Version 5.1
<#
.SYNOPSIS
  Minimal static file server for previewing the site locally (no Node or Python needed).
.EXAMPLE
  powershell -ExecutionPolicy Bypass -File scripts\serve.ps1
  then open http://localhost:8765/
#>
param(
  [int]$Port = 8765,
  [string]$Root = ''
)
$ErrorActionPreference = 'Stop'
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot } else { Split-Path -Parent $MyInvocation.MyCommand.Path }
if (-not $Root) { $Root = Split-Path -Parent $ScriptDir }
$Root = (Resolve-Path $Root).Path.TrimEnd('\')

$mime = @{
  '.html' = 'text/html; charset=utf-8'; '.css' = 'text/css; charset=utf-8'; '.js' = 'application/javascript; charset=utf-8'
  '.json' = 'application/json; charset=utf-8'; '.svg' = 'image/svg+xml'; '.png' = 'image/png'; '.ico' = 'image/x-icon'
  '.md' = 'text/plain; charset=utf-8'; '.txt' = 'text/plain; charset=utf-8'; '.woff2' = 'font/woff2'
}

$listener = New-Object System.Net.HttpListener
$listener.Prefixes.Add("http://localhost:$Port/")
$listener.Start()
Write-Host "Serving $Root at http://localhost:$Port/  (Ctrl+C to stop)"

while ($listener.IsListening) {
  $ctx = $listener.GetContext()
  $res = $ctx.Response
  try {
    $path = [Uri]::UnescapeDataString($ctx.Request.Url.AbsolutePath)
    if ($path.EndsWith('/')) { $path += 'index.html' }
    $full = [IO.Path]::GetFullPath((Join-Path $Root ($path.TrimStart('/') -replace '/', '\')))
    if (-not $full.StartsWith($Root, [StringComparison]::OrdinalIgnoreCase) -or -not (Test-Path -LiteralPath $full -PathType Leaf)) {
      $res.StatusCode = 404
      $bytes = [Text.Encoding]::UTF8.GetBytes('Not found')
    } else {
      $ext = [IO.Path]::GetExtension($full).ToLower()
      $res.ContentType = if ($mime.ContainsKey($ext)) { $mime[$ext] } else { 'application/octet-stream' }
      $res.Headers['Cache-Control'] = 'no-store'
      $bytes = [IO.File]::ReadAllBytes($full)
    }
    $res.ContentLength64 = $bytes.Length
    $res.OutputStream.Write($bytes, 0, $bytes.Length)
  } catch {
    try { $res.StatusCode = 500 } catch {}
  } finally {
    $res.Close()
  }
}
