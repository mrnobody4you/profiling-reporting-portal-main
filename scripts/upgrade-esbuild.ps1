Param(
    [string]$Version = '0.28.1',
    [switch]$DeleteLockfileIfStubborn
)

$ErrorActionPreference = 'Stop'

$timestamp = (Get-Date -Format "yyyyMMddHHmmss")
if (Test-Path pnpm-lock.yaml) {
    Copy-Item pnpm-lock.yaml "pnpm-lock.yaml.bak.$timestamp"
}

Write-Host "Checking pnpm/node versions..."
pnpm -v
node -v

Write-Host "Listing current esbuild packages (may show transitive resolutions)..."
try {
    pnpm ls esbuild
} catch {
    Write-Host "pnpm ls esbuild failed"
}
try {
    pnpm ls @esbuild/win32-x64
} catch {
    Write-Host "pnpm ls @esbuild/win32-x64 failed"
}

Write-Host "Removing all node_modules folders in workspace..."
Get-ChildItem -Directory -Recurse -Filter node_modules -ErrorAction SilentlyContinue | ForEach-Object {
    Write-Host "Removing: $($_.FullName)"
    Remove-Item $_.FullName -Recurse -Force -ErrorAction SilentlyContinue
}

if (Test-Path node_modules) {
    Remove-Item -Recurse -Force node_modules -ErrorAction SilentlyContinue
}

Write-Host "Pruning pnpm store to remove unused packages..."
pnpm store prune

Write-Host "Updating esbuild to $Version across workspaces (recursive)..."
# Preferred: update workspace package.json resolutions and lockfile
pnpm up -r "esbuild@$Version" --latest

Write-Host "Installing with updated lockfile..."
pnpm install

Write-Host "Verifying installed versions..."
pnpm ls esbuild
pnpm ls @esbuild/win32-x64

if (Test-Path .\node_modules\esbuild\package.json) {
    try {
        $v = (Get-Content .\node_modules\esbuild\package.json | ConvertFrom-Json).version
        Write-Host "Top-level node_modules/esbuild reports version $v"
    } catch {
        Write-Host "Could not read node_modules/esbuild/package.json"
    }
} else {
    Write-Host "No top-level esbuild package.json found; rely on pnpm ls output."
}

# Detect lingering 0.27.x occurrences
$lsOutput = pnpm ls esbuild --depth 4 | Out-String
if ($lsOutput -match "0\.27\.") {
    Write-Host "\nDetected esbuild@0.27.x still present in dependency graph."
    Write-Host "Run with -DeleteLockfileIfStubborn to remove pnpm-lock.yaml and reinstall as a fallback."
    if ($DeleteLockfileIfStubborn.IsPresent) {
        Write-Host "Removing pnpm-lock.yaml (backup already created) and reinstalling..."
        Remove-Item -Force pnpm-lock.yaml -ErrorAction SilentlyContinue
        pnpm install
        Write-Host "Post-fallback verification..."
        pnpm ls esbuild
        pnpm ls @esbuild/win32-x64
    }
} else {
    Write-Host "No 0.27.x matches found in pnpm ls output."
}

Write-Host "Done. If you still see mismatches, run: pnpm why esbuild to find dependents."
