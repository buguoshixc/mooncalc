# 权威语料回传记录（provenance）

本目录 `corpus/cases/*.json` 由真实桌面 Excel 计算生成，来源可复现。

## 生成环境

| 项 | 值 |
| --- | --- |
| 生成日期 | 2026-11-15 17:08–17:09 (Asia/Shanghai)；同一配置连续运行两次，采用第二次（17:09:31–17:09:36）输出 |
| Excel 版本（文件 → 帐户 → 关于 Excel） | Microsoft® Excel® 2024 MSO（Microsoft Office 家庭版 2024 / Home2024Retail；zh-CN） |
| 完整版本号 | 版本 2610；Build 16.0.20527.20196（64 位；Click-to-Run 即点即用；当前频道 / Production::CC） |
| COM 报告 | `Application.Version` 16.0 / `Build` 20527 / `OperatingSystem` Windows (64-bit) NT 10.00 |
| 生成器 | `corpus/excel/generate_corpus.bas`（`GenerateCorpus`，含按用例迭代设置支持；11,315 bytes / 314 行模块；SHA-256 `dc4eae007f0d6032f904a26afb6b73124fd2df8219939b66314850bd9272e74b`） |
| 生成工作簿 | `corpus/excel/generator.xlsm`（新建工作簿 → 另存为启用宏工作簿 → 导入上述 .bas；34,393 bytes；SHA-256 `1668180a6460d4872fed6b7f8a4a6563e5b38fc587818dcfce6f3328026fe856`） |
| 生成方式 | 桌面 Excel COM 自动化：新建工作簿 → `SaveAs(.xlsm)` → 导入 .bas → `Application.Run "GenerateCorpus"`（等价于手动 Alt+F11 导入 + Alt+F8 运行；导入 VBA 模块临时开启 Excel「信任对 VBA 工程对象模型的访问」，生成后已还原为未设置） |
| 规格输入 | `corpus/spec/*.tsv`（8 文件 / 1,171 条：date 113、generic 237、iter 18、logic 103、lookup 135、math 168、stat 131、text 266） |
| 结果 | 导出 1,169/1,171 条；2 条被 Excel 拒绝录入（见下节，`logic.skipped.txt`） |
| 计算模式 | 宏内临时改为手动计算、逐条强制重算；带 `iter` 规格的用例在填写/读取期间临时启用 `Application.Iteration` 并设置 `MaxIterations`/`MaxChange`，读取后立即还原（默认关闭），下一用例不受上一用例设置影响 |
| 弹窗 | 仅宏结束时出现一次「Corpus generation complete: 8 spec file(s).」；无循环引用弹窗（迭代先于填充启用 + `DisplayAlerts=false`） |
| 确定性 | 两次运行（17:08 与 17:09）除 `NOW()` 捕获值外逐条一致；`iter.json` 两次 SHA-256 相同（`49c146b3…`） |
| 生成证据 | Windows 工作目录 `C:\mooncalc_work3\`（`run.log`、`watcher.log`、`spec/`、`cases/`、`excel/generator.xlsm`） |

## 文件清单（SHA-256 / 条数）

| 文件 | 条数 | SHA-256 |
| --- | --- | --- |
| `date.json` | 113 | `f408050cc8dd02a2a4adf50e2375d743f935825e48e8aa6331d823816820b9b4` |
| `generic.json` | 237 | `e7ee6fb5244a6d85f0eb4a8eba43698b5bede45d46e18a1d4e105badd04df88b` |
| `iter.json` | 18 | `49c146b317177457c039059ad3115381468eb9e2776d72106aa520fac1e4d4f9` |
| `logic.json` | 101 | `c47adef20a1e1ed3af850a5c0d16451060221bf43b38a0d2a2b715f9bf08c99e` |
| `lookup.json` | 135 | `cc01ec452a429e9b3063a8f2e8b097242e243a64a454f688e3cc47379c14f47b` |
| `math.json` | 168 | `0418ab5950e31d63f96760c7e0601a7bac0c96768c01de48b947ce1f66813196` |
| `stat.json` | 131 | `33b268f6924a43ffc9de3656c8c2150e57fe1f595b6165a6219363b0e7ad5465` |
| `text.json` | 266 | `53cb234ed7670ccf57de134517e91cf7e7f6aea6083abc0d04fab1d0797532ce` |
| **合计** | **1,169** | — |
| `logic.skipped.txt` | 2 | `48b571b5e71db4b6ae81952cd9869a0506ef93a9107abef1ef3442c5f41b5e3a` |

## 基准结果

- `corpus/reports/real.json` 仍是上一版 1,001 条基准（1,001/1,001），**本版未覆盖**。（2026-11-15 更新：裁定修正后已重跑并覆盖为 1,169/1,169，见提交 390eb26、dc14323。）
- 本版首次 bench 预览（`scripts/run-bench.sh corpus/cases`，只读、未写报告）：**1,153/1,169（98.6%）**；桶计数 match 1,135、clock-tolerance 3、excel-precision 15、type-mismatch 2、value-mismatch 13、numeric-tolerance 1。
- 16 条失败均来自本轮新增答案键对临时语义的裁定点（见下节），尚无引擎修正；裁定并修正后重跑 bench、更新 `real.json` 与 `docs/`。

### M7 待裁定失败（首次 bench，16 条）

| 组 | 用例 | Excel 答案键 | 引擎当前 | 说明 |
| --- | --- | --- | --- | --- |
| 迭代 | 12 条（`iter-*`） | 见 `iter.json` | 差 1 轮 / 迭代序 / 判停细节 | 围栏：Excel 在 N 轮后仍多一次求值（100→101、32767→32768）；收敛判停与迭代序（`self-converge-0002`/`two-converge-0018` 1.9990234375 vs 2，`mutual-0003` 403 vs 399，`maxchange-0004` 0.001 vs 0.05，`single-0005` 2 vs 1）；文本环 "0xx" vs "0xxxxx"；`max_change=1000` 语义（2 vs 100）；迭代关闭对照 1 vs 0；`tight-tol-0012` 尾差 3.2e-11 落 numeric-tolerance |
| FLOOR | `math-floor-0006` `=FLOOR(5,0)`、`math-floor-0007` `=FLOOR(-5,0)` | `#DIV/0!` | `0` | Excel 对 FLOOR 的 sig=0 返回 `#DIV/0!`；CEILING(x,0) 的 Excel 答案为 0，与临时语义一致（`zero-significance` 其余 2 条通过） |
| 文本 | `text-proper-0011` `=PROPER("ßeta")` | `"ßeta"` | `"ßEta"` | Excel 视 ß 为有大小写字母（词内不切分）；引擎词边界规则使后一字母大写 |
| 文本 | `text-replace-0006` `=REPLACE("😀abc",2,1,"X")` | `"�Xabc"`（U+FFFD） | 含孤立代理项 | 语料把 Excel 半代理对结果记为 U+FFFD（`EF BF BD`；VBA→ADODB UTF-8 序列化观察值，单元格内部可能是孤立代理项）；引擎按 UTF-16 码元切割后产生孤立高代理项 D83D，无法以 JSON 文本表达 |

### 工具问题（裁定前需处理）

- 孤立代理项无法 UTF-8 编码：`mooncalc bench --report` 写报告时 panic（`invalid surrogate pair`，`cmd/main/main.mbt:152` → `@fs.write_string_to_file`）；默认 stdout 在首个孤立代理项处截断（`text-replace-0006` 的 FAIL 明细及其后的 `text-proper-0011` 未出现在输出中）。裁定该用例前需先决定文本表示（U+FFFD 归一，或显式不可表示并跳过），并修 `Json` 序列化 / 报告输出路径。

## 与上一版（1,001 条）的差异

- 上一版 1,001 条用例 id 全部保留；其中 990 条 `expected` 完全一致（0 处行为差异；含 16 条 `TODAY` 用例仅 `now` 更新、同日 `expected` 不变）。
- 11 条 `NOW()` 派生用例因生成时刻从 11:14 变为 17:09 更新了 `now`/`expected`：`date-now-0001/0002/0005/0006/0007/0008/0011/0012/0014/0015/0016`；bench 按 `--clock-tol` 判定。
- 新增导出 168 条：150 条 M7 新函数答案键（logic 15、lookup 15、math 30、stat 45、text 45）+ 18 条迭代计算（新文件 `iter.json`）。
- 2 条奇数参数 IFS 仍被拒绝，`logic.skipped.txt` 不变。
- 逐文件条数变化：logic 86→101（+15）、lookup 120→135（+15）、math 138→168（+30）、stat 86→131（+45）、text 221→266（+45）、iter 0→18（新）、date 113 与 generic 237 不变。

## 迭代计算答案键（`iter.json`，18 条）

- 17 条带 `iter` 字段，1 条（`iter-off-control-0016`）不带 → 覆盖「迭代关闭」对照（其前面的用例已启用迭代，用于验证设置已还原）。
- 设置组合：`100:0.001` ×11、`1:0.001`、`5:0.001`、`6:0.001`、`100:1e-10`、`32767:0.001`、`100:1000` 各 1。
- Excel 2024 实测要点：`max_iterations=100` 的发散环（`A1=A1+1`）答案为 101，上限用例（32767）为 32768（Excel 在 N 轮后仍多一次求值/读取）；文本环得到 `"0xx"`，布尔环 FALSE，错误环 `#DIV/0!`；迭代关闭对照（`=A1`，A1=A1+1）为 1；收敛环（100 轮）为 1.9990234375。期望值类型：number 15、text 1、bool 1、error 1。
- 这些值是对 `docs/semantics.md`「迭代计算（opt-in）」中围栏 / 迭代序 / 收敛细节的直接裁定依据；引擎对齐属后续任务。

## 跳过用例（Excel 拒绝录入，spec 标记 `subset-out`）

| 用例 | 公式 | 原因 |
| --- | --- | --- |
| `logic-ifs-0005` | `=IFS(TRUE,1,FALSE)` | IFS 参数个数为奇数（缺少成对的值参数），Excel 拒绝录入（VBA 设置 `Formula` 返回 1004 错误） |
| `logic-ifs-0015` | `=IFS(A1>0,IFS(A1>5,"big","mid"),TRUE,"neg")` | 内层 IFS 参数个数为奇数，同上 |

Excel 无法为「奇数参数 IFS」产生任何答案值，因此该行为不可复现；引擎按 `docs/semantics.md` 返回 `#VALUE!`；这是 Excel 拒录的非法输入，不是标准语义，spec 已加 `subset-out` 标签，不进入基准分母。

## 已知注意

- **`text-textjoin-0021`（`=LEN(TEXTJOIN("",TRUE,A1:B1))`，A1/B1 各 20,000 字符）**：真实 Excel 返回 `#CALC!`（VBA 错误码 2050）；生成器 `ErrName` 已显式映射 `2050 → #CALC!`，引擎 `XlError` 亦新增 `Calc` 变体，基准按错误值精确比对通过。
- 文件为 UTF-8 带 BOM（VBA `ADODB.Stream` 行为）；`logic.skipped.txt` 同样带 BOM（首行 id 前有 U+FEFF，读时按 UTF-8-sig 处理）。CLI 读取时会剥除 BOM（`@codec.strip_utf8_bom`）。
- 数值由 VBA `CStr` 输出，有效数字上限 15 位；bench 对这类表征差单独计入 `excel-precision` 桶（相对差 ≤1e-14，通过并披露），不掩盖真实行为差异。
- `now` 字段：宏在写入答案公式的**同一次重算**里，把 `=NOW()` 写进辅助格 `ZY1`，`Application.Calculate` 后读回该格序列值（15 位十进制）。因此 `now` 与答案格的 `NOW()`/`TODAY()` 是同一计算时刻的同一 double 值，而不是 VBA `Now`（整秒截断）。
- 含 `TODAY`/`NOW` 的用例若与答案格仍有 <1e-6 天的差（例如派生比较产生的尾差），bench 按 `clock_tol`（绝对天数）判定并单列 `clock-tolerance` 桶。
- 日期系统固定为 1900（含 Lotus 幻影日 serial 60）；1904 日期系统不在子集内。
- 迭代设置：`Application.Iteration` 仅在存在打开工作簿时可设置（无工作簿时 COM 抛 `0x800A03EC`），生成器在填写前启用、读取后还原；Excel 上限 `MaxIterations=32767` 实测可用（约 0.3 s/用例）。
- 文本代理项：Excel 的 UTF-16 半代理对结果经 VBA→ADODB UTF-8 序列化后记录为 U+FFFD，见上文「M7 待裁定失败」；对含孤立代理项的引擎结果，JSON 报告与 stdout 当前均不可用。
- 生成证据留存于 Windows 工作目录 `C:\mooncalc_work3\`（`run.log`、`watcher.log`、`spec/`、`cases/`、`excel/generator.xlsm`）。

## M7 裁定记录（2026-11-15）

- 本批 1,169 条（含 M7 新增 150 函数 + 18 迭代）接入 bench：1,168/1,169（99.9%）。
- 迭代语义裁定：初始 1 轮 + 至多 N 轮、每轮后查收敛、非数值变化不阻止收敛
  （引擎据此修正围栏与 delta 解包，12 条迭代差异全部修复）。
- FLOOR(x,0)=#DIV/0!（与 CEILING(x,0)=0 不对称）、PROPER 视 ß 为字母，均已按答案键修正。
- REPLACE 半代理对（text-replace-0006）：VBA 将孤代理对序列化为 U+FFFD，单列
  surrogate-representation 桶披露通过；引擎保留原始 UTF-16 码元。
- iter-off-control-0016：迭代刚关闭时 VBA 单步 Application.Calculate 对自增环返回
  瞬态 1（非稳态语义）。spec 改为非环控制（=A1*2, A1=5）后于 17:33 重新生成，通过。
- 最终：**1,169/1,169（100%）**，1,149 match + 3 clock-tolerance + 16 excel-precision
  + 1 surrogate-representation，无未归因失败。

> 以下是 M8 时点的历史记录；其中“声明子集”“移出验收分母”是当时口径，已被 ADR 0009 的完整符合性终点取代。当前分母与 1,505/1,505 结果见文末 M9 节。

## M8 refs 批（2026-11-17）

| 项 | 值 |
| --- | --- |
| 生成日期 | 2026-11-17 22:15 (Asia/Shanghai；spec 于 22:14 更新后重生成) |
| Excel 版本 | 版本 2610；Build 16.0.20527.20196（64 位；Home2024Retail；zh-CN） |
| COM 报告 | `Application.Version` 16.0 / `Build` 20527 / `OperatingSystem` Windows (64-bit) NT 10.00 |
| 生成器 | `corpus/excel/generate_corpus.bas`（834 行；SHA-256 `f45fc1eb4a961f6de556e28655871a7cdf99565206d680065b4acc8805eb8340`；模块 `MoonCalcCorpus` 833 行） |
| 生成工作簿 | `corpus/excel/generator.xlsm`（61,505 bytes；SHA-256 `E2B1DCDED523380317FB57774A06DA4BC6E48DAEDA30435487A51AC47187D4D2`；旧 314 行模块已删除并导入上述 .bas） |
| 规格输入 | `corpus/spec/refs.tsv`（106 条，7 列：id/formula/grid/now/tags/iter/names） |
| 生成方式 | 桌面 Excel COM：打开工作簿 → 删除旧 `MoonCalcCorpus` → 导入 .bas → `Application.Run "GenerateCorpusOne"`；临时开启 VBA 工程访问，结束后还原注册表 |
| 计算模式 | 手动计算、逐条强制重算；迭代关闭（无 `iter` 规格）；`DisplayAlerts=false`，未出现循环引用弹窗 |
| 结果 | 导出 103/106 条；3 条被跳过（`refs.skipped.txt`） |
| 弹窗 | 仅结束提示「Corpus generation complete: 1 spec file(s).」 |
| 生成证据 | Windows 工作目录 `C:\mooncalc_work4\`（`run_refs.log`、`watcher_refs.log`、`vbe_check.log`、`spec/`、`cases/`、`excel/`） |

### 本批输出（SHA-256）

| 文件 | 条数 | SHA-256 |
| --- | --- | --- |
| `refs.json` | 103 | `70E5FBD7178BA6A39AEDB6A3856200E2B74240E302E6988A4D01EA1088CAB196` |
| `refs.skipped.txt` | 3 | `F1DD7BFCF44D186F949F1DBCE2F840A43B3A28D6A79AF6D05DE4E2209B47437E` |

### 跳过用例（Excel 拒绝录入）

| 用例 | 原因 |
| --- | --- |
| `refs-names-025` | 定义名称 `A1` 是单元格引用形，非法 |
| `refs-names-026` | 定义名称含空格，非法 |
| `refs-names-027` | 定义名称 `Rate` 与已有 `rate` 大小写重复 |

### 生成器修复（导入前修正的两处 .bas 缺陷）

1. `EvalCase` 内局部变量 `namesJson` 与 `Private Function NamesJson` 同名（VBA 不区分大小写），在 `NamesJson = NamesJson(namesSpec)` 处被编译为字符串下标 → 编译错误「缺少数组」。已把局部变量改名为 `namesField`（第 155/160/223/235 行）。
2. `NamesJson` 起始片段原为 `out = """,""names"":{`，生成 JSON 时多出一个前导 `"`，使含 `names` 的记录在 `}","names"` 处非法。已改为 `out = ",""names"":{`（第 744 行）。

两处修复同时进入 `corpus/excel/generate_corpus.bas` 与工作簿内 `MoonCalcCorpus` 模块；编译检查通过后重新生成。

### 边界观察（供 M8 裁定）

- `refs-probe-004`（`=A1`，A1 为 `=A1+1`，迭代关闭）Excel 返回 `1`。与 M7 记录的「迭代刚关闭时单步重算对自增环返回瞬态 1」一致；原 `iter-off-control` 因该瞬态已改为非环控制，本用例再次覆盖该行为，需在 M8 裁定中明确。
- `refs-probe-008`（`=H5`）Excel 返回 `200`：主表链自 `A1=Data!H20+1=161` 起、至 `H5=200`；`Data!H5` 为 `40`。该用例验证裸 `H5` 绑定主表而非 Data 表，spec 于 22:14 由 `=Data!H5` 改为 `=H5` 并重生成。
- `refs-names-011/012`（成环/自环定义名称）Excel 返回 `#NAME?`，不是 `#REF!`。
- 7 条 `missheet` 用例均返回 `#REF!`。
- `refs-names-021` 为 `COUNT` 类聚合，返回 `3`（非 `SUM` 的 6）。

### 与 W3 的关系

`corpus/reports/mbtexcel.json`（2026-11-17 22:05，mbtexcel 0.3.2）覆盖的是旧 8 个文件 / 1,169 条；本批 `refs.json` 未进入该报告。若 bench 以 `corpus/cases` 目录整体为输入重跑，需注意新增 `refs.json` 会被纳入。

## M8 裁定（2026-11-17，Lead）

generator 已按上表产出 103 条；随后按“声明子集语义”裁定，5 条移出验收分母，最终 **98 条**进入 L1/L2 验收。

| 项 | 值 |
| --- | --- |
| 裁定后 `refs.json` | 98 条，26,946 B；SHA-256 `1415B4DA47BA0E7F197717F9636B2760EF85B6F92A437F6678E6467D82903EB7` |
| 移出文件 | `corpus/excluded/refs-out-of-subset.json`，5 条，2,130 B；SHA-256 `11B6B0C57CE0C5E16F789696233CCAC483FE577A586EF48364EB7B0EA67B5608` |

移出理由（答案键保留，不伪造、不计分）：

| 用例 | 理由 |
| --- | --- |
| `refs-missheet-006/007` | 公式用 `INDIRECT`，该函数不在 60 函数声明子集内；“缺表 → `#REF!`”已由 5 条直接引用答案键（`refs-missheet-001..005`）验证，无需转述路径 |
| `refs-probe-003` | `SUMSQ` 不在声明子集内（文本忽略语义由 `SUM` 探针覆盖） |
| `refs-probe-006` | `COUNTBLANK` 不在声明子集内 |
| `refs-probe-004` | 迭代关闭下自增环的单趟值（Excel 得 1）属非稳态语义，当前契约按“环 = 0 + `circular`”明示披露，不把该瞬态纳入权威答案键 |

裁定结果与代码动作：

- 名称环：`=LoopA` / `=SelfLoop` → Excel 得 `#NAME?`，不是 0、不是 `#REF!`。`src/engine/eval.mbt` 的 `eval_name` 环分支据此改为返回 `Err(XlError::Name)`（不再返回 0，也不再打 `circular` 标），`src/engine/m8_test.mbt`、`docs/adr/0008-m8-reference-semantics.md`、`docs/semantics.md` 同步。
- 缺表：`=NoSheet!A1`、`=SUM(NoSheet!A1:A3)`、混合引用均得 `#REF!`，与实现一致（`refs-missheet-001..005` 通过）。
- `refs-probe-008`（200 格跨表链，答案 `=H5` → 200）通过，验证裸引用绑定主表。
- 全语料（1,169 + 98 = **1,267 条**）MoonCalc 重跑：**1,267/1,267**（`match` 1,247 + `clock-tolerance` 3 + `excel-precision` 16 + `surrogate-representation` 1），无失败。

## 数组 / 交集 / 并集 / 隐式交集批（`arrays.json`，2026-11-21）

| 项 | 值 |
| --- | --- |
| 生成日期 | 2026-11-21 01:17 (Asia/Shanghai) |
| Excel 版本 | 版本 2610；Build 16.0.20527.20196（64 位；Home2024Retail；zh-CN）；`Application.Version` 16.0 / `Build` 20527 |
| 生成器 | `corpus/probes/run_probes.ps1`（PowerShell COM；数据驱动；按 `mode` 用 `Range.Formula`（normal）/ `Range.Formula2`（dynamic）/ `Range.FormulaArray`（CSE）写入并重算；读取标量或选区二维值；SHA-256 `1bb754fa8f31cc814f9e4f1e68caf16bdc64420a2eb8e69d32c043be6fc3b8fe`） |
| 规格输入 | `corpus/probes/arrays.tsv`（238 条，7 列：id/anchor/mode/rows/cols/formula/setup；SHA-256 `09831d1b802dd8aa83a5559c4f0638a35f36e040f145651380c2b74f2567052c`） |
| 原始答案键 | `corpus/probes/arrays.results.json`（238/238 成功，0 条录入失败；SHA-256 `5fde606afa4ea9375bc51e83664bb8db4decc38c40d940689c665e5613b6a078`） |
| 转换器 | `corpus/probes/arrays_to_corpus.py`（只复制 `arrays.results.json` 的答案值，不计算期望值；SHA-256 `5bbc1ecdc55325360062d6924d3f8e4ee531f34b51fb40de62c3d9c7e0afa89b`） |
| 输出 | `arrays.json` 238 条；SHA-256 `159c17ed50f679a3457fed5bd2d96c88734077731f4bea216c1bd8cecdba6f45` |
| 生成命令 | `powershell.exe -NoProfile -ExecutionPolicy Bypass -File corpus/probes/run_probes.ps1 -SpecPath <arrays.tsv 的 Windows 路径> -OutPath <arrays.results.json 的 Windows 路径>`；随后 `python3 corpus/probes/arrays_to_corpus.py` |
| 计算模式 | 每条新建临时工作簿/临时表，写入 setup 网格与公式，`Application.Calculate` 后读取；CSE 用 `Range.FormulaArray` 选中多格；dynamic 用 `Range.Formula2`；normal 用 `Range.Formula`；不启用迭代计算 |
| 基准结果 | `corpus/cases` 全量 **1,505/1,505**：`match` 1,485 + `clock-tolerance` 3 + `excel-precision` 16 + `surrogate-representation` 1；无失败 |

### 收录与排除

- 238 条从探针结果中收录；覆盖：空/单格/多格交集（`#NULL!`）、并集聚合与并集拒绝、`@` 显式交集、隐式交集（行/列/二维/整列整行）、数组字面量与逐元素广播、数组 `IF`、CSE 选区分发（截断/广播/`#N/A`/标量填充）、动态 spill、spill 阻塞 `#SPILL!`、`INDEX` `area_num`。`#` 运算符与 spill 格引用由 `src/engine/array_test.mbt` 和 `examples/array-demo` 覆盖，不在本批答案键内。
- 排除 `p014`/`p015`（`=SUM (A1:A2)` / `=SUM  (A1:A2)`）：真实 Excel 返回 `#NAME?`；引擎按用户要求把 `Ident + 空白 + (` 继续识别为函数调用（`SUM (A1)` 合法），属于**有意记录的分歧**，不进入权威分母。见 `docs/semantics.md`「函数调用与空白」。
- 排除 `p126`（dynamic `=INDEX(A1:C3,0,0)` 写在 C3）：公式覆盖了自身引用区域，Excel 缓存 0 是循环/覆盖瞬态，不是稳定语义；不作为答案键。
- `SEQUENCE`/`OFFSET`/`INDIRECT` 相关探针不进入本批：这三个函数尚未在引擎注册，属于 `docs/adr/0009` 当前缺口清单，待后续里程碑补齐；不以答案键伪装覆盖。
- 239 条有效探针回放中引擎 **236/239** 通过；未过的 3 条即 p014、p015（有意分歧）与 p126（不稳定覆盖探针），理由同上。

### 说明

- 本批答案键来自与既有 1,267 条相同的桌面 Excel 版本，但由独立 COM 探针生成器产生；`arrays.json` 的 `array`/`anchor` 字段是 corpus schema 的扩展（见 `corpus/schema.md`），用于表达 CSE 选区、动态 spill 锚点与普通公式宿主格。
- 本批不包含手写期望值；`arrays_to_corpus.py` 只做结构与类型转换。
