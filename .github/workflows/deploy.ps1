<#
.SYNOPSIS
  Publishes the static site to S3 and invalidates CloudFront.

.DESCRIPTION
  Uploads with per-type Content-Type and Cache-Control headers:
    - assets (css/js/svg/pdf) : cached hard for 1 year (change the filename to bust)
    - html / xml / txt        : must-revalidate, so edits appear immediately

  The bucket stays PRIVATE. CloudFront reads it through an Origin Access Control.
  Nothing here makes any object public.

.PREREQUISITES
  - AWS CLI v2 installed and 'aws configure' completed
  - S3 bucket created, Block Public Access ON
  - CloudFront distribution created with OAC pointing at the bucket

.EXAMPLE
  .\deploy.ps1 -Bucket "abhishektyagi-site" -DistributionId "E1234567890ABC"

.EXAMPLE
  .\deploy.ps1 -Bucket "abhishektyagi-site" -DistributionId "E1234567890ABC" -WhatIfOnly
#>
[CmdletBinding()]
param(
  [Parameter(Mandatory = $true)][string]$Bucket,
  [Parameter(Mandatory = $true)][string]$DistributionId,
  [string]$Profile,
  [string]$Region = "eu-central-1",
  [switch]$WhatIfOnly
)

$ErrorActionPreference = 'Stop'
$root = $PSScriptRoot

if (-not (Get-Command aws -ErrorAction SilentlyContinue)) {
  throw "AWS CLI not found. Install AWS CLI v2 and run 'aws configure' first."
}

$common = @("--region", $Region)
if ($Profile) { $common += @("--profile", $Profile) }
if ($WhatIfOnly) { $common += "--dryrun" }

# Anything not deployed to the site.
$excludeAlways = @(
  "--exclude", "*.ps1",
  "--exclude", "aws/*",
  "--exclude", ".git/*",
  "--exclude", "*.md"
)

function Invoke-Sync {
  param([string[]]$Args)
  Write-Host ("aws " + ($Args -join " ")) -ForegroundColor DarkGray
  & aws @Args
  if ($LASTEXITCODE -ne 0) { throw "aws exited with code $LASTEXITCODE" }
}

Write-Host "==> 1/5 immutable assets (css, js, svg)" -ForegroundColor Cyan
Invoke-Sync (@("s3", "sync", $root, "s3://$Bucket") + $common + $excludeAlways + @(
  "--exclude", "*",
  "--include", "assets/css/*.css",
  "--cache-control", "public, max-age=31536000, immutable",
  "--content-type", "text/css; charset=utf-8",
  "--delete"
))

Invoke-Sync (@("s3", "sync", $root, "s3://$Bucket") + $common + $excludeAlways + @(
  "--exclude", "*",
  "--include", "assets/js/*.js",
  "--cache-control", "public, max-age=31536000, immutable",
  "--content-type", "text/javascript; charset=utf-8"
))

Invoke-Sync (@("s3", "sync", $root, "s3://$Bucket") + $common + $excludeAlways + @(
  "--exclude", "*",
  "--include", "assets/img/*.svg",
  "--cache-control", "public, max-age=31536000, immutable",
  "--content-type", "image/svg+xml"
))

Write-Host "==> 2/5 CV pdf" -ForegroundColor Cyan
Invoke-Sync (@("s3", "sync", $root, "s3://$Bucket") + $common + $excludeAlways + @(
  "--exclude", "*",
  "--include", "assets/*.pdf",
  "--cache-control", "public, max-age=86400",
  "--content-type", "application/pdf"
))

Write-Host "==> 3/5 html" -ForegroundColor Cyan
Invoke-Sync (@("s3", "sync", $root, "s3://$Bucket") + $common + $excludeAlways + @(
  "--exclude", "*",
  "--include", "*.html",
  "--cache-control", "public, max-age=0, must-revalidate",
  "--content-type", "text/html; charset=utf-8"
))

Write-Host "==> 4/5 robots + sitemap" -ForegroundColor Cyan
Invoke-Sync (@("s3", "cp", (Join-Path $root "robots.txt"), "s3://$Bucket/robots.txt") + $common + @(
  "--cache-control", "public, max-age=3600",
  "--content-type", "text/plain; charset=utf-8"
))
Invoke-Sync (@("s3", "cp", (Join-Path $root "sitemap.xml"), "s3://$Bucket/sitemap.xml") + $common + @(
  "--cache-control", "public, max-age=3600",
  "--content-type", "application/xml; charset=utf-8"
))

if ($WhatIfOnly) {
  Write-Host "`nDry run finished. Nothing was uploaded and no invalidation was created." -ForegroundColor Yellow
  return
}

Write-Host "==> 5/5 CloudFront invalidation" -ForegroundColor Cyan
$inv = @("cloudfront", "create-invalidation", "--distribution-id", $DistributionId, "--paths", "/*")
if ($Profile) { $inv += @("--profile", $Profile) }
& aws @inv | Out-Null
if ($LASTEXITCODE -ne 0) { throw "Invalidation failed with code $LASTEXITCODE" }

Write-Host "`nDeployed. Allow a minute or two for the invalidation to complete." -ForegroundColor Green
