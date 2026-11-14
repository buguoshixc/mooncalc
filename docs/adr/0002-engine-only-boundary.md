# 产品边界为纯引擎库加薄 CLI，不碰 XLSX 文件

引擎只接受单元格网格、只返回求值结果，不读写 `.xlsx`。这样与 `moonbitlang/mbtexcel`（excelize 移植，仓库内 `CalcCellValue`/`formula` 命中为 0）形成「它读写、我们算」的互补关系，而非竞争关系。

## 备选方案

- 引擎 + XLSX 读写集成：演示更直观，但范围翻倍，且正面撞上官方 `moonbitlang/office.mbt` 已排期的 formula calculation 与 cache refresh（其 TODO.md 将 Formula verification/cache refresh 明确列在 Deferred 段）。
- 引擎 + 公式审计/依赖分析层：差异化更强，但 16 天内多做一层风险偏高。

## 后果

不碰 XLSX 使引擎有机会被官方 office 项目直接采用，生态增量更明确；代价是演示必须依靠 CLI 与对照报告，而非「打开一个真实表格算给你看」。