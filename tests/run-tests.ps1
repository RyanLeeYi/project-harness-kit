<#
.SYNOPSIS
    check.ps1 的回歸測試：建一個臨時 repo，跑過每一種該擋與不該擋的情境。

.DESCRIPTION
    這支腳本存在的理由，就是這個 kit 的核心主張本身——
    一道會無聲倒塌的牆比沒有牆更危險。check.ps1 若哪天壞掉（改壞、環境變了、
    PowerShell 行為變了），它不會噴錯，只會安靜地全部放行。

    所以每次改 check.ps1 都要跑這支：
        pwsh -File tests/run-tests.ps1
#>
[CmdletBinding()]
param([string]$WorkDir)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$KitRoot = Split-Path $PSScriptRoot -Parent
if (-not $WorkDir) { $WorkDir = Join-Path ([System.IO.Path]::GetTempPath()) "harness-kit-test-$(Get-Random)" }

$script:Pass = 0
$script:Fail = 0

function New-Sandbox {
    if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force }
    New-Item -ItemType Directory -Path (Join-Path $WorkDir '.harness') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $WorkDir 'src/Orders') -Force | Out-Null
    New-Item -ItemType Directory -Path (Join-Path $WorkDir 'docs/evidence') -Force | Out-Null
    Push-Location $WorkDir
    & git init -q -b main
    & git config user.email 'test@example.com'
    & git config user.name  'harness test'
    Copy-Item (Join-Path $KitRoot 'check.ps1') '.harness/check.ps1'
    Set-Content 'AGENTS.md' "# AGENTS`n" -Encoding UTF8
    Set-Content 'src/Orders/Discount.cs' 'baseline' -Encoding UTF8
    Save-FeatureList (New-FeatureList)
    & git add -A
    & git commit -qm 'init'
    Pop-Location
}

function New-FeatureList {
    return [ordered]@{
        project              = 'sandbox'
        harness_version      = 1
        promote_base         = 'beta'
        always_allowed_paths = @('.harness/**', 'docs/**', 'AGENTS.md')
        envelopes            = @()
        features             = @(
            [ordered]@{
                id                = 'F1'
                title             = '折扣計算'
                status            = 'failing'
                envelope          = $null
                prerequisites     = @()
                non_goals         = @()
                rollback          = $null
                scope_paths       = @('src/Orders/**')
                acceptance_frozen = $true
                signed_off_by     = 'Tester'
                signed_off_at     = '2026-07-28'
                acceptance        = @([ordered]@{ id = 'A1'; check = '跑折扣批次，金額與試算表一致（10 筆抽樣）' })
                evidence          = @()
            }
        )
    }
}

function Save-FeatureList {
    param($Data)
    $Data | ConvertTo-Json -Depth 10 | Set-Content (Join-Path $WorkDir '.harness/feature_list.json') -Encoding UTF8
}

function Get-FeatureList {
    return Get-Content (Join-Path $WorkDir '.harness/feature_list.json') -Raw | ConvertFrom-Json
}

function Invoke-Case {
    param(
        [string]$Name,
        [ValidateSet('PASS', 'FAIL')][string]$Expect,
        [scriptblock]$Arrange,
        [switch]$Promote
    )
    New-Sandbox
    Push-Location $WorkDir
    try {
        & $Arrange
        $args = @('-NoProfile', '-File', '.harness/check.ps1')
        if ($Promote) { $args += '-Promote' }
        $output = & pwsh @args 2>&1
        $actual = if ($LASTEXITCODE -eq 0) { 'PASS' } else { 'FAIL' }
        if ($actual -eq $Expect) {
            Write-Host "[ok]   $Name"
            $script:Pass++
        } else {
            Write-Host "[FAIL] $Name — 預期 $Expect，實際 $actual"
            $output | ForEach-Object { Write-Host "       $_" }
            $script:Fail++
        }
    } finally {
        Pop-Location
    }
}

# ---------------------------------------------------------------- 情境

Invoke-Case -Name '乾淨狀態' -Expect 'PASS' -Arrange {}

# 迴歸：主控台是非 UTF-8 codepage（繁中 Windows 預設 cp950）時，PowerShell 會用它解碼
# `git show` 的輸出，acceptance 裡的中文全變亂碼 → 基準與工作區永遠比不相等 → 乾淨狀態誤擋。
# 這個 bug 不噴錯，只會安靜地擋住所有人，所以要在測試裡把那個環境重現出來。
$prevConsoleEnc = [Console]::OutputEncoding
try {
    [Console]::OutputEncoding = [System.Text.Encoding]::GetEncoding(950)
    Invoke-Case -Name '主控台非 UTF-8 時中文 acceptance 不誤擋' -Expect 'PASS' -Arrange {}
} catch [System.NotSupportedException] {
    Write-Host '[skip] 主控台非 UTF-8 迴歸（此平台沒有 cp950）'
} finally {
    [Console]::OutputEncoding = $prevConsoleEnc
}

Invoke-Case -Name '改到 scope 之外的檔案' -Expect 'FAIL' -Arrange {
    New-Item -ItemType Directory -Path 'src/Billing' -Force | Out-Null
    Set-Content 'src/Billing/Invoice.cs' 'touched' -Encoding UTF8
}

Invoke-Case -Name '偷改已凍結的 acceptance' -Expect 'FAIL' -Arrange {
    $fl = Get-FeatureList
    $fl.features[0].acceptance[0].check = '跑一下看起來對就好'
    Save-FeatureList $fl
}

Invoke-Case -Name '改凍結的 acceptance 但帶簽核 trailer' -Expect 'PASS' -Arrange {
    $fl = Get-FeatureList
    $fl.features[0].acceptance[0].check = '改後的標準（已核准）'
    Save-FeatureList $fl
    & git add -A
    & git commit -qm "harness: revise acceptance`n`nAcceptance-Change-Approved-By: Tester"
}

Invoke-Case -Name '翻 passing 但沒有 evidence' -Expect 'FAIL' -Arrange {
    $fl = Get-FeatureList
    $fl.features[0].status = 'passing'
    Save-FeatureList $fl
}

Invoke-Case -Name 'evidence 指向不存在的檔案' -Expect 'FAIL' -Arrange {
    $fl = Get-FeatureList
    $fl.features[0].status = 'passing'
    $fl.features[0].evidence = @(@{ acceptance_id = 'A1'; how = '跑過'; output = 'docs/evidence/nope.txt'; verified_by = 'Tester'; at = '2026-07-28' })
    Save-FeatureList $fl
}

Invoke-Case -Name 'passing 但從未簽核' -Expect 'FAIL' -Arrange {
    Set-Content 'docs/evidence/F1-A1.txt' '筆數 10，差異 0' -Encoding UTF8
    $fl = Get-FeatureList
    $fl.features[0].status = 'passing'
    $fl.features[0].acceptance_frozen = $false
    $fl.features[0].signed_off_by = $null
    $fl.features[0].evidence = @(@{ acceptance_id = 'A1'; how = '跑過'; output = 'docs/evidence/F1-A1.txt'; verified_by = 'Tester'; at = '2026-07-28' })
    Save-FeatureList $fl
}

Invoke-Case -Name 'schema 缺欄位要 fail-closed' -Expect 'FAIL' -Arrange {
    $fl = Get-FeatureList
    $fl.features[0].PSObject.Properties.Remove('evidence')
    Save-FeatureList $fl
}

Invoke-Case -Name 'feature_list.json 不是合法 JSON' -Expect 'FAIL' -Arrange {
    Set-Content '.harness/feature_list.json' '{ 壞掉的 json' -Encoding UTF8
}

Invoke-Case -Name 'system-notes 沒進索引' -Expect 'FAIL' -Arrange {
    New-Item -ItemType Directory -Path 'docs/system-notes' -Force | Out-Null
    Set-Content 'docs/system-notes/batch-timing.md' '# 批次時序' -Encoding UTF8
}

Invoke-Case -Name '晉升時 feature 仍是 failing' -Expect 'FAIL' -Promote -Arrange {
    & git branch beta
    & git checkout -q -b feature/F1-discount
    Set-Content 'src/Orders/Discount.cs' 'v2' -Encoding UTF8
    & git add -A
    & git commit -qm 'feat: v2'
}

Invoke-Case -Name '晉升時全部齊備' -Expect 'PASS' -Promote -Arrange {
    & git branch beta
    & git checkout -q -b feature/F1-discount
    Set-Content 'src/Orders/Discount.cs' 'v2' -Encoding UTF8
    Set-Content 'docs/evidence/F1-A1.txt' '筆數 10，差異 0' -Encoding UTF8
    $fl = Get-FeatureList
    $fl.features[0].status = 'passing'
    $fl.features[0].evidence = @(@{ acceptance_id = 'A1'; how = '測試環境批次'; output = 'docs/evidence/F1-A1.txt'; verified_by = 'Tester'; at = '2026-07-28' })
    Save-FeatureList $fl
    & git add -A
    & git commit -qm 'feat: complete F1'
}

# ---------------------------------------------------------------- 結果

if (Test-Path $WorkDir) { Remove-Item $WorkDir -Recurse -Force -ErrorAction SilentlyContinue }

Write-Host ''
Write-Host ('-' * 50)
Write-Host "通過 $script:Pass ／ 失敗 $script:Fail"
if ($script:Fail -gt 0) { exit 1 } else { exit 0 }
