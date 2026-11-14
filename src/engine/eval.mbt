pub(all) enum Cell {
  Literal(Value)
  Formula(String)
} derive(Show, Debug, Eq)

pub(all) struct Grid {
  cells : Map[String, Cell]
} derive(Show, Debug)

pub fn new_grid() -> Grid {
  { cells: Map::new() }
}

pub(all) struct EvalOptions {
  now : Double?
} derive(Show, Debug)

pub(all) struct EvalOutput {
  value : Value
  circular : Bool
} derive(Show, Debug)

pub(all) struct RecalcOutput {
  cells : Map[String, EvalOutput]
  parse_errors : Array[(String, String)]
}

struct Ctx {
  grid : Grid
  cache : Map[String, Value]
  stack : Array[String]
  on_stack : Map[String, Bool]
  circular : Map[String, Bool]
  parse_errors : Array[(String, String)]
  now : Double?
}

fn new_ctx(grid : Grid, options : EvalOptions) -> Ctx {
  {
    grid,
    cache: Map::new(),
    stack: [],
    on_stack: Map::new(),
    circular: Map::new(),
    parse_errors: [],
    now: options.now,
  }
}

fn cell_value(ctx : Ctx, key : String) -> Value {
  if ctx.cache.get(key) is Some(v) {
    return v
  }
  if ctx.on_stack.contains(key) {
    // Excel default with iterative calculation off: every cell on the
    // cycle evaluates to 0. Mark only the cycle suffix of the DFS path.
    let mut i = 0
    while i < ctx.stack.length() && ctx.stack[i] != key {
      i += 1
    }
    for j in i..<ctx.stack.length() {
      ctx.circular[ctx.stack[j]] = true
    }
    return Value::Num(0.0)
  }
  let v = match ctx.grid.cells.get(key) {
    None => Value::Blank
    Some(Literal(lit)) => lit
    Some(Formula(src)) => {
      let expr = try @syntax.parse(src) catch {
        @syntax.ParseError(msg) => {
          ctx.parse_errors.push((key, msg))
          None
        }
      } noraise { e => Some(e) }
      match expr {
        None => Value::Err(XlError::Value)
        Some(e) => {
          ctx.stack.push(key)
          ctx.on_stack[key] = true
          let r = eval_expr(ctx, e)
          let _ = ctx.stack.pop()
          let _ = ctx.on_stack.remove(key)
          if ctx.circular.contains(key) { Value::Num(0.0) } else { r }
        }
      }
    }
  }
  ctx.cache[key] = v
  v
}

fn eval_expr(ctx : Ctx, e : @syntax.Expr) -> Value {
  match e {
    Lit(v) => v
    // A reference stays a 1x1 range so aggregates apply the reference
    // channel (ignore text/bool/blank) while literals coerce.
    Ref(addr) =>
      match cell_value(ctx, addr.key()) {
        Range(r) => Value::Range(r)
        v => Value::Range({ rows: 1, cols: 1, cells: [v] })
      }
    Range(lo, hi) => {
      let rows = hi.row - lo.row + 1
      let cols = hi.col - lo.col + 1
      let cells : Array[Value] = []
      for r in lo.row..=hi.row {
        for c in lo.col..=hi.col {
          let a : CellAddr = { row: r, col: c, abs_row: false, abs_col: false }
          cells.push(cell_value(ctx, a.key()))
        }
      }
      Value::Range({ rows, cols, cells })
    }
    Unary(op, sub) => {
      let v = scalarize(eval_expr(ctx, sub))
      match to_number(v) {
        Err(e) => Value::Err(e)
        Ok(d) =>
          match op {
            Neg => Value::Num(-d)
            Pos => Value::Num(d)
            Percent => Value::Num(d / 100.0)
          }
      }
    }
    Binary(op, l, r) => eval_binary(ctx, op, l, r)
    Call(name, args) => eval_call(ctx, name, args)
  }
}

fn pow_excel(a : Double, b : Double) -> Value {
  if a == 0.0 && b < 0.0 {
    return Value::Err(XlError::Div0)
  }
  let p = a.pow(b)
  if p.is_finite() { Value::Num(p) } else { Value::Err(XlError::Num) }
}

fn eval_binary(
  ctx : Ctx,
  op : @syntax.BinOp,
  l : @syntax.Expr,
  r : @syntax.Expr
) -> Value {
  let lv = scalarize(eval_expr(ctx, l))
  let rv = scalarize(eval_expr(ctx, r))
  // Error propagation: leftmost error wins.
  match lv {
    Err(e) => return Value::Err(e)
    _ => ()
  }
  match rv {
    Err(e) => return Value::Err(e)
    _ => ()
  }
  match op {
    Concat =>
      match to_text(scalarize(lv)) {
        Err(e) => Value::Err(e)
        Ok(a) =>
          match to_text(scalarize(rv)) {
            Err(e) => Value::Err(e)
            Ok(b) => Value::Text(a + b)
          }
      }
    Eq | Ne | Lt | Le | Gt | Ge =>
      match compare_values(lv, rv) {
        Err(e) => Value::Err(e)
        Ok(c) =>
          Value::Bool(
            match op {
              Eq => c == 0
              Ne => c != 0
              Lt => c < 0
              Le => c <= 0
              Gt => c > 0
              Ge => c >= 0
              _ => false
            },
          )
      }
    _ => {
      let a = match to_number(scalarize(lv)) {
        Ok(d) => d
        Err(e) => return Value::Err(e)
      }
      let b = match to_number(scalarize(rv)) {
        Ok(d) => d
        Err(e) => return Value::Err(e)
      }
      let d = match op {
        Add => a + b
        Sub => a - b
        Mul => a * b
        Div =>
          if b == 0.0 {
            return Value::Err(XlError::Div0)
          } else {
            a / b
          }
        Pow => return pow_excel(a, b)
        _ => return Value::Err(XlError::Value)
      }
      if d.is_finite() { Value::Num(d) } else { Value::Err(XlError::Num) }
    }
  }
}

fn eval_call(ctx : Ctx, name : String, args : Array[@syntax.Expr]) -> Value {
  match lookup_fn(name) {
    None => Value::Err(XlError::Name)
    Some(spec) => {
      if args.length() < spec.min || args.length() > spec.max {
        return Value::Err(XlError::Value)
      }
      let thunks : Array[Thunk] = args.map(a => () => eval_expr(ctx, a))
      (spec.call)(ctx, thunks)
    }
  }
}

pub fn eval_formula(
  formula : String,
  grid : Grid,
  options : EvalOptions
) -> Result[EvalOutput, @syntax.ParseError] {
  let expr = try @syntax.parse(formula) catch { e => return Err(e) }
  let ctx = new_ctx(grid, options)
  let v = eval_expr(ctx, expr)
  Ok({ value: scalar_output(v), circular: ctx.circular.length() > 0 })
}

pub fn eval_at(
  addr : CellAddr,
  grid : Grid,
  options : EvalOptions
) -> EvalOutput {
  let ctx = new_ctx(grid, options)
  let key = addr.key()
  let v = scalar_output(cell_value(ctx, key))
  { value: v, circular: ctx.circular.contains(key) }
}

pub fn recalc(grid : Grid, options : EvalOptions) -> RecalcOutput {
  let ctx = new_ctx(grid, options)
  let out : Map[String, EvalOutput] = Map::new()
  for key, cell in grid.cells {
    match cell {
      Formula(_) => {
        let v = scalar_output(cell_value(ctx, key))
        out[key] = { value: v, circular: ctx.circular.contains(key) }
      }
      Literal(_) => ()
    }
  }
  { cells: out, parse_errors: ctx.parse_errors }
}