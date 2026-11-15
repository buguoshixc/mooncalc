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

/// 调用方持有的公式 AST 缓存：按公式全文缓存解析结果（含解析失败消息）。
///
/// 跨多次 `recalc_cached` 复用可跳过重复解析；公式文本变化即产生新键，无需手动失效。
pub type ParseCache = @engine.ParseCache

/// 创建一个空的公式 AST 缓存。
pub fn new_parse_cache() -> ParseCache {
  @engine.new_parse_cache()
}

/// 按依赖关系重算整个网格，复用调用方持有的 AST 缓存；语义与 `recalc` 完全一致。
///
/// 同一份缓存可跨多次重算复用（公式文本未变的格跳过解析），适合交互式编辑场景。
/// 循环引用复刻 Excel 默认（迭代计算关闭）：环上单元格结果为 0，元数据 `circular: true`。
pub fn recalc_cached(
  grid : Grid,
  options : EvalOptions,
  cache : ParseCache
) -> RecalcOutput {
  @engine.recalc_cached(grid, options, cache)
}

/// 增量重算状态（调用方持有，单所有者）：依赖图 + AST 缓存 + 上次求值结果。
pub type RecalcState = @engine.RecalcState

/// 全量重算并建立增量状态；输出与 `recalc` 完全一致。
pub fn recalc_init(
  grid : Grid,
  options : EvalOptions
) -> (RecalcState, RecalcOutput) {
  @engine.recalc_init(grid, options)
}

/// 增量重算：只重算 `changed` 的下游闭包，输出与 `recalc(grid, options)` 逐字段一致。
///
/// `changed` 必须列出相对上次调用网格内容发生变化的全部地址（含 Literal↔Formula
/// 切换与删除）。出现循环引用、解析错误或超大区域时自动回退全量重算，调用方无需感知。
pub fn recalc_update(
  state : RecalcState,
  grid : Grid,
  changed : Array[String],
  options : EvalOptions
) -> RecalcOutput {
  @engine.recalc_update(state, grid, changed, options)
}

/// 增量重算元数据：`recomputed` 为本次实际重新求值的公式格（地址升序），
/// `full_fallback` 表示是否回退全量重算（环 / 解析错误 / 超大区域）。
pub type RecalcReport = @engine.RecalcReport

/// 同 `recalc_update`，另返回重算元数据（交互式场景展示「本次重算 N/M 格」用）。
pub fn recalc_update_report(
  state : RecalcState,
  grid : Grid,
  changed : Array[String],
  options : EvalOptions
) -> (RecalcOutput, RecalcReport) {
  @engine.recalc_update_report(state, grid, changed, options)
}

/// 迭代计算选项（对应 Excel「启用迭代计算」）：`max_iterations` 默认 100，
/// `max_change` 默认 0.001。用 `new_iter_options()` 缺省构造。
pub type IterOptions = @engine.IterOptions

/// 创建迭代选项；缺省即 Excel 默认（100 次、最大变化 0.001）。
pub fn new_iter_options(
  max_iterations~ : Int = 100,
  max_change~ : Double = 0.001
) -> IterOptions {
  @engine.new_iter_options(max_iterations=max_iterations, max_change=max_change)
}

/// 启用迭代计算重算整个网格：环上格从 0 起迭代至收敛或次数上限，`circular: true`
/// 但值为迭代结果。默认 `recalc`（迭代关闭）不受影响。
pub fn recalc_iterative(
  grid : Grid,
  options : EvalOptions,
  iter : IterOptions
) -> RecalcOutput {
  @engine.recalc_iterative(grid, options, iter)
}

/// 单公式迭代求值（公式挂到空键参与整网格迭代）；解析失败走 `Err(ParseError)` 通道。
pub fn eval_formula_iterative(
  formula : String,
  grid : Grid,
  options : EvalOptions,
  iter : IterOptions
) -> Result[EvalOutput, ParseError] {
  @engine.eval_formula_iterative(formula, grid, options, iter)
}

/// 错误传播路径上的一步（addr/formula/value/is_source/precedents）。
pub type ExplainStep = @engine.ExplainStep

/// 错误解释结果：目标值、传播路径（源→目标）、错误源头、解析失败消息。
pub type ExplainOutput = @engine.ExplainOutput

/// 解释单元格的错误来源：贡献性错误传播路径（最左错误规则感知）。
///
/// 目标非错误值或落在环上时 `steps` 为空；上游超 256 格降级为纯错误前驱链。
pub fn explain(
  addr : CellAddr,
  grid : Grid,
  options : EvalOptions
) -> ExplainOutput {
  @engine.explain(addr, grid, options)
}

/// 网格依赖图：公式格 → 直接前驱 / 格 → 直接下游（AST 级，区域展开）。
pub type DepGraph = @engine.DepGraph

/// 提取整网格依赖图；任一区域超 65536 格返回 `None`。
pub fn dependency_graph(grid : Grid) -> DepGraph? {
  @engine.dependency_graph(grid)
}

/// 用 Excel 的 1900 日期系统算法（含 Lotus 幻影日 1900-02-29）把年月日折算为序列日。
///
/// 年参数 0..1899 会先 +1900，再按月溢出归一化；越界（序列 <0 或 >2958465）返回 `#NUM!`。
pub fn date_serial(y : Int, m : Int, d : Int) -> Result[Int, XlError] {
  @engine.date_serial(y, m, d)
}
