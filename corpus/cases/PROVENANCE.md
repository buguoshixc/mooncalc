# 权威语料回传记录（provenance）

本目录 `corpus/cases/*.json` 由真实桌面 Excel 计算生成，来源可复现。

## 生成环境

| 项 | 值 |
| --- | --- |
| 生成日期 | 2026-11-15 11:14 (Asia/Shanghai) |
| Excel 版本（文件 → 帐户 → 关于 Excel） | Microsoft® Excel® 2024 MSO（Microsoft Office 家庭版 2024 / Home2024Retail；zh-CN） |
| 完整版本号 | 版本 2610；Build 16.0.20527.20196（64 位；Click-to-Run 即点即用；当前频道 / Production::CC） |
| COM 报告 | `Application.Version` 16.0 / `Build` 20527 / `OperatingSystem` Windows (64-bit) NT 10.00 |
| 生成器 | `corpus/excel/generate_corpus.bas`（`GenerateCorpus`；9,760 bytes；SHA-256 `645e440edbc20a2048f2dddf50c43522b0eb899807386e61304891c203b8a2ae`） |
| 生成工作簿 | `corpus/excel/generator.xlsm`（新建工作簿 → 另存为启用宏工作簿 → 导入上述 .bas；SHA-256 `92e3497ef90ba5f9a9f8c5f495a58b078738505a77cd83cb533efd7c0f81de80`） |
| 生成方式 | 桌面 Excel COM 自动化：新建工作簿 → `SaveAs(.xlsm)` → 导入 .bas → `Application.Run "GenerateCorpus"`（等价于手动 Alt+F11 导入 + Alt+F8 运行；导入 VBA 模块需 Excel 信任对 VBA 工程对象模型的访问，本次临时开启并在生成后还原） |
| 规格输入 | `corpus/spec/*.tsv`（7 文件 / 1,003 条） |
| 结果 | 导出 1,001/1,003 条；2 条被 Excel 拒绝录入（见下节，`logic.skipped.txt`） |
| 计算模式 | 宏内临时改为手动计算、逐条强制重算；结束恢复 |
| 弹窗 | 仅宏结束时出现一次「Corpus generation complete: 7 spec file(s).」，已确认 |

## 文件清单（SHA-256 / 条数）

| 文件 | 条数 | SHA-256 |
| --- | --- | --- |
| `date.json` | 113 | `8e13ad2a343e76a7820a7fba9e75ee8ecaa38e5ef3b210e8af47f43d467f59a2` |
| `generic.json` | 237 | `4010558a4fc5f9630102c65b814b886eb05c925baa1c69b9654dea5b07f0aa42` |
| `logic.json` | 86 | `5c7f7771957b1acaa58280ec5e75f168a969499da4e00907c749515ae108cb6a` |
| `lookup.json` | 120 | `db2367e9a6d60e5a43bd23f0359e4775c8b8696b19227c891e60e74bdb2058d3` |
| `math.json` | 138 | `647fdc3712bbbf4a03a8d0b216e983aeeb4d167b4ac90b18bdf1cb599c863442` |
| `stat.json` | 86 | `8f89f8f0cc5030d2f1a64429f5cea709dfde7733836786b6d257ea7d9b55da7a` |
| `text.json` | 221 | `2ce881c34b4866ed98586f7e8abe1fcfaa1442993befb4c9151efa419f2dc9ba` |
| **合计** | **1,001** | — |
| `logic.skipped.txt` | 2 | `48b571b5e71db4b6ae81952cd9869a0506ef93a9107abef1ef3442c5f41b5e3a` |

## 基准结果

`corpus/reports/real.json`（由 `mooncalc bench --corpus corpus/cases --report corpus/reports/real.json` 生成）：

- 总数 1,001，通过 1,001，通过率 **100%**；
- 容差桶：`match` 996、`clock-tolerance` 4、`excel-precision` 1；
- 全部来源 `excel-desktop`；`#CALC!` 用例（`text-textjoin-0021`）已由本版生成器正确记录。

## 与上一版（752 条）的差异

- 上一版 752 条用例全部保留：其中 719 条确定性用例的 `expected` 完全一致；33 条带 `clock` 标签的用例因生成时刻变为 2026-11-15 而更新了 `now`/`expected`（bench 按 `--clock-tol` 判定，单列 `clock-tolerance`）。
- 新增导出 249 条（`corpus/spec` 本版新增 251 条规格：Batch 3/4 新函数与 TEXT 深化 214 条 + 本轮补充的 37 条裁定探针，后者全部通过；214 条中 2 条奇数参数 IFS 被 Excel 拒录，故导出 212 + 37 = 249 条）。
- 上一版无 `*.skipped.txt`；本次新增 `logic.skipped.txt`（2 条）。

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
- 生成证据留存于 Windows 工作目录 `C:\mooncalc_work2\`（`run.log`、`watcher.log`、`spec/`、`cases/`、`excel/generator.xlsm`）。
