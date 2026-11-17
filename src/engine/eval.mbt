/// 单元格内容：字面值或公式源码。
pub(all) enum Cell {
  /// 字面值（数字/文本/布尔/错误/空白）。
  Literal(Value)
  /// 公式源码（前导 `=` 可有可无）。
  Formula(String)
} derive(Show, Debug, Eq)

/// 单元格网格：引擎的唯一输入数据契约。
///
/// `cells` 的键为限定地址：默认表用裸 `A1`，其它表用 `SHEET!A1`
/// （表名 ASCII 大写；含特殊字符的表名保留单引号写法 `'MY SHEET'!A1`，
/// 由 `@value.sheet_key` 生成）。
pub(all) struct Grid {
  /// 地址 → 单元格内容。未出现的地址按空白处理。
  cells : Map[String, Cell]
  /// 工作簿级定义名称：ASCII 大写名称 → 引用文本（如 `Data!A1:B2`）。
  /// 名称体在求值时重新解析，因此必须自包含工作表限定（默认表可裸写）。
  names : Map[String, String]
} derive(Show, Debug)

/// 创建一个空的单元格网格。
pub fn new_grid() -> Grid {
  { cells: Map::new(), names: Map::new() }
}

/// 求值选项。
pub(all) struct EvalOptions {
  /// 调用方注入的时钟（Excel 序列日，含小数）。`TODAY`/`NOW` 依赖它；
  /// `None` 时按显式契约返回 `#NUM!`（核心从不读取系统时钟）。
  now : Double?
} derive(Show, Debug)

/// 单格/单公式求值结果。
pub(all) struct EvalOutput {
  /// 标量化后的值（`Blank`→0；多格区域按值模型规则处理）。
  value : Value
  /// 该格是否落在循环引用环上（环上结果固定为 0）。
  circular : Bool
} derive(Show, Debug)

/// 全网格重算结果。
pub(all) struct RecalcOutput {
  /// 公式格的结果（字面值格不出现）。
  cells : Map[String, EvalOutput]
  /// 解析失败的格与原因（地址, 消息）；这些格的结果为 `#VALUE!`。
  parse_errors : Array[(String, String)]
}

struct Ctx {
  grid : Grid
  cache : Map[String, Value]
  range_cache : Map[String, Value]
  ast_cache : Map[String, CachedAst]?
  stack : Array[String]
  on_stack : Map[String, Bool]
  circular : Map[String, Bool]
  parse_errors : Array[(String, String)]
  now : Double?
  /// 当前公式的宿主工作表（`""` = 默认表）；裸引用按它限定。
  mut current_sheet : String
  /// 每表 used-range 右下角缓存：表名 → (max_row, max_col)；(0,0) = 该表不存在。
  bounds_cache : Map[String, (Int, Int)]
}

fn new_ctx(
  grid : Grid,
  options : EvalOptions,
  ast_cache : Map[String, CachedAst]?
) -> Ctx {
  {
    grid,
    cache: Map::new(),
    range_cache: Map::new(),
    ast_cache,
    stack: [],
    on_stack: Map::new(),
    circular: Map::new(),
    parse_errors: [],
    now: options.now,
    current_sheet: "",
    bounds_cache: Map::new(),
  }
}

/// 名称定义递归上限（防御恶意/意外的名称链）。
let max_name_depth : Int = 32

/// 该表 used-range 的右下角（含）。默认表恒存在且至少 1×1；其它表若无任何单元格
/// 返回 (0,0)，对它的引用按缺表 `#REF!` 处理（与 Excel 一致）。
fn used_bounds(ctx : Ctx, sheet : String) -> (Int, Int) {
  match ctx.bounds_cache.get(sheet) {
    Some(b) => b
    None => {
      let mut mr = if sheet == "" { 1 } else { 0 }
      let mut mc = if sheet == "" { 1 } else { 0 }
      for k, _ in ctx.grid.cells {
        let (s, text) = @value.split_key(k)
        if s == sheet {
          match @value.parse_addr(text) {
            Some(a) => {
              if a.row > mr {
                mr = a.row
              }
              if a.col > mc {
                mc = a.col
              }
            }
            None => ()
          }
        }
      }
      let b = (mr, mc)
      ctx.bounds_cache[sheet] = b
      b
    }
  }
}

/// 该表是否存在：默认表恒存在；其它表只要含至少一个单元格即存在。
fn grid_sheet_exists(grid : Grid, sheet : String) -> Bool {
  if sheet == "" {
    return true
  }
  for k, _ in grid.cells {
    if @value.split_key(k).0 == sheet {
      return true
    }
  }
  false
}

/// 物化 [lo, hi] 区域（含端点）。同一 (表, 区域) 在一次求值上下文内共享结果。
fn materialize_range(
  ctx : Ctx,
  sheet : String,
  lo : CellAddr,
  hi : CellAddr
) -> Value {
  let rkey = @value.sheet_key(sheet, lo) + ":" + @value.sheet_key(sheet, hi)
  match ctx.range_cache.get(rkey) {
    Some(v) => v
    None => {
      let rows = hi.row - lo.row + 1
      let cols = hi.col - lo.col + 1
      let cells : Array[Value] = []
      for r in lo.row..=hi.row {
        for c in lo.col..=hi.col {
          let a : CellAddr = { row: r, col: c, abs_row: false, abs_col: false }
          cells.push(cell_value(ctx, @value.sheet_key(sheet, a)))
        }
      }
      let v = Value::Range({ rows, cols, cells })
      ctx.range_cache[rkey] = v
      v
    }
  }
}

/// 名称体解析失败按 `#VALUE!` 处理；名称体自身不产生 parse_errors（不伪造单元格）。
fn parse_name_body(text : String) -> @syntax.Expr? {
  try @syntax.parse(text) catch { _ => None } noraise { e => Some(e) }
}

/// 求值定义名称。名称在解析期与求值期都不做缓存（可随时被引擎以外修改），
/// 只以 `NAME:` 前缀的栈标记做环守卫：环上按 Excel 迭代关闭语义取 0 并打标。
fn eval_name(ctx : Ctx, name : String) -> Value {
  let text = match ctx.grid.names.get(name) {
    Some(t) => t
    None => return Value::Err(XlError::Name)
  }
  let guard_key = "NAME:" + name
  if ctx.on_stack.contains(guard_key) {
    let mut i = 0
    while i < ctx.stack.length() && ctx.stack[i] != guard_key {
      i += 1
    }
    for j in i..<ctx.stack.length() {
      if !ctx.stack[j].has_prefix("NAME:") {
        ctx.circular[ctx.stack[j]] = true
      }
    }
    let mut h = ctx.stack.length() - 1
    while h >= 0 {
      if !ctx.stack[h].has_prefix("NAME:") {
        ctx.circular[ctx.stack[h]] = true
        break
      }
      h -= 1
    }
    // 顶层 `=LoopA` 没有宿主格：名称守卫自身也记入环集合，供 circular 元数据使用。
    ctx.circular[guard_key] = true
    return Value::Num(0.0)
  }
  let mut depth = 0
  for k in ctx.stack {
    if k.has_prefix("NAME:") {
      depth += 1
    }
  }
  if depth >= max_name_depth {
    return Value::Err(XlError::Name)
  }
  let saved_sheet = ctx.current_sheet
  ctx.current_sheet = ""
  let expr = parse_name_body(text)
  ctx.current_sheet = saved_sheet
  match expr {
    None => Value::Err(XlError::Value)
    Some(e) => {
      ctx.stack.push(guard_key)
      ctx.on_stack[guard_key] = true
      let v = eval_expr(ctx, e)
      let _ = ctx.stack.pop()
      let _ = ctx.on_stack.remove(guard_key)
      v
    }
  }
}

// None = uncached fast path (plain recalc): unique-text workloads must not pay
// cache hashing overhead. Some = content-addressed cache shared across cells
// and/or recalcs (recalc_cached).
fn parse_formula(ctx : Ctx, key : String, src : String) -> @syntax.Expr? {
  match ctx.ast_cache {
    None =>
      try @syntax.parse(src) catch {
        @syntax.ParseError(msg) => {
          ctx.parse_errors.push((key, msg))
          None
        }
      } noraise { e => Some(e) }
    Some(cache) =>
      match cache.get(src) {
        Some(Ast(e)) => Some(e)
        Some(Bad(msg)) => {
          ctx.parse_errors.push((key, msg))
          None
        }
        None =>
          try @syntax.parse(src) catch {
            @syntax.ParseError(msg) => {
              cache[src] = Bad(msg)
              ctx.parse_errors.push((key, msg))
              None
            }
          } noraise { e => {
            cache[src] = Ast(e)
            Some(e)
          } }
      }
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
      let expr = parse_formula(ctx, key, src)
      match expr {
        None => Value::Err(XlError::Value)
        Some(e) => {
          let saved_sheet = ctx.current_sheet
          ctx.current_sheet = @value.split_key(key).0
          ctx.stack.push(key)
          ctx.on_stack[key] = true
          let r = eval_expr(ctx, e)
          let _ = ctx.stack.pop()
          let _ = ctx.on_stack.remove(key)
          ctx.current_sheet = saved_sheet
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
      match cell_value(ctx, @value.sheet_key(ctx.current_sheet, addr)) {
        Range(r) => Value::Range(r)
        v => Value::Range({ rows: 1, cols: 1, cells: [v] })
      }
    // Cell values are immutable within one evaluation context, so a
    // materialized range can be shared by every formula referencing it.
    Range(lo, hi) => materialize_range(ctx, ctx.current_sheet, lo, hi)
    Sheet(sheet, inner) => {
      // 缺表：Excel 对不存在工作表的引用报 `#REF!`；引用文本里的表名不区分大小写。
      if sheet != "" && used_bounds(ctx, sheet) == (0, 0) {
        Value::Err(XlError::Ref)
      } else {
        let saved_sheet = ctx.current_sheet
        ctx.current_sheet = sheet
        let v = eval_expr(ctx, inner)
        ctx.current_sheet = saved_sheet
        v
      }
    }
    WholeCols(c1, c2) => {
      // 整列按该表 used-range 展开（空表 1 行），不做静默截断。
      let (mr, _) = used_bounds(ctx, ctx.current_sheet)
      let lo : CellAddr = { row: 1, col: c1, abs_row: false, abs_col: false }
      let hi : CellAddr = {
        row: if mr == 0 { 1 } else { mr },
        col: c2,
        abs_row: false,
        abs_col: false,
      }
      materialize_range(ctx, ctx.current_sheet, lo, hi)
    }
    WholeRows(r1, r2) => {
      // 整行按该表 used-range 展开（空表 1 列）。
      let (_, mc) = used_bounds(ctx, ctx.current_sheet)
      let lo : CellAddr = { row: r1, col: 1, abs_row: false, abs_col: false }
      let hi : CellAddr = {
        row: r2,
        col: if mc == 0 { 1 } else { mc },
        abs_row: false,
        abs_col: false,
      }
      materialize_range(ctx, ctx.current_sheet, lo, hi)
    }
    Name(n) => eval_name(ctx, n)
    Unary(op, sub) => {
      // Postfix % is not nesting-counted by the parser, so chains like
      // 1%%%... up to the length limit must fold iteratively, like binary
      // spines. Inside-out application order matches the recursive version.
      let ops : Array[@syntax.UnOp] = [op]
      let mut cur = sub
      while true {
        match cur {
          Unary(o2, sub2) => {
            ops.push(o2)
            cur = sub2
          }
          _ => break
        }
      }
      let mut v = scalarize(eval_expr(ctx, cur))
      let mut i = ops.length() - 1
      while i >= 0 {
        // Excel unary plus is an identity operator: +"3" stays text "3" and
        // +TRUE stays boolean TRUE; only unary minus / percent coerce.
        v = match ops[i] {
          Pos => v
          Neg =>
            match to_number(v) {
              Err(e) => Value::Err(e)
              Ok(d) => Value::Num(-d)
            }
          Percent =>
            match to_number(v) {
              Err(e) => Value::Err(e)
              Ok(d) => Value::Num(d / 100.0)
            }
        }
        i -= 1
      }
      v
    }
    Binary(op, l, r) => eval_binary(ctx, op, l, r)
    Call(name, args) => eval_call(ctx, name, args)
  }
}

fn pow_excel(a : Double, b : Double) -> Value {
  if a == 0.0 {
    if b == 0.0 {
      return Value::Err(XlError::Num)
    }
    if b < 0.0 {
      return Value::Err(XlError::Div0)
    }
    return Value::Num(0.0)
  }
  if a < 0.0 && b != b.trunc() {
    // Excel allows negative bases only when the exponent is an integer or the
    // reciprocal of an odd integer: (-8)^(1/3) = -2, (-8)^(2/3) = #NUM!.
    let inv = 1.0 / b
    let k = inv.round()
    if (inv - k).abs() > 1.0e-10 || k.trunc() != k || k % 2.0 == 0.0 {
      return Value::Err(XlError::Num)
    }
    let p = (-a).pow(b)
    if p.is_finite() {
      return Value::Num(-p)
    }
    return Value::Err(XlError::Num)
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
  // All binary operators are left-associative, so chains form a left-deep
  // tree. Fold the left spine iteratively: an 8192-char formula must not
  // overflow the wasm-gc stack. Evaluation order (left subtree fully before
  // each right operand) and leftmost-error-wins are preserved.
  let spine : Array[(@syntax.BinOp, @syntax.Expr)] = []
  let mut cur = l
  let mut o = op
  let mut rhs = r
  while true {
    spine.push((o, rhs))
    match cur {
      Binary(o2, l2, r2) => {
        o = o2
        rhs = r2
        cur = l2
      }
      _ => break
    }
  }
  let mut acc = scalarize(eval_expr(ctx, cur))
  let mut i = spine.length() - 1
  while i >= 0 {
    let (o2, re) = spine[i]
    let rv = scalarize(eval_expr(ctx, re))
    acc = apply_binary(o2, acc, rv)
    i -= 1
  }
  acc
}

fn apply_binary(op : @syntax.BinOp, lv : Value, rv : Value) -> Value {
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

/// 解析并求值单条公式（不写入网格）。引用会递归求值。
///
/// 解析失败返回 `Err(ParseError)`；求值阶段的错误值（如 `#DIV/0!`）作为 `Ok` 中的
/// `Value::Err` 返回。超过 Excel 公式限制（8192 字符 / 64 层嵌套）按解析失败处理。
pub fn eval_formula(
  formula : String,
  grid : Grid,
  options : EvalOptions
) -> Result[EvalOutput, @syntax.ParseError] {
  let expr = try @syntax.parse(formula) catch { e => return Err(e) }
  let ctx = new_ctx(grid, options, None)
  let v = eval_expr(ctx, expr)
  Ok({ value: scalar_output(v), circular: ctx.circular.length() > 0 })
}

/// 求值网格中某个限定地址（`A1` 或 `SHEET!A1`）；空白格返回 `Blank`。
/// 循环引用语义与 `recalc` 一致。
pub fn eval_at_key(
  key : String,
  grid : Grid,
  options : EvalOptions
) -> EvalOutput {
  let (sheet, text) = @value.split_key(key)
  let k = match @value.parse_addr(text) {
    Some(a) => @value.sheet_key(sheet, a)
    None => key
  }
  let ctx = new_ctx(grid, options, None)
  let v = scalar_output(cell_value(ctx, k))
  { value: v, circular: ctx.circular.contains(k) }
}

/// 求值网格中某个单元格；空白格返回 `Blank`。循环引用语义与 `recalc` 一致。
pub fn eval_at(
  addr : CellAddr,
  grid : Grid,
  options : EvalOptions
) -> EvalOutput {
  eval_at_key(addr.key(), grid, options)
}

/// 按依赖关系重算整个网格（DFS + 记忆化 + 环检测）。
///
/// 循环引用复刻 Excel 默认（迭代计算关闭）：环上单元格结果为 0，元数据 `circular: true`。
pub fn recalc(grid : Grid, options : EvalOptions) -> RecalcOutput {
  recalc_impl(grid, options, None).0
}