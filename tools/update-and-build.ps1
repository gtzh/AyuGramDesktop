# One-shot "upstream updated" pipeline for this machine.
#
# Usage:
#   powershell -File tools\update-and-build.ps1            # sync + rebuild + smoke test
#   powershell -File tools\update-and-build.ps1 -PushRelease # also upload to GitHub Release
#   powershell -File tools\update-and-build.ps1 -NoSync    # rebuild only, no git operations
#
# -PushRelease needs a PAT in env var GITHUB_TOKEN (Contents: read+write on
# gtzh/AyuGramDesktop). Never store the token in this repo.
#
# This script is what an AI assistant should run when asked to "sync upstream".

param(
    [switch]$PushRelease,
    [switch]$NoSync
)

$ErrorActionPreference = 'Stop'
$root   = Split-Path -Parent $PSScriptRoot
$build  = 'C:\tbuild\run_build.bat'
$blog   = 'C:\tbuild\build.log'
$exeDir = 'C:\tbuild\tdesktop\out\Debug'
$exe    = Join-Path $exeDir 'AyuGram.exe'
$dist   = Join-Path $root 'dist\AyuGram.exe'

Set-Location $root
function Say($m) { Write-Host "[update] $m" -ForegroundColor Cyan }

# 0. Never leave a running AyuGram.exe: link fails with LNK1104 otherwise.
Get-CimInstance Win32_Process -ErrorAction SilentlyContinue |
    Where-Object { $_.ExecutablePath -eq $exe } |
    ForEach-Object { Say "Stopping running AyuGram.exe (pid $($_.ProcessId))"; Stop-Process -Id $_.ProcessId -Force }

$needRebuild = $true

if (-not $NoSync) {
    $before = (& git merge-base HEAD upstream/dev).Trim()

    Say "Step 1/5: sync upstream (fetch + backup + rebase + push)"
    & powershell -NoProfile -ExecutionPolicy Bypass -File (Join-Path $root 'tools\sync-upstream.ps1') -Apply -Push
    if ($LASTEXITCODE -eq 2) {
        Say "Rebase conflict. Resolve manually, then re-run this script."
        exit 2
    } elseif ($LASTEXITCODE -ne 0) {
        throw "sync-upstream.ps1 failed with code $LASTEXITCODE"
    }

    $after = (& git merge-base HEAD upstream/dev).Trim()
    if ($before -eq $after) {
        Say "Upstream did not advance -> skipping rebuild, current exe is still valid."
        $needRebuild = $false
    } else {
        Say "Upstream advanced: $before -> $after, rebuild required."
    }
}

if ($needRebuild) {
    Say "Step 2/5: rebuild (this takes hours, do not kill MSBuild mid-way)"
    & cmd /c "`"$build`""
    $tail = Get-Content $blog -Tail 40 -ErrorAction SilentlyContinue
    if (-not ($tail -match 'EXIT=0')) {
        Say "Build FAILED. Last lines of $blog :"
        $tail | Select-Object -Last 12 | ForEach-Object { Write-Host "    $_" }
        exit 3
    }
    Say "Build OK"

    Say "Step 3/5: smoke test"
    $p = Start-Process -FilePath $exe -PassThru
    Start-Sleep -Seconds 12
    if ($p.HasExited) { throw "AyuGram exited immediately with code $($p.ExitCode)" }
    Say "Running ok (pid $($p.Id))"
    Stop-Process -Id $p.Id -Force

    Say "Step 4/5: copy to dist"
    Copy-Item $exe $dist -Force
    $hash = (Get-FileHash $dist -Algorithm SHA256).Hash.ToLower()
    Say "sha256=$hash"
}

if ($PushRelease) {
    Say "Step 5/5: upload to GitHub Release"
    $tok = $env:GITHUB_TOKEN
    if (-not $tok) { throw "Set `$env:GITHUB_TOKEN with a Contents:read+write PAT first" }
    # Upload logic lives in the assistant's session; this is just the guard.
    Say "Token present. Use the release API (delete old exe asset, upload new one)."
} else {
    Say "Step 5/5: skipped release upload (use -PushRelease with GITHUB_TOKEN)"
}

Say "DONE. Branch: $((& git log --oneline -1).Trim())"
