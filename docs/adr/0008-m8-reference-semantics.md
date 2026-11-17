# M8 核心引用语义：跨表引用、工作簿级定义名称、整列整行

M7 之前，引擎的引用语义只有「默认表内的 A1 引用与矩形区域」。这带来两个问题：其一，真实工作簿的公式大量使用 `Sheet!A1`、工作簿级名称与 `A:A` 形式的整列聚合，只能被解析为错误；其二，兼容性终点无法定义——「声明子集内的函数语义逐格对齐真实 Excel」不覆盖“引用如何落到单元格”这一层。M8 把这一层补上，并把终点拆成可验收的三层（L1 函数语义 / L2 核心引用语义 / L3 多表工作簿读→算→写），完整 Excel 兼容作为长期路线图、不作承诺。

## 决定

1. **限定键契约**：网格内单元格键为 `SHEET!A1`；表名归一为 ASCII 大写并解 `''` 转义引号；**默认表用空表名＋裸键 `A1`**，旧网格与旧语料（1,169 条）零改动。实现：`src/value/value.mbt` 的 `sheet_key / split_key / valid_sheet_name / parse_qualified_addr / parse_column / parse_row`。
2. **工作簿级定义名称**：`Grid.names : Map[String, String]`（名称→引用文本，如 `Input!$A$1`）。名称在 AST 中是独立节点 `Name(String)`；求值时名称体用空宿主表解析（与 Excel 名称相对工作簿而非当前表一致），递归上限 32，环用 `"NAME:"+名称` 栈守卫——**环上返回 `#NAME?`**（真实 Excel 答案键裁定：`refs-names-011/012` 的成环与自环定义名称均得 `#NAME?`，Excel 把不可解析的名称当作未定义，而不是迭代关闭下的 0；也不标 `circular`）。
3. **整列/整行按 used-range 展开**：`A:A`、`2:2` 展开为该表已用区域的对应列/行范围（`grid.cells` 中该表键的 min/max）；默认空表按 1 行×1 列处理；**不静默截断到固定窗口**。未知整列/整行（或非默认表不存在）→ `#REF!`。
4. **宿主表**：`Ctx.current_sheet` 随求值上下文传播——`cell_value` 按宿主键前缀设置；`Sheet(sheet, expr)` 包装器 save/set/restore；迭代计算与 explain 的探针入口同样设置。区域缓存键（`rkey`）含表名，避免跨表同坐标串缓存。
5. **增量与解释**：`expr_refs(grid, 宿主表, …)` 解析名称与限定引用；名称递归带独立 visited 与深度帽；整列/整行、名称环等不可枚举情形返回 `false`，增量退化为全量（`full_fallback`），explain 退化为纯错误前驱链（`oversized`）并如实披露，不静默丢前驱。`RecalcState` 保存名称快照，名称变化（不在 changed 地址里）触发全量。
6. **显式排除**（解析错误或文档约定）：R1C1、数组字面量 `{}`、交集（空格）与联合、3D 引用 `Sheet1:Sheet3!A1`、外部工作簿链接 `[Book]Sheet!A1`、未加引号的数字开头表名、函数实参中的空占位。

## 已知偏差（书面披露）

- **INDEX 越界语义**：`INDEX` 的 base range 是调用方给出的区域；当 base 是整列（used-range 展开）时，索引到 used-range 之外返回 `#REF!`，而 Excel 对空白单元格返回 0。这是“不静默截断”与“空白格 0 语义”的边界取舍，M8 选择前者，并在 `docs/semantics.md` 记录；整列规格限聚合函数（SUM/COUNT/…）不受影响。
- **表存在性判定**：网格中没有任何该表单元格时视为不存在 → `#REF!`。真实 Excel 答案键已验证“缺表引用”为 `#REF!`（`refs-missheet-001..005`，含 `SUM(NoSheet!A1:A3)`、混合引用），但“存在但整表全空”的表在本项目的网格模型里与缺表不可区分，仍按 `#REF!` 处理（Excel 对空表引用返回 0）；该差异保留为书面披露，等待能表达“空表存在性”的语料格式后再裁定。
- **名称作用域**：只实现工作簿级名称；工作表级名称（sheet-scoped）显式排除。

## 答案键裁定（2026-11-17）

- `corpus/cases/refs.json` 由桌面 Excel 2610 生成 103/106 条（3 条非法/重复名称被 Excel 拒绝，见 `refs.skipped.txt`），其中 5 条超出声明子集或属非稳态（`INDIRECT`×2、`SUMSQ`、`COUNTBLANK`、迭代关闭下自增环的单趟值），移入 `corpus/excluded/refs-out-of-subset.json` 并书面说明，不计入验收分母；余 **98 条**全部进入 L2 验收。
- 裁定结果：名称环 → `#NAME?`（本 ADR 第 2 条据此修改）；缺表 → `#REF!`（5 条直接引用答案键，非 `INDIRECT` 转述）；整列/整行、跨表区域、带引号表名、名称链与 `BLOCK` 区域均与 Excel 逐格一致。
- 工程后果：`eval_name` 环分支由“0 + circular”改为 `Err(Name)`；`m8_test` 与本文档同步。W3 差分报告据此重跑（1,267 条，含 `engine-crash` 桶）。

## 后果

- 引用语义与函数语义分层验收：L2 的验收不再依赖函数覆盖广度；L3 由 `examples/xlsx-demo` 的多表端到端演示给出。
- 旧 API 完全向后兼容：`eval_at(addr, …)` 保留，新增 `eval_at_key(key, …)`；网格键、codec、CLI（`--names`）、bench、playground 共用同一契约。
- 增量重算在“不可枚举依赖”时牺牲性能换正确性（全量回退），报告字段 `full_fallback` 保持可见。
- 与 mbtexcel 的关系：其 0.3.2 已含公式求值，本项目的差异化回到“真实 Excel 答案键语料 + 语义深度 + 增量/解释 API”，引用广度上承认对方更宽（详见 `docs/comparison-mbtexcel.md`）。
