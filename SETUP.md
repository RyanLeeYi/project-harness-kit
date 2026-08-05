# SETUP — 建置指引（寫給 AI agent 讀）

你的任務：在使用者的既有 repo 裡建立這套 harness。

**可以自己做的**：複製檔案、建立目錄、填入從 repo 裡讀得出來的事實（專案名稱、建置指令、目錄結構）。

**必須跟使用者討論、不准自己填的**：

- **範圍邊界**（`scope_paths`）——哪些路徑屬於本次工作
- **驗收標準**（`acceptance`）——什麼叫做完

這兩件事你猜不出來。猜錯了，後面七道檢查會全部通過，而東西是錯的。

---

## Step 0 · 先確認三件事

問使用者，或從 repo 讀出來後**複述給使用者確認**：

1. 這個 repo 是什麼系統？本次要做的是什麼？
2. 開發分支流程長怎樣？（預設假設 `feature/*` → `beta` → `master`，不同就改）
3. 有沒有既有的目錄規範，會跟 `.harness/` 衝突？

## Step 1 · 複製檔案

本 kit 位於目標 repo 的 `_harness-kit/`（或編輯器工作區裡的另一個資料夾）。**它是安裝來源，不是專案的一部分**——所有檔案用複製的，最後整個來源資料夾要刪掉。

從本 kit 複製到目標 repo：

```
templates/AGENTS.md          →  <repo>/AGENTS.md
templates/CLAUDE.md          →  <repo>/CLAUDE.md
templates/feature_list.json  →  <repo>/.harness/feature_list.json
templates/session-handoff.md →  <repo>/.harness/session-handoff.md
templates/ARCHITECTURE.md    →  <repo>/docs/ARCHITECTURE.md
check.ps1                    →  <repo>/.harness/check.ps1
init.ps1                     →  <repo>/init.ps1
pr-template.md               →  <repo>/.github/pull_request_template.md
                                （GitLab 用 .gitlab/merge_request_templates/default.md）
```

建立空目錄：`<repo>/docs/system-notes/`、`<repo>/docs/evidence/`

在 `.gitignore` 追加：

```
.harness/last-check.md
```

## Step 2 · 填 `AGENTS.md`

模板裡標 `<< >>` 的地方要填。其中：

- **專案一句話說明**、**建置與執行指令** → 你可以從 repo 讀出來，填完請使用者確認
- **能動哪 / 不能動哪** → **必須問使用者**。這是整套的邊界，問清楚為什麼不能動，把理由也寫進去——說得出理由的規則才有人遵守

填完把 `AGENTS.md` 全文給使用者看過一次再往下。

## Step 3 · 把需求轉成 feature 條目（草案）

在 `.harness/feature_list.json` 起草。每個 feature：

- `id`、`title`
- `scope_paths` — 本 feature 能動的路徑（glob）
- `acceptance` — 陣列，每條有 `id` 與 `check`
- `acceptance_frozen: false`、`signed_off_by: null`（**還沒簽核，不准填**）
- `status: "failing"`
- `prerequisites` — 必須先完成的 feature id 陣列，無則 `[]`。它決定順序，也決定哪幾條能平行；指向不存在的條目或形成循環會被 schema 自檢擋下
- `non_goals` — 這條**明確不做**的相鄰工作，無則 `[]`（先想過再寫空）
- `rollback` — 出事怎麼還原。`git revert` 就能解的填 `null`；**碰 DB migration、外部服務設定、不可逆操作的一定要填**
- `envelope` — 屬於哪個大工作，小工作填 `null`（見下）

**大工作先開 envelope**：預估跨 3 條以上 feature，或跨多個面向（前端＋後端＋資料），先在 `envelopes` 開一條共用約束層——`id`／`outcome`／`constraints`／`non_goals`／`frozen: false`，每個 feature 用 `envelope` 指回去。**envelope 先簽核，再逐條談底下的 feature**；簽核後 `constraints` 與 `non_goals` 與 acceptance 同級凍結。目的是在規劃期就把大工作切成可獨立核准、可平行的單位——acceptance 凍結之後才發現要拆，只能走取代流程，很貴。

**acceptance 撰寫規則**：每條都要寫「怎麼做 + 判準」，不准只寫結果形容詞。

| ❌ 不合格 | ✅ 合格 |
|---|---|
| 折扣計算正常 | 用測試資料集跑折扣批次，金額與人工試算表一致（10 筆抽樣） |
| 不影響既有功能 | 月結報表改版前後數字比對，差異為 0 |
| 效能可接受 | 5 萬筆資料下批次在 30 分鐘內完成 |

## Step 4 · ⛔ 停下來，要求簽核

**你不得自行開工。** 把 acceptance **逐條**唸給使用者確認，並主動標出你自己覺得模糊或無法驗證的條目——自曝不確定處，是提升簽核品質最便宜的手段。

使用者確認後，請他**自己執行**這行（不要你代跑，簽核痕跡必須在你之外）：

```powershell
git add .harness/feature_list.json
git commit -m "harness: sign off acceptance for F1

Acceptance-Signed-Off-By: <使用者名字>"
```

然後把 feature 的 `acceptance_frozen` 改成 `true`、`signed_off_by` / `signed_off_at` 填上。

## Step 5 · 驗證 harness 真的活著

```powershell
pwsh -File .harness/check.ps1
```

應該看到七道檢查逐條結果，最後一行 `RESULT: PASS`。

再做一次**故意失敗**的測試——這一步不要省，沒驗過的防線等於沒有防線：

1. 隨便改一個 `scope_paths` 之外的檔案
2. 再跑一次 `check.ps1`
3. 應該 `RESULT: FAIL`，且明確指出是哪個檔案越界

看到 FAIL 才代表牆是真的。還原那個改動，建置完成。

## Step 6 · 裝 git hook（選用）

```powershell
pwsh -File init.ps1
```

會把 `check.ps1` 掛進 pre-commit。這層是加分，不是地板——真正的關卡在 `feature → beta` 的 PR。

---

## Step 7 · 刪掉安裝來源

```powershell
Remove-Item _harness-kit -Recurse -Force
```

留在 repo 裡的應該只有：`AGENTS.md`、`CLAUDE.md`、`.harness/`、`docs/`、`init.ps1`、PR template。

---

## 之後的日常

規則全部寫在目標 repo 的 `AGENTS.md`，那是唯一入口。這份 `SETUP.md` 建置完就用不到了。
