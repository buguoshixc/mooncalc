# MoonCalc vs mbtexcel 0.3.2：能力矩阵与语义差分

> 日期：2026-11-17　被测版本：`moonbitlang/mbtexcel@0.3.2`（钉死，`moon info` 与 `moon.mod` 均记录）　MoonCalc：本仓库 `main`（M8 完成后）
> 判官：**桌面 Excel 2026-11-17 生成的答案键**（`corpus/cases/`，1,267 条；环境见 [corpus/cases/PROVENANCE.md](../corpus/cases/PROVENANCE.md)）。
> 本文件中的每个数字都能用文末命令从仓库重跑；报告与哈希一并入库。

## 一句话结论

mbtexcel 0.3.2 是**功能宽度远大于 MoonCalc 的 XLSX 库**（含公式求值，约 438 个函数名），但在“声明子集内的公式语义”上，用同一份真实 Excel 答案键做差分，**1,267 条里通过 1,023 条（80.7%）**，失败可稳定归因到 6 类语义缺口与 3 类工程缺口（见下）；MoonCalc 在同一份答案键上 **1,267/1,267**。两者的定位不同：mbtexcel 解决“读写 xlsx + 尽量算”，MoonCalc 解决“把声明子集内的公式算得和 Excel 一样，并把不可枚举依赖做成增量/可解释 API”。

诚实让步放在最前面：

- **函数广度**：mbtexcel 约 438 个规范函数名（564 个注册项，含 80 个 `_XLFN.` 别名与 46 个内部点号拼写），MoonCalc 是 60 个。差距是数量级的，本文件不试图用 60 个函数去论证“更强的电子表格引擎”。
- **文件能力**：mbtexcel 读写 `.xlsx`（工作表、样式、图元等），MoonCalc 核心不碰文件；本项目通过 `examples/xlsx-demo` 把两者组合成读→算→写链路。
- **生态位置**：mbtexcel 是 MoonBit 生态里已有的 XLSX 方案；MoonCalc 的差异化只在“真实 Excel 答案键驱动的语义深度 + 增量/解释 + M8 引用语义”，不声称替代它。

## 复跑方式（钉版本）

```bash
# mbtexcel 差分（独立适配器，不 import mooncalc；冷构建约 1 分钟）
cd examples/compare
moon run --target native . -- --corpus ../../corpus/cases  --report ../../corpus/reports/mbtexcel.json
moon run --target native . -- --corpus ../../corpus/probes --report ../../corpus/reports/mbtexcel-probes.json

# MoonCalc 同语料
cd ../..
moon build --target native
_build/native/debug/build/buguoshixc/mooncalc/cmd/main/main.exe bench --corpus corpus/cases --report corpus/reports/real.json
_build/native/debug/build/buguoshixc/mooncalc/cmd/main/main.exe bench --corpus corpus/probes
```

适配器 `examples/compare/main.mbt` 只依赖 `moonbitlang/mbtexcel`、`moonbitlang/x` 与 core：它把语料网格逐格写入一个全新工作簿，用 `Workbook::calc_cell_typed` 求值答案格，再按与 `src/codec/bench.mbt` 相同的桶规则（`match` / `excel-precision` / `clock-tolerance` / `numeric-tolerance` / `value-mismatch` / `type-mismatch` / `surrogate-representation`）分类。**报告可复现**：除 33 条 `clock` 记录的实际值随宿主机时钟变化外，重跑字节一致。

## 三方数字（同一份 1,267 条答案键）

| 引擎 | 通过 | 失败 | 通过率 | 备注 |
| --- | --- | --- | --- | --- |
| 桌面 Excel（答案键生成者） | 1,267 | 0 | 100% | VBA 逐条重算后读答案格 |
| **MoonCalc** | **1,267** | 0 | **100%** | 1,247 match + 16 excel-precision + 3 clock-tolerance + 1 surrogate |
| mbtexcel 0.3.2 | 1,023 | 244 | 80.74% | 见下方桶分解 |

mbtexcel 的 1,267 条桶分解（`corpus/reports/mbtexcel.json`）：

| 桶 | 条数 | 含义 |
| --- | --- | --- |
| `match` | 1,019 | 精确一致 |
| `excel-precision` | 3 | 15 位有效数字表征差内一致 |
| `surrogate-representation` | 1 | 孤代理对表征差（VBA 侧 U+FFFD） |
| `value-mismatch` | 106 | 值不同 |
| `type-mismatch` | 99 | 类型不同（多数为“应得数值却得错误”） |
| `parse-error` | 4 | 引擎拒绝解析 |
| `engine-crash` | 2 | **进程崩溃（SIGSEGV），经二分定位后不再调用引擎、仅归因** |
| `clock-no-injection` | 33 | 无时钟注入 API，时钟类用例不可比（不计入通过） |

失败按公式函数聚类（前 16）：`(无函数调用)` 31、`TEXT` 28、`TODAY` 15、`NOW` 15、`COUNTIF` 14、`SUMIF` 13、`COUNT` 13、`MATCH` 13、`SUM` 9、`COUNTA` 9、`YEAR` 6、`POWER` 5、`XLOOKUP` 5、`CHOOSE` 5、`SUMPRODUCT` 4、`MEDIAN` 4。其中 30 条是时钟（TODAY/NOW），33 条见上表；其余 181 条由下面的语义缺口解释。

## 能力矩阵（证据均给 `path:line`）

| 能力 | MoonCalc | mbtexcel 0.3.2 | 证据 |
| --- | --- | --- | --- |
| 公式求值 | 60 函数 + M8 引用语义 | 约 438 个规范函数名 | `xlsx/formula_builtins.mbt:133`（`build_raising_handlers`）与 `:252`（`build_plain_handlers`）；README.md:18 “300+ built-in functions” |
| 跨表引用 `Sheet!A1` / `Sheet!A1:B2` | ✅ | ✅ | 探针 `probe-xsheet-ref`、语料 `refs-xsheet-*` 双方通过 |
| 整列/整行 `A:A` / `2:2` | ✅（used-range 展开） | ✅ | 探针 `probe-whole-col` 双方通过 |
| 工作簿级定义名称（读写） | ✅ `Grid.names` | ✅ `set_defined_name` / `defined_names` | `xlsx/workbook.mbt:926`、`:227`；`xlsx/defined_name.mbt:3` |
| 工作簿级定义名称（公式求值） | ✅ | ❌ 恒 `#VALUE!` | 探针 `probe-defined-name`（`=Rate*2` 期望 0.14）；`eval_defined_name_ref` 在 `xlsx/formula_eval.mbt:2` 存在但裸标识符进不了解析路径（解析期 `InvalidCellRef`） |
| 循环定义名称 | ✅ `#NAME?`（真实 Excel 答案键） | ❌ **段错误** | `refs-names-011/012`；适配器二分到单条记录，`engine-crash` 桶 |
| 循环引用（迭代关闭） | ✅ 环上 = 0 + `circular:true` | ❌ `#CALC!` | 探针 `probe-circular-no-iter`、语料 `refs-xsheet-021` |
| 依赖深度 | 无固定上限（长链迭代求值） | **128 层后 `#CALC!`** | `xlsx/formula_parse.mbt:10` `max_depth: 128`、`xlsx/formula_builtins_stats.mbt:1837` |
| 迭代计算（`CalcPropsOptions`） | ✅ opt-in API（Excel 默认 100/0.001） | ❌ 属性存而不用 | 18 条 `iter` 语料：属性经 `set_calc_props` 写入，但 `calc_cell_typed` 单趟求值不读（`calc_props` 在 `formula_eval*.mbt`/`formula_builtins*.mbt` 0 命中）；14 条失败 |
| 重算记忆化 | ✅ 网格/区域/公式结果三级缓存 | ❌ 每次调用重算 | `xlsx/workbook.mbt:2116`：“recomputes on every call with no memoization” |
| AST 缓存 | ✅ `ParseCache`（热态 2.6×） | ❌ 每格每次 `parse_formula_expr` | `xlsx/formula_builtins_stats.mbt:1945` |
| 增量重算 API | ✅ 改一格只算下游（5.2×）+ 回退元数据 | ❌ 无 | `grep -rn "pub fn .*recalc"` 0 命中 |
| 错误解释 / 依赖图 | ✅ `explain` + `dependency_graph` | ❌ 无 | 本仓库 `src/engine/explain.mbt`、`incremental.mbt` |
| 系统时钟注入 | ✅ `now` 参数（未注入 → `#NUM!`） | ❌ 硬读 `@env.now()` | 33 条 `clock` 语料不可比 |
| 真实 Excel 答案键语料 | ✅ 1,267 条入库（生成器 + 溯源 + 哈希） | ❌ 无 `.xlsx`/答案键 fixture | `find . -name "*.xlsx" \| wc -l` = 0；验证方式是 excelize 语义对齐（`README.md:407` 指向 `../docs/excelize-parity.md` 与 `test_semantic_parity*.sh`，这些脚本**不在发布包内**） |
| 错误字面量作公式实参 | ✅ | ❌ 解析拒绝 | 4 条 `parse-error`：`logic-iferror-0007`、`lookup-xlookup-0033`、`gen-count-0009`、`gen-counta-0005`（`InvalidXml(msg="formula args invalid")`） |
| 读/写 `.xlsx` | ❌（交给示例壳） | ✅ | `xlsx/workbook.mbt` 读写 API |

## 语义偏差清单（可复现的 6 个探针）

`corpus/probes/probes.json` 12 条，选的是“同一段语义在 Excel 里唯一、且两家都可能踩”的边界；期望值全部来自桌面 Excel 答案键（未回收前标 provisional，现已确认）。

| 探针 | 公式 | Excel 期望 | mbtexcel 实际 | 结论 |
| --- | --- | --- | --- | --- |
| `probe-blank-eq5` | `=A1=5`（A1 空白） | `FALSE` | `TRUE` | 空白参与比较时被当成 0 的错误一侧（Excel：空白 = 0 仅用于算术，比较时空白≠数字） |
| `probe-sum-text-arg` | `=SUM("abc",2)` | `#VALUE!` | `2` | 直接文本实参应报错；文本在**区域**里才忽略 |
| `probe-sumsq-text-range` | `=SUMSQ(A1:A2)`（3, "x"） | `9` | `#VALUE!` | 区域里的文本应被忽略，而非报错 |
| `probe-circular-no-iter` | `=A1`，A1=`=A1+1` | `0` | `#CALC!` | 迭代关闭的环语义：Excel 环上 = 0（单趟瞬态值另计，已移出验收分母） |
| `probe-200-chain` | 200 格跨表链 `=H5` | `200` | `#CALC!` | 依赖深度硬上限 128 |
| `probe-defined-name` | `=Rate*2`（RATE→`Data!$A$1`=0.07） | `0.14` | `#VALUE!` | 定义名称不进公式求值；`=Rate`、`=SUM(Rate,1)` 同样 `#VALUE!` |

探针汇总：mbtexcel **6/12 通过**（6 条偏差：1 条 `value-mismatch` + 5 条 `type-mismatch`）；MoonCalc **10/12**，未过的 2 条（`SUMSQ`、`COUNTBLANK`）是**函数不在 60 条声明子集内**（结果 `#NAME?`，属于公开契约“子集外 = `#NAME?`”，不是语义判错）。语义探针口径：MoonCalc 10/10。

全语料里同源的偏差还有：

- **统计口径**：`COUNT` 把区域内的布尔值与“数字样文本”计入（`stat-count-0001` 得 3，Excel 2；`stat-count-0004` 得 3，Excel 1），且区域内出现错误值时直接返回该错误（`stat-error-0002` 得 `#N/A`，Excel 的 `COUNT` 忽略错误）；`COUNTA` 同类。
- **criteria 语义**：`COUNTIF`/`SUMIF` 的大小写不敏感、`~*`/`~?` 通配转义、`<>x` 否定语义缺失（`COUNTIF` 14 条、`SUMIF` 13 条失败）。
- **查找**：`MATCH` 的类型匹配、大小写不敏感与通配符缺失（13 条）。
- **TEXT**：格式串语义与 Excel 不同（28 条）：`TEXT(1.5,"0.??")` 少尾随空格、`TEXT(1234567,"0,,")` 不缩放、`TEXT("abc","0")` 应 `#VALUE!`、`TEXT(TRUE,"0")` 应 `"TRUE"`。
- **日期**：`DATE` 的 1900 闰日与年偏移（`DATE(100,1,1)` 应 36526 得 `#NUM!`、`DATE(1899,12,31)` 应 693962 得 0、`DATE(1900,2,29)` 应 60 得 61）；`YEAR(0)` 应 1900 得 1899；`YEAR(日期文本)` 应解析得年份，实际 `#VALUE!`。
- **数值**：`ROUND(1.005,2)` 应 1.01 得 1；`POWER(-1,0.5)` 应 `#NUM!`，实际返回**数值 `NaN`**（类型也错）。
- **`SUM` 对区域布尔值**：`sum-0002` 应 1 得 2（Excel 的 `SUM` 忽略区域内的布尔值）。

## 方法论差异（为什么数字不能反向解读）

- mbtexcel 的正确性目标是 **excelize（Go）语义对齐**：README.md:6 自述 “port of the popular Go excelize”，README.md:407 的 parity 文档与脚本不在发布包内；包内**没有任何真实 Excel 答案键或 `.xlsx` fixture**。因此“它是 excelize 的移植、公式计算仍是空白”这类旧说法需要更新为两句话：**公式引擎已存在**（这是事实）；**它没有用真实 Excel 答案键做逐格验收**（这是可验证的差异）。
- MoonCalc 的判官只有桌面 Excel：1,267 条答案键由 VBA 生成器在同一台 Excel 2610 上逐条重算后读出（生成器、溯源、SHA-256 全入库），比较桶规则公开。代价是覆盖面窄（60 函数）与语料生成需要人工/N 次桌面 Excel 会话。
- 两者的“通过率”不在同一分母上：mbtexcel 的 1,267 条里有 33 条时钟用例它**无法**参与比较（无注入 API），我们把它单列为 `clock-no-injection` 而不是算失败；即便把这 33 条全部按通过计，mbtexcel 也只有 1,056/1,267（83.3%）。

## 何时用谁

- 要**读写 xlsx / 样式 / 大而全的函数面**：用 mbtexcel。
- 要**把声明子集内的公式算到与 Excel 逐格一致**、需要**增量重算/错误解释/确定性时钟**、或要把 xlsx 计算接进自己的服务：用 MoonCalc；需要文件能力时按 `examples/xlsx-demo` 组合两者（读→算→写，核心零 IO）。
