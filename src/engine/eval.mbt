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

/// CSE 数组公式：锚点格的公式与选中区域尺寸。
pub(all) struct CseSpec {
  formula : String
  rows : Int
  cols : Int
} derive(Show, Debug, Eq)

/// 数组公式布局（网格契约的可选扩展）：CSE 锚点 → 选中区域；动态数组锚点 → 公式。
/// 普通 `recalc` 不读取布局；`recalc_arrays` 在此之上叠加溢出/填充语义。
pub(all) struct ArrayLayout {
  cse : Map[String, CseSpec]
  dynamic : Map[String, String]
} derive(Show, Debug)

/// 创建一个空的数组公式布局。
pub fn new_array_layout() -> ArrayLayout {
  { cse: Map::new(), dynamic: Map::new() }
}

/// 全网格重算结果。
pub(all) struct RecalcOutput {
  /// 公式格的结果（字面值格不出现）。
  cells : Map[String, EvalOutput]
  /// 解析失败的格与原因（地址, 消息）；这些格的结果为 `#VALUE!`。
  parse_errors : Array[(String, String)]
}

/// 求值模式：普通公式（引用参与隐式交集）或数组上下文（CSE/动态数组，引用保持区域）。
pub(all) enum EvalMode {
  /// 普通单元格公式。
  Normal
  /// 数组公式/CSE 或动态数组求值。
  Array
} derive(Show, Debug, Eq)

/// 带数组布局的重算结果。
pub(all) struct ArrayRecalcOutput {
  /// 公式格（含 CSE/动态锚点）的结果。
  cells : Map[String, EvalOutput]
  /// 锚点及所有溢出/填充格的值（含锚点）。
  values : Map[String, Value]
  /// 锚点 → 溢出/选中区域的尺寸（供 `D4#` 解析）。
  ranges : Map[String, (Int, Int)]
  /// 解析失败的格与原因。
  parse_errors : Array[(String, String)]
} derive(Show, Debug)

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
  /// 普通/数组上下文。
  mut mode : EvalMode
  /// 当前公式宿主的行号（隐式交集用；0 = 未知）。
  mut host_row : Int
  /// 当前公式宿主的列号。
  mut host_col : Int
  /// 动态数组/ CSE 非锚点格的值：键 → 值。优先于网格字面/公式。
  spill : Map[String, Value]
  /// 动态数组锚点 → (rows, cols)，供 `D4#` 解析溢出区域。
  spill_ranges : Map[String, (Int, Int)]
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
    mode: Normal,
    host_row: 0,
    host_col: 0,
    spill: Map::new(),
    spill_ranges: Map::new(),
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
      let v = Value::Range(RangeValue::reference(sheet, lo.row, lo.col, rows, cols, cells))
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
/// 只以 `NAME:` 前缀的栈标记做环守卫：环上按真实 Excel 答案键返回 `#NAME?`
/// （见 corpus/cases/refs.json refs-names-011/012）。
fn eval_name(ctx : Ctx, name : String) -> Value {
  let text = match ctx.grid.names.get(name) {
    Some(t) => t
    None => return Value::Err(XlError::Name)
  }
  let guard_key = "NAME:" + name
  if ctx.on_stack.contains(guard_key) {
    // 真实 Excel 答案键（corpus/cases/refs.json refs-names-011/012，2026-11-17 桌面
    // Excel 2610）：循环定义名称求值为 #NAME?——Excel 把无法收敛的名称视为不可解析，
    // 而不是迭代关闭下的 0。故环上不返回 0、也不标 circular。
    return Value::Err(XlError::Name)
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
  if ctx.spill.get(key) is Some(v) {
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
          let (key_sheet, key_text) = @value.split_key(key)
          let host = @value.parse_addr(key_text)
          let saved_sheet = ctx.current_sheet
          let saved_row = ctx.host_row
          let saved_col = ctx.host_col
          ctx.current_sheet = key_sheet
          match host {
            Some(a) => {
              ctx.host_row = a.row
              ctx.host_col = a.col
            }
            None => {
              ctx.host_row = 0
              ctx.host_col = 0
            }
          }
          ctx.stack.push(key)
          ctx.on_stack[key] = true
          let r = eval_expr(ctx, e)
          let _ = ctx.stack.pop()
          let _ = ctx.on_stack.remove(key)
          ctx.current_sheet = saved_sheet
          ctx.host_row = saved_row
          ctx.host_col = saved_col
          if ctx.circular.contains(key) {
            match r {
              // 并集在标量上下文是 #VALUE!；Excel 探针 p105 显示该错误优先于
              // 循环引用的 0 占位。
              Range(rv) if rv.is_union() => Value::Err(XlError::Value)
              _ => Value::Num(0.0)
            }
          } else {
            r
          }
        }
      }
    }
  }
  ctx.cache[key] = v
  v
}


/// 取引用区域的分量；非引用/数组返回空数组。
fn ref_areas(v : Value) -> Array[RangeArea] {
  match v {
    Range(r) =>
      if r.is_union() {
        r.areas
      } else {
        match r.as_single_area() {
          Some(a) => [a]
          None => []
        }
      }
    _ => []
  }
}

/// 隐式交集：普通公式中的引用按宿主行/列收窄为单格。
/// 1×1 引用直接取值；并集/数组/宿主未知返回 #VALUE!；宿主不在引用范围内返回 #VALUE!。
fn formula_output(v : Value) -> Value {
  match v {
    Blank => Value::Num(0.0)
    _ => v
  }
}

fn implicit_intersect(ctx : Ctx, r : RangeValue) -> Value {
  if r.is_union() || !r.is_ref {
    return Value::Err(XlError::Value)
  }
  if r.rows == 1 && r.cols == 1 {
    return r.cells[0]
  }
  if ctx.host_row == 0 || ctx.host_col == 0 {
    return Value::Err(XlError::Value)
  }
  if r.cols == 1 {
    let off = ctx.host_row - r.origin_row
    if off >= 0 && off < r.rows {
      r.cells[off]
    } else {
      Value::Err(XlError::Value)
    }
  } else if r.rows == 1 {
    let off = ctx.host_col - r.origin_col
    if off >= 0 && off < r.cols {
      r.cells[off]
    } else {
      Value::Err(XlError::Value)
    }
  } else {
    let rr = ctx.host_row - r.origin_row
    let cc = ctx.host_col - r.origin_col
    if rr >= 0 && rr < r.rows && cc >= 0 && cc < r.cols {
      r.cells[rr * r.cols + cc]
    } else {
      Value::Err(XlError::Value)
    }
  }
}

/// 二元/一元运算的数组操作数：普通模式先把引用隐式交集；数组上下文保留区域。
fn to_array_operand(ctx : Ctx, v : Value) -> Value {
  match v {
    Range(r) =>
      if r.is_ref && ctx.mode == Normal {
        implicit_intersect(ctx, r)
      } else {
        v
      }
    _ => v
  }
}

/// 输出边界的标量化：引用按宿主隐式交集；数组取左上角；并集 #VALUE!；空白→0。
fn scalar_output_at(ctx : Ctx, v : Value) -> Value {
  let out = match v {
    Range(r) =>
      if r.is_union() {
        Value::Err(XlError::Value)
      } else if r.is_ref {
        implicit_intersect(ctx, r)
      } else {
        r.cells[0]
      }
    _ => v
  }
  formula_output(out)
}

fn intersect_rect(a : RangeArea, b : RangeArea) -> RangeArea? {
  if a.sheet != b.sheet {
    return None
  }
  let r0 = if a.row > b.row { a.row } else { b.row }
  let c0 = if a.col > b.col { a.col } else { b.col }
  let ar1 = a.row + a.rows - 1
  let br1 = b.row + b.rows - 1
  let ac1 = a.col + a.cols - 1
  let bc1 = b.col + b.cols - 1
  let r1 = if ar1 < br1 { ar1 } else { br1 }
  let c1 = if ac1 < bc1 { ac1 } else { bc1 }
  if r0 > r1 || c0 > c1 {
    return None
  }
  let rows = r1 - r0 + 1
  let cols = c1 - c0 + 1
  let cells : Array[Value] = []
  for r in r0..=r1 {
    for c in c0..=c1 {
      let idx = (r - a.row) * a.cols + (c - a.col)
      cells.push(a.cells[idx])
    }
  }
  Some({ sheet: a.sheet, row: r0, col: c0, rows, cols, cells })
}

fn eval_intersect(lv : Value, rv : Value) -> Value {
  let la = ref_areas(lv)
  let ra = ref_areas(rv)
  if la.length() == 0 || ra.length() == 0 {
    return Value::Err(XlError::Value)
  }
  let out : Array[RangeArea] = []
  for a in la {
    for b in ra {
      match intersect_rect(a, b) {
        Some(x) => out.push(x)
        None => ()
      }
    }
  }
  if out.length() == 0 {
    return Value::Err(XlError::Null)
  }
  if out.length() == 1 {
    let a = out[0]
    Value::Range(RangeValue::reference(a.sheet, a.row, a.col, a.rows, a.cols, a.cells))
  } else {
    Value::Range(RangeValue::union(out))
  }
}

fn eval_union(lv : Value, rv : Value) -> Value {
  let la = ref_areas(lv)
  let ra = ref_areas(rv)
  if la.length() == 0 || ra.length() == 0 {
    return Value::Err(XlError::Value)
  }
  let all : Array[RangeArea] = []
  for a in la {
    all.push(a)
  }
  for b in ra {
    all.push(b)
  }
  Value::Range(RangeValue::union(all))
}

fn eval_array_lit(ctx : Ctx, rows : Array[Array[@syntax.Expr]]) -> Value {
  let out : Array[Value] = []
  let ncols = rows[0].length()
  for row in rows {
    for e in row {
      match eval_expr(ctx, e) {
        Range(_) => out.push(Value::Err(XlError::Value))
        v => out.push(v)
      }
    }
  }
  Value::Range(RangeValue::array(rows.length(), ncols, out))
}

/// `D4#`：按锚点记录的溢出区域读取所有格（锚点取公式值，其余取 spill 映射）。
fn eval_spill(ctx : Ctx, sub : @syntax.Expr) -> Value {
  let v = eval_expr(ctx, sub)
  let r = match v {
    Range(x) => x
    _ => return Value::Err(XlError::Value)
  }
  if !r.is_ref || r.is_union() || r.rows != 1 || r.cols != 1 {
    return Value::Err(XlError::Value)
  }
  let anchor : CellAddr = { row: r.origin_row, col: r.origin_col, abs_row: false, abs_col: false }
  let key = @value.sheet_key(r.sheet, anchor)
  let (rows, cols) = match ctx.spill_ranges.get(key) {
    Some(x) => x
    None => return Value::Err(XlError::Ref)
  }
  let cells : Array[Value] = []
  for rr in 0..<rows {
    for cc in 0..<cols {
      let a : CellAddr = { row: anchor.row + rr, col: anchor.col + cc, abs_row: false, abs_col: false }
      let k = @value.sheet_key(r.sheet, a)
      let cv = if rr == 0 && cc == 0 {
        cell_value(ctx, k)
      } else {
        match ctx.spill.get(k) {
          Some(x) => x
          None => Value::Blank
        }
      }
      cells.push(cv)
    }
  }
  Value::Range(RangeValue::array(rows, cols, cells))
}

fn apply_unary_scalar(op : @syntax.UnOp, v : Value) -> Value {
  match op {
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
}

fn apply_unary(op : @syntax.UnOp, v : Value) -> Value {
  match v {
    Range(r) => {
      let cells : Array[Value] = []
      for c in r.cells {
        cells.push(apply_unary_scalar(op, c))
      }
      Value::Range(RangeValue::array(r.rows, r.cols, cells))
    }
    _ => apply_unary_scalar(op, v)
  }
}

fn operand_cell(r : RangeValue, rr : Int, cc : Int) -> Value {
  let er = if r.rows == 1 { 0 } else { rr }
  let ec = if r.cols == 1 { 0 } else { cc }
  if er < r.rows && ec < r.cols {
    r.cells[er * r.cols + ec]
  } else {
    Value::Err(XlError::NA)
  }
}

fn apply_binary_elementwise(op : @syntax.BinOp, a : RangeValue, b : RangeValue) -> Value {
  let rows = if a.rows > b.rows { a.rows } else { b.rows }
  let cols = if a.cols > b.cols { a.cols } else { b.cols }
  let cells : Array[Value] = []
  for rr in 0..<rows {
    for cc in 0..<cols {
      cells.push(apply_binary(op, operand_cell(a, rr, cc), operand_cell(b, rr, cc)))
    }
  }
  Value::Range(RangeValue::array(rows, cols, cells))
}

fn apply_binary_any(op : @syntax.BinOp, lv : Value, rv : Value) -> Value {
  match (lv, rv) {
    (Range(a), Range(b)) => apply_binary_elementwise(op, a, b)
    (Range(a), _) => apply_binary_elementwise(op, a, RangeValue::array(1, 1, [rv]))
    (_, Range(b)) => apply_binary_elementwise(op, RangeValue::array(1, 1, [lv]), b)
    _ => apply_binary(op, lv, rv)
  }
}


/// 仅按引用几何求值交集/并集的左操作数：返回区域矩形，不读取任何单元格。
/// 这是避免“公式宿主格落在源区域内、但交集结果不含宿主格”被误判为循环引用的关键。
fn expr_areas(ctx : Ctx, e : @syntax.Expr) -> Array[RangeArea]? {
  match e {
    Ref(addr) => Some([{ sheet: ctx.current_sheet, row: addr.row, col: addr.col, rows: 1, cols: 1, cells: [] }])
    Range(lo, hi) => {
      let r0 = if lo.row < hi.row { lo.row } else { hi.row }
      let r1 = if lo.row < hi.row { hi.row } else { lo.row }
      let c0 = if lo.col < hi.col { lo.col } else { hi.col }
      let c1 = if lo.col < hi.col { hi.col } else { lo.col }
      Some([{ sheet: ctx.current_sheet, row: r0, col: c0, rows: r1 - r0 + 1, cols: c1 - c0 + 1, cells: [] }])
    }
    Sheet(sheet, inner) => {
      let saved = ctx.current_sheet
      ctx.current_sheet = sheet
      let out = expr_areas(ctx, inner)
      ctx.current_sheet = saved
      out
    }
    WholeCols(c1, c2) => {
      let (mr, _) = used_bounds(ctx, ctx.current_sheet)
      let c0 = if c1 < c2 { c1 } else { c2 }
      let ce = if c1 < c2 { c2 } else { c1 }
      Some([{ sheet: ctx.current_sheet, row: 1, col: c0, rows: if mr == 0 { 1 } else { mr }, cols: ce - c0 + 1, cells: [] }])
    }
    WholeRows(r1, r2) => {
      let (_, mc) = used_bounds(ctx, ctx.current_sheet)
      let r0 = if r1 < r2 { r1 } else { r2 }
      let re = if r1 < r2 { r2 } else { r1 }
      Some([{ sheet: ctx.current_sheet, row: r0, col: 1, rows: re - r0 + 1, cols: if mc == 0 { 1 } else { mc }, cells: [] }])
    }
    Union(l, r) =>
      match (expr_areas(ctx, l), expr_areas(ctx, r)) {
        (Some(a), Some(b)) => {
          let out : Array[RangeArea] = []
          for x in a { out.push(x) }
          for x in b { out.push(x) }
          Some(out)
        }
        _ => None
      }
    Intersect(l, r) =>
      match (expr_areas(ctx, l), expr_areas(ctx, r)) {
        (Some(a), Some(b)) => {
          let out : Array[RangeArea] = []
          for x in a {
            for y in b {
              match geom_intersect(x, y) {
                Some(z) => out.push(z)
                None => ()
              }
            }
          }
          Some(out)
        }
        _ => None
      }
    _ => None
  }
}

fn geom_intersect(a : RangeArea, b : RangeArea) -> RangeArea? {
  if a.sheet != b.sheet { return None }
  let r0 = if a.row > b.row { a.row } else { b.row }
  let c0 = if a.col > b.col { a.col } else { b.col }
  let ar1 = a.row + a.rows - 1
  let br1 = b.row + b.rows - 1
  let ac1 = a.col + a.cols - 1
  let bc1 = b.col + b.cols - 1
  let r1 = if ar1 < br1 { ar1 } else { br1 }
  let c1 = if ac1 < bc1 { ac1 } else { bc1 }
  if r0 > r1 || c0 > c1 { return None }
  Some({ sheet: a.sheet, row: r0, col: c0, rows: r1 - r0 + 1, cols: c1 - c0 + 1, cells: [] })
}

fn materialize_area(ctx : Ctx, a : RangeArea) -> Value {
  let lo : CellAddr = { row: a.row, col: a.col, abs_row: false, abs_col: false }
  let hi : CellAddr = { row: a.row + a.rows - 1, col: a.col + a.cols - 1, abs_row: false, abs_col: false }
  materialize_range(ctx, a.sheet, lo, hi)
}

fn eval_intersect_expr(ctx : Ctx, l : @syntax.Expr, r : @syntax.Expr) -> Value {
  match (expr_areas(ctx, l), expr_areas(ctx, r)) {
    (Some(la), Some(ra)) => {
      let out : Array[RangeArea] = []
      for a in la {
        for b in ra {
          match geom_intersect(a, b) {
            Some(z) => out.push(z)
            None => ()
          }
        }
      }
      if out.length() == 0 {
        Value::Err(XlError::Null)
      } else if out.length() == 1 {
        materialize_area(ctx, out[0])
      } else {
        let mats : Array[RangeArea] = []
        for a in out {
          match materialize_area(ctx, a) {
            Range(rv) => mats.push({ sheet: rv.sheet, row: rv.origin_row, col: rv.origin_col, rows: rv.rows, cols: rv.cols, cells: rv.cells })
            _ => ()
          }
        }
        Value::Range(RangeValue::union(mats))
      }
    }
    _ => eval_intersect(eval_expr(ctx, l), eval_expr(ctx, r))
  }
}

fn eval_union_expr(ctx : Ctx, l : @syntax.Expr, r : @syntax.Expr) -> Value {
  match (expr_areas(ctx, l), expr_areas(ctx, r)) {
    (Some(la), Some(ra)) => {
      let mats : Array[RangeArea] = []
      for a in la {
        match materialize_area(ctx, a) {
          Range(rv) => mats.push({ sheet: rv.sheet, row: rv.origin_row, col: rv.origin_col, rows: rv.rows, cols: rv.cols, cells: rv.cells })
          _ => ()
        }
      }
      for b in ra {
        match materialize_area(ctx, b) {
          Range(rv) => mats.push({ sheet: rv.sheet, row: rv.origin_row, col: rv.origin_col, rows: rv.rows, cols: rv.cols, cells: rv.cells })
          _ => ()
        }
      }
      Value::Range(RangeValue::union(mats))
    }
    _ => eval_union(eval_expr(ctx, l), eval_expr(ctx, r))
  }
}


fn index_number(ctx : Ctx, e : @syntax.Expr) -> Result[Int, XlError] {
  match eval_expr(ctx, e) {
    v =>
      match to_number(v) {
        Ok(d) => Ok(d.trunc().to_int())
        Err(err) => Err(err)
      }
  }
}

/// 惰性 INDEX：按引用几何先算出返回的子区域，只物化该子区域。
/// 这样 `=INDEX(A1:C3,0,1)` 写在 C3 时不会因为读取整张 A1:C3 而误判循环。
fn eval_index_ref(ctx : Ctx, args : Array[@syntax.Expr]) -> Value? {
  if args.length() < 2 || args.length() > 4 {
    return None
  }
  let areas = match expr_areas(ctx, args[0]) {
    Some(a) if a.length() > 0 => a
    _ => return None
  }
  let area_no = if args.length() == 4 {
    match index_number(ctx, args[3]) {
      Ok(n) => n
      Err(e) => return Some(Value::Err(e))
    }
  } else {
    1
  }
  if area_no < 1 || area_no > areas.length() {
    return Some(Value::Err(XlError::Ref))
  }
  let a = areas[area_no - 1]
  let rn = match index_number(ctx, args[1]) {
    Ok(n) => n
    Err(e) => return Some(Value::Err(e))
  }
  if args.length() == 2 && a.rows == 1 && a.cols > 1 {
    if rn < 1 || rn > a.cols {
      return Some(Value::Err(XlError::Ref))
    }
    return Some(materialize_area(ctx, {
      sheet: a.sheet,
      row: a.row,
      col: a.col + rn - 1,
      rows: 1,
      cols: 1,
      cells: [],
    }))
  }
  let cn = if args.length() >= 3 {
    match index_number(ctx, args[2]) {
      Ok(n) => n
      Err(e) => return Some(Value::Err(e))
    }
  } else {
    1
  }
  if rn < 0 || cn < 0 || rn > a.rows || cn > a.cols {
    return Some(Value::Err(XlError::Ref))
  }
  let r0 = if rn == 0 { 1 } else { rn }
  let r1 = if rn == 0 { a.rows } else { rn }
  let c0 = if cn == 0 { 1 } else { cn }
  let c1 = if cn == 0 { a.cols } else { cn }
  Some(materialize_area(ctx, {
    sheet: a.sheet,
    row: a.row + r0 - 1,
    col: a.col + c0 - 1,
    rows: r1 - r0 + 1,
    cols: c1 - c0 + 1,
    cells: [],
  }))
}

fn eval_expr(ctx : Ctx, e : @syntax.Expr) -> Value {
  match e {
    Lit(v) => v
    // A reference stays a 1x1 range so aggregates apply the reference
    // channel (ignore text/bool/blank) while literals coerce.
    Ref(addr) =>
      match cell_value(ctx, @value.sheet_key(ctx.current_sheet, addr)) {
        Range(r) => Value::Range(r)
        v => Value::Range(RangeValue::reference(ctx.current_sheet, addr.row, addr.col, 1, 1, [v]))
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
    ArrayLit(rows) => eval_array_lit(ctx, rows)
    Intersect(l, r) => eval_intersect_expr(ctx, l, r)
    Union(l, r) => eval_union_expr(ctx, l, r)
    Implicit(sub) =>
      match eval_expr(ctx, sub) {
        Range(r) =>
          if r.is_union() {
            Value::Err(XlError::Value)
          } else if r.is_ref {
            implicit_intersect(ctx, r)
          } else {
            r.cells[0]
          }
        v => v
      }
    Spill(sub) => eval_spill(ctx, sub)
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
      let mut v = to_array_operand(ctx, eval_expr(ctx, cur))
      let mut i = ops.length() - 1
      while i >= 0 {
        // Excel unary plus is an identity operator: +"3" stays text "3" and
        // +TRUE stays boolean TRUE; only unary minus / percent coerce.
        v = apply_unary(ops[i], v)
        i -= 1
      }
      v
    }
    Binary(op, l, r) => eval_binary(ctx, op, l, r)
    Call(name, args) =>
      if name == "INDEX" {
        match eval_index_ref(ctx, args) {
          Some(v) => v
          None => eval_call(ctx, name, args)
        }
      } else {
        eval_call(ctx, name, args)
      }
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
  let mut acc = to_array_operand(ctx, eval_expr(ctx, cur))
  let mut i = spine.length() - 1
  while i >= 0 {
    let (o2, re) = spine[i]
    let rv = to_array_operand(ctx, eval_expr(ctx, re))
    acc = apply_binary_any(o2, acc, rv)
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
  // 独立公式默认按 Excel 答案键的宿主格 ZZ1 求值；隐式交集需要宿主坐标。
  eval_formula_at(formula, "ZZ1", grid, options)
}

/// 在指定宿主格求值单条公式（隐式交集/`@` 依宿主坐标）。
pub fn eval_formula_at(
  formula : String,
  host_key : String,
  grid : Grid,
  options : EvalOptions
) -> Result[EvalOutput, @syntax.ParseError] {
  let expr = try @syntax.parse(formula) catch { e => return Err(e) }
  let ctx = new_ctx(grid, options, None)
  let (sheet, text) = @value.split_key(host_key)
  ctx.current_sheet = sheet
  match @value.parse_addr(text) {
    Some(a) => {
      ctx.host_row = a.row
      ctx.host_col = a.col
    }
    None => {
      ctx.host_row = 0
      ctx.host_col = 0
    }
  }
  let v = eval_expr(ctx, expr)
  Ok({ value: scalar_output_at(ctx, v), circular: ctx.circular.length() > 0 })
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
  match @value.parse_addr(text) {
    Some(a) => {
      ctx.host_row = a.row
      ctx.host_col = a.col
    }
    None => ()
  }
  let v = scalar_output_at(ctx, cell_value(ctx, k))
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

/// 在布局中登记一个 CSE 数组公式（锚点须为选中区域左上角）。
pub fn ArrayLayout::set_cse(
  self : ArrayLayout,
  key : String,
  formula : String,
  rows : Int,
  cols : Int
) -> Unit {
  self.cse[key] = { formula, rows, cols }
}

/// 在布局中登记一个动态数组公式。
pub fn ArrayLayout::set_dynamic(
  self : ArrayLayout,
  key : String,
  formula : String
) -> Unit {
  self.dynamic[key] = formula
}

fn parse_layout_formula(ctx : Ctx, key : String, formula : String) -> @syntax.Expr? {
  try {
    Some(@syntax.parse(formula))
  } catch {
    @syntax.ParseError(msg) => {
      ctx.parse_errors.push((key, msg))
      None
    }
  }
}

/// 以 Array 模式求值布局公式，返回原始（未标量化）结果。
/// 在宿主格上下文中求值并标量化：隐式交集需要当前格的行列，
/// `cell_value` 返回后会把宿主恢复，因此标量化必须在其外层完成。
fn cell_scalar_at(ctx : Ctx, key : String) -> Value {
  let (sheet, host_opt) = sheet_of_key(key)
  let host = match host_opt {
    Some(a) => a
    None => return Value::Err(XlError::Ref)
  }
  let saved_sheet = ctx.current_sheet
  let saved_row = ctx.host_row
  let saved_col = ctx.host_col
  let saved_mode = ctx.mode
  ctx.current_sheet = sheet
  ctx.host_row = host.row
  ctx.host_col = host.col
  ctx.mode = Normal
  let v = scalar_output_at(ctx, cell_value(ctx, key))
  ctx.current_sheet = saved_sheet
  ctx.host_row = saved_row
  ctx.host_col = saved_col
  ctx.mode = saved_mode
  v
}

fn eval_layout_formula(ctx : Ctx, key : String, formula : String) -> Value {
  let expr = match parse_layout_formula(ctx, key, formula) {
    Some(e) => e
    None => return Value::Err(XlError::Value)
  }
  let (sheet, text) = @value.split_key(key)
  let host = @value.parse_addr(text)
  let saved_sheet = ctx.current_sheet
  let saved_row = ctx.host_row
  let saved_col = ctx.host_col
  let saved_mode = ctx.mode
  ctx.current_sheet = sheet
  match host {
    Some(a) => {
      ctx.host_row = a.row
      ctx.host_col = a.col
    }
    None => {
      ctx.host_row = 0
      ctx.host_col = 0
    }
  }
  ctx.mode = Array
  let v = eval_expr(ctx, expr)
  ctx.current_sheet = saved_sheet
  ctx.host_row = saved_row
  ctx.host_col = saved_col
  ctx.mode = saved_mode
  v
}

fn array_at(r : RangeValue, row : Int, col : Int) -> Value {
  if r.is_union() || r.rows <= 0 || r.cols <= 0 {
    Value::Err(XlError::Value)
  } else if row >= r.rows || col >= r.cols {
    Value::Err(XlError::NA)
  } else {
    r.cells[row * r.cols + col]
  }
}

/// CSE 填充：结果按行/列循环复制；超出结果列数补 #N/A；标量填满选区。
fn cse_fill_value(r : RangeValue, row : Int, col : Int) -> Value {
  if r.rows == 1 && r.cols == 1 {
    r.cells[0]
  } else {
    // 单行结果沿行方向复制、单列结果沿列方向复制；结果维度 >1 的超出方向补 #N/A。
    // 探针：2x1 → 2x2 得 [[5,5],[8,8]]；1x2 → 1x3 得 [1,2,#N/A]。
    let rr = if r.rows == 1 { 0 } else if row >= r.rows {
      return Value::Err(XlError::NA)
    } else {
      row
    }
    let cc = if r.cols == 1 { 0 } else if col >= r.cols {
      return Value::Err(XlError::NA)
    } else {
      col
    }
    array_at(r, rr, cc)
  }
}

fn sheet_of_key(key : String) -> (String, CellAddr?) {
  let (sheet, text) = @value.split_key(key)
  (sheet, @value.parse_addr(text))
}

fn offset_key(sheet : String, base : CellAddr, dr : Int, dc : Int) -> String {
  let a : CellAddr = {
    row: base.row + dr,
    col: base.col + dc,
    abs_row: false,
    abs_col: false,
  }
  @value.sheet_key(sheet, a)
}

fn in_layout(layout : ArrayLayout, key : String) -> Bool {
  layout.cse.contains(key) || layout.dynamic.contains(key)
}

/// 带 CSE / 动态数组布局的全网格重算。
///
/// 先求值数组锚点并把溢出/填充值登记到上下文，再按依赖顺序求值普通公式；
/// 普通公式可以引用溢出格。动态溢出被占用时锚点为 `#SPILL!`。
pub fn recalc_arrays(
  grid : Grid,
  layout : ArrayLayout,
  options : EvalOptions
) -> ArrayRecalcOutput {
  let ctx = new_ctx(grid, options, None)
  let out : Map[String, EvalOutput] = Map::new()
  let values : Map[String, Value] = Map::new()
  let ranges : Map[String, (Int, Int)] = Map::new()

  // 1) CSE：选区是公式自身的领地，先占位。
  let cse_keys : Array[String] = []
  for key, _ in layout.cse {
    cse_keys.push(key)
  }
  cse_keys.sort()
  for key in cse_keys {
    let spec = layout.cse[key]
    let raw = eval_layout_formula(ctx, key, spec.formula)
    let (sheet, host_opt) = sheet_of_key(key)
    let host = match host_opt {
      Some(a) => a
      None => {
        ctx.cache[key] = Value::Err(XlError::Ref)
        values[key] = Value::Err(XlError::Ref)
        out[key] = { value: Value::Err(XlError::Ref), circular: false }
        continue
      }
    }
    // 选区被其它网格内容占用：Excel 无法录入这样一块 CSE，按 #SPILL! 拒绝。
    let mut blocked = false
    if spec.rows <= 0 || spec.cols <= 0 ||
      host.row + spec.rows - 1 > @value.max_row ||
      host.col + spec.cols - 1 > @value.max_col {
      blocked = true
    } else {
      for dr in 0..<spec.rows {
        for dc in 0..<spec.cols {
          if dr == 0 && dc == 0 {
            continue
          }
          let k = offset_key(sheet, host, dr, dc)
          if grid.cells.contains(k) && !in_layout(layout, k) {
            blocked = true
          }
        }
      }
    }
    if blocked {
      ctx.cache[key] = Value::Err(XlError::Spill)
      values[key] = Value::Err(XlError::Spill)
      out[key] = { value: Value::Err(XlError::Spill), circular: false }
      continue
    }
    match raw {
      Range(r) =>
        if r.is_union() {
          // CSE 选区内每个格都放 #VALUE!（Excel 探针 q053：2x1 全错误）。
          ctx.cache[key] = Value::Err(XlError::Value)
          ctx.spill_ranges[key] = (spec.rows, spec.cols)
          ranges[key] = (spec.rows, spec.cols)
          values[key] = Value::Err(XlError::Value)
          for dr in 0..<spec.rows {
            for dc in 0..<spec.cols {
              let k = offset_key(sheet, host, dr, dc)
              values[k] = Value::Err(XlError::Value)
              if dr != 0 || dc != 0 {
                ctx.spill[k] = Value::Err(XlError::Value)
              }
            }
          }
          out[key] = { value: Value::Err(XlError::Value), circular: false }
        } else {
          let anchor_v = cse_fill_value(r, 0, 0)
          ctx.cache[key] = anchor_v
          ctx.spill_ranges[key] = (spec.rows, spec.cols)
          ranges[key] = (spec.rows, spec.cols)
          values[key] = anchor_v
          for dr in 0..<spec.rows {
            for dc in 0..<spec.cols {
              let v = cse_fill_value(r, dr, dc)
              let k = offset_key(sheet, host, dr, dc)
              values[k] = v
              if dr != 0 || dc != 0 {
                ctx.spill[k] = v
              }
            }
          }
          out[key] = { value: anchor_v, circular: ctx.circular.contains(key) }
        }
      v => {
        // 标量/错误填满整个选区。
        ctx.cache[key] = v
        ctx.spill_ranges[key] = (spec.rows, spec.cols)
        ranges[key] = (spec.rows, spec.cols)
        values[key] = v
        for dr in 0..<spec.rows {
          for dc in 0..<spec.cols {
            let k = offset_key(sheet, host, dr, dc)
            values[k] = v
            if dr != 0 || dc != 0 {
              ctx.spill[k] = v
            }
          }
        }
        out[key] = { value: v, circular: ctx.circular.contains(key) }
      }
    }
  }

  // 2) 动态数组：溢出区不得与网格/已有 CSE/其它溢出重叠。
  let dyn_keys : Array[String] = []
  for key, _ in layout.dynamic {
    dyn_keys.push(key)
  }
  dyn_keys.sort()
  for key in dyn_keys {
    let formula = layout.dynamic[key]
    let raw = eval_layout_formula(ctx, key, formula)
    let (sheet, host_opt) = sheet_of_key(key)
    let host = match host_opt {
      Some(a) => a
      None => {
        ctx.cache[key] = Value::Err(XlError::Ref)
        values[key] = Value::Err(XlError::Ref)
        out[key] = { value: Value::Err(XlError::Ref), circular: false }
        continue
      }
    }
    match raw {
      Range(r) =>
        if r.is_union() {
          ctx.cache[key] = Value::Err(XlError::Value)
          values[key] = Value::Err(XlError::Value)
          out[key] = { value: Value::Err(XlError::Value), circular: false }
        } else if r.rows * r.cols <= 1 {
          let v = array_at(r, 0, 0)
          ctx.cache[key] = v
          values[key] = v
          out[key] = { value: v, circular: ctx.circular.contains(key) }
        } else {
          let mut blocked = host.row + r.rows - 1 > @value.max_row ||
            host.col + r.cols - 1 > @value.max_col
          if !blocked {
            for dr in 0..<r.rows {
              for dc in 0..<r.cols {
                let k = offset_key(sheet, host, dr, dc)
                if k != key &&
                  (grid.cells.contains(k) ||
                    ctx.spill.contains(k) ||
                    ctx.cache.contains(k) ||
                    in_layout(layout, k)) {
                  blocked = true
                }
              }
            }
          }
          if blocked {
            ctx.cache[key] = Value::Err(XlError::Spill)
            values[key] = Value::Err(XlError::Spill)
            out[key] = { value: Value::Err(XlError::Spill), circular: false }
          } else {
            let anchor_v = r.cells[0]
            ctx.cache[key] = anchor_v
            ctx.spill_ranges[key] = (r.rows, r.cols)
            ranges[key] = (r.rows, r.cols)
            values[key] = anchor_v
            for dr in 0..<r.rows {
              for dc in 0..<r.cols {
                let v = r.cells[dr * r.cols + dc]
                let k = offset_key(sheet, host, dr, dc)
                values[k] = v
                if dr != 0 || dc != 0 {
                  ctx.spill[k] = v
                }
              }
            }
            out[key] = { value: anchor_v, circular: ctx.circular.contains(key) }
          }
        }
      v => {
        ctx.cache[key] = v
        values[key] = v
        out[key] = { value: v, circular: ctx.circular.contains(key) }
      }
    }
  }

  // 3) 普通公式（布局锚点已预求值）。
  for key, cell in grid.cells {
    if in_layout(layout, key) {
      continue
    }
    match cell {
      Formula(_) => {
        let v = cell_scalar_at(ctx, key)
        out[key] = { value: v, circular: ctx.circular.contains(key) }
      }
      Literal(_) => ()
    }
  }

  { cells: out, values, ranges, parse_errors: ctx.parse_errors }
}

/// 按依赖关系重算整个网格（DFS + 记忆化 + 环检测）。
///
/// 循环引用复刻 Excel 默认（迭代计算关闭）：环上单元格结果为 0，元数据 `circular: true`。
pub fn recalc(grid : Grid, options : EvalOptions) -> RecalcOutput {
  recalc_impl(grid, options, None).0
}