<#
.SYNOPSIS
    Harness 前置檢查 + 安裝 pre-commit hook。

.DESCRIPTION
    舊系統的開發環境多半沒辦法「一鍵回到可開發狀態」（要 VS、內網、資料庫連線）。
    所以這支腳本不假裝能幫你裝環境——它做兩件務實的事：
      1. 檢查 harness 檔案齊不齊，缺什麼直接講
      2. 把 check.ps1 掛進 pre-commit

    pre-commit 是加分，不是地板：同事沒跑這支腳本就沒有這層。
    真正的關卡在 feature → beta 的 PR。
#>
[CmdletBinding()]
param([switch]$SkipHook)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

$RepoRoot = (& git rev-parse --show-toplevel 2>$null)
if (-not $RepoRoot) { Write-Host 'FATAL: 不在 git repo 內'; exit 1 }

$required = @(
    'AGENTS.md',
    '.harness/feature_list.json',
    '.harness/check.ps1',
    '.harness/session-handoff.md',
    'docs/ARCHITECTURE.md'
)

Write-Host ''
Write-Host 'Harness 前置檢查'
Write-Host ('-' * 60)

$missing = @()
foreach ($f in $required) {
    $path = Join-Path $RepoRoot $f
    if (Test-Path $path) {
        Write-Host "[ok]   $f"
    } else {
        Write-Host "[MISS] $f"
        $missing += $f
    }
}

foreach ($d in @('docs/system-notes', 'docs/evidence')) {
    $path = Join-Path $RepoRoot $d
    if (-not (Test-Path $path)) {
        New-Item -ItemType Directory -Path $path -Force | Out-Null
        Write-Host "[new]  $d/（已建立）"
    }
}

$gitignore = Join-Path $RepoRoot '.gitignore'
$ignoreLine = '.harness/last-check.md'
if (-not (Test-Path $gitignore) -or ((Get-Content $gitignore -Raw) -notmatch [regex]::Escape($ignoreLine))) {
    Add-Content -Path $gitignore -Value "`n$ignoreLine"
    Write-Host "[new]  .gitignore 追加 $ignoreLine"
}

if ($missing.Count -gt 0) {
    Write-Host ('-' * 60)
    Write-Host "缺少 $($missing.Count) 個檔案，請照 SETUP.md 補齊後再跑一次。"
    exit 1
}

if (-not $SkipHook) {
    $hookPath = Join-Path $RepoRoot '.git/hooks/pre-commit'
    $hook = @(
        '#!/bin/sh',
        '# installed by project-harness-kit init.ps1',
        'exec powershell.exe -NoProfile -ExecutionPolicy Bypass -File .harness/check.ps1'
    ) -join "`n"
    Set-Content -Path $hookPath -Value $hook -Encoding ASCII -NoNewline
    Write-Host "[new]  pre-commit hook 已安裝"
}

Write-Host ('-' * 60)
Write-Host '完成。下一步：'
Write-Host '  pwsh -File .harness/check.ps1'
Write-Host ''
Write-Host '記得做一次「故意失敗」測試——改一個 scope 之外的檔案，確認它真的擋。'
Write-Host '沒驗過的防線等於沒有防線。'
