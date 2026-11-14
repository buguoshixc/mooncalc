# 函数子集取通用表格自动化口径，约 50 个

子集覆盖六族：逻辑（IF/AND/OR/NOT/IFERROR）、文本（LEFT/RIGHT/MID/LEN/TRIM/UPPER/LOWER/CONCAT/TEXT/VALUE/FIND/SUBSTITUTE）、数学（ROUND/ROUNDUP/ROUNDDOWN/ABS/INT/MOD/POWER/SQRT/SUM/SUMIF/SUMPRODUCT）、统计（AVERAGE/COUNT/COUNTA/COUNTIF/MIN/MAX/MEDIAN）、查找（VLOOKUP/HLOOKUP/INDEX/MATCH）、日期（DATE/YEAR/MONTH/DAY/TODAY/NOW）。

## 备选方案

- 最小核心约 25 个 + 极深边界：通过率更容易做高，但功能面窄、演示单薄。
- 财务/报表专用集（PMT/NPV/IRR/RATE）：垂直差异化强，但语义复杂、验证更难、受众窄，16 天风险高。

## 后果

选择通用口径意味着演示面广、贴合 agent 表格自动化场景，但每族都必须严格对照 Excel 语义，不能只覆盖常见路径。具体函数清单是公开契约，需在文档中逐条列出并标注支持状态。