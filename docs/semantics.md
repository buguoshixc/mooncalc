# MoonCalc 语义规范（v1）

本文档记录引擎**已实现**的语义与显式契约。凡与 Excel 可能有出入、需真实语料裁定的条目集中在[语料裁定项](#语料裁定项)。实现位置以 `src/` 为准；本文随实现更新。

## 值模型（src/value）

- `Value = Num(Double) | Text(String) | Bool | Err(XlError) | Blank | Range`。
- **Blank 与 Num(0) 严格区分**：空白格是 `Blank`，不是 0；参与运算/比较时按下方规则转换。
- **公式结果永不为真空白**：输出边界把 Blank 归一为 `Num(0)`（Excel 中 `=A1` 引用空白格得 0，公式格的 ISBLANK 恒为 FALSE）；`""` 是空文本不是空白。Blank 只作为网格输入状态存在。
- `Range` 行主序保留形状（rows×cols）。**1×1 区域可标量化**；>1 格区域进入标量上下文 → `#VALUE!`（不做动态数组溢出）。
- 7 种错误值：`#DIV/0! #N/A #NAME? #NULL! #NUM! #REF! #VALUE!`。
- 地址上限 XFD（16384 列）/ 1048576 行；`$` 绝对标记解析保真（v1 无复制填充场景）。
- **解析失败走独立通道**：`eval_formula` 返回 `Result[_, ParseError]`；网格重算把失败格记入 `parse_errors` 并使该格值为 `#VALUE!`，不混入正常结果。

## 解析器与优先级（src/syntax）

Excel 优先级（高→低）：

| 级 | 运算符 | 备注 |
|---|---|---|
| 80 | `:` 区域 | 仅 引用:引用；B2:A1 归一化为 A1:B2 |
| 70 | `%` 后缀 | `50%` = 0.5 |
| 60 | 一元 `-` | **`-2^2 = 4`**（负号先于乘方） |
| 50 | `^` | **左结合：`2^3^2 = 64`** |
| 40 | `* /` | |
| 30 | `+ -` | |
| 20 | `&` | 文本连接 |
| 10 | `= <> < <= > >=` | |

- 字面量：数字/科学计数、字符串（`""` 转义）、TRUE/FALSE（大小写不敏感）、7 种错误字面量。
- 形如引用但后随 `(` 的记号按函数名处理（如 `LOG10(` 不是单元格）。
- 前导 `=` 可有可无。
- **不支持（解析错误）**：整列/整行（A:A）、交集（空格）、联合（逗号在区域层）、R1C1、定义名称、数组字面量 `{}`、跨表引用 `Sheet1!A1`。

## 强制转换（src/engine/coerce.mbt，唯一入口）

**locale 不变式**：小数点恒为 `.`；千分位、货币符号、日期文本一律 `#VALUE!`（不猜 locale）。

### to_number（算术运算、数值参数）

| 输入 | 结果 |
|---|---|
| Num | 原值 |
| Blank | 0 |
| Bool | TRUE→1，FALSE→0 |
| Text | 前后空白裁剪后解析：可选符号 + 数字 + 可选小数 + 可选科学计数 + 可选 `%` 后缀（`"50%"`→0.5）；解析失败 → `#VALUE!` |
| Err | 原样传播 |
| Range | 1×1 递归；否则 `#VALUE!` |

### to_text（`&`、文本参数）

| 输入 | 结果 |
|---|---|
| Num | **15 位有效数字**、去尾零（Excel 显示精度）；非有限值 → `#NUM!` |
| Text | 原值 |
| Bool | `"TRUE"` / `"FALSE"` |
| Blank | `""` |
| Err | 传播 |
| Range | 1×1 递归；否则 `#VALUE!` |

### to_bool（逻辑参数）

| 输入 | 结果 |
|---|---|
| Bool | 原值 |
| Num | ≠0 → TRUE |
| Blank | FALSE |
| Text | 仅 `"TRUE"`/`"FALSE"`（大小写不敏感）；其余 `#VALUE!` |
| Err | 传播 |
| Range | 1×1 递归；否则 `#VALUE!` |

## 比较排序（`=` `<` 等，**不强制转换**）

- 跨类型全序：**数字 < 文本 < 布尔**，故 `"1" = 1` → FALSE、`1 < "a"` → TRUE。
- 文本比较**大小写不敏感**、逐码点字典序（MoonBit 原生 String 比较是长度优先，已用自定义 lex_compare 替换）。
- Blank 与对方同化：对数字视为 0、对文本视为 `""`、对布尔视为 FALSE；Blank=Blank → TRUE。
- 错误值参与比较 → 传播（左先）。

## 引用 vs 字面量双通道

通道划分以**引用/字面量**为界，不是以单格/区域为界：单格引用 `A1` 同样走引用通道（实现上引用统一包成 1×1 Range，强制转换函数自动解包）。

- **字面量参数**走强制转换：`SUM("3",4) = 7`、`SUM(TRUE,1) = 2`。
- **引用参数**（含单格引用）：SUM/AVERAGE/MIN/MAX/MEDIAN/SUMPRODUCT 等忽略文本与布尔（不转换、不报错），故 `SUM(A1,4)`（A1 为文本）= 4、`AVERAGE(A1)`（A1 为文本）= `#DIV/0!`；**COUNT 只数数字**；**COUNTA 数一切非空**（含公式产生的 `""`）。
- AND/OR 的引用参数**只认布尔格**（数字/文本/空白忽略）；全部参数都没有逻辑值 → `#VALUE!`；字面量参数走 to_bool。
- 引用内的错误值传播（见下）；**例外**：COUNT 忽略引用内错误格、COUNTA 将其计为非空；COUNTIF/SUMIF 的条件区域内错误格只是不匹配、不传播，criteria 参数为错误才传播；SUMIF 求和区域的错误格在被选中求和时传播。COUNT/COUNTA/SUMPRODUCT 的**直接**错误参数（字面量或计算结果）传播。

## 错误传播与求值顺序

- 二元运算/急切函数：**从左到右最先出现的错误胜出**（`1/0 + #N/A` → `#DIV/0!`）。
- **惰性**：IF（只求值被选分支）、IFERROR（第一参数无错则不求值第二参数）。`IF(TRUE,1,1/0) = 1`。
- **急切**：AND/OR 及其余全部函数。`AND(TRUE,1/0)` → `#DIV/0!`。
- 未知函数 → `#NAME?`；参数个数不符 → `#VALUE!`（显式契约；Excel 实际在录入时拒绝，语料无法覆盖此差异）。

## 网格重算与循环引用（src/engine/eval.mbt）

- `eval_formula`（单公式）/ `eval_at`（单格）/ `recalc`（全网格）共享同一 DFS：引用递归 + cache 记忆化 + on_stack 环检测。
- **循环引用复刻 Excel 默认（迭代计算关闭）：环上每个单元格 = 0**，结果元数据 `circular: true`。
- 只标记 DFS 路径中的**环后缀**：`=D1+1` 自环的 D1 标 circular；依赖环的 `D2==D1+5` 得 5 且 circular=false（与 Excel 一致：依赖格拿到 0 继续算）。
- 无系统时钟、无随机：同一输入必然同一输出（时钟经注入，见下）。

## 函数边界语义（45 函数）

### 逻辑（5）
IF / IFERROR 惰性；AND/OR 急切、引用参数只认布尔格（无逻辑值 → `#VALUE!`）、字面量走 to_bool（直接文本参数须为 TRUE/FALSE）；NOT 走 to_bool。

### 数学（11）
- **ROUND/ROUNDUP/ROUNDDOWN：half-away-from-zero，十进制字符串修正**——`ROUND(2.675,2) = 2.68`（朴素 double 会得 2.67）；负位数作用于整数位。
- **MOD 符号随除数**：`MOD(-3,2) = 1`、`MOD(3,-2) = -1`；除数 0 → `#DIV/0!`。
- POWER/SQRT 定义域外 → `#NUM!`（负底数非整数次幂、负数开方）；`0^负数` → `#DIV/0!`。
- INT 向下取整（`INT(-2.5) = -3`）；ABS 平凡。
- SUM/SUMIF/SUMPRODUCT：SUMIF criteria 支持比较符前缀（`">2"`、`"<>x"`）与通配符 `* ? ~`；SUMPRODUCT 形状不齐 → `#VALUE!`，区域内非数值按 0。
- 溢出/非有限结果 → `#NUM!`。

### 统计（7）
AVERAGE 无数值 → `#DIV/0!`；MIN/MAX 无数值 → 0；COUNT/COUNTA 见双通道；COUNTIF 同 SUMIF criteria；MEDIAN 偶数个取中点均值。

### 文本（12）
- LEFT/RIGHT/MID 按**字符**（码点）计；n<0 / start<1 → `#VALUE!`；越界裁剪不报错。
- LEN 数码点。**UPPER/LOWER 仅 ASCII**（非 ASCII 原样保留，记偏差候选）。
- **TRIM 仅压缩 ASCII 空格**（去两端、内部连续压成一个；不动 tab/全角空格）。
- FIND **大小写敏感、无通配符**；找不到 → `#VALUE!`；空 needle 返回 start。
- SUBSTITUTE 第 4 参指定第几次出现（<1 → `#VALUE!`）；空 old 原样返回。
- CONCAT 区域逐格拼接；VALUE 走 to_number 的文本解析。
- TEXT 见专节。

### 查找（4）
- VLOOKUP/HLOOKUP：第 4 参 FALSE/0 精确（找不到 `#N/A`）；TRUE/省略近似（首列/行升序假设，取 ≤lookup 的最后一项，小于最小值 → `#N/A`）。col/row_index <1 → `#VALUE!`，超出表宽 → `#REF!`。
- MATCH：0 精确（支持通配符）、1 升序近似、-1 降序近似；找不到 `#N/A`。
- INDEX：row/col = 0 返回整列/整行（Range 值）；越界 → `#REF!`。

### 日期（6）
- **1900 日期系统 + Lotus bug**：serial 60 = 幻影 1900-02-29；1..59 用 epoch 1899-12-31，≥61 用 1899-12-30；serial 0 → DAY=0。
- DATE 溢出归一化：`DATE(2026,13,1)` → 2027-01-01；**`DATE(1900,2,29)` → 61（=1900-03-01）**；y∈0..1899 自动 +1900。
- 负 serial / ≥2958466 → `#NUM!`。
- **时钟注入契约**：`EvalOptions { now : Double? }`（序列日含小数）。TODAY=INT(now)、NOW=now；**未注入 → `#NUM!`**（核心不读系统时钟，CLI `--now` 在壳层转换 ISO/serial）。

## TEXT 子集（src/engine/text_format.mbt）

- 数字段：`0 # ? . , %`、引号字面量、`\` 转义；最多 3 分段 `正;负;零`。
- 文本输入原样返回；TRUE/FALSE 转大写词。
- **子集外一律 `#VALUE!`（响亮失败）**：颜色 `[Red]`、locale `[$-...]`、累计时长 `[h]`、科学计数 `E+`、分数 `?/?`、条件分段 `[>100]`、日期时间码（yyyy/mm/dd/hh/ss，v1 未实现）。

## 不支持特性清单（v1 显式排除）

动态数组/溢出、隐式交集 `@`、整列整行引用、跨表/跨簿引用、定义名称、R1C1、数组字面量、迭代计算（循环=0 固定）、1904 日期系统、locale 相关解析与格式、TEXT 日期时间码、非 ASCII 大小写、通配符在 FIND 中。

## 语料裁定项（待真实 Excel 语料归因）

以下条目已埋入 corpus/spec/generic.tsv 等规格，等 corpus/cases/ 到达后以 Excel 为唯一裁判：

1. COUNT/COUNTA/SUMPRODUCT 对**直接错误参数**的传播（已实现：直接错误参数传播 `COUNT(#N/A)` → `#N/A`；引用内错误 COUNT 忽略、COUNTA 计数；待语料确认）。
2. MEDIAN 对空白引用的处理（已实现：引用通道忽略空白，无数值 → `#NUM!`；待语料确认）。
3. IFERROR 第一参数为空白引用时的返回（已实现：空白非错误，透传并经输出边界归一为 0；待语料确认）。
4. 非 ASCII 的 UPPER/LOWER/LEN 行为（当前 ASCII-only，预期记署名偏差）。
5. 文本日期（`"2026-01-02"`）参与 DATEVALUE 类转换（当前 locale 不变式 → `#VALUE!`）。
6. to_text 科学计数阈值（当前 15 位有效数字实现的具体切换点）。
7. 浮点尾差：bench 单列 numeric-tolerance 桶（相对差 <1e-9，计失败但单独归因）。

## 零 IO 与确定性

核心（src/、web/、facade.mbt）禁 `@fs`/`@sys`/`println`/`extern "C"`，由 scripts/check.sh 机械守卫；双目标（native + wasm-gc）编译保证无平台依赖。唯一 IO 点是 cmd/main 壳层。同输入同输出，时钟经显式注入。