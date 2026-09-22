<#
.SYNOPSIS
  Replaces the SITE_URL placeholder across the site source with your real domain.

.DESCRIPTION
  Run this ONCE after you have registered your free domain on DNSExit and decided
  whether you will serve the site from the apex (example.com) or from www.

  It rewrites every occurrence of the literal token SITE_URL in the HTML, robots.txt
  and sitemap.xml files. Pass -Revert to put the placeholder back.

.EXAMPLE
  .\set-domain.ps1 -SiteUrl "https://abhishektyagi.dnsexit-domain.com"

.EXAMPLE
  .\set-domain.ps1 -Revert
#>
[CmdletBinding(DefaultParameterSetName = 'Apply')]
param(
  [Parameter(Mandatory = $true, ParameterSetName = 'Apply')]
  [string]$SiteUrl,

  [Parameter(Mandatory = $true, ParameterSetName = 'Revert')]
  [switch]$Revert
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

if ($PSCmdlet.ParameterSetName -eq 'Apply') {
  if ($SiteUrl -notmatch '^https://') {
    throw "SiteUrl must start with https:// (CloudFront will serve HTTPS)."
  }
  $SiteUrl = $SiteUrl.TrimEnd('/')
  $from = 'SITE_URL'
  $to   = $SiteUrl
} else {
  $current = Read-Host "Enter the URL currently baked into the files (e.g. https://example.com)"
  $from = $current.TrimEnd('/')
  $to   = 'SITE_URL'
}

$targets = Get-ChildItem -Path $root -Recurse -Include *.html, robots.txt, sitemap.xml -File |
           Where-Object { $_.FullName -notmatch '\\aws\\' }

$changed = 0
foreach ($f in $targets) {
  $text = Get-Content -LiteralPath $f.FullName -Raw -Encoding UTF8
  if ($text.Contains($from)) {
    $new = $text.Replace($from, $to)
    [System.IO.File]::WriteAllText($f.FullName, $new, (New-Object System.Text.UTF8Encoding($false)))
    Write-Host ("updated  {0}" -f $f.FullName.Substring($root.Length + 1))
    $changed++
  }
}

Write-Host ""
Write-Host ("Done. {0} file(s) updated. Token '{1}' -> '{2}'." -f $changed, $from, $to) -ForegroundColor Green
if ($changed -eq 0) {
  Write-Warning "Nothing matched. Check that the token you supplied is exactly what is in the files."
}
