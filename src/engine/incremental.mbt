// Incremental recalculation: caller-owned state with AST-extracted dependency
// edges. Only the dirty closure of changed cells is re-evaluated. Cycles and
// parse errors fall back to a full rebuild: cycle marking depends on DFS suffix
// order and parse_errors on DFS discovery order, neither of which is
// reproducible incrementally (correctness first).

/// 增量重算状态（调用方持有，单所有者）。由 `recalc_init` 创建，传给 `recalc_update`
/// 复用依赖图、AST 缓存与上次求值结果。
pub struct RecalcState {
  priv precedents : Map[String, Array[String]]
  priv dependents : Map[String, Array[String]]
  priv mut raw : Map[String, Value]
  priv circular : Map[String, Bool]
  priv cache : ParseCache
  priv mut has_cycle : Bool
  priv mut range_fallback : Bool
}

/// 全量重算并建立增量状态；输出与 `recalc` 完全一致。
pub fn recalc_init(
  grid : Grid,
  options : EvalOptions
) -> (RecalcState, RecalcOutput) {
  let state : RecalcState = {
    precedents: Map::new(),
    dependents: Map::new(),
    raw: Map::new(),
    circular: Map::new(),
    cache: new_parse_cache(),
    has_cycle: false,
    range_fallback: false,
  }
  let out = full_rebuild(state, grid, options)
  (state, out)
}

/// 增量重算：只重算 `changed` 的下游闭包，输出与 `recalc(grid, options)` 逐字段一致。
///
/// `changed` 必须列出相对上次调用网格内容发生变化的全部地址（含 Literal↔Formula
/// 切换与删除）。出现循环引用、解析错误或超大区域（>65536 格）时自动回退全量重算。
pub fn recalc_update(
  state : RecalcState,
  grid : Grid,
  changed : Array[String],
  options : EvalOptions
) -> RecalcOutput {
  if state.has_cycle || state.range_fallback {
    return full_rebuild(state, grid, options)
  }
  for key in changed {
    remove_edges(state, key)
    match grid.cells.get(key) {
      Some(cell) => add_edges(state, key, cell)
      None => ()
    }
  }
  if state.range_fallback {
    return full_rebuild(state, grid, options)
  }
  let dirty : Map[String, Bool] = Map::new()
  let queue : Array[String] = []
  for key in changed {
    if !dirty.contains(key) {
      dirty[key] = true
      queue.push(key)
    }
  }
  let mut i = 0
  while i < queue.length() {
    let key = queue[i]
    match state.dependents.get(key) {
      Some(deps) =>
        for d in deps {
          if !dirty.contains(d) {
            dirty[d] = true
            queue.push(d)
          }
        }
      None => ()
    }
    i += 1
  }
  let ctx = new_ctx(grid, options, Some(state.cache.entries))
  for key, v in state.raw {
    if !dirty.contains(key) {
      ctx.cache[key] = v
    }
  }
  for key, cell in grid.cells {
    if dirty.contains(key) {
      match cell {
        Formula(_) => {
          let _ = cell_value(ctx, key)
        }
        Literal(_) => ()
      }
    }
  }
  if ctx.circular.length() > 0 {
    return full_rebuild(state, grid, options)
  }
  for _, cell in grid.cells {
    match cell {
      Formula(src) =>
        match state.cache.entries.get(src) {
          Some(Bad(_)) => return full_rebuild(state, grid, options)
          _ => ()
        }
      Literal(_) => ()
    }
  }
  let out : Map[String, EvalOutput] = Map::new()
  for key, cell in grid.cells {
    match cell {
      Formula(_) => {
        let raw = ctx.cache.get(key).unwrap()
        state.raw[key] = raw
        state.circular.remove(key)
        out[key] = { value: scalar_output(raw), circular: false }
      }
      Literal(_) => ()
    }
  }
  { cells: out, parse_errors: [] }
}

fn full_rebuild(
  state : RecalcState,
  grid : Grid,
  options : EvalOptions
) -> RecalcOutput {
  let (out, raw) = recalc_impl(grid, options, Some(state.cache.entries))
  state.raw = raw
  state.circular.clear()
  state.has_cycle = false
  for key, o in out.cells {
    if o.circular {
      state.circular[key] = true
      state.has_cycle = true
    }
  }
  state.precedents.clear()
  state.dependents.clear()
  state.range_fallback = false
  for key, cell in grid.cells {
    add_edges(state, key, cell)
  }
  out
}

fn add_edges(state : RecalcState, key : String, cell : Cell) -> Unit {
  match cell {
    Literal(_) => ()
    Formula(src) => {
      let refs : Array[String] = []
      let ok = match state.cache.parse(src) {
        Some(e) => expr_refs(e, refs, 65536)
        None => true
      }
      if !ok {
        state.range_fallback = true
        return
      }
      let seen : Map[String, Bool] = Map::new()
      let uniq : Array[String] = []
      for r in refs {
        if !seen.contains(r) {
          seen[r] = true
          uniq.push(r)
        }
      }
      state.precedents[key] = uniq
      for r in uniq {
        match state.dependents.get(r) {
          Some(arr) => arr.push(key)
          None => state.dependents[r] = [key]
        }
      }
    }
  }
}

fn remove_edges(state : RecalcState, key : String) -> Unit {
  match state.precedents.get(key) {
    Some(refs) => {
      for r in refs {
        match state.dependents.get(r) {
          Some(arr) => state.dependents[r] = arr.filter(x => x != key)
          None => ()
        }
      }
      state.precedents.remove(key)
    }
    None => ()
  }
  state.raw.remove(key)
  state.circular.remove(key)
}

// Collect referenced cell keys from an AST (ranges expanded row-major).
// Returns false when the cap is exceeded; shared with iterative/explain.
fn expr_refs(e : @syntax.Expr, out : Array[String], cap : Int) -> Bool {
  match e {
    Lit(_) => true
    Ref(addr) => {
      out.push(addr.key())
      out.length() <= cap
    }
    Range(lo, hi) => {
      for r in lo.row..=hi.row {
        for c in lo.col..=hi.col {
          let a : CellAddr = { row: r, col: c, abs_row: false, abs_col: false }
          out.push(a.key())
          if out.length() > cap {
            return false
          }
        }
      }
      true
    }
    Unary(_, sub) => expr_refs(sub, out, cap)
    Binary(_, l, r) => expr_refs(l, out, cap) && expr_refs(r, out, cap)
    Call(_, args) => {
      for a in args {
        if !expr_refs(a, out, cap) {
          return false
        }
      }
      true
    }
  }
}

/// 网格依赖图（AST 级提取，区域展开、去重）：公式格 → 直接前驱 / 格 → 直接下游。
pub(all) struct DepGraph {
  /// 公式格 → 引用的单元格地址。
  precedents : Map[String, Array[String]]
  /// 单元格 → 直接引用它的公式格。
  dependents : Map[String, Array[String]]
} derive(Show, Debug)

/// 提取整网格依赖图；任一区域超过 65536 格时返回 `None`（调用方降级）。
pub fn dependency_graph(grid : Grid) -> DepGraph? {
  let cache = new_parse_cache()
  let g : DepGraph = { precedents: Map::new(), dependents: Map::new() }
  for key, cell in grid.cells {
    match cell {
      Formula(src) => {
        let refs : Array[String] = []
        let ok = match cache.parse(src) {
          Some(e) => expr_refs(e, refs, 65536)
          None => true
        }
        if !ok {
          return None
        }
        let seen : Map[String, Bool] = Map::new()
        let uniq : Array[String] = []
        for r in refs {
          if !seen.contains(r) {
            seen[r] = true
            uniq.push(r)
          }
        }
        g.precedents[key] = uniq
        for r in uniq {
          match g.dependents.get(r) {
            Some(arr) => arr.push(key)
            None => g.dependents[r] = [key]
          }
        }
      }
      Literal(_) => ()
    }
  }
  Some(g)
}