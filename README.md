# MoonCalc

**Excel 兼容的电子表格公式引擎，用 MoonBit 编写。**

> 状态（2026-11-14，M5 完成）：45 函数引擎（**MoonBit**）、native CLI、wasm-gc playground 已实现并通过四层验证；**真实 Excel 答案键语料 752/752（100%）**（Excel 2024 · 16.0.20527.20196 · zh-CN 生成，0 跳过），无未归因失败：748 条精确命中 + 3 条 `clock-tolerance` + 1 条 `excel-precision`（均在报告披露）。2026 MoonBit 年度黑客松 11 月赛参赛项目。

## 这是什么

MoonCalc 接收一组单元格——每个单元格承载字面值或公式——按 Excel 语义求值并返回结果或错误值。它不读写 `.xlsx` 文件，文件读写交给 mbtexcel 这类工具，MoonCalc 只负责计算。

项目走“窄而深”的路线：首批只实现 45 个核心函数，覆盖逻辑、文本、数学、统计、查找、日期六族；每个函数的弱类型强制转换、错误值传播和边界情形都要严格对照真实 Excel。正确性用真实 Excel 生成的答案键语料逐条验证，对外公开用例数和通过率，未通过的用例逐条归因。

## 快速开始

```bash
export PATH="$HOME/.moon/bin:$PATH"

# 全量验证：双目标构建 + 63 项单测 + 零 IO 守卫
bash scripts/check.sh

# CLI：求值一个含引用链/错误传播/循环引用的网格
moon build --target native
_build/native/debug/build/cmd/main/main.exe eval --grid tests/fixtures/grid.json

# 跑分：真实 Excel 权威语料（默认 corpus/cases）
bash scripts/run-bench.sh

# 浏览器 playground（wasm-gc）
bash scripts/build-playground.sh
(cd playground && python3 -m http.server 8080)   # 打开 http://localhost:8080/

# headless Chromium 冒烟（12 断言，零 npm 依赖）
node scripts/smoke.mjs
```

完整演示脚本见 [docs/demo.md](docs/demo.md)。

## 正确性指标（诚实口径）

| 层 | 数字 | 性质 |
|---|---|---|
| 单元/快照测试 | 63/63 | 手写期望（引擎语义回归 + codec + 语法 + bench 桶） |
| 过渡语料 bench | 34/34（100%） | source: manual，**非权威**，仅证明流程 |
| 用例规格 | 752 条（corpus/spec/，每函数 ≥15） | 已由真实 Excel 全部生成答案键（0 跳过） |
| **真实 Excel 语料** | **752/752（100%）** | Excel 2024 为唯一裁判；0 条未归因失败，见 `corpus/reports/real.json` |

比较策略：默认精确相等；**15 位有效数字表征差**（相对差 ≤1e-14）单列 `excel-precision` 桶并通过（源头是 Excel/VBA 只能以 15 位十进制序列化答案）；`clock` 用例按**绝对天数**容差（`--clock-tol`，默认 1e-6 天）单列 `clock-tolerance` 桶并通过（`now` 由生成器在同一重算里经 `=NOW()` 辅助格捕获）；相对差 <1e-9 仍单列 `numeric-tolerance` 桶计失败并归因。权威报告：`corpus/reports/real.json`。

## 设计要点

- **纯计算核心，不做任何 IO**：同一份核心同时编译到 native 和 wasm-gc；`scripts/check.sh` 机械守卫（双目标构建 + grep 禁 `@fs`/`@sys`/`println`）。native 侧跑答案键语料对照，wasm-gc 侧做浏览器 playground。
- **输入是内存网格契约**：单元格网格是唯一数据契约，JSON 序列化跨进程传递；CLI 与 wasm 导出共用同一 codec。
- **函数子集是公开契约**：子集外行为显式约定（未知函数 `#NAME?`、TEXT 子集外 `#VALUE!`），见 [docs/semantics.md](docs/semantics.md)。
- **核心不读系统时钟**：`TODAY`/`NOW` 由调用方注入 `now`（未注入 → `#NUM!`），同一份语料任何时候跑出同样结果。
- **循环引用复刻 Excel 默认**（迭代关闭）：环上单元格 = 0，元数据标 `circular:true`。
- **离线、确定性**：不调用模型 API 或网络服务，适合放进 CI 做回归对照。

## 函数子集（45，已全部实现）

| 族 | 函数 |
| --- | --- |
| 逻辑 | IF、AND、OR、NOT、IFERROR |
| 文本 | LEFT、RIGHT、MID、LEN、TRIM、UPPER、LOWER、CONCAT、TEXT、VALUE、FIND、SUBSTITUTE |
| 数学 | ROUND、ROUNDUP、ROUNDDOWN、ABS、INT、MOD、POWER、SQRT、SUM、SUMIF、SUMPRODUCT |
| 统计 | AVERAGE、COUNT、COUNTA、COUNTIF、MIN、MAX、MEDIAN |
| 查找 | VLOOKUP、HLOOKUP、INDEX、MATCH |
| 日期 | DATE、YEAR、MONTH、DAY、TODAY、NOW |

逐函数状态与用例数：[docs/support-matrix.md](docs/support-matrix.md)。已实现的语义细节（强制转换三表、比较排序、错误传播顺序、Lotus 日期 bug、TEXT 子集、语料裁定项）：[docs/semantics.md](docs/semantics.md)。

## 仓库状态

- [x] 仓库初始化（README / LICENSE / .gitignore）
- [x] 设计与决策记录（`docs/adr/0001`–`0006`）
- [x] 项目申报书（[项目申报书.md](项目申报书.md)）
- [x] 公式解析与求值核心（Pratt 解析器、Excel 优先级、记忆化重算、环检测）
- [x] 首批 45 函数实现（含十进制舍入修正、双通道强制转换、时钟注入）
- [x] 答案键语料 schema + VBA 生成器 + 752 条用例规格 + 对照 CLI（eval/bench）
- [x] wasm-gc playground（8×8 网格、语义预设、headless 冒烟 PASS）
- [x] 文档与支持矩阵（semantics / support-matrix / demo / toolchain）
- [x] 真实 Excel 语料接入与 M5 对照修复（Excel 2024 生成 752 条、0 跳过；752/752 通过，见 [corpus/cases/PROVENANCE.md](corpus/cases/PROVENANCE.md)）
- [x] M5 修复循环完成：36 条差异逐条归因/修复（11 条时钟、24 条语义、1 条 15 位表征），
      重跑 bench 752/752 并更新 `corpus/reports/real.json`
- [x] README/支持矩阵权威 N/X% 替换基线数字

## 语料生成（用户侧动作）

权威语料已由桌面 Excel 2024 生成并放入 `corpus/cases/`（752 条，0 跳过；来源与环境见 [corpus/cases/PROVENANCE.md](corpus/cases/PROVENANCE.md)）。重新生成时在桌面 Excel 运行 [corpus/excel/generate_corpus.bas](corpus/excel/generate_corpus.bas)（说明见 [corpus/excel/README.md](corpus/excel/README.md)），把导出的 JSON 放入 `corpus/cases/`，然后：

```bash
_build/native/debug/build/cmd/main/main.exe bench --corpus corpus/cases --report corpus/reports/real.json
```

## 设计文档

- [ADR 0001：放弃 MoonPack，转向电子表格公式引擎](docs/adr/0001-pivot-to-formula-engine.md)
- [ADR 0002：产品边界为纯引擎库加薄 CLI，不碰 XLSX 文件](docs/adr/0002-engine-only-boundary.md)
- [ADR 0003：窄而深，限定函数子集，逐个严格对照 Excel](docs/adr/0003-narrow-and-deep-conformance.md)
- [ADR 0004：纯计算核心 + 薄 IO 壳，引擎支持全后端](docs/adr/0004-pure-core-thin-io-shell.md)
- [ADR 0005：新建 mooncalc 仓库，moonpack 归档](docs/adr/0005-new-mooncalc-repo.md)
- [ADR 0006：函数子集取通用表格自动化口径，约 50 个](docs/adr/0006-general-purpose-function-subset.md)
- [工具链实测记录](docs/toolchain.md)

## 许可证

本项目采用 MIT License，参见 [LICENSE](LICENSE)。