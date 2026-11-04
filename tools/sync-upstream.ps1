# Sync this fork with upstream AyuGramDesktop while keeping the two local
# features on branch feat/hide-video-controls.
#
# Usage:
#   powershell -File tools\sync-upstream.ps1              # dry run: fetch + show diff
#   powershell -File tools\sync-upstream.ps1 -Apply       # fetch + backup + rebase
#   powershell -File tools\sync-upstream.ps1 -Apply -Push # also push to your fork
#
# Requirements: git remote "upstream" (official repo), "mine" (your fork).
# PowerShell 5.1 compatible.

param(
    [switch]$Apply,
    [switch]$Push,
    [string]$Upstream = 'upstream',
    [string]$Fork     = 'mine',
    [string]$Base     = 'dev',
    [string]$Branch   = 'feat/hide-video-controls'
)

$ErrorActionPreference = 'Stop'
$repo = Split-Path -Parent $PSScriptRoot
Set-Location $repo

function Say($m) { Write-Host "[sync] $m" -ForegroundColor Cyan }

# 1. Working tree must be clean (untracked build artifacts are fine).
$dirty = & git status --porcelain --untracked-files=no
if ($dirty) {
    throw "Working tree has staged/modified files. Commit or stash them first:`n$dirty"
}

# 2. Always fetch upstream. A shallow clone must be unshallowed once, otherwise
#    rebase/merge bases are missing and the sync will silently do the wrong thing.
Say "Fetching $Upstream ..."
if ((& git rev-parse --is-shallow-repository) -eq 'true') {
    Say "Shallow clone detected -> fetching full history (one time, may take a while)"
    & git fetch --unshallow $Upstream --tags
    if ($LASTEXITCODE -ne 0) { throw "git fetch --unshallow failed" }
} else {
    & git fetch $Upstream --tags
    if ($LASTEXITCODE -ne 0) { throw "git fetch failed" }
}

$target = "$Upstream/$Base"
$behind = @(& git log --oneline "HEAD..$target")
$ahead  = @(& git log --oneline "$target..HEAD")
Say "Behind upstream: $($behind.Count) commits"
Say "Your commits on top: $($ahead.Count) commit(s):"
$ahead | ForEach-Object { Write-Host "    $_" }

if ($behind.Count -eq 0) {
    Say "Already up to date, nothing to do."
    exit 0
}
if (-not $Apply) {
    Say "Dry run only. Re-run with -Apply to rebase (and optionally -Push)."
    Write-Host ""
    Write-Host "New upstream commits:" -ForegroundColor Yellow
    $behind | Select-Object -First 20 | ForEach-Object { Write-Host "    $_" }
    exit 0
}

# 3. Safety backup of the current feature branch before rewriting history.
$stamp = Get-Date -Format 'yyyyMMdd-HHmm'
$backup = "backup/$Branch-$stamp"
Say "Creating backup branch $backup"
& git branch -f $backup HEAD
if ($LASTEXITCODE -ne 0) { throw "backup branch failed" }

# 4. Rebase keeps the two feature commits as clean patches on top of upstream.
#    rerere.enabled=true (set once for this repo) remembers conflict resolutions.
Say "Rebasing $Branch onto $target ..."
& git checkout $Branch
if ($LASTEXITCODE -ne 0) { throw "checkout failed" }
& git rebase $target
if ($LASTEXITCODE -ne 0) {
    Write-Host ""
    Write-Host "[sync] CONFLICT. Resolve it, then:" -ForegroundColor Red
    Write-Host "    git add <files>"
    Write-Host "    git rebase --continue"
    Write-Host "    powershell -File tools\sync-upstream.ps1 -Apply -Push"
    Write-Host ""
    Write-Host "If it goes wrong: git rebase --abort ; git reset --hard $backup" -ForegroundColor Red
    exit 2
}

Say "Rebase OK. Current history:"
& git log --oneline --decorate -6

# 5. Also fast-forward your fork's default branch to upstream (optional, nice).
Say "Updating $Fork/$Base ..."
& git push $Fork "$target`:refs/heads/$Base"
if ($LASTEXITCODE -ne 0) { Write-Host "[sync] (non-critical) could not update fork's dev" -ForegroundColor Yellow }

if ($Push) {
    # --force-with-lease is required because rebase rewrote the 2 commits.
    Say "Pushing rebased feature branch (force-with-lease) ..."
    & git push --force-with-lease $Fork "$Branch`:$Branch"
    if ($LASTEXITCODE -ne 0) { throw "push failed" }
    Say "Pushed. https://github.com/gtzh/AyuGramDesktop/tree/$Branch"
} else {
    Say "Not pushed. Review, rebuild, then run with -Push."
}

Say "DONE. Remember to rebuild: C:\tbuild\run_build.bat"
