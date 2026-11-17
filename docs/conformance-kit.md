# 一致性验收套件（Conformance Kit）

> 版本：2026-11-18　语料：`mooncalc-corpus/1`，1,267 条答案键（桌面 Excel 生成）
> 角色：把“以真实 Excel 为唯一裁判”的验收方法做成可复用基础设施。MoonCalc 是第一个接入者，不是套件的所有者；任何引擎（包括 `mbtexcel`）都可以接入，且不需要引用 MoonCalc 的代码或数字。

## 1. 为什么需要一把公开的尺子

MoonBit 生态里“有没有公式引擎”已经有答案：`moonbitlang/mbtexcel@0.3.2` 自带公式求值，折叠 `_XLFN.` 与 `XdotY` 拼写后约 **438 个规范函数名**，并负责 `.xlsx` 读写（证据：[comparison-mbtexcel.md](comparison-mbtexcel.md) 的能力矩阵）。

但“算得对不对”缺少公共裁判。mbtexcel 的上游自述与门禁是 **excelize parity**：

- `README.mbt.md:6`：“A pure MoonBit library for reading and writing Microsoft Excel (XLSX) files. This is a port of the popular Go excelize library.”
- `README.mbt.md:397-416`：parity gate 指向 `../scripts/test_parity_gates.sh` 与 `../docs/excelize-parity.md`、`../docs/parity-commands.md`；这些文件**不在发布包内**。
- 发布包内**没有真实 Excel 答案键，也没有 `.xlsx` fixture**（包内 `*.xlsx` 计数为 0）。

“与另一个库一致”是有效的工程目标，但它不能推出“与 Excel 一致”：另一个库自身的语义偏差会被当成正确行为继承下来，而它的门禁不会报告这些偏差。本套件补的正是这一层——**一组由真实桌面 Excel 生成的答案键 + 一套公开的桶/归因规则 + 一个任何引擎都能实现的适配器契约**。裁判席上只有 Excel，MoonCalc 不在裁判席上。

## 2. Kit 构成

| 部件 | 位置 | 说明 |
| --- | --- | --- |
| 语料 schema | [`corpus/schema.md`](../corpus/schema.md) | `mooncalc-corpus/1`；多工作表 / 定义名称 / 整列整行为向后兼容扩展（可选 `names` 字段、`SHEET!A1` 键） |
| 答案键 | [`corpus/cases/`](../corpus/cases/) | 1,267 条，9 个 JSON 文件；来源、生成器与 SHA-256 见 [PROVENANCE.md](../corpus/cases/PROVENANCE.md) |
| 生成器 | [`corpus/excel/generate_corpus.bas`](../corpus/excel/generate_corpus.bas) | 桌面 Excel VBA：`GenerateCorpus` 全量、`GenerateCorpusOne` 单批；用法见 [corpus/excel/README.md](../corpus/excel/README.md) |
| 桶与归因规则 | [`corpus/schema.md`](../corpus/schema.md) §比较策略 + 本文件 §2.2 | 精确/容差/类型/解析/崩溃/不可比，全部单列 |
| 参考适配器 | [`examples/compare/`](../examples/compare/) | 独立 MoonBit 模块，**不 import mooncalc**，重写桶规则；已用于 mbtexcel 差分 |
| 语义探针（单列） | [`corpus/probes/probes.json`](../corpus/probes/probes.json) | 12 条，用于观察边界语义，不进入 1,267 主分母 |

### 2.1 答案键与分母

- 生成环境：桌面 Excel 2024，版本 2610 / Build 16.0.20527.20196（64 位，zh-CN）；VBA 宏逐条写入输入与公式、强制重算、读取答案格，再由宏导出 JSON。生成方式与逐文件指纹见 [PROVENANCE.md](../corpus/cases/PROVENANCE.md)。
- 分母构成：
  - 8 个函数族 spec 共 1,171 条 → 导出 1,169 条（2 条奇数参数 `IFS` 被 Excel 拒绝录入，见 `corpus/cases/logic.skipped.txt`）。
  - M8 refs 批 106 条 → 导出 103 条（3 条非法/重复定义名称被 Excel 拒绝录入，见 `corpus/cases/refs.skipped.txt`）→ **裁定后 98 条**（5 条移出：`INDIRECT`/`SUMSQ`/`COUNTBLANK` 超出 60 函数声明子集，1 条迭代关闭的环瞬态属非稳态；原答案键保留在 [`corpus/excluded/refs-out-of-subset.json`](../corpus/excluded/refs-out-of-subset.json)，不伪造、不计分）。
  - 验收分母 = 1,169 + 98 = **1,267**。
- 当前逐文件指纹（2026-11-18 由仓库字节重算；`sha256sum corpus/cases/*.json` 可复核）：

| 文件 | 条数 | SHA-256 |
| --- | --- | --- |
| `date.json` | 113 | `f408050cc8dd02a2a4adf50e2375d743f935825e48e8aa6331d823816820b9b4` |
| `generic.json` | 237 | `e7ee6fb5244a6d85f0eb4a8eba43698b5bede45d46e18a1d4e105badd04df88b` |
| `iter.json` | 18 | `e98782af9c0090c7de44b462e4c1ddf6a1ab0a052338bf7f74d350815ca68d9e` |
| `logic.json` | 101 | `c47adef20a1e1ed3af850a5c0d16451060221bf43b38a0d2a2b715f9bf08c99e` |
| `lookup.json` | 135 | `cc01ec452a429e9b3063a8f2e8b097242e243a64a454f688e3cc47379c14f47b` |
| `math.json` | 168 | `0418ab5950e31d63f96760c7e0601a7bac0c96768c01de48b947ce1f66813196` |
| `refs.json` | 98 | `1415b4da47ba0e7f197717f9636b2760ef85b6f92a437f6678e6467d82903eb7` |
| `stat.json` | 131 | `33b268f6924a43ffc9de3656c8c2150e57fe1f595b6165a6219363b0e7ad5465` |
| `text.json` | 266 | `53cb234ed7670ccf57de134517e91cf7e7f6aea6083abc0d04fab1d0797532ce` |

> 注：[PROVENANCE.md](../corpus/cases/PROVENANCE.md) 的逐文件表记录首次导出批次；其中 `iter.json` 一行写的是 17:09 的旧哈希 `49c146b3…`，该文件在 17:33 因控制组用例重生成（见该文件「M7 裁定记录」），以上表为重算后的仓库字节。其余 8 个 cases 文件与 PROVENANCE 表一致。该旧哈希行属于源文档的已知滞后，本套件不改动已冻结的语料与溯源文件。

### 2.2 桶规则（分类顺序即优先级）

| 桶 | 判定 | 计通过？ | 说明 |
| --- | --- | --- | --- |
| `match` | 值与类型精确相等（数值按 Double） | ✅ | 默认要求 |
| `excel-precision` | 数值相对差 ≤ `1e-14` | ✅ | Excel/VBA 只能以 15 位有效数字序列化答案，此量级是表征差 |
| `clock-tolerance` | 带 `clock` 标签且数值绝对差 ≤ `clock-tol`（默认 `1e-6` 天） | ✅ | `now` 由生成器在同一次重算中捕获 |
| `surrogate-representation` | 文本按孤代理对归一后相等 | ✅ | VBA 把半代理对序列化为 U+FFFD |
| `numeric-tolerance` | 相对差介于 `1e-14` 与 `tol`（默认 `1e-9`）之间 | ❌ | 单列计失败，避免把“差不多”混进通过 |
| `value-mismatch` | 同类型、值不同 | ❌ | |
| `type-mismatch` | 类型不同（含“应得错误却得数值”） | ❌ | |
| `parse-error` | 被测引擎拒绝解析/求值该公式 | ❌ | 适配器需保留引擎原始错误文本 |
| `engine-crash` | 进程崩溃（信号） | ❌ | 适配器需先定位到单条记录再归因，避免整批中断 |
| `clock-no-injection` | 带 `clock` 标签，但引擎无时钟注入 API | ❌（不计通过） | **不可比不冒充通过**：即使宿主时钟偶然一致也不改桶 |

相对差定义：`rel_diff(a,b) = |a-b| / max(|a|,|b|)`，零尺度视为相等。所有失败必须落桶并写入 `failures[]`（`id` / `formula` / `tags` / `expected` / `actual` / `bucket` / `detail`），**不设“其他”桶**。

### 2.3 归因字段

报告另带 `attribution`，用于披露“引擎能力”而不是给通过率注水：

- `attribution.clock`：`tagged_records` 33、`exact_matches_if_compared` 9；说明引擎无注入、`NOW`/`TODAY` 读宿主时钟、该桶不计通过。
- `attribution.iteration`：`tagged_records` 18、`with_settings` 17；说明迭代设置可存但求值单趟，结果如实记录。
- `by_source` 区分 `excel-desktop`（权威）与 `manual`（过渡，非权威）；对外指标只用前者。

## 3. 适配器契约（接入自己的引擎）

参考实现是 [`examples/compare/`](../examples/compare/)（约 1,200 行 MoonBit，只依赖被测引擎、`moonbitlang/x` 与 core）。它刻意不 import MoonCalc、不复用 MoonCalc 的比较代码——桶规则是独立重写的第二实现。

### 3.1 硬性要求

1. **独立**：适配器不得 import `buguoshixc/mooncalc`，不得调用其 bench/比较代码；只调用被测引擎的公开 API。
2. **逐条隔离**：每条记录新建工作簿/求值上下文；记录之间不共享状态（定义名称、工作表、迭代设置都要在记录结束后清理/丢弃）。
3. **写入 grid**（与 [`corpus/schema.md`](../corpus/schema.md) 一致）：JSON 数字 → 数值；字符串 → 文本（含文本型数字）；`true`/`false` → 布尔；`null` → 空白；`{"formula":"=..."}` → 公式；`{"error":"#N/A"}` → 错误值。`SHEET!A1` 键创建命名工作表，裸 `A1` 键写主表；`names` 字段写入引擎的名称存储（引擎没有名称存储时，该记录按实际结果/不支持处理，不得伪造）。
4. **答案格**：把 `formula` 原样写入固定单元格（参考实现写主表 `ZZ1`；主表名 `MoonCalcMain`，若记录本身占用该名则改名），调用**单格求值入口**（参考实现 `Workbook::calc_cell_typed`）。
5. **值态映射（五态）**：number / text / bool / error / blank（`None` 视为 blank）；blank 归一为数值 0 与 harness 一致；错误按 `#...#` 字符串名比较。
6. **分类**：按 §2.2 顺序判定；容差可用 `--tol` / `--clock-tol` 覆盖并写入报告。
7. **时钟**：引擎支持注入时用记录的 `now`；不支持 → `clock-no-injection`，不得计通过。
8. **迭代**：记录带 `iter` 时，按 `max_iterations`/`max_change` 求值；引擎若“存设置但求值不读”，如实计失败并在 `attribution.iteration` 披露。
9. **崩溃**：单条记录崩溃时，适配器应二分/隔离到该记录并记 `engine-crash`，不让整批中断。

### 3.2 第三方接入步骤

1. 复制 `examples/compare/` 或自写适配器（只需要被测引擎的“建工作簿 + 写格 + 单格求值”三件事）。
2. 把 `--corpus` 指向本仓库的 `corpus/cases`（只读）。
3. 输出报告 JSON，字段至少包含：`engine`（名称/版本/工具链）、`total`、`passed`、`failed`、`rate`、`tolerances`、`buckets`、`by_source`、`by_tag`、`failures`、`attribution`、`rerun`（确切命令）。
4. 用同一桶规则与 [`corpus/reports/real.json`](../corpus/reports/real.json)（MoonCalc 的 1,267/1,267）对照；差异逐条归因。
5. 报告放在你自己的仓库/发布页即可；套件不要求注册、授权或联系维护者。

### 3.3 复跑命令（2026-11-18 已实跑验证）

```bash
export PATH="$HOME/.moon/bin:$PATH"

# 1) 被测引擎（示例：MoonCalc 自身，1,267/1,267）
bash scripts/run-bench.sh

# 2) 第三方引擎（示例：mbtexcel 0.3.2，独立适配器；写 _build，不覆盖权威报告）
mkdir -p _build/conformance
(cd examples/compare && moon run --target native . -- \
  --corpus ../../corpus/cases \
  --report ../../_build/conformance/mbtexcel.json)
```

期望输出（mbtexcel 0.3.2）：`total=1267 passed=1023 failed=244`，桶计数 `match 1019`、`excel-precision 3`、`surrogate-representation 1`、`value-mismatch 106`、`type-mismatch 99`、`parse-error 4`、`engine-crash 2`、`clock-no-injection 33`。

**不要**把 `--report` 指向 `corpus/reports/mbtexcel.json`：权威报告只由维护者在确认结果后更新；日常复跑写 `_build/` 即可。

### 3.4 已接入引擎（同一份 1,267 条答案键）

| 引擎 | 通过 | 失败 | 通过率 | 备注 |
| --- | --- | --- | --- | --- |
| 桌面 Excel（判官/答案键生成者） | 1,267 | 0 | 100% | VBA 逐条重算后读答案格 |
| MoonCalc（本仓库） | **1,267** | 0 | **100%** | 1,247 match + 16 excel-precision + 3 clock-tolerance + 1 surrogate |
| mbtexcel 0.3.2（参考适配器） | 1,023 | 244 | 80.74% | 桶分解见 §3.3；33 条时钟不可比 |

12 条语义探针另计：mbtexcel 6/12（1 value + 5 type），MoonCalc 10/12（未过的 2 条是 `SUMSQ`/`COUNTBLANK` 不在 60 函数声明子集内，按公开契约返回 `#NAME?`）。探针用于观察边界，不进入主分母，也不改变上表。

**复跑核验（2026-11-18）**：用上述命令重跑 mbtexcel 适配器，`total`/`passed`/`failed`/`buckets`/`by_source` 与权威报告逐项一致，失败 id 集合与按 id 的桶完全一致；唯一变化是 33 条 `clock` 记录的 `actual` 值（宿主时钟，报告已在 `attribution.clock` 声明）。这条“除时钟外可复现”的性质由适配器自身保证，不是维护者的口头承诺。

## 4. 边界与诚实声明

- **判官是采样行为，不是规范**：答案键来自桌面 Excel 2024（2610 / 16.0.20527.20196 / zh-CN）的实测行为。套件只声称“与本机 Excel 一致”；不同 Excel 版本/区域设置可能存在差异，欢迎用同一生成器在别的版本上重采。
- **覆盖是声明子集**：60 个函数 + M8 核心引用语义（跨表/定义名称/整列整行）。子集外函数返回 `#NAME?` 是公开契约，不是“与 Excel 相同”；完整 Excel 不在本套件范围内。
- **不可比单列**：33 条时钟记录在无注入引擎上记为 `clock-no-injection`，不计通过；5 条越界/非稳态用例移出分母并保留原答案键；12 条探针不进入主分母。
- **不评性能、文件 IO、格式**：套件只回答“公式结果是否与 Excel 一致”。与 excelize parity 是不同目的，不互斥，也不替代。
- **“生态首个”的范围**：截至 2026-11-18，在我们可核验的公开 MoonBit 包/仓库范围内，这是首个以真实 Excel 答案键为唯一裁判的公开验收套件。若有更早的公开套件，欢迎指出，我们改口径——这句话本身也应被当作可证伪的声明。
- **许可**：本仓库 MIT；答案键由 Excel 行为生成，可自由用于验收与回归。

## 5. 复核清单

```bash
# 语料指纹（与 §2.1 表对照）
sha256sum corpus/cases/*.json

# 报告指纹（权威报告，随仓库入库）
sha256sum corpus/reports/real.json corpus/reports/mbtexcel.json corpus/reports/mbtexcel-probes.json
# real.json              427c2b51cf69c0d499cdbc6088f066081cc726a49a5f96a9dc7f414dd68e46bc
# mbtexcel.json          94e46b1a398cfe8a91ab51326db72716bd6bfe29c07fe1fd95d6eac2486a9178
# mbtexcel-probes.json   c4f73e49ea69e39d743b3ae981ec0a631ab14b0dbe94687a22f5b200a6e5fd90

# 本套件自身的数字：MoonCalc 1,267/1,267；mbtexcel 1,023/1,267（§3.3 命令）
```

## 6. 相关文档

- 语料 schema 与桶规则：[`corpus/schema.md`](../corpus/schema.md)
- 来源、生成器、逐文件指纹与裁定记录：[`corpus/cases/PROVENANCE.md`](../corpus/cases/PROVENANCE.md)
- 桌面 Excel 生成步骤：[`corpus/excel/README.md`](../corpus/excel/README.md)
- 参考适配器与方法说明：[`examples/compare/README.md`](../examples/compare/README.md)
- mbtexcel 差分全文（能力矩阵 / 口径继承 / 架构能力）：[`docs/comparison-mbtexcel.md`](comparison-mbtexcel.md)
