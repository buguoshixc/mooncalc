# MoonCalc

**Excel 兼容的电子表格公式引擎，用 MoonBit 编写。**

> 状态（2026-11-14）：45 函数引擎、native CLI、wasm-gc playground 已实现并通过四层验证；**真实 Excel 答案键语料待接入**（531 条用例规格与 VBA 生成器已就绪，等待在桌面 Excel 运行回传）。2026 MoonBit 年度黑客松 11 月赛参赛项目。

## 这是什么

MoonCalc 接收一组单元格——每个单元格承载字面值或公式——按 Excel 语义求值并返回结果或错误值。它不读写 `.xlsx` 文件，文件读写交给 mbtexcel 这类工具，MoonCalc 只负责计算。

项目走“窄而深”的路线：首批只实现 45 个核心函数，覆盖逻辑、文本、数学、统计、查找、日期六族；每个函数的弱类型强制转换、错误值传播和边界情形都要严格对照真实 Excel。正确性用真实 Excel 生成的答案键语料逐条验证，对外公开用例数和通过率，未通过的用例逐条归因。

## 快速开始

```bash
export PATH="$HOME/.moon/bin:$PATH"

# 全量验证：双目标构建 + 49 项单测 + 零 IO 守卫
bash scripts/check.sh

# CLI：求值一个含引用链/错误传播/循环引用的网格
moon build --target native
_build/native/debug/build/cmd/main/main.exe eval --grid tests/fixtures/grid.json

# 跑分：过渡语料（真实语料到达后改为 corpus/cases）
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
| 单元/快照测试 | 49/49 | 手写期望 |
| 过渡语料 bench | 34/34（100%） | source: manual，**非权威**，仅证明流程 |
| 用例规格 | 531 条（corpus/spec/） | 已交付 VBA 生成器，待真实 Excel 运行 |
| **真实 Excel 语料** | **待接入 → N 条 / X%** | M5：Excel 为唯一裁判，差异逐条归因 |

比较策略：默认精确相等；相对差 <1e-9 单列 numeric-tolerance 桶（计失败、单独归因）；clock 标签容差披露。基线报告：`corpus/reports/provisional.json`。

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
- [x] 答案键语料 schema + VBA 生成器 + 531 条用例规格 + 对照 CLI（eval/bench）
- [x] wasm-gc playground（8×8 网格、语义预设、headless 冒烟 PASS）
- [x] 文档与支持矩阵（semantics / support-matrix / demo / toolchain）
- [ ] **真实 Excel 语料接入与修复循环（M5，等待用户回传 corpus/cases/）**
- [ ] README 权威 N/X% 替换过渡数字

## 语料生成（用户侧动作）

在桌面 Excel 运行 [corpus/excel/generate_corpus.bas](corpus/excel/generate_corpus.bas)（说明见 [corpus/excel/README.md](corpus/excel/README.md)），把导出的 JSON 放入 `corpus/cases/`，然后：

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