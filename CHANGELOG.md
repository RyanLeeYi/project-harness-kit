# Changelog

格式：新的在上。

## v0.1（2026-07-28）

首次發佈。

- `check.ps1` — 六道檢查（acceptance 凍結、evidence gate、範圍邊界、索引同步、schema 自檢、簽核關卡），日常與 `-Promote` 兩種模式，輸出可貼進 PR 的 markdown 報告
- `init.ps1` — 前置檢查 + pre-commit hook 安裝
- 模板組 — `AGENTS.md`（唯一入口）、`CLAUDE.md` 薄殼、`feature_list.json`、`session-handoff.md`、`ARCHITECTURE.md`
- `SETUP.md` — 給 AI agent 讀的建置指引
- `pr-template.md` — PR 描述模板
- `tests/run-tests.ps1` — 12 個情境的回歸測試
