// Root package: public facade of the engine (eval/recalc API).
pub type Value = @value.Value

pub type XlError = @value.XlError

pub type CellAddr = @value.CellAddr

pub type RangeValue = @value.RangeValue

pub type ParseError = @syntax.ParseError

pub type Cell = @engine.Cell

pub type Grid = @engine.Grid

pub type EvalOptions = @engine.EvalOptions

pub type EvalOutput = @engine.EvalOutput

pub type RecalcOutput = @engine.RecalcOutput

pub fn new_grid() -> Grid {
  @engine.new_grid()
}

pub fn parse_addr(s : String) -> CellAddr? {
  @value.parse_addr(s)
}

pub fn eval_formula(
  formula : String,
  grid : Grid,
  options : EvalOptions
) -> Result[EvalOutput, ParseError] {
  @engine.eval_formula(formula, grid, options)
}

pub fn eval_at(addr : CellAddr, grid : Grid, options : EvalOptions) -> EvalOutput {
  @engine.eval_at(addr, grid, options)
}

pub fn recalc(grid : Grid, options : EvalOptions) -> RecalcOutput {
  @engine.recalc(grid, options)
}

pub fn date_serial(y : Int, m : Int, d : Int) -> Result[Int, XlError] {
  @engine.date_serial(y, m, d)
}