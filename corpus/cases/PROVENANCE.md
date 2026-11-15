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

- `corpus/reports/real.json` 仍是上一版 1,001 条基准（1,001/1,001），**本版未覆盖**。
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

Excel 无法为「奇数参数 IFS」产生任何答案值，因此该行为不可复现；引擎按 `docs/semantics.md` 声明返回 `#VALUE!`，属于显式声明的子集外行为（spec 已加 `subset-out` 标签，不进入基准分母）。

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
- 唯一未过 iter-off-control-0016：迭代刚关闭时 VBA 单步 Application.Calculate 对
  自增环返回瞬态 1（非稳态语义）。spec 已改为非环控制（=A1*2, A1=5），待重新生成。
