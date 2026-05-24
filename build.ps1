#!/usr/bin/env pwsh
# Build IsoOS on a Windows host via Docker Desktop.
# The actual build (debootstrap, mksquashfs, xorriso, ...) runs inside a
# privileged Ubuntu 24.04 container; only the final ISO lands back on Windows.

$ErrorActionPreference = 'Stop'

if (-not (Get-Command docker -ErrorAction SilentlyContinue)) {
    throw 'Docker Desktop is required. Install it from https://www.docker.com/products/docker-desktop and enable the WSL2 backend.'
}

try { docker info *> $null } catch {
    throw 'Docker daemon is not running. Start Docker Desktop and retry.'
}

$Root  = $PSScriptRoot
$Image = 'isoos-builder:latest'

Write-Host '[build.ps1] building builder image' -ForegroundColor Cyan
docker build -t $Image $Root
if ($LASTEXITCODE -ne 0) { throw 'docker build failed' }

New-Item -ItemType Directory -Force -Path (Join-Path $Root 'out') | Out-Null

# Bind-mount the repo so the container sees build.sh / branding / boot, and
# the final ISO lands in .\out on the Windows host. The chroot scratch
# (work/) goes into a named Docker volume so debootstrap can create device
# nodes and preserve Unix permissions — NTFS bind mounts can't.
Write-Host '[build.ps1] running build container (privileged)' -ForegroundColor Cyan
docker run --rm --privileged `
    -v "${Root}:/iso" `
    -v 'isoos-work:/iso/work' `
    -e WORK_DIR=/iso/work `
    $Image
if ($LASTEXITCODE -ne 0) { throw 'build container exited non-zero' }

Write-Host '[build.ps1] done. ISO is in .\out' -ForegroundColor Green
Get-ChildItem (Join-Path $Root 'out')
