<#
.SYNOPSIS
    Harness 合規關卡：七道檢查，不需要自動測試也能跑。

.DESCRIPTION
    檢查的是「流程合規」——沒偷改驗收標準、沒超出範圍、證據有逐條對上。
    PASS 不代表功能做對了，功能正確性靠 acceptance 本身的驗證。

.PARAMETER Promote
    晉升模式：比對當前分支與基準分支（預設 beta）的完整 diff，供 PR 關卡使用。
    不加此參數則檢查工作區相對 HEAD 的改動，供日常快速回饋使用。

.PARAMETER Base
    晉升模式的基準分支。預設讀 feature_list.json 的 promote_base，再退回 beta。

.PARAMETER Report
    報告輸出路徑。省略時寫入 .harness/last-check.md（該檔應列入 .gitignore）。

.EXAMPLE
    pwsh -File .harness/check.ps1
    pwsh -File .harness/check.ps1 -Promote -Report docs/evidence/check-F1-20260728.md
#>
[CmdletBinding()]
param(
    [switch]$Promote,
    [string]$Base,
    [string]$Report
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
# PowerShell 用 [Console]::OutputEncoding 解碼 native 指令的 stdout。Windows 主控台預設是
# 系統 ANSI codepage（繁中機器＝cp950），於是 `git show` 讀回來的中文全變亂碼——
# 基準版本與工作區永遠比不相等，gate 1 在什麼都沒改的乾淨狀態下就誤擋。
# 只要 acceptance 寫中文就必中，而且不會噴錯，只會安靜地擋住所有人。
[Console]::OutputEncoding = [System.Text.Encoding]::UTF8
# PowerShell 7.4+ 預設會把 native 指令的非零 exit code 當成錯誤丟出。
# 這裡刻意關掉：git 的「查無此物」是預期中的狀況，要由後面的邏輯判讀，不是例外。
if (Test-Path variable:PSNativeCommandUseErrorActionPreference) {
    $PSNativeCommandUseErrorActionPreference = $false
}

$RepoRoot = (& git rev-parse --show-toplevel 2>$null)
if (-not $RepoRoot) { Write-Host 'FATAL: 不在 git repo 內'; Write-Host 'RESULT: FAIL'; exit 1 }
$RepoRoot = $RepoRoot -replace '\\', '/'

$FeatureListPath = Join-Path $RepoRoot '.harness/feature_list.json'
$AgentsPath      = Join-Path $RepoRoot 'AGENTS.md'
$SystemNotesDir  = Join-Path $RepoRoot 'docs/system-notes'

# 檢查結果累積器。每筆：Id / Name / Status(PASS|FAIL|WARN|SKIP) / Detail(string[])
$script:Results = @()
$script:ModeDesc = 'schema 自檢階段'

function Add-Result {
    param([string]$Id, [string]$Name, [string]$Status, [string[]]$Detail = @())
    $script:Results += [pscustomobject]@{ Id = $Id; Name = $Name; Status = $Status; Detail = $Detail }
}

function Get-Verdict {
    if ($script:Results | Where-Object { $_.Status -eq 'FAIL' }) { return 'FAIL' }
    return 'PASS'
}

function Write-Summary {
    Write-Host ''
    Write-Host "Harness Check — $script:ModeDesc"
    Write-Host ('-' * 60)
    foreach ($r in ($script:Results | Sort-Object Id)) {
        $mark = switch ($r.Status) { 'PASS' { '[ok]  ' } 'FAIL' { '[FAIL]' } 'WARN' { '[warn]' } default { '[skip]' } }
        Write-Host ("{0} {1}. {2}" -f $mark, $r.Id, $r.Name)
        if ($r.Status -in @('FAIL', 'WARN')) {
            foreach ($d in $r.Detail) { if ($d) { Write-Host "       $d" } }
        }
    }
    Write-Host ('-' * 60)
}

function Stop-FailClosed {
    param([string]$Reason)
    # schema 自檢失敗一律 FAIL-CLOSED：讀不到預期結構就不准放行。
    # 一道會無聲倒塌的牆比沒有牆更危險——因為你以為它還在。
    Add-Result -Id '5' -Name 'schema 自檢' -Status 'FAIL' -Detail @($Reason, '防線無法確認完整，拒絕放行（fail-closed）')
    Write-Summary
    # 這裡刻意不產報告：schema 都讀不動時，任何「改動清單」與「驗收現況」都不可信。
    Write-Host 'RESULT: FAIL'
    exit 1
}

function ConvertTo-PathRegex {
    param([string]$Glob)
    $escaped = [regex]::Escape(($Glob -replace '\\', '/'))
    # 先把 ** 換成不會被下一步誤傷的明碼 token。
    # 別用 \x00 之類的跳脫序列當佔位——replacement 字串是字面解讀、pattern 是 regex 解讀，兩邊對不上。
    $pattern = $escaped -replace '\\\*\\\*', 'DOUBLESTARTOKEN'
    $pattern = $pattern -replace '\\\*', '[^/]*'          # * 不跨目錄
    $pattern = $pattern -replace 'DOUBLESTARTOKEN', '.*'  # ** 跨目錄
    $pattern = $pattern -replace '\\\?', '.'
    return "^$pattern$"
}

function Test-MatchAny {
    param([string]$Path, [string[]]$Globs)
    foreach ($g in $Globs) {
        if ($Path -match (ConvertTo-PathRegex $g)) { return $true }
    }
    return $false
}

function Get-JsonProperty {
    param($Object, [string]$Name)
    if ($null -eq $Object) { return $null }
    if ($Object.PSObject.Properties.Name -contains $Name) { return $Object.$Name }
    return $null
}

function Test-JsonField {
    param($Object, [string]$Name)
    # 存在性一律用這支判斷，不要用取值——PowerShell 的函式回傳會把空陣列展開成 $null，
    # 用 Get-JsonProperty 檢查 "evidence": [] 會誤判成「欄位不存在」。
    return ($null -ne $Object) -and ($Object.PSObject.Properties.Name -contains $Name)
}

# ---------------------------------------------------------------- 載入與 schema 自檢

if (-not (Test-Path $FeatureListPath)) {
    Stop-FailClosed "找不到 .harness/feature_list.json"
}

try {
    $fl = Get-Content $FeatureListPath -Raw -Encoding UTF8 | ConvertFrom-Json
} catch {
    Stop-FailClosed "feature_list.json 不是合法 JSON：$($_.Exception.Message)"
}

foreach ($field in @('harness_version', 'features', 'always_allowed_paths')) {
    if (-not (Test-JsonField $fl $field)) {
        Stop-FailClosed "feature_list.json 缺少必要欄位：$field"
    }
}

$features = @($fl.features)
foreach ($f in $features) {
    foreach ($field in @('id', 'title', 'status', 'scope_paths', 'acceptance', 'acceptance_frozen', 'evidence',
                         'envelope', 'prerequisites', 'non_goals')) {
        if (-not (Test-JsonField $f $field)) {
            $fid = if (Test-JsonField $f 'id') { $f.id } else { '(無 id)' }
            Stop-FailClosed "feature $fid 缺少必要欄位：$field"
        }
    }
    if ($f.status -notin @('failing', 'passing')) {
        Stop-FailClosed "feature $($f.id) 的 status 只能是 failing / passing，實際為：$($f.status)"
    }
    foreach ($a in @($f.acceptance)) {
        if ((-not (Test-JsonField $a 'id')) -or (-not (Test-JsonField $a 'check'))) {
            Stop-FailClosed "feature $($f.id) 的 acceptance 條目缺少 id 或 check"
        }
    }
}

# envelope（大工作的共用約束層）。整個 key 可以不存在＝這份 harness 沒有大工作；
# 一旦存在，每一條都要完整——半成品的 envelope 比沒有更糟，因為 feature 會指向它。
# 不要寫成 `$x = if (...) { @(...) } else { @() }`——if 區塊回傳空陣列時會被展開成 $null，
# StrictMode 下後面取 .Count 就炸（同 Test-JsonField 上面那段註解講的同一類坑）。
$envelopes = @()
if (Test-JsonField $fl 'envelopes') { $envelopes = @($fl.envelopes) }
foreach ($e in $envelopes) {
    foreach ($field in @('id', 'outcome', 'constraints', 'non_goals', 'frozen')) {
        if (-not (Test-JsonField $e $field)) {
            $eid = if (Test-JsonField $e 'id') { $e.id } else { '(無 id)' }
            Stop-FailClosed "envelope $eid 缺少必要欄位：$field"
        }
    }
}
$envelopeIds = @($envelopes | ForEach-Object { $_.id })
$featureIds  = @($features  | ForEach-Object { $_.id })

foreach ($f in $features) {
    $envId = Get-JsonProperty $f 'envelope'
    if ($envId -and ($envId -notin $envelopeIds)) {
        Stop-FailClosed "feature $($f.id) 的 envelope 指向不存在的 $envId"
    }
    foreach ($p in @($f.prerequisites)) {
        if ($p -notin $featureIds) {
            Stop-FailClosed "feature $($f.id) 的 prerequisites 指向不存在的 feature：$p"
        }
        if ($p -eq $f.id) {
            Stop-FailClosed "feature $($f.id) 的 prerequisites 指向自己"
        }
    }
}

# 循環相依：反覆移除「前置條件都已滿足」的條目，移不動就是有環。
# 有環的清單排不出順序，也判不出誰能平行——讓它靜靜留在檔案裡最貴。
$pending = @{}
foreach ($f in $features) { $pending[$f.id] = @(@($f.prerequisites) | Where-Object { $_ }) }
$progress = $true
while ($progress -and $pending.Count -gt 0) {
    $progress = $false
    foreach ($id in @($pending.Keys)) {
        if (@($pending[$id] | Where-Object { $pending.ContainsKey($_) }).Count -eq 0) {
            $pending.Remove($id); $progress = $true
        }
    }
}
if ($pending.Count -gt 0) {
    Stop-FailClosed "prerequisites 出現循環相依：$(@($pending.Keys | Sort-Object) -join ', ')"
}

Add-Result -Id '5' -Name 'schema 自檢' -Status 'PASS' `
    -Detail @("feature 數：$($features.Count)；envelope 數：$($envelopes.Count)；必要欄位齊全、參照有效、無循環相依")

# ---------------------------------------------------------------- 決定比較基準與改動清單

$alwaysAllowed = @($fl.always_allowed_paths)
$branch = (& git rev-parse --abbrev-ref HEAD 2>$null)

if ($Promote) {
    if (-not $Base) {
        $Base = if (Test-JsonField $fl 'promote_base') { $fl.promote_base } else { 'beta' }
    }
    if (-not (& git rev-parse --verify --quiet $Base)) {
        Stop-FailClosed "晉升模式找不到基準分支：$Base"
    }
    $changed = @(& git diff --name-only "$Base...HEAD" 2>$null)
    $baseRef = $Base
    $script:ModeDesc = "晉升模式（$branch ⇢ $Base）"
} else {
    # -uall：未追蹤的目錄要展開成個別檔案，否則越界的檔案會顯示成 "src/Billing/" 而看不出是誰
    $changed = @(& git status --porcelain -uall 2>$null | ForEach-Object { ($_ -replace '^.{3}', '').Trim('"') })
    $baseRef = 'HEAD'
    $script:ModeDesc = "日常模式（工作區 vs HEAD）"
}
$changed = @($changed | Where-Object { $_ } | ForEach-Object { $_ -replace '\\', '/' } | Sort-Object -Unique)

# ---------------------------------------------------------------- 決定當前 feature

$currentFeature = $null
if ($branch -match 'feature/(?<id>[A-Za-z]\d+)') {
    $currentFeature = $features | Where-Object { $_.id -eq $Matches['id'] } | Select-Object -First 1
}
if ($currentFeature) {
    $scopeSource = "分支名指定：$($currentFeature.id)"
    $scopeFeatures = @($currentFeature)
} else {
    $scopeSource = "分支名未帶 feature id，改用所有 failing feature 的範圍聯集"
    $scopeFeatures = @($features | Where-Object { $_.status -eq 'failing' })
}

# ---------------------------------------------------------------- 1 · acceptance／envelope 凍結

$prevJson = (& git show "${baseRef}:.harness/feature_list.json" 2>$null) -join "`n"
if (-not $prevJson) {
    Add-Result -Id '1' -Name 'acceptance／envelope 凍結' -Status 'SKIP' `
        -Detail @("$baseRef 上沒有 feature_list.json（首次建置），無從比對")
} else {
    $prev = $prevJson | ConvertFrom-Json
    $violations = @()
    foreach ($pf in @($prev.features)) {
        if (-not (Test-JsonField $pf 'acceptance_frozen') -or -not $pf.acceptance_frozen) { continue }
        $cur = $features | Where-Object { $_.id -eq $pf.id } | Select-Object -First 1
        if (-not $cur) { $violations += "$($pf.id)：已凍結的 feature 被整條刪除"; continue }
        $before = ($pf.acceptance | ConvertTo-Json -Depth 10 -Compress)
        $after  = ($cur.acceptance | ConvertTo-Json -Depth 10 -Compress)
        if ($before -ne $after) { $violations += "$($pf.id)：已凍結的 acceptance 被修改" }
    }
    # envelope 的 constraints 與 non_goals 簽核後與 acceptance 同級凍結：
    # 底下每個 slice 都是在那組約束下被核准的，事後改約束等於整批 slice 的核准失效。
    # 基準版本可能還沒有 envelopes 這個 key（導入前的 harness）——StrictMode 下直接取值會炸，
    # 一律走 Test-JsonField。沒有就是沒有大工作要比對。
    $prevEnvelopes = @()
    if (Test-JsonField $prev 'envelopes') { $prevEnvelopes = @($prev.envelopes) }
    foreach ($pe in $prevEnvelopes) {
        if (-not (Test-JsonField $pe 'frozen') -or -not $pe.frozen) { continue }
        $cur = $envelopes | Where-Object { $_.id -eq $pe.id } | Select-Object -First 1
        if (-not $cur) { $violations += "$($pe.id)：已凍結的 envelope 被整條刪除"; continue }
        foreach ($field in @('constraints', 'non_goals')) {
            if (-not (Test-JsonField $pe $field)) { continue }
            $before = ($pe.$field | ConvertTo-Json -Depth 10 -Compress)
            $after  = ($cur.$field | ConvertTo-Json -Depth 10 -Compress)
            if ($before -ne $after) { $violations += "$($pe.id)：已凍結的 envelope $field 被修改" }
        }
    }

    if ($violations.Count -eq 0) {
        Add-Result -Id '1' -Name 'acceptance／envelope 凍結' -Status 'PASS' -Detail @('已凍結的驗收標準與 envelope 約束沒有被改動')
    } else {
        $range = if ($Promote) { "$Base..HEAD" } else { 'HEAD~1..HEAD' }
        $log = (& git log $range --format=%B 2>$null) -join "`n"
        $hasTrailer = $log -match '(?m)^(Acceptance-Change-Approved-By|Acceptance-Signed-Off-By):\s*\S+'
        if ($hasTrailer) {
            Add-Result -Id '1' -Name 'acceptance／envelope 凍結' -Status 'PASS' `
                -Detail (@('驗收標準有改動，但帶有簽核 trailer：') + $violations)
        } else {
            Add-Result -Id '1' -Name 'acceptance／envelope 凍結' -Status 'FAIL' `
                -Detail (@('已凍結的驗收標準被改動，且沒有簽核 trailer。') +
                         $violations +
                         @('', '規則：發現漏了就「新增」一條標 failing 回去簽核，不要改舊的。',
                           '真的要改 → 由人執行 commit 並帶 trailer：Acceptance-Change-Approved-By: <名字>'))
        }
    }
}

# ---------------------------------------------------------------- 2 · evidence gate

$evidenceIssues = @()
$privacyWarnings = @()
foreach ($f in $features | Where-Object { $_.status -eq 'passing' }) {
    $evi = @($f.evidence)
    foreach ($a in @($f.acceptance)) {
        $hit = $evi | Where-Object { (Get-JsonProperty $_ 'acceptance_id') -eq $a.id } | Select-Object -First 1
        if (-not $hit) {
            $evidenceIssues += "$($f.id)/$($a.id)：狀態是 passing，但沒有對應的 evidence"
            continue
        }
        foreach ($field in @('how', 'output', 'verified_by')) {
            if (-not (Get-JsonProperty $hit $field)) {
                $evidenceIssues += "$($f.id)/$($a.id)：evidence 缺 $field"
            }
        }
        $out = Get-JsonProperty $hit 'output'
        if ($out) {
            $outPath = Join-Path $RepoRoot $out
            if (-not (Test-Path $outPath)) {
                $evidenceIssues += "$($f.id)/$($a.id)：evidence 指向的檔案不存在 → $out"
            } elseif ((Get-Content $outPath -Raw -ErrorAction SilentlyContinue) -match '\d{13,19}') {
                # 粗篩：長數字串常見於卡號、身分識別碼。只示警不擋，避免誤殺金額與批次號。
                $privacyWarnings += "$out 含 13 位以上連續數字，請確認已去識別化"
            }
        }
    }
}

if ($evidenceIssues.Count -eq 0) {
    $detail = @('所有 passing 的 feature 都有逐條對應的證據')
    if ($privacyWarnings.Count -gt 0) { $detail += @('', '⚠ 去識別化提醒：') + $privacyWarnings }
    Add-Result -Id '2' -Name 'evidence gate' -Status $(if ($privacyWarnings) { 'WARN' } else { 'PASS' }) -Detail $detail
} else {
    Add-Result -Id '2' -Name 'evidence gate' -Status 'FAIL' -Detail ($evidenceIssues + $privacyWarnings)
}

# ---------------------------------------------------------------- 3 · 範圍邊界

$scopeGlobs = @()
foreach ($f in $scopeFeatures) { $scopeGlobs += @($f.scope_paths) }
$allowedGlobs = @($scopeGlobs + $alwaysAllowed)

$outOfScope = @()
$inScope = @()
foreach ($file in $changed) {
    if (Test-MatchAny -Path $file -Globs $allowedGlobs) {
        $owner = ($scopeFeatures | Where-Object { Test-MatchAny -Path $file -Globs @($_.scope_paths) } |
                  Select-Object -First 1)
        $label = if ($owner) { $owner.id } else { '共用檔案' }
        $inScope += "$file  ← $label"
    } else {
        $outOfScope += $file
    }
}

if ($changed.Count -eq 0) {
    Add-Result -Id '3' -Name '範圍邊界' -Status 'SKIP' -Detail @('沒有偵測到改動')
} elseif ($outOfScope.Count -eq 0) {
    Add-Result -Id '3' -Name '範圍邊界' -Status 'PASS' -Detail (@("$scopeSource", '') + $inScope)
} else {
    Add-Result -Id '3' -Name '範圍邊界' -Status 'FAIL' `
        -Detail (@("$scopeSource", '', '⛔ 不在任何 scope_paths 內：') + $outOfScope +
                 @('', '要動這些檔案 → 停下來問人，或把路徑加進該 feature 的 scope_paths 並重新簽核。'))
}

# ---------------------------------------------------------------- 4 · 索引同步

if (-not (Test-Path $SystemNotesDir)) {
    Add-Result -Id '4' -Name '索引同步' -Status 'SKIP' -Detail @('尚無 docs/system-notes/')
} elseif (-not (Test-Path $AgentsPath)) {
    Add-Result -Id '4' -Name '索引同步' -Status 'FAIL' -Detail @('找不到 AGENTS.md，索引無處可放')
} else {
    $agents = Get-Content $AgentsPath -Raw -Encoding UTF8
    $missing = @(Get-ChildItem $SystemNotesDir -Filter '*.md' -File |
                 Where-Object { $agents -notmatch [regex]::Escape($_.Name) } |
                 ForEach-Object { $_.Name })
    if ($missing.Count -eq 0) {
        Add-Result -Id '4' -Name '索引同步' -Status 'PASS' -Detail @('system-notes 全數列在 AGENTS.md 索引中')
    } else {
        Add-Result -Id '4' -Name '索引同步' -Status 'FAIL' `
            -Detail (@('以下筆記沒有出現在 AGENTS.md 的索引段：') + $missing)
    }
}

# ---------------------------------------------------------------- 6 · 簽核關卡

$signoffIssues = @()
foreach ($f in $features | Where-Object { $_.status -eq 'passing' }) {
    if (-not $f.acceptance_frozen) { $signoffIssues += "$($f.id)：狀態 passing，但 acceptance 從未凍結" }
    if (-not (Get-JsonProperty $f 'signed_off_by')) { $signoffIssues += "$($f.id)：狀態 passing，但沒有簽核人" }
}
# 晉升到基準分支＝宣告完成。還在 failing 就不該晉升。
if ($Promote -and $currentFeature -and $currentFeature.status -ne 'passing') {
    $signoffIssues += "$($currentFeature.id)：要晉升到 $Base，但狀態仍是 failing——尚未完成就不該送出"
}
if ($signoffIssues.Count -eq 0) {
    Add-Result -Id '6' -Name '簽核關卡' -Status 'PASS' -Detail @('沒有跳過簽核就宣告完成的 feature')
} else {
    Add-Result -Id '6' -Name '簽核關卡' -Status 'FAIL' `
        -Detail ($signoffIssues + @('', '驗收標準要先由人簽核凍結，才能開工、才能宣告完成。'))
}

# ---------------------------------------------------------------- 7 · 前置條件

# prerequisites 宣告的是「誰得先做完」。一條 feature 的前置還在 failing 就宣告 passing，
# 代表它其實不依賴那條（宣告錯了），或驗收沒真的跑過依賴路徑（驗收虛過）。兩種都要停下來看。
$prereqIssues = @()
$statusById = @{}
foreach ($f in $features) { $statusById[$f.id] = $f.status }
foreach ($f in $features | Where-Object { $_.status -eq 'passing' }) {
    foreach ($p in @($f.prerequisites)) {
        if ($statusById[$p] -ne 'passing') {
            $prereqIssues += "$($f.id)：狀態 passing，但前置 $p 仍是 $($statusById[$p])"
        }
    }
}
if ($prereqIssues.Count -eq 0) {
    Add-Result -Id '7' -Name '前置條件' -Status 'PASS' -Detail @('沒有前置未完成就宣告完成的 feature')
} else {
    Add-Result -Id '7' -Name '前置條件' -Status 'FAIL' `
        -Detail ($prereqIssues + @('', '要嘛前置真的還沒做完（先做完），要嘛 prerequisites 宣告錯了（回簽核改）。'))
}

# ---------------------------------------------------------------- 輸出

function Write-Report {
    $path = if ($Report) { $Report } else { '.harness/last-check.md' }
    $full = if ([System.IO.Path]::IsPathRooted($path)) { $path } else { Join-Path $RepoRoot $path }
    $dir = Split-Path $full -Parent
    if ($dir -and -not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }

    $head = (& git rev-parse --short HEAD 2>$null)
    $lines = @(
        "# Harness Check 報告",
        "",
        "- **模式**：$script:ModeDesc",
        "- **分支 / commit**：``$branch`` @ ``$head``",
        "- **執行時間**：$(Get-Date -Format 'yyyy-MM-dd HH:mm')",
        "- **結論**：**$(Get-Verdict)**",
        "",
        "## 改動清單",
        ""
    )
    if ($changed.Count -eq 0) {
        $lines += '（無改動）'
    } else {
        $lines += @('| 檔案 | 歸屬 |', '|------|------|')
        foreach ($file in $changed) {
            $owner = ($scopeFeatures | Where-Object { Test-MatchAny -Path $file -Globs @($_.scope_paths) } |
                      Select-Object -First 1)
            $label = if ($owner) { $owner.id }
                     elseif (Test-MatchAny -Path $file -Globs $alwaysAllowed) { '共用檔案' }
                     else { '⛔ **超出範圍**' }
            $lines += "| ``$file`` | $label |"
        }
    }

    $lines += @('', '## 驗收現況', '')
    foreach ($f in $features) {
        $lines += "### $($f.id) — $($f.title)  ·  ``$($f.status)``"
        $lines += ''
        $lines += @('| # | 驗收標準 | 證據 |', '|---|----------|------|')
        foreach ($a in @($f.acceptance)) {
            $hit = @($f.evidence) | Where-Object { (Get-JsonProperty $_ 'acceptance_id') -eq $a.id } | Select-Object -First 1
            $ev = if ($hit) { "$($hit.how) → ``$($hit.output)``（$($hit.verified_by)）" } else { '—' }
            $lines += "| $($a.id) | $($a.check) | $ev |"
        }
        $lines += ''
    }

    $lines += @('## 檢查結果', '')
    foreach ($r in ($script:Results | Sort-Object Id)) {
        $lines += "**$($r.Id). $($r.Name)** — $($r.Status)"
        $lines += ''
        foreach ($d in $r.Detail) { if ($d) { $lines += "- $d" } }
        $lines += ''
    }

    $lines += @(
        '---',
        '',
        '> check PASS 只代表流程合規：沒偷改驗收標準、沒超出範圍、證據有逐條對上。',
        '> 功能到底對不對，看的是上面「驗收現況」每一條證據本身。'
    )

    Set-Content -Path $full -Value ($lines -join "`n") -Encoding UTF8
    Write-Host "報告：$path"
}

Write-Summary
Write-Report
$verdict = Get-Verdict
Write-Host "RESULT: $verdict"
if ($verdict -eq 'FAIL') { exit 1 } else { exit 0 }
