// In-process recalc benchmarks. Grid construction is excluded from timing;
// the engine core stays pure (timing lives here in the IO shell).

struct PerfRow {
  scenario : String
  cells : Int
  best_ms : Double
  check : String
}

fn perf_check(out : @facade.RecalcOutput, key : String, expected : Double) -> String {
  match out.cells.get(key) {
    Some(o) if o.value == @facade.Value::Num(expected) => "OK " + key + "=" + expected.to_string()
    Some(o) => "FAIL " + key + ": got " + o.value.to_string()
    None => "FAIL missing " + key
  }
}

fn time_recalc(grid : @facade.Grid, repeat : Int) -> (Double, @facade.RecalcOutput) {
  let mut best = -1.0
  let mut out : @facade.RecalcOutput = { cells: Map::new(), parse_errors: [] }
  for _ in 0..<repeat {
    let start = @bench.monotonic_clock_start()
    out = @facade.recalc(grid, { now: None })
    let us = @bench.monotonic_clock_end(start)
    if best < 0.0 || us < best {
      best = us
    }
  }
  (best / 1000.0, out)
}

fn time_recalc_cached(
  grid : @facade.Grid,
  repeat : Int,
  cache : @facade.ParseCache
) -> (Double, @facade.RecalcOutput) {
  let mut best = -1.0
  let mut out : @facade.RecalcOutput = { cells: Map::new(), parse_errors: [] }
  for _ in 0..<repeat {
    let start = @bench.monotonic_clock_start()
    out = @facade.recalc_cached(grid, { now: None }, cache)
    let us = @bench.monotonic_clock_end(start)
    if best < 0.0 || us < best {
      best = us
    }
  }
  (best / 1000.0, out)
}

fn time_recalc_cached_fresh(
  grid : @facade.Grid,
  repeat : Int
) -> (Double, @facade.RecalcOutput) {
  let mut best = -1.0
  let mut out : @facade.RecalcOutput = { cells: Map::new(), parse_errors: [] }
  for _ in 0..<repeat {
    let cache = @facade.new_parse_cache()
    let start = @bench.monotonic_clock_start()
    out = @facade.recalc_cached(grid, { now: None }, cache)
    let us = @bench.monotonic_clock_end(start)
    if best < 0.0 || us < best {
      best = us
    }
  }
  (best / 1000.0, out)
}

fn chain_grid(n : Int) -> @facade.Grid {
  let g = @facade.new_grid()
  g.cells["A1"] = @facade.Cell::Literal(@facade.Value::Num(1.0))
  for i in 2..=n {
    let key = "A" + i.to_string()
    g.cells[key] = @facade.Cell::Formula("=A" + (i - 1).to_string() + "+1")
  }
  g
}

fn perf_chain(n : Int, repeat : Int) -> PerfRow {
  let g = chain_grid(n)
  let (ms, out) = time_recalc(g, repeat)
  { scenario: "chain", cells: n, best_ms: ms, check: perf_check(out, "A" + n.to_string(), n.to_double()) }
}

fn perf_wide(n : Int, repeat : Int) -> PerfRow {
  let g = @facade.new_grid()
  for i in 1..<n {
    g.cells["A" + i.to_string()] = @facade.Cell::Literal(@facade.Value::Num(1.0))
  }
  let key = "A" + n.to_string()
  g.cells[key] = @facade.Cell::Formula("=SUM(A1:A" + (n - 1).to_string() + ")")
  let (ms, out) = time_recalc(g, repeat)
  { scenario: "wide", cells: n, best_ms: ms, check: perf_check(out, key, (n - 1).to_double()) }
}

fn mixed_grid(n : Int) -> @facade.Grid {
  let rows = n / 4
  let g = @facade.new_grid()
  for i in 1..=rows {
    let r = i.to_string()
    g.cells["A" + r] = @facade.Cell::Literal(@facade.Value::Num(i.to_double()))
    g.cells["B" + r] = @facade.Cell::Formula("=A" + r + "*2")
    g.cells["C" + r] = @facade.Cell::Formula("=B" + r + "+A" + r)
    g.cells["D" + r] = @facade.Cell::Formula("=SUM(A" + r + ":C" + r + ")")
  }
  g
}

fn perf_mixed(n : Int, repeat : Int) -> PerfRow {
  let rows = n / 4
  let g = mixed_grid(n)
  let (ms, out) = time_recalc(g, repeat)
  let key = "D" + rows.to_string()
  { scenario: "mixed", cells: rows * 4, best_ms: ms, check: perf_check(out, key, (6 * rows).to_double()) }
}

fn perf_shared(n : Int, repeat : Int) -> PerfRow {
  let base = 100
  let g = @facade.new_grid()
  for i in 1..=base {
    g.cells["A" + i.to_string()] = @facade.Cell::Literal(@facade.Value::Num(i.to_double()))
  }
  let formulas = n - base
  for i in 1..=formulas {
    g.cells["B" + i.to_string()] = @facade.Cell::Formula(
      "=SUM($A$1:$A$100)+" + i.to_string(),
    )
  }
  let (ms, out) = time_recalc(g, repeat)
  let key = "B" + formulas.to_string()
  { scenario: "shared", cells: n, best_ms: ms, check: perf_check(out, key, (5050 + formulas).to_double()) }
}

fn perf_dup(n : Int, repeat : Int) -> PerfRow {
  let base = 100
  let g = @facade.new_grid()
  for i in 1..=base {
    g.cells["A" + i.to_string()] = @facade.Cell::Literal(@facade.Value::Num(i.to_double()))
  }
  let formulas = n - base
  for i in 1..=formulas {
    let k = (i - 1) / 100 + 1
    g.cells["B" + i.to_string()] = @facade.Cell::Formula(
      "=SUM($A$1:$A$100)+" + k.to_string(),
    )
  }
  let (ms, out) = time_recalc_cached_fresh(g, repeat)
  let key = "B" + formulas.to_string()
  let k_last = (formulas - 1) / 100 + 1
  { scenario: "dup", cells: n, best_ms: ms, check: perf_check(out, key, (5050 + k_last).to_double()) }
}

fn perf_repeat(n : Int, repeat : Int) -> PerfRow {
  let rows = n / 4
  let g = mixed_grid(n)
  let cache = @facade.new_parse_cache()
  let (ms, out) = time_recalc_cached(g, repeat, cache)
  let key = "D" + rows.to_string()
  { scenario: "repeat", cells: rows * 4, best_ms: ms, check: perf_check(out, key, (6 * rows).to_double()) }
}

fn perf_edit(n : Int, repeat : Int) -> PerfRow {
  let rows = n / 4
  let g = mixed_grid(n)
  let (state, _) = @facade.recalc_init(g, { now: None })
  let mid = rows / 2
  let key = "A" + mid.to_string()
  let mut best = -1.0
  let mut out : @facade.RecalcOutput = { cells: Map::new(), parse_errors: [] }
  for _ in 0..<repeat {
    g.cells[key] = @facade.Cell::Literal(@facade.Value::Num(999.0))
    let start = @bench.monotonic_clock_start()
    out = @facade.recalc_update(state, g, [key], { now: None })
    let us = @bench.monotonic_clock_end(start)
    if best < 0.0 || us < best {
      best = us
    }
  }
  { scenario: "edit", cells: rows * 4, best_ms: best / 1000.0, check: perf_check(out, "D" + mid.to_string(), 5994.0) }
}

fn perf_edit_chain(n : Int, repeat : Int) -> PerfRow {
  let g = chain_grid(n)
  let (state, _) = @facade.recalc_init(g, { now: None })
  let mut best = -1.0
  let mut out : @facade.RecalcOutput = { cells: Map::new(), parse_errors: [] }
  for _ in 0..<repeat {
    g.cells["A1"] = @facade.Cell::Literal(@facade.Value::Num(2.0))
    let start = @bench.monotonic_clock_start()
    out = @facade.recalc_update(state, g, ["A1"], { now: None })
    let us = @bench.monotonic_clock_end(start)
    if best < 0.0 || us < best {
      best = us
    }
  }
  { scenario: "edit-chain", cells: n, best_ms: best / 1000.0, check: perf_check(out, "A" + n.to_string(), (n + 1).to_double()) }
}

fn run_perf(a : Args) -> Unit {
  let n = a.cells
  if n < 1000 {
    die("perf requires --cells >= 1000")
  }
  if a.repeat < 1 {
    die("perf requires --repeat >= 1")
  }
  let rows = [
    perf_chain(n, a.repeat),
    perf_wide(n, a.repeat),
    perf_mixed(n, a.repeat),
    perf_shared(n, a.repeat),
    perf_dup(n, a.repeat),
    perf_repeat(n, a.repeat),
    perf_edit(n, a.repeat),
    perf_edit_chain(n, a.repeat),
  ]
  println("scenario   cells    best ms (of " + a.repeat.to_string() + ")   cells/s        check")
  for r in rows {
    let rate = if r.best_ms > 0.0 {
      (r.cells.to_double() / r.best_ms * 1000.0).round().to_int().to_string()
    } else {
      "-"
    }
    println(
      r.scenario + "   " + r.cells.to_string() + "   " + r.best_ms.to_string() +
      "   " + rate + "   " + r.check,
    )
  }
  for r in rows {
    if r.check.substring(start=0, end=2) != "OK" {
      die("perf verification failed: " + r.check)
    }
  }
  let cold = rows[2].best_ms
  let hot = rows[5].best_ms
  if cold > 0.0 && hot > 0.0 {
    println(
      "AST cache (mixed layout): cold " + cold.to_string() + " ms -> hot " +
      hot.to_string() + " ms (" + (cold / hot).to_string() + "x)",
    )
  }
}