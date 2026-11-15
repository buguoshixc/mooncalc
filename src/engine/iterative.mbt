// Opt-in iterative calculation (Excel "Enable iterative calculation").
// The default recalc path is untouched: circular cells stay 0 there.
// Semantics here are provisional (source: manual) until the real-Excel iter
// corpus adjudicates fenceposts, iteration order and convergence details.

/// 迭代计算选项（对应 Excel「启用迭代计算」）。默认 100 次 / 最大变化 0.001。
pub(all) struct IterOptions {
  /// 最大迭代次数（Excel 默认 100，上限 32767）。
  max_iterations : Int
  /// 收敛阈值：一轮内所有格的最大绝对变化小于它即停（Excel 默认 0.001）。
  max_change : Double
} derive(Show, Debug)

/// 创建迭代选项；缺省即 Excel 默认（100 次、0.001）。
pub fn new_iter_options(
  max_iterations~ : Int = 100,
  max_change~ : Double = 0.001
) -> IterOptions {
  { max_iterations, max_change }
}

fn value_delta(a : Value, b : Value) -> Double {
  match (a, b) {
    (Num(x), Num(y)) => (x - y).abs()
    _ => if a == b { 0.0 } else { 1.0e308 }
  }
}

/// 启用迭代计算重算整个网格：环上格从 0 起按 grid 插入序就地迭代（Gauss-Seidel），
/// 直到最大变化 < `max_change` 或达到 `max_iterations`。
///
/// 环上格 `circular: true` 但值为迭代结果（不再是 0）；非环格与 `recalc` 一致。
/// 默认 `recalc` 路径不受影响（迭代关闭是 Excel 默认）。
pub fn recalc_iterative(
  grid : Grid,
  options : EvalOptions,
  iter : IterOptions
) -> RecalcOutput {
  let cache = new_parse_cache()
  // Base pass gives static cycle membership and DFS-order parse_errors.
  let base = recalc_impl(grid, options, Some(cache.entries)).0
  let work : Map[String, Value] = Map::new()
  for key, cell in grid.cells {
    match cell {
      Literal(v) => work[key] = v
      Formula(_) => work[key] = Value::Num(0.0)
    }
  }
  let max_passes = if iter.max_iterations < 1 { 1 } else { iter.max_iterations }
  let mut pass = 0
  while pass < max_passes {
    let ctx = new_ctx(grid, options, Some(cache.entries))
    for key, v in work {
      ctx.cache[key] = v
    }
    let mut max_delta = 0.0
    for key, cell in grid.cells {
      match cell {
        Formula(src) => {
          let old = work[key]
          let new_v = match parse_formula(ctx, key, src) {
            None => Value::Err(XlError::Value)
            Some(e) => eval_expr(ctx, e)
          }
          let d = value_delta(old, new_v)
          if d > max_delta {
            max_delta = d
          }
          work[key] = new_v
          ctx.cache[key] = new_v
        }
        Literal(_) => ()
      }
    }
    pass += 1
    if max_delta < iter.max_change {
      break
    }
  }
  let out : Map[String, EvalOutput] = Map::new()
  for key, cell in grid.cells {
    match cell {
      Formula(_) =>
        out[key] = {
          value: scalar_output(work[key]),
          circular: base.cells[key].circular,
        }
      Literal(_) => ()
    }
  }
  { cells: out, parse_errors: base.parse_errors }
}

/// 单公式迭代求值：公式挂到网格中一个确定不存在的键（从 ZZ1 探测）参与整网格迭代。
///
/// 解析失败返回 `Err(ParseError)`；`circular` 表示网格中出现过任何环（与 `eval_formula` 一致）。
pub fn eval_formula_iterative(
  formula : String,
  grid : Grid,
  options : EvalOptions,
  iter : IterOptions
) -> Result[EvalOutput, @syntax.ParseError] {
  let _ = try @syntax.parse(formula) catch { e => return Err(e) }
  let mut key = "ZZ1"
  let mut n = 1
  while grid.cells.contains(key) {
    n += 1
    key = "ZZ" + n.to_string()
  }
  let g2 : Grid = { cells: grid.cells.copy() }
  g2.cells[key] = Formula(formula)
  let out = recalc_iterative(g2, options, iter)
  let any_cycle = {
    let mut found = false
    for _, o in out.cells {
      if o.circular {
        found = true
      }
    }
    found
  }
  match out.cells.get(key) {
    Some(o) => Ok({ value: o.value, circular: any_cycle })
    None => Ok({ value: Value::Blank, circular: any_cycle })
  }
}