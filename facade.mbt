// Root package: public facade of the engine (eval/recalc API).
// The core is pure: no IO, no system clock, fully deterministic.

/// 单元格的值：`Num(数字)`、`Text(文本)`、`Bool(布尔)`、`Err(错误值)`、`Blank(空白)` 或 `Range(区域值)`。
///
/// 公式结果不会是真空白：输出边界把 `Blank` 归一为 `Num(0)`；`Blank` 只作为网格输入状态存在。
pub type Value = @value.Value

/// 7 种 Excel 错误值：`#DIV/0!`、`#N/A`、`#NAME?`、`#NULL!`、`#NUM!`、`#REF!`、`#VALUE!`。
pub type XlError = @value.XlError

/// 单元格地址（1 基行列 + `$` 绝对标记）。用 `parse_addr` 从 `"A1"`/`"$B$2"` 解析。
pub type CellAddr = @value.CellAddr

/// 行主序的区域值（`rows` × `cols`），元素为 `Value`。
pub type RangeValue = @value.RangeValue

/// 公式解析失败（语法/不支持的引用形式）。与求值产生的 `XlError` 是两条独立通道。
pub type ParseError = @syntax.ParseError

/// 单元格内容：`Literal(Value)` 字面值，或 `Formula(String)` 公式源码（前导 `=` 可有可无）。
pub type Cell = @engine.Cell

/// 单元格网格：`Map[String, Cell]`，键为 `A1` 形式的大写地址。引擎的唯一输入数据契约。
pub type Grid = @engine.Grid

/// 求值选项。`now` 是调用方注入的时钟（Excel 序列日，含小数）：`TODAY`/`NOW` 依赖它，
/// 未注入时按显式契约返回 `#NUM!`（核心从不读取系统时钟）。
pub type EvalOptions = @engine.EvalOptions

/// 单格/单公式求值结果：`value` 为标量化后的值，`circular` 表示该格是否落在循环引用环上。
pub type EvalOutput = @engine.EvalOutput

/// 全网格重算结果：`cells` 只含公式格的结果，`parse_errors` 记录解析失败的格与原因。
pub type RecalcOutput = @engine.RecalcOutput

/// 创建一个空的单元格网格。
pub fn new_grid() -> Grid {
  @engine.new_grid()
}

/// 解析 `A1` 形式的单元格地址（支持 `$` 绝对标记）；非法地址返回 `None`。
pub fn parse_addr(s : String) -> CellAddr? {
  @value.parse_addr(s)
}

/// 解析并求值单条公式（不写入网格）。
///
/// - `formula`：公式源码，前导 `=` 可有可无。
/// - `grid`：公式引用的单元格网格（字面值或公式）；引用会递归求值。
/// - `options`：求值选项（时钟注入）。
///
/// 解析失败返回 `Err(ParseError)`；求值阶段的错误值（如 `#DIV/0!`）作为 `Ok` 中的 `Value::Err` 返回。
/// 顶层结果按标量上下文归一化：`Blank`→0，多格区域按值模型规则处理。
pub fn eval_formula(
  formula : String,
  grid : Grid,
  options : EvalOptions
) -> Result[EvalOutput, ParseError] {
  @engine.eval_formula(formula, grid, options)
}

/// 求值网格中某个单元格（取该格的缓存结果）；空白格返回 `Blank`。
///
/// 这是 `eval_formula("=<addr>", ...)` 的便捷形式，循环引用语义与 `recalc` 一致。
pub fn eval_at(addr : CellAddr, grid : Grid, options : EvalOptions) -> EvalOutput {
  @engine.eval_at(addr, grid, options)
}

/// 按依赖关系重算整个网格（DFS + 记忆化 + 环检测）。
///
/// 循环引用复刻 Excel 默认（迭代计算关闭）：环上单元格结果为 0，元数据 `circular: true`。
pub fn recalc(grid : Grid, options : EvalOptions) -> RecalcOutput {
  @engine.recalc(grid, options)
}

/// 用 Excel 的 1900 日期系统算法（含 Lotus 幻影日 1900-02-29）把年月日折算为序列日。
///
/// 年参数 0..1899 会先 +1900，再按月溢出归一化；越界（序列 <0 或 >2958465）返回 `#NUM!`。
pub fn date_serial(y : Int, m : Int, d : Int) -> Result[Int, XlError] {
  @engine.date_serial(y, m, d)
}
