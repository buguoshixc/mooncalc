# MoonCalc

**Excel 兼容的电子表格公式引擎，用 MoonBit 编写。**

> 状态：项目已启动，设计与决策文档就绪，实现代码尚未开始（2026 MoonBit 年度黑客松 11 月赛参赛项目）。

## 这是什么

MoonCalc 接收一组单元格——每个单元格承载字面值或公式——按 Excel 语义求值并返回结果或错误值。它不读写 `.xlsx` 文件，文件读写交给 mbtexcel 这类工具，MoonCalc 只负责计算。

项目走“窄而深”的路线：首批只实现 45 个核心函数，覆盖逻辑、文本、数学、统计、查找、日期六族；每个函数的弱类型强制转换、错误值传播和边界情形都要严格对照真实 Excel。正确性用真实 Excel 生成的答案键语料逐条验证，对外公开用例数和通过率，未通过的用例逐条归因。

## 设计要点

- **纯计算核心，不做任何 IO**：同一份核心同时编译到 native 和 wasm-gc。native 侧跑答案键语料对照，wasm-gc 侧做浏览器 playground 演示。
- **输入是内存网格契约**：单元格网格是引擎与外部世界之间唯一的数据契约，与文件格式、界面和模型都无关，可以序列化成 JSON 跨进程传递。
- **函数子集是公开契约**：支持哪些函数、子集之外的行为如何定义，都写在文档里，不靠对常见路径的猜测。
- **核心不读系统时钟**：`TODAY`、`NOW` 需要的当前时间由调用方传入，保证同一份语料任何时候都能跑出同样的结果。
- **离线、确定性**：不调用模型 API 或网络服务，适合放进 CI 做回归对照。
- **核心指标是“N 条真实 Excel 用例，通过率 X%”**：不追求函数数量，差异要能逐条定位到实现。

## 函数子集（首批，计划支持）

| 族 | 函数 |
| --- | --- |
| 逻辑 | IF、AND、OR、NOT、IFERROR |
| 文本 | LEFT、RIGHT、MID、LEN、TRIM、UPPER、LOWER、CONCAT、TEXT、VALUE、FIND、SUBSTITUTE |
| 数学 | ROUND、ROUNDUP、ROUNDDOWN、ABS、INT、MOD、POWER、SQRT、SUM、SUMIF、SUMPRODUCT |
| 统计 | AVERAGE、COUNT、COUNTA、COUNTIF、MIN、MAX、MEDIAN |
| 查找 | VLOOKUP、HLOOKUP、INDEX、MATCH |
| 日期 | DATE、YEAR、MONTH、DAY、TODAY、NOW |

子集之外函数的返回值会在实现文档中显式约定，不按常见路径临时猜测。

## 计划功能

- 公式解析：A1 风格引用（相对/绝对）、区域引用、数值/字符串/布尔/错误字面量、算术/比较/连接运算符、函数调用与括号；
- 求值核心：Excel 的弱类型强制转换、错误值传播、空单元格与文本型数字处理；
- 函数实现：首批 45 个函数，逐个对照 Excel 语义；
- native CLI：读入 JSON 网格与公式输出求值结果；批量跑答案键语料，输出用例数、通过率和差异明细；
- 答案键语料：由真实 Excel 生成，覆盖正常值与边界情形，离线可复现；
- wasm-gc playground：在浏览器里输入网格和公式，现场演示求值结果；
- 测试与文档：单元测试 + 语料对照回归，函数清单与语义边界写成公开文档。

## 仓库状态

- [x] 仓库初始化（README / LICENSE / .gitignore）
- [x] 设计与决策记录（`docs/adr/0001`–`0006`）
- [x] 项目申报书（[项目申报书.md](项目申报书.md)）
- [ ] 公式解析与求值核心
- [ ] 首批函数实现
- [ ] 答案键语料与对照 CLI
- [ ] wasm-gc playground
- [ ] 文档与支持矩阵

## 设计文档

- [ADR 0001：放弃 MoonPack，转向电子表格公式引擎](docs/adr/0001-pivot-to-formula-engine.md)
- [ADR 0002：产品边界为纯引擎库加薄 CLI，不碰 XLSX 文件](docs/adr/0002-engine-only-boundary.md)
- [ADR 0003：窄而深，限定函数子集，逐个严格对照 Excel](docs/adr/0003-narrow-and-deep-conformance.md)
- [ADR 0004：纯计算核心 + 薄 IO 壳，引擎支持全后端](docs/adr/0004-pure-core-thin-io-shell.md)
- [ADR 0005：新建 mooncalc 仓库，moonpack 归档](docs/adr/0005-new-mooncalc-repo.md)
- [ADR 0006：函数子集取通用表格自动化口径，约 50 个](docs/adr/0006-general-purpose-function-subset.md)

## 许可证

本项目采用 MIT License，参见 [LICENSE](LICENSE)。
