// Error explanation: trace which precedents actually contribute to a cell's
// error value (leftmost-wins aware) via contribution probes, reusing the DFS
// engine and AST-level reference extraction.

/// 错误传播路径上的一步。
pub(all) struct ExplainStep {
  /// 单元格地址。
  addr : String
  /// 公式源码；字面值格为空串。
  formula : String
  /// 求值结果（链上格均为错误值）。
  value : Value
  /// 是否错误源头（无贡献性错误前驱）。
  is_source : Bool
  /// 直接前驱地址（AST 提取，区域展开、去重）。
  precedents : Array[String]
} derive(Show, Debug)

/// 错误解释结果。
pub(all) struct ExplainOutput {
  /// 目标单元格地址。
  target : String
  /// 目标求值结果。
  value : Value
  /// 目标是否落在循环引用环上（环不是错误传播，steps 为空）。
  circular : Bool
  /// 源→目标顺序的传播路径；目标非错误时为空。
  steps : Array[ExplainStep]
  /// 错误源头地址（地址序）。
  sources : Array[String]
  /// 目标解析失败时的消息。
  parse_error : String?
} derive(Show, Debug)

fn cell_precedents(
  grid : Grid,
  key : String,
  cache : ParseCache
) -> Array[String] {
  match grid.cells.get(key) {
    Some(Formula(src)) => {
      let refs : Array[String] = []
      match cache.parse(src) {
        Some(e) => {
          let _ = expr_refs(e, refs, 65536)
        }
        None => ()
      }
      let seen : Map[String, Bool] = Map::new()
      let uniq : Array[String] = []
      for r in refs {
        if !seen.contains(r) {
          seen[r] = true
          uniq.push(r)
        }
      }
      uniq
    }
    _ => []
  }
}

// Re-evaluate C with precedent P replaced by 0: if C's error disappears or
// changes, P contributes to it. This reproduces leftmost-wins (replacing the
// right-hand error of A1+A2 leaves the result unchanged) and also handles
// error-ignoring functions (COUNT) and lazy branches naturally.
fn probe_contributes(
  grid : Grid,
  options : EvalOptions,
  raw : Map[String, Value],
  cache : ParseCache,
  c_key : String,
  p_key : String
) -> Bool {
  let original = scalar_output(raw[c_key])
  let ctx = new_ctx(grid, options, Some(cache.entries))
  for k, v in raw {
    ctx.cache[k] = v
  }
  ctx.cache[p_key] = Value::Num(0.0)
  let probe = match grid.cells.get(c_key) {
    Some(Formula(src)) =>
      match parse_formula(ctx, c_key, src) {
        Some(e) => scalar_output(eval_expr(ctx, e))
        None => Value::Err(XlError::Value)
      }
    _ => original
  }
  probe != original
}

/// 解释单元格的错误来源：返回贡献性错误传播路径（源→目标）与错误源头。
///
/// 目标非错误值或落在环上时 `steps` 为空。上游超过 256 格时降级为纯错误前驱链
///（过近似，不做贡献性探针）。
pub fn explain(
  addr : CellAddr,
  grid : Grid,
  options : EvalOptions
) -> ExplainOutput {
  let key = addr.key()
  let cache = new_parse_cache()
  let (out, raw) = recalc_impl(grid, options, Some(cache.entries))
  let target_out = match out.cells.get(key) {
    Some(o) => o
    None => {
      let v = match grid.cells.get(key) {
        Some(Literal(lit)) => lit
        _ => Value::Blank
      }
      { value: scalar_output(v), circular: false }
    }
  }
  let parse_error = match grid.cells.get(key) {
    Some(Formula(src)) =>
      match cache.entries.get(src) {
        Some(Bad(msg)) => Some(msg)
        _ => None
      }
    _ => None
  }
  let base : ExplainOutput = {
    target: key,
    value: target_out.value,
    circular: target_out.circular,
    steps: [],
    sources: [],
    parse_error,
  }
  if target_out.circular {
    return base
  }
  match target_out.value {
    Err(_) => ()
    _ => return base
  }
  // Upstream closure (cap 256 cells; beyond that degrade to the plain
  // error-precedent chain without contribution probes).
  let prec : Map[String, Array[String]] = Map::new()
  let closure : Map[String, Bool] = Map::new()
  let queue : Array[String] = [key]
  closure[key] = true
  let mut i = 0
  let mut oversized = false
  while i < queue.length() && !oversized {
    let k = queue[i]
    let refs = cell_precedents(grid, k, cache)
    prec[k] = refs
    for r in refs {
      if !closure.contains(r) {
        closure[r] = true
        queue.push(r)
        if closure.length() > 256 {
          oversized = true
          break
        }
      }
    }
    i += 1
  }
  // Iterative DFS postorder over contribution edges: sources first, target last.
  // Contribution rule: a precedent contributes if replacing it with 0 changes
  // the cell's error (effective, leftmost-wins aware). When every probe is
  // unchanged (identical errors masking each other, e.g. a diamond), keep all
  // error precedents — they share the same underlying source.
  let contrib : Map[String, Array[String]] = Map::new()
  let steps : Array[ExplainStep] = []
  let sources : Array[String] = []
  let visited : Map[String, Bool] = Map::new()
  let stack : Array[(String, Bool)] = [(key, false)]
  while stack.length() > 0 {
    let (k, expanded) = stack.pop().unwrap()
    if expanded {
      let cps = contrib[k]
      let formula = match grid.cells.get(k) {
        Some(Formula(src)) => src
        _ => ""
      }
      let value = match raw.get(k) {
        Some(v) => scalar_output(v)
        None => target_out.value
      }
      let refs = match prec.get(k) {
        Some(rs) => rs
        None => []
      }
      steps.push({
        addr: k,
        formula,
        value,
        is_source: cps.length() == 0,
        precedents: refs,
      })
      if cps.length() == 0 {
        sources.push(k)
      }
    } else {
      if visited.contains(k) {
        continue
      }
      visited[k] = true
      stack.push((k, true))
      let refs = match prec.get(k) {
        Some(rs) => rs
        None => cell_precedents(grid, k, cache)
      }
      let err_pre : Array[String] = []
      for p in refs {
        let pv = match raw.get(p) {
          Some(v) => scalar_output(v)
          None => Value::Blank
        }
        match pv {
          Err(_) => err_pre.push(p)
          _ => ()
        }
      }
      let cps : Array[String] = []
      if oversized {
        for p in err_pre {
          cps.push(p)
        }
      } else if err_pre.length() > 0 {
        let changed : Array[Bool] = []
        let mut any_changed = false
        for p in err_pre {
          let c = probe_contributes(grid, options, raw, cache, k, p)
          changed.push(c)
          if c {
            any_changed = true
          }
        }
        if any_changed {
          for j in 0..<err_pre.length() {
            if changed[j] {
              cps.push(err_pre[j])
            }
          }
        } else {
          for p in err_pre {
            cps.push(p)
          }
        }
      }
      contrib[k] = cps
      let mut j = cps.length() - 1
      while j >= 0 {
        stack.push((cps[j], false))
        j -= 1
      }
    }
  }
  sources.sort()
  { ..base, steps, sources }
}