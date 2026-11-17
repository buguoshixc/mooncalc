# 产品边界为纯引擎库加薄 CLI，不碰 XLSX 文件

引擎只接受单元格网格、只返回求值结果，不读写 `.xlsx`。这样与 `moonbitlang/mbtexcel`（excelize 移植，仓库内 `CalcCellValue`/`formula` 命中为 0）形成「它读写、我们算」的互补关系，而非竞争关系。

> **更正（M8，2026-11）**：上句“`CalcCellValue`/`formula` 命中为 0”只描述 ADR 0001 时点的仓库状态；mbtexcel **0.3.2 已自带公式解析与求值引擎**（`xlsx/formula_eval.mbt`、`formula_builtins*.mbt`），因此边界互补关系需要重新论证为“读写库 vs 以真实 Excel 答案键验收的计算内核”，实测差分与关系定位见 [ADR 0008](0008-m8-reference-semantics.md) 与 [docs/comparison-mbtexcel.md](../comparison-mbtexcel.md)。本 ADR 其余决定（引擎不碰 `.xlsx`）不变。

## 备选方案

- 引擎 + XLSX 读写集成：演示更直观，但范围翻倍，且与官方 `moonbitlang/office.mbt` 的 formula calculation 路线存在重叠风险（该判断参考 2026-10 时其仓库 TODO；本轮未复核上游现状）。
- 引擎 + 公式审计/依赖分析层：差异化更强，但 16 天内多做一层风险偏高。

## 后果

不碰 XLSX 使引擎有机会被官方 office 项目直接采用，生态增量更明确；代价是演示必须依靠 CLI 与对照报告，而非「打开一个真实表格算给你看」。