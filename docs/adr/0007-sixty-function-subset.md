# ADR 0007：函数子集扩至 60（新增 10 个通用函数）

- 状态：已接受（2026-11-15）
- 关联：修订 ADR 0003（窄而深）、ADR 0006（约 50 函数）

## 背景

M6 完成后 50 函数子集对真实 Excel 语料 1,001/1,001 全过。表格自动化场景频繁用到
样本统计（STDEV/VAR/PERCENTILE）、文本清洗（REPLACE/SEARCH/PROPER）、倍数舍入
（CEILING/FLOOR）、索引选择（CHOOSE）与逻辑异或（XOR）。

## 决策

子集从 50 扩至 60，新增 10 函数按族列明：

| 族 | 新增 |
| --- | --- |
| 统计 | STDEV、VAR、PERCENTILE |
| 文本 | REPLACE、SEARCH、PROPER |
| 数学 | CEILING、FLOOR |
| 查找 | CHOOSE |
| 逻辑 | XOR |

纪律不变（窄而深）：每函数 ≥15 条规格用例、真实 Excel 2024 答案键裁定、偏差逐条
归因。**不做动态数组**（FILTER/SORT 等 spill 语义突破现有网格契约，改动量级不同，
另立项）。

## 备选方案

- 维持 50：覆盖缺口持续存在，用户需自行组合等价公式。
- 扩到 80+：语料生成与裁定成本线性上升，黑客松周期内不可控。

## 后果

- 语料分母增至约 1,169（1,001 + 150 新函数 + 18 迭代，以实际生成数为准），
  通过率叙事不变（未通过逐条归因）。
- support-matrix / README / semantics 同步 50→60。
- 新函数语义以语料裁定为准：CEILING/FLOOR 符号组合、REPLACE 半代理对切割、
  PROPER 字母判定表、XOR 急切错误传播为最大裁定面；单测期望先按 legacy 文档
  写为 manual 临时值。