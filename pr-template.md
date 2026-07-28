## Feature

<!-- feature id 與一句話。例：F1 — 新增折扣計算 -->

## Harness Check

<!--
執行：pwsh -File .harness/check.ps1 -Promote -Report docs/evidence/check-<feature>-<日期>.md
把報告內容貼在下面。審核者從這裡就能看到：動了哪些檔案、有沒有超出範圍、
驗收標準逐條的證據對不對，不用自己去翻 feature_list.json。
-->

```
<< 貼上 check 報告 >>
```

## 風險與備註

<!--
這次改動可能影響到什麼？有沒有暫時的繞道、待辦的技術債？
沒有就寫「無」。
-->

---

<!--
提醒：check PASS 只代表流程合規（沒偷改驗收標準、沒超範圍、證據有對上）。
功能到底對不對，看的是上面 acceptance 逐條的證據本身。
-->
