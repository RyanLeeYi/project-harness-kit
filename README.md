# Project Harness Kit

> 把 AI agent 的工作規範，從「每次重講的 prompt」變成「隨 repo 走的可執行關卡」。
>
> **v0.2** · 給既有專案用的專案層級 harness 安裝包

*A drop-in, tool-neutral harness for existing repos: one entry file any AI agent reads, plus a PowerShell gate that fails when scope, acceptance, or evidence rules are broken. Docs in Traditional Chinese.*

---

## 這是什麼

一組可以直接放進**既有 repo** 的檔案，讓任何 AI agent（Copilot、Cursor、Codex、Claude Code…）在這個 repo 裡工作時，遵守同一套規則——而且規則不是靠提醒，是靠一支跑得起來的腳本擋。

適用情境：

- 團隊裡**每個人用不同的 AI 工具**，沒有共同的本地設定可以假設
- **新功能長在舊系統裡**，需要限制 agent 只能動指定範圍
- **CI 只有 build、沒有自動測試**，或流程上跑不了額外的 pipeline
- 半年後**接手的人（或 agent）要能冷啟動**

## 核心主張

**agent 的可靠性不來自 prompt 寫得多好，來自 repo 裡的結構化產物。** prompt 每個 session 重來一次、會漂移、會被忘記；檔案不會，它就躺在 repo 裡當唯一事實來源。

而規則要真的有效，得能被執行：

> **寫在文件是宣示，寫在可執行的東西裡才是機制。**

所以這個 kit 的重點不是那幾份 markdown，是 `check.ps1`——它會因為你超出範圍、偷改驗收標準、或宣稱完成卻沒有證據而**回傳失敗**。

## 七道檢查

`check.ps1` 檢查的全部是「不需要自動測試也能驗」的東西：

| # | 檢查 | 擋住什麼 |
|---|------|----------|
| 1 | **acceptance／envelope 凍結** — 已簽核的驗收標準或 envelope 約束被改動，且 commit 沒帶簽核 trailer | 把標準改鬆讓它過 |
| 2 | **evidence gate** — feature 翻 `passing` 但證據沒有逐條對應 | 「做好了」其實沒驗證 |
| 3 | **範圍邊界** — 動到的檔案不在該 feature 宣告的 `scope_paths` 內 | agent 順手改到不該碰的地方 |
| 4 | **索引同步** — `system-notes/` 有新檔但索引沒更新 | 知識寫了沒人找得到 |
| 5 | **schema 自檢** — 讀不到預期欄位、參照指向不存在的條目、或前置條件出現循環，就 **FAIL-CLOSED 並明講** | 防線無聲失效卻看起來很健康 |
| 6 | **簽核關卡** — `passing` 但驗收標準根本沒被簽核過 | 跳過人工確認直接做完 |
| 7 | **前置條件** — feature 宣告 `passing`，但它的 `prerequisites` 還在 `failing` | 依賴沒做完就宣稱完成，或依賴宣告根本是錯的 |

第 5 條是這套的體檢：**一道會無聲倒塌的牆，比沒有牆更危險——因為你以為它還在。**

## 大工作：envelope + slice

一條 feature 裝不下的工作（跨 3 條以上、或跨前端＋後端＋資料），在**規劃期**就切開，不要等動工後才發現要拆——acceptance 一旦簽核凍結，事後拆要走取代流程，很貴。

```jsonc
{
  "envelopes": [
    { "id": "E1", "outcome": "...", "constraints": [...], "non_goals": [...], "frozen": false }
  ],
  "features": [
    { "id": "F12", "envelope": "E1", "prerequisites": ["F11"], "non_goals": [...], "rollback": null }
  ]
}
```

- **envelope 先簽核，再逐條談 slice。** slice 就是 feature，不另立一套 ID，`features` 維持平坦陣列
- envelope 的 `constraints` 與 `non_goals` 簽核後**與 acceptance 同級凍結**（gate 1 擋）——底下每個 slice 都是在那組約束下被核准的
- `prerequisites` 決定順序，也決定能不能平行；指向不存在的條目或形成循環會被 gate 5 擋
- 小工作不必開 envelope，`envelopes` 留空陣列、feature 的 `envelope` 填 `null`

## 怎麼用

**這個 kit 是安裝來源，不是專案的一部分。** 裝完它就該消失，留下來的是 `AGENTS.md`、`.harness/`、`docs/`。

在你的專案根目錄：

```powershell
git clone https://github.com/RyanLeeYi/project-harness-kit _harness-kit
```

然後對你的 AI agent 說：

> 讀 `_harness-kit/SETUP.md`，照它的步驟在這個專案裡建立 harness。

建置完成後刪掉來源：

```powershell
Remove-Item _harness-kit -Recurse -Force
```

> 為什麼 clone 進專案裡？因為多數 AI agent 只讀得到當前工作區的檔案。不想放暫存目錄的話，clone 到別處、再把該資料夾加進編輯器的工作區也可以，效果一樣。
>
> `_harness-kit/` 自帶 `.git`，一般不會被誤 commit，但建置完就刪最保險。

`SETUP.md` 是寫給 agent 看的建置指引。它會帶著你——不是替你——決定範圍邊界與驗收標準，因為那兩件事 agent 猜不出來，**猜錯了整套就白建**。

## 這套自己也要被驗證

`check.ps1` 若哪天壞掉——改壞了、環境變了、PowerShell 行為變了——它不會噴錯，只會**安靜地全部放行**。所以 kit 自帶回歸測試：

```powershell
pwsh -File tests/run-tests.ps1
```

13 個情境，每一種該擋的與不該擋的都跑一遍（含 schema 缺欄位、JSON 壞掉這種「防線自己失效」的情況）。改過 `check.ps1` 就跑一次。

其中一個情境是把主控台編碼強制設成 cp950 再跑——v0.1 有個真實的無聲倒塌：PowerShell 用主控台編碼解碼 `git show` 的輸出，繁中 Windows 預設的 cp950 會把中文 acceptance 讀成亂碼，於是 gate 1 在**什麼都沒改**的乾淨狀態下就誤擋。不噴錯、不留線索，只是安靜地擋住每一個 acceptance 寫中文的專案。

同樣的道理也適用於建置完成當下：`SETUP.md` 的最後一步要求你**故意製造一次失敗**，看到 FAIL 才算裝好。**沒驗過的防線等於沒有防線。**

## 這套的上限（先說清楚）

- **evidence 擋不住蓄意造假**，它擋的是「順手宣稱完成」
- **簽核擋不住偽造**：agent 有寫檔權限就能自己填簽核欄位。它擋的是「無意間跳過」。要真正防偽造，簽核得走 repo 之外的權威來源（PR approve）
- **`check.ps1` PASS ≠ 功能做對了**。它檢的是流程合規；功能對不對，靠驗收標準本身的驗證，那是人做的

知道上限才用得對。把 PASS 當成「驗收通過」是這套最容易被誤用的方式。

## 相關

個人版的通用框架（三級漸進、完整模板組、雙語）：[harness-for-builders](https://github.com/RyanLeeYi/harness-for-builders)。這個 kit 是它的團隊／無 CI 變體——把強制力從「本地設定」搬到「隨 repo 走的腳本 + 既有的 PR 關卡」。

MIT License.
