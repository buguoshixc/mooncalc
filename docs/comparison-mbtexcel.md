# MoonCalc vs mbtexcel 0.3.2：能力矩阵与语义差分

> 日期：2026-11-17（2026-11-18 增补「口径继承」与「架构能力矩阵」；2026-11-21 M9 更新）　被测版本：`moonbitlang/mbtexcel@0.3.2`（钉死，`moon info` 与 `moon.mod` 均记录）　MoonCalc：本仓库 `main`（M9 完成后）
> 判官：**桌面 Excel 2026-11-17 生成的旧批答案键**（`corpus/cases/` 中 1,267 条；环境见 [corpus/cases/PROVENANCE.md](../corpus/cases/PROVENANCE.md)）。M9 新增的 238 条数组/交集与 23 条 spill 引用答案键**不在本差分内**（mbtexcel 适配器尚未扩展数组通道）；本文件不把旧 1,267 分母冒充 1,528。
> 本文件中的每个数字都能用文末命令从仓库重跑；报告与哈希一并入库。

## 一句话结论

mbtexcel 0.3.2 是**功能宽度远大于 MoonCalc 的 XLSX 库**（含公式求值，约 438 个规范函数名），但在“旧批 1,267 条公式语义”上，用同一份真实 Excel 答案键做差分，**1,267 条里通过 1,023 条（80.7%）**；244 条失败全部逐条落在五个桶里（没有“其他”桶），每桶都有代表行与归因（见下）。MoonCalc 在同一份旧批答案键上 **1,267/1,267**；加上 M9 数组批与 spill 引用批后全量 **1,528/1,528**（该批不在本差分内）。两者的定位不同：mbtexcel 解决“读写 xlsx + 尽量算”，MoonCalc 解决“把当前覆盖的公式语义算得和 Excel 一样，并把不可枚举依赖做成增量/可解释 API”；完整终点见 [ADR 0009](adr/0009-full-conformance-endpoint.md)。

诚实让步放在最前面：

- **函数广度**：mbtexcel 约 438 个规范函数名（发布包两张 handler 表去重、折叠 `_XLFN.` 前缀与 `XdotY` 拼写后可复算），MoonCalc 当前是 61 个。差距是数量级的，本文件不试图用 61 个函数去论证“更强的电子表格引擎”。
- **文件能力**：mbtexcel 读写 `.xlsx`（工作表、样式、图元等），MoonCalc 核心不碰文件；本项目通过 `examples/xlsx-demo` 把两者组合成读→算→写链路。
- **生态位置**：mbtexcel 是 MoonBit 生态里已有的 XLSX 方案；MoonCalc 的差异化在“真实 Excel 答案键驱动的语义深度 + 增量/解释 + 引用语义的求值一致性”。跨表引用、整列整行、定义名称的**存储 API** 这些单项能力上游也已具备，逐项分层见下方能力矩阵与架构能力矩阵；不声称替代它。

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

注意：上面两条 `--report` 会把结果写回 `corpus/reports/`（这是权威报告的生成方式）；只想核对而不改动入库报告时，把 `--report` 指到 `_build/` 下的临时路径。

适配器 `examples/compare/main.mbt` 只依赖 `moonbitlang/mbtexcel`、`moonbitlang/x` 与 core：它把语料网格逐格写入一个全新工作簿，用 `Workbook::calc_cell_typed` 求值答案格，再按与 `src/codec/bench.mbt` 相同的桶规则（`match` / `excel-precision` / `clock-tolerance` / `numeric-tolerance` / `value-mismatch` / `type-mismatch` / `surrogate-representation`）分类。**报告可复现**：重跑后 `total`/`passed`/`buckets`/失败 id 集合逐项一致；唯一变化是 33 条 `clock` 记录的 `actual` 值（读宿主时钟，报告 `attribution.clock` 已声明），因此重跑报告与入库报告的 SHA 不同是预期行为。

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

失败按公式首个函数归并（前 16）：`(无函数调用)` 31、`TEXT` 28、`TODAY` 15、`NOW` 15、`COUNTIF` 14、`SUMIF` 13、`COUNT` 13、`MATCH` 13、`SUM` 9、`COUNTA` 9、`YEAR` 6、`POWER` 5、`XLOOKUP` 5、`CHOOSE` 5、`SUMPRODUCT` 4、`MEDIAN` 4（合计 189）。其中 30 条是时钟（TODAY/NOW），已包含在上表的 33 条 `clock-no-injection` 里，不重复计；**非时钟失败为 211 条**（244 − 33），由下面的语义缺口解释。

## 能力矩阵（证据均给 `path:line`）

| 能力 | MoonCalc | mbtexcel 0.3.2 | 证据 |
| --- | --- | --- | --- |
| 公式求值 | 61 函数 + M8 引用语义 + M9 数组语义 | 约 438 个规范函数名 | `xlsx/formula_builtins.mbt:133`（`build_raising_handlers`）与 `:252`（`build_plain_handlers`）；折叠 `_XLFN.` 与 `XdotY` 拼写、去重后可复算 438；`README.mbt.md:18` “300+ built-in functions” |
| 跨表引用 `Sheet!A1` / `Sheet!A1:B2` | ✅ | ✅ 基础形态通过 | 探针 `probe-xsheet-ref` 双方通过；`refs-xsheet` 语料 24/26，2 条失败均非“跨表解析”本身（1 条跨表自环、1 条 200 格深链，见本表「循环引用」「依赖深度」两行） |
| 整列/整行 `A:A` / `2:2` | ✅（used-range 展开） | ✅ 基础形态通过（解析器另有 `parse_range_unbounded`） | 探针 `probe-whole-col` 双方通过；语料 wholecol 15/15、wholerow 11/11；上游 `inspect/range.mbt:56/:71` |
| 工作簿级定义名称（存储 API） | ✅ `Grid.names` | ✅ `set/get/delete/get_defined_names` | `xlsx/workbook.mbt:926/961/984/227`、`xlsx/workbook_compat.mbt:89` |
| 工作簿级定义名称（公式求值） | ✅ | ⚠️ 部分可用：24 条名称用例通过 15，失败 9（7 条 `#VALUE!` + 2 条名称环 SIGSEGV） | 探针 `probe-defined-name`（`=Rate*2` 期望 0.14，得 `#VALUE!`）；失败 7 条为 `refs-names-001/002/016/019/020/023/024`。对照：`refs-names-001`（`RATE`→`Data!$A$1`）失败而 `refs-names-013`（`DATA_RATE`→`Data!$A$1`）通过，两者名称体相同、仅标识符不同；失败涉及的 `RATE` 与 `N` 均为上游已注册函数名（`xlsx/formula_builtins.mbt`），`N` 那条还同时含带引号表名因素，未拆分。发布包内有名称求值代码（`xlsx/formula_eval.mbt:2`），补充可观测链：`refs-names-016` 顶层公式 `=A1` 不含名称引用，但其引用的 A1 单元格公式为 `=Rate*2`（记录 `names` 含 `RATE`→`Data!$A$1`），`#VALUE!` 经 A1 传递；本条不能单独区分名称注册层与公式引用层，机制不推断。本表只报告实测 |
| 循环定义名称 | ✅ `#NAME?`（真实 Excel 答案键） | ❌ 实测进程 SIGSEGV | `refs-names-011/012`；适配器二分到单条记录，`engine-crash` 桶（报告 `actual: null`） |
| 循环引用（迭代关闭） | ✅ 环上 = 0 + `circular:true` | ❌ `#CALC!` | 探针 `probe-circular-no-iter`；语料 `refs-xsheet-021`（`Data!A1` 内的裸 `A1` 指回自身，构成跨表自环；Excel 环上=0，mbtexcel `#CALC!`） |
| 依赖深度 | 按 Excel 公式长度限制求值（8192 字符，约 4000 项左结合链，迭代不递归） | ❌ 深链 `#CALC!`（源码上限 128；实测 200 格链失败，未二分阈值） | `docs/semantics.md:48`；`xlsx/formula_parse.mbt:10` `max_depth: 128`、`xlsx/formula_builtins_stats.mbt:1837`；`refs-probe-008`（200 格）与 `probe-200-chain` |
| 迭代计算（`CalcPropsOptions`） | ✅ opt-in API（Excel 默认 100/0.001） | ❌ 设置可存、求值不读（14/18 失败） | 18 条 `iter` 语料：属性经 `set_calc_props` 写入并落到 workbook.xml（`xlsx/workbook.mbt:379/384`、`xlsx/write_workbook_xml.mbt:175`），但求值侧 0 读取（`calc_props` 在 `formula_eval*.mbt`/`formula_builtins*.mbt` 0 命中）；失败 14 = type 12 + value 2 |
| 重算记忆化 | ✅ 网格/区域/公式结果三级缓存 | ❌ 每次调用重算 | `xlsx/workbook.mbt:2116`：“recomputes on every call with no memoization” |
| AST 缓存 | ✅ `ParseCache`（热态 2.6×） | ❌ 每格每次 `parse_formula_expr` | `xlsx/formula_builtins_stats.mbt:1945` |
| 增量重算 API | ✅ 改一格只算下游（5.2×）+ 回退元数据 | ❌ 无 | `grep -rn "pub fn .*recalc"` 0 命中 |
| 错误解释 / 依赖图 | ✅ `explain` + `dependency_graph` | ❌ 无 | 本仓库 `src/engine/explain.mbt`、`incremental.mbt` |
| 系统时钟注入 | ✅ `now` 参数（未注入 → `#NUM!`） | ❌ 硬读 `@env.now()` | 33 条 `clock` 语料不可比 |
| 真实 Excel 答案键语料 | ✅ 1,528 条入库（旧批 1,267 + M9 数组 238 + spill 引用 23；生成器 + 溯源 + 哈希） | ❌ 无 `.xlsx`/答案键 fixture | 发布包内 `find . -name "*.xlsx" \| wc -l` = 0；上游自述的验收目标是 excelize 语义对齐（`README.mbt.md:6`；`:397-416` 指向 `../scripts/test_parity_gates.sh`、`../docs/excelize-parity.md` 等，**这些 docs/scripts 不在发布包内**） |
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
| `probe-200-chain` | 200 格跨表链 `=H5` | `200` | `#CALC!` | 深链失败（源码深度上限常量 128；实测 200 格失败，未二分阈值） |
| `probe-defined-name` | `=Rate*2`（RATE→`Data!$A$1`=0.07） | `0.14` | `#VALUE!` | 实测三种写法（`=Rate`、`=Rate*2`、`=SUM(Rate,1)`）均 `#VALUE!`；本探针只记录该可观测行为 |

探针汇总：mbtexcel **6/12 通过**（6 条偏差：1 条 `value-mismatch` + 5 条 `type-mismatch`）；MoonCalc **10/12**，未过的 2 条（`SUMSQ`、`COUNTBLANK`）是**函数尚未实现**（结果 `#NAME?`，属于公开缺口 M10，不是“语义判错”，也不是验收范围外）。语义探针口径：MoonCalc 10/10。

全语料里同源的偏差还有：

- **统计口径**：`COUNT` 把区域内的布尔值与“数字样文本”计入（`stat-count-0001` 得 3，Excel 2；`stat-count-0002` 得 2，Excel 1；`stat-count-0004` 得 3，Excel 1），且区域内出现错误值时直接返回该错误（`stat-error-0002` 得 `#N/A`，Excel 的 `COUNT` 忽略错误）；`COUNTA` 同类（9 条）。
- **criteria 语义**：`COUNTIF`/`SUMIF` 的大小写不敏感、`~*`/`~?` 通配转义、`<>x` 否定语义缺失（`COUNTIF` 14 条、`SUMIF` 13 条失败）。
- **查找**：`MATCH` 的类型匹配、大小写不敏感与通配符缺失（13 条）。
- **TEXT**：格式串语义与 Excel 不同（28 条）：`TEXT(1.5,"0.??")` 应 `"1.5 "` 得 `"1.5"`（少尾随空格）；`TEXT(1234567,"0,,")` 应 `"1"` 得 `"1234567,,"`（不缩放）；`TEXT("abc","0")` 应原样返回 `"abc"` 却得 `#VALUE!`；`TEXT(TRUE,"0")` 应 `"TRUE"` 得 `"1"`；`TEXT(123,"General")` 应 `#VALUE!` 得 `"123"`；`TEXT(2.675,"0.00")` 应 `"2.68"` 得 `"2.67"`。
- **日期**：`DATE` 的 1900 闰日与年偏移（`date-date-0008` `=DATE(1900,2,29)` 应 60 得 61、`date-date-0010` `=DATE(100,1,1)` 应 36526 得 `#NUM!`、`date-date-0011` `=DATE(1899,12,31)` 应 693962 得 0）；`date-year-0003` `=YEAR(0)` 应 1900 得 1899；`date-year-0008` `=YEAR(日期文本)` 应解析得年份，实际 `#VALUE!`。
- **数值**：`gen-round-0012` `=ROUND(1.005,2)` 应 1.01 得 1；`math-power-0002` `=POWER(-1,0.5)` 应 `#NUM!` 却返回**数值 `NaN`**；`math-power-0003` `=POWER(0,0)` 应 `#NUM!` 得 1；`gen-power-0005` `=POWER(0,-1)` 应 `#DIV/0!` 得 `Infinity`；`math-floor-0006/0007` 与 `math-ceiling-0006/0007` 应 `#DIV/0!`/0 却得 `NaN`。全语料 `NaN` 6 条、`Infinity` 1 条。
- **`SUM` 对区域布尔值**：`math-sum-0002` 应 1 得 2（Excel 的 `SUM` 忽略区域内的布尔值）；另 `refs-probe-002` `=SUM("abc",2)`（在主分母内）应 `#VALUE!` 得 2（直接文本实参应报错）。

## 口径继承：为什么“补函数”追不平这些偏差

### 证据等级（先划清）

| 命题 | 依据 | 等级 |
| --- | --- | --- |
| mbtexcel 0.3.2 在某条用例上的输出 | `corpus/reports/mbtexcel.json` 的 `failures[]`（`id`/`formula`/`expected`/`actual`/`bucket`/`detail`），按上文命令可重跑 | 实测，可复现 |
| mbtexcel 注册了哪些函数 | 发布包 `xlsx/formula_builtins.mbt:133` 与 `:252` 两张 handler 表 | 静态可核（发布包字节） |
| excelize（Go）自身的逐条输出 | **未实测**；只引用上游自述“port of excelize”与 parity gate 目标（`README.mbt.md:6`、`:397-416`） | 上游自述，不逐条断言 |

本文所有“excelize”出现处只指**上游自述的验收目标**，不指其运行时输出；不声称 excelize 对任何一条公式会返回什么。

### 244 条失败的桶合计

| 桶 | 条数 | 可复现性 |
| --- | --- | --- |
| `value-mismatch` | 106 | 是 |
| `type-mismatch` | 99 | 是 |
| `clock-no-injection` | 33 | `actual` 随宿主时钟漂移，桶/id 稳定 |
| `parse-error` | 4 | 是（`detail = engine: InvalidXml(msg="formula args invalid")`） |
| `engine-crash` | 2 | 是（二分到单条后不再调用引擎，`actual: null`） |
| **合计** | **244** | |

### 代表行（逐条可在报告的 `failures[]` 中按 id 检索）

| 语义缺口 | 代表用例（Excel 答案键 → mbtexcel 0.3.2） | 桶 | 同缺口条数 |
| --- | --- | --- | --- |
| 数值边界以 `NaN`/`Infinity` 代替错误值或正确值 | `math-floor-0006/0007` `=FLOOR(±5,0)`：`#DIV/0!` → number `NaN`；`math-ceiling-0006/0007` `=CEILING(±5,0)`：0 → `NaN`；`math-power-0002` `=POWER(-1,0.5)`：`#NUM!` → `NaN`；`math-power-0003` `=POWER(0,0)`：`#NUM!` → 1；`gen-power-0005` `=POWER(0,-1)`：`#DIV/0!` → `Infinity` | type-mismatch | 8（`NaN` 6 + `Infinity` 1 + 错值 1） |
| 文本大小写映射 | `text-proper-0011` `=PROPER("ßeta")`：`ßeta` → `ßEta`；`text-proper-0010` `=PROPER("ÜBER cool")`：`Über Cool` → `ÜBer Cool` | value-mismatch | 2 |
| `TEXT` 格式串 | `text-text-0006` `=TEXT(1.5,"0.??")`：`"1.5 "` → `"1.5"`；`text-text-0009` `=TEXT("abc","0")`：`"abc"` → `#VALUE!`；`text-text-0143` `=TEXT(2.675,"0.00")`：`"2.68"` → `"2.67"` | value-mismatch | 28 |
| 迭代计算 | `iter-self-diverge-0001`（A1=`=A1+1`，100/0.001）：101 → `#CALC!`；`iter-self-converge-0002`：1.9990234375 → `#CALC!`；`iter-text-cycle-0007`：`"0xx"` → `"#CALC!x"` | type 12 + value 2 | 14（/18） |
| 时钟不可比 | `TODAY`/`NOW` 类（答案键注入 `now`）→ 读宿主时钟 | clock-no-injection | 33 |
| 定义名称求值 | `refs-names-001` `=Rate`：0.07 → `#VALUE!`；`refs-names-019` `=Rate+Tax`：2.5 → `#VALUE!` | type-mismatch | 7（全部涉及与内置函数同名的标识符 `RATE`/`N`；`RATE` 与 `DATA_RATE` 的名称体同为 `Data!$A$1`，前者失败、后者通过，对照见能力矩阵；补充可观测链：`refs-names-016` 顶层公式 `=A1` 不含名称引用，但其引用的 A1 单元格公式为 `=Rate*2`（记录 `names` 含 `RATE`→`Data!$A$1`），`#VALUE!` 经 A1 传递；本条不能单独区分名称注册层与公式引用层，机制不推断） |
| 名称环崩溃 | `refs-names-011/012`：`#NAME?` → SIGSEGV | engine-crash | 2 |
| 错误字面量作实参 | `logic-iferror-0007` `=IFERROR(1/0,#N/A)`、`lookup-xlookup-0033`、`gen-count-0009`、`gen-counta-0005` → 解析拒绝 | parse-error | 4 |
| 深链 / 跨表自环 | `refs-probe-008` 200 格链：200 → `#CALC!`；`refs-xsheet-021`（`Data!A1` 内裸 `A1` 指回自身）：0 → `#CALC!` | type-mismatch | 2 |

上表 9 类合计 100 条；其余 144 条是同族函数的语义差（`COUNT`/`COUNTIF`/`SUMIF`/`MATCH`/`DATE`/`SUM`/`XLOOKUP` 等），逐条归因见 `failures[]` 的 `detail` 与上一节清单。

### 这些失败没有一条是“函数不存在”

- 244 条失败中，213 条至少含一个函数调用，共涉及 **43 个不同函数名**；这 43 个全部出现在上游发布的 438 个规范函数名里，且**没有一条** `actual` 是 `#NAME?`（未知函数）——失败发生在“已经注册的函数”的语义细节上。
- 其余 31 条不含函数调用（运算符、字面量、单元格引用），补函数与它们无关。
- 因此“补函数”只能改变这 43 个名字之外的新函数；对上述 244 条中的任何一条都不起作用：
  - `FLOOR(5,0)` 仍返回数值 `NaN`，不会变成 `#DIV/0!`；
  - `PROPER("ßeta")` 仍返回 `ßEta`；
  - 18 条迭代用例里 14 条仍 `#CALC!`；
  - 33 条时钟用例仍读宿主时钟；
  - 2 条名称环用例仍会让进程崩溃。
- 要追平这些，必须换裁判（真实 Excel 答案键）、逐条归因到实现、再改已有函数——不是加函数。这就是 MoonCalc 的裁定循环（M7/M8 两次记录见 `corpus/cases/PROVENANCE.md`），也是本文所说“口径”而非“数量”的净贡献。

### 口径如何决定“哪些缺陷能被发现”

以“与另一个库一致”为验收函数：该库未覆盖的 Excel 语义不会进入任何用例，偏差会被继承为“正确”；以“与 Excel 一致”为验收函数：偏差在第一次跑分就暴露，并被迫逐条裁定。两者的差别不是投入多少，而是**验收函数的定义域**不同。

三条诚实边界，必须与上面的结论一起读：

- 本表只描述 **mbtexcel 0.3.2 在 2026-11-18 的实测**，不预测上游未来版本；也不声称 excelize 本身有同样偏差。
- 上游若把 parity 目标换成真实 Excel 答案键，这 244 条就是它的第一份待裁定清单；尺子已可直接接它，见 [conformance-kit.md](conformance-kit.md)。
- 33 条时钟失败是“不可比”而非“算错”：mbtexcel 没有注入契约，报告把它们单列，不并入 106/99 的语义失败。

## 架构能力矩阵（公开 API 面）

mbtexcel 的公开 API 面取自发布包 0.3.2 的 `pub fn` 与文档注释（可在 [mooncakes 的 module_index](https://mooncakes.io/docs/moonbitlang/mbtexcel) 对照）；MoonCalc 取自 `facade.mbt`。只比较**公开可调用能力**，不比较内部实现，也不假设第三方不能在其上自建。

| 能力 | mbtexcel 0.3.2 公开 API | MoonCalc（`facade.mbt` / 实测） | 证据 |
| --- | --- | --- | --- |
| 整网格依赖重算 | ❌ 只有单格入口 `calc_cell_value`/`calc_cell_typed`（`xlsx/workbook.mbt:2026`/`:2119`），无 `recalc` API | ✅ `recalc` 全网格拓扑重算 | `facade.mbt:119`；上游 `grep "pub fn .*recalc"` 0 命中 |
| 增量重算 + 全量等价 | ❌ 无更新 API；每次调用重算且无 memoization（`xlsx/workbook.mbt:2116`） | ✅ `recalc_init`/`recalc_update`/`recalc_update_report`；10 万格改一格 5.2×；500 轮 fuzz（300 混合回退 + 200 快路径）与全量等价 | `facade.mbt:149/160/174`；`src/engine/incremental_test.mbt:205/212`；`docs/performance.md` |
| 错误解释 + 依赖图 | ❌ 无 `explain`/`dependency` API | ✅ `explain`/`explain_at_key`/`dependency_graph`；依赖不可枚举时显式降级 | `facade.mbt:224/233/245` |
| 迭代计算（opt-in，Excel 围栏） | ❌ 设置可存不可用：`CalcProps` 仅 `get_calc_props`/`set_calc_props`（`xlsx/workbook.mbt:379/384`）并写入 workbook.xml（`xlsx/write_workbook_xml.mbt:175`），求值侧 0 读取；18 条 iter 语料 14 条失败 | ✅ `recalc_iterative`/`eval_formula_iterative`（`IterOptions`，Excel 默认 100/0.001）；18 条答案键全过（M7 裁定） | `facade.mbt:197`；`corpus/reports/mbtexcel.json` 的 `attribution.iteration` |
| 系统时钟注入（确定性） | ❌ 无注入 API；`NOW`/`TODAY` 直接 `@env.now()`（`xlsx/formula_builtins_eval_date_time.mbt:642/658`）；33 条不可比 | ✅ `now: Option[Double]` 契约，未注入 → `#NUM!`；33 条 clock 全过（30 精确 + 3 容差） | `facade.mbt`；`docs/semantics.md` |
| 零 IO 纯核心 + 双目标 + 交互 playground | 库/CLI 可构 wasm（`README.mbt.md:369-370`，CLI 需 nightly 的 wasm fs）；求值绑定 `Workbook` 对象并读宿主时钟；包内含 xlsx 读写与 demos | ✅ 核心 grep 禁止 `@fs`/`@sys`/`println`/`extern "C"`；native + wasm-gc 双目标构建；`playground/` 交互页 smoke 39 断言 | `scripts/check.sh:17`；`README.md`；`playground/smoke.html` |

四条脚注，防止误读：

1. **上游能构 wasm**：README 明写库与 CLI 都可构 wasm；差异不在“能否编译 wasm”，而在“零 IO 纯核心契约 + 双目标同测 + 浏览器内交互 playground”。
2. **单格入口 ≠ 整网格 API**：`calc_cell_typed` 每次调用重算、无记忆化（源码注释自述）；增量/解释/迭代在其公开 API 里不存在。第三方当然可以在其上自建，但那是第三方代码，不是它的能力。
3. **R1C1 是当前缺口**：上游另有 R1C1 入口 `calc_cell_typed_rc`/`calc_cell_value_rc`（`:2076`/`:2144`）；MoonCalc 的 R1C1 仍是未实现里程碑（M11），不是“验收范围外”。
4. **计数口径**：438 由两张 handler 表（564 个注册条目：80 个 `_XLFN.` 别名、46 个 `XdotY` 拼写）去重、折叠后得到；这是“注册名”数，不代表每个都达到 Excel 语义（本文 244 条失败即为反证）。

## 复现边界与分母口径

- MoonCalc 的判官只有桌面 Excel：旧批 1,267 条答案键由 VBA 生成器在同一台 Excel 2610 上逐条重算后读出，M9 数组批 238 条与 spill 引用批 23 条由 COM 探针 harness 生成（生成器、溯源、SHA-256 全入库），比较桶规则公开。代价是当前函数面仍窄（61 函数）与语料生成需要桌面 Excel 会话。
- 两者的“通过率”不在同一分母上：mbtexcel 的 1,267 条里有 33 条时钟用例它**无法**参与比较（无注入 API），我们把它单列为 `clock-no-injection` 而不是算失败；即便把这 33 条全部按通过计，mbtexcel 也只有 1,056/1,267（83.3%）。
- 重跑边界：`total`/`passed`/`buckets`/失败 id 集合可复现；33 条 clock 的 `actual` 随宿主时钟变化，因此重跑报告的 SHA 与入库报告不同，这是报告已声明的预期漂移。

## 何时用谁

- 要**读写 xlsx / 样式 / 大而全的函数面**：用 mbtexcel。
- 要**把当前覆盖的公式语义算到与 Excel 逐格一致**、需要**增量重算/错误解释/确定性时钟**、或要把 xlsx 计算接进自己的服务：用 MoonCalc；需要文件能力时按 `examples/xlsx-demo` 组合两者（读→算→写，核心零 IO）。
