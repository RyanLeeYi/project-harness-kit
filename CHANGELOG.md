# Changelog

格式：新的在上。

## 未發佈

### Fixed

- **`check.ps1` 在繁中 Windows 上無聲誤擋**：PowerShell 用 `[Console]::OutputEncoding` 解碼 native 指令的 stdout，主控台預設 cp950 時 `git show` 讀回來的中文 acceptance 全是亂碼，基準版本與工作區永遠比不相等——gate 1 在**什麼都沒改**的乾淨狀態下就 FAIL。不噴錯、不留線索，等於擋住每一個 acceptance 寫中文的專案。修正是在腳本開頭把 `[Console]::OutputEncoding` 設為 UTF-8；回歸測試新增一個把主控台強制設成 cp950 的情境（沒有 cp950 的平台會 skip 而不是假通過）

## v0.1（2026-07-28）

首次發佈。

- `check.ps1` — 六道檢查（acceptance 凍結、evidence gate、範圍邊界、索引同步、schema 自檢、簽核關卡），日常與 `-Promote` 兩種模式，輸出可貼進 PR 的 markdown 報告
- `init.ps1` — 前置檢查 + pre-commit hook 安裝
- 模板組 — `AGENTS.md`（唯一入口）、`CLAUDE.md` 薄殼、`feature_list.json`、`session-handoff.md`、`ARCHITECTURE.md`
- `SETUP.md` — 給 AI agent 讀的建置指引
- `pr-template.md` — PR 描述模板
- `tests/run-tests.ps1` — 12 個情境的回歸測試
