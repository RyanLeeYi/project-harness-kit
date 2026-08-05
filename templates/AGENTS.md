# AGENTS.md — AI Agent 唯一入口

> 適用所有 AI 工具（Copilot、Cursor、Codex、Claude Code…）。規則只寫在這一份，其他檔案不重複。

## 1 · 這個專案

<< 一句話：這是什麼系統、本次要做什麼 >>

**建置與執行**：`<< 指令 >>`
**測試**：`<< 指令，沒有就寫「無自動測試，驗收靠 acceptance 的人工步驟」 >>`

**能動的範圍**：`<< 路徑 >>`
**不能動的範圍與理由**：`<< 路徑 — 為什麼 >>`

細節見 `docs/ARCHITECTURE.md`（只描述本次工作的邊界，不是整個系統的地圖）。

## 2 · 開場（每個 session 第一件事）

依序讀：本檔 → `.harness/session-handoff.md` → `.harness/feature_list.json`

然後**說出**：「這次要做哪個 feature、怎麼驗證算過。」

答不出來就是 harness 有缺口——先補檔案，不要開工。

## 3 · `feature_list.json` 使用規則

- `status` 只有 `failing` / `passing`，**沒有中間狀態**
- **acceptance 簽核後凍結，不得修改。** 發現漏了 → **新增**一條標 `failing` 並回去簽核，**不是**改舊的
  > 一次放寬一點點，最後標準會全部消失。所以只准增、不准改
- **envelope 的 `constraints` 與 `non_goals` 簽核後同級凍結**——底下每個 feature 都是在那組約束下被核准的，事後改約束等於整批核准失效
- `prerequisites` 是宣告的順序，也是能不能平行的依據。不互為前置、`scope_paths` 無交集的 feature 才可以同時進行
- 翻成 `passing` 的四個要件，缺一不可：
  1. `check.ps1` 回傳 PASS
  2. evidence **逐條對應** acceptance
  3. 動到的檔案全在該 feature 的 `scope_paths` 內
  4. `prerequisites` 列的 feature 全都已經 `passing`
- **清單以外的事不要做。** 冒出新需求 → 先加進清單標 `failing`，回到第 4 節走簽核

## 4 · 新需求進來怎麼辦

```
1. 歸檔上一案 ── 已 passing 的 features 搬進
                 .harness/archive/feature_list-<案名>-<日期>.json
2. 起草 feature ── id / title / scope_paths / acceptance
                   prerequisites / non_goals / rollback / envelope
                   acceptance_frozen: false, signed_off_by: null
   （跨 3 條以上或跨多面向 → 先開 envelope 並先簽核）
3. ⛔ 停下來要簽核 ── 不得自行開工
4. 使用者簽核 ── 他自己執行 commit（trailer 帶 Acceptance-Signed-Off-By）
5. 開工
```

**acceptance 撰寫規則**：每條要有「怎麼做 + 判準」，禁止只寫結果形容詞。

| ❌ | ✅ |
|---|---|
| 折扣計算正常 | 用測試資料集跑折扣批次，金額與人工試算表一致（10 筆抽樣） |
| 不影響既有功能 | 月結報表改版前後數字比對，差異為 0 |

第 3 步呈現 acceptance 時要**逐條**確認，並主動標出你覺得模糊或無法驗證的條目。

## 5 · evidence 規則

翻 `passing` 時，每條 acceptance 都要有一筆 evidence：

```json
{ "acceptance_id": "A1",
  "how": "測試環境 20260728 批次",
  "output": "docs/evidence/F1-A1-20260728.txt",
  "verified_by": "<人名>", "at": "2026-07-28" }
```

**硬規則：evidence 一律去識別化。** 只留筆數、金額彙總、關鍵欄位，**不貼原始資料列**（可能含個資或機敏資料）。

## 6 · `docs/system-notes/` 規則

踩到舊系統的坑就補一則：**現象 / 根因 / 涉及模組與檔案 / 日期**。

- **這是某天的觀察，不是現況保證。超過半年的內容要重新驗證再依賴。**
- 平常不讀，需要時才開；本檔第 9 節只放索引行
- 新增一則 → 同一次改動內補上索引行（`check.ps1` 會檢）

## 7 · 收尾與收工

**收尾（feature 做完）**
```
pwsh -File .harness/check.ps1
```
FAIL → 修到過。**不准改 acceptance 讓它過。**
PASS → evidence 補齊，`status` 翻 `passing`

**晉升（feature → beta）**
```
pwsh -File .harness/check.ps1 -Promote -Report docs/evidence/check-<feature>-<日期>.md
```
把報告貼進 PR 描述，讓審核者一眼看到範圍與驗收現況。

**收工（session 結束）**
- 覆寫 `.harness/session-handoff.md`：現況 / 下一步 / 卡點
- 踩到坑 → 補 system-notes + 索引行

## 8 · 硬禁止

- ❌ 改 acceptance 讓檢查通過
- ❌ 動 `scope_paths` 以外的檔案（真的需要 → 停下來問人）
- ❌ `--no-verify`、`git push --force`、`git reset --hard`
- ❌ 把 `check.ps1` PASS 當成「驗收通過」
  > **PASS 只代表流程合規**——沒偷改標準、沒超範圍、證據有對上。功能到底對不對，靠 acceptance 本身的驗證，那是人做的

## 9 · system-notes 索引

<< 一行一則：`檔名` — 一句話（日期） >>
