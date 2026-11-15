// Incremental recalculation must be byte-identical to full recalc, including
// parse_errors order and circular flags. Fuzz covers both the fast path and
// the cycle/parse-error fallbacks.

fn assert_recalc_eq(
  a : @engine.RecalcOutput,
  b : @engine.RecalcOutput
) -> Unit raise {
  assert_eq(a.cells.length(), b.cells.length())
  for key, o in a.cells {
    match b.cells.get(key) {
      Some(p) => {
        assert_eq(o.value, p.value)
        assert_eq(o.circular, p.circular)
      }
      None => panic()
    }
  }
  assert_eq(a.parse_errors, b.parse_errors)
}

test "incremental: chain edit" {
  let g = grid([("A1", lit(1.0)), ("A2", f("=A1+1")), ("A3", f("=A2+1"))])
  let (state, init) = recalc_init(g, { now: None })
  assert_recalc_eq(init, recalc(g, { now: None }))
  g.cells["A1"] = lit(10.0)
  let out = recalc_update(state, g, ["A1"], { now: None })
  assert_recalc_eq(out, recalc(g, { now: None }))
  assert_num(out.cells["A3"].value, 12.0)
}

test "incremental: diamond and shared range" {
  let g = grid([
    ("A1", lit(1.0)),
    ("B1", f("=A1*2")),
    ("C1", f("=A1*3")),
    ("D1", f("=SUM(B1:C1)")),
  ])
  let (state, _) = recalc_init(g, { now: None })
  g.cells["A1"] = lit(4.0)
  let out = recalc_update(state, g, ["A1"], { now: None })
  assert_recalc_eq(out, recalc(g, { now: None }))
  assert_num(out.cells["D1"].value, 20.0)
}

test "incremental: cycle introduction falls back, resolution recovers" {
  let g = grid([("A1", lit(1.0)), ("B1", f("=A1"))])
  let (state, _) = recalc_init(g, { now: None })
  g.cells["B1"] = f("=B1")
  let out = recalc_update(state, g, ["B1"], { now: None })
  assert_recalc_eq(out, recalc(g, { now: None }))
  assert_num(out.cells["B1"].value, 0.0)
  assert_eq(out.cells["B1"].circular, true)
  g.cells["B1"] = f("=A1")
  let out2 = recalc_update(state, g, ["B1"], { now: None })
  assert_recalc_eq(out2, recalc(g, { now: None }))
  assert_num(out2.cells["B1"].value, 1.0)
  g.cells["A1"] = lit(5.0)
  let out3 = recalc_update(state, g, ["A1"], { now: None })
  assert_recalc_eq(out3, recalc(g, { now: None }))
}

test "incremental: parse error fallback and fix" {
  let g = grid([("A1", f("=IF(TRUE,1,B1)")), ("B1", f("=1+"))])
  let (state, init) = recalc_init(g, { now: None })
  assert_recalc_eq(init, recalc(g, { now: None }))
  // B1 is a top-level grid cell: recalc parses it regardless of IF's laziness.
  assert_eq(init.parse_errors.length(), 1)
  g.cells["A1"] = f("=IF(FALSE,1,B1)")
  let out = recalc_update(state, g, ["A1"], { now: None })
  assert_recalc_eq(out, recalc(g, { now: None }))
  assert_eq(out.parse_errors.length(), 1)
  g.cells["B1"] = f("=2")
  let out2 = recalc_update(state, g, ["B1"], { now: None })
  assert_recalc_eq(out2, recalc(g, { now: None }))
  assert_num(out2.cells["A1"].value, 2.0)
}

test "incremental: parse_errors DFS discovery order preserved" {
  let g = grid([("A1", f("=C1")), ("B1", f("=1+")), ("C1", f("=1+"))])
  let (state, init) = recalc_init(g, { now: None })
  assert_recalc_eq(init, recalc(g, { now: None }))
  assert_eq(init.parse_errors[0].0, "C1")
  assert_eq(init.parse_errors[1].0, "B1")
  g.cells["A1"] = f("=C1+1")
  let out = recalc_update(state, g, ["A1"], { now: None })
  assert_recalc_eq(out, recalc(g, { now: None }))
}

test "incremental: literal-formula switches and deletion" {
  let g = grid([("A1", lit(1.0)), ("B1", f("=A1+1")), ("C1", f("=B1*2"))])
  let (state, _) = recalc_init(g, { now: None })
  g.cells["A1"] = f("=10")
  let out = recalc_update(state, g, ["A1"], { now: None })
  assert_recalc_eq(out, recalc(g, { now: None }))
  assert_num(out.cells["C1"].value, 22.0)
  g.cells["B1"] = lit(100.0)
  let out2 = recalc_update(state, g, ["B1"], { now: None })
  assert_recalc_eq(out2, recalc(g, { now: None }))
  assert_num(out2.cells["C1"].value, 200.0)
  g.cells.remove("A1")
  let out3 = recalc_update(state, g, ["A1"], { now: None })
  assert_recalc_eq(out3, recalc(g, { now: None }))
}

test "incremental: range endpoint edit" {
  let g = grid([
    ("A1", lit(1.0)),
    ("A2", lit(2.0)),
    ("A3", lit(3.0)),
    ("A4", lit(10.0)),
    ("B1", f("=SUM(A1:A3)")),
  ])
  let (state, _) = recalc_init(g, { now: None })
  g.cells["B1"] = f("=SUM(A1:A4)")
  let out = recalc_update(state, g, ["B1"], { now: None })
  assert_recalc_eq(out, recalc(g, { now: None }))
  assert_num(out.cells["B1"].value, 16.0)
}

test "incremental: oversized range falls back" {
  let g = grid([("A1", lit(1.0)), ("B1", f("=SUM(A1:A100000)"))])
  let (state, init) = recalc_init(g, { now: None })
  assert_recalc_eq(init, recalc(g, { now: None }))
  g.cells["A1"] = lit(2.0)
  let out = recalc_update(state, g, ["A1"], { now: None })
  assert_recalc_eq(out, recalc(g, { now: None }))
  assert_num(out.cells["B1"].value, 2.0)
}

fn fuzz_incremental(
  seed : UInt,
  rounds : Int,
  pool : Array[String]
) -> Unit raise {
  let mut s = seed
  let keys = [
    "A1", "A2", "A3", "A4", "B1", "B2", "B3", "B4", "C1", "C2", "C3", "C4",
    "D1", "D2", "D3", "D4",
  ]
  for _ in 0..<rounds {
    let g = @engine.new_grid()
    for key in keys {
      s = xorshift(s)
      let kind = (s % 10U).reinterpret_as_int()
      if kind < 5 {
        g.cells[key] = lit((s % 100U).reinterpret_as_int().to_double())
      } else if kind < 6 {
        g.cells[key] = txt("x")
      } else {
        s = xorshift(s)
        g.cells[key] = f(pool[(s % pool.length().reinterpret_as_uint()).reinterpret_as_int()])
      }
    }
    let (state, init) = recalc_init(g, { now: None })
    assert_recalc_eq(init, recalc(g, { now: None }))
    s = xorshift(s)
    let edits = 1 + (s % 3U).reinterpret_as_int()
    let changed : Array[String] = []
    for _ in 0..<edits {
      s = xorshift(s)
      let key = keys[(s % 16U).reinterpret_as_int()]
      s = xorshift(s)
      let kind = (s % 12U).reinterpret_as_int()
      if kind < 5 {
        g.cells[key] = lit((s % 50U).reinterpret_as_int().to_double())
      } else if kind < 6 {
        g.cells.remove(key)
      } else {
        s = xorshift(s)
        g.cells[key] = f(pool[(s % pool.length().reinterpret_as_uint()).reinterpret_as_int()])
      }
      changed.push(key)
    }
    let out = recalc_update(state, g, changed, { now: None })
    assert_recalc_eq(out, recalc(g, { now: None }))
  }
}

test "incremental fuzz: mixed with fallbacks (300 rounds)" {
  fuzz_incremental(0x5EED1234U, 300, [
    "=A1+1", "=B1*2", "=SUM(A1:B2)", "=IF(A1>0,B1,C1)", "=A1&B1",
    "=SUM(A1:D4)", "=C1+D1", "=1+", "=A1", "=ROUND(A1,2)",
  ])
}

test "incremental fuzz: error-free fast path (200 rounds)" {
  fuzz_incremental(0xABCD9876U, 200, [
    "=A1+1", "=B1*2", "=SUM(A1:B2)", "=IF(A1>0,B1,C1)", "=A1&B1",
    "=SUM(A1:D4)", "=C1+D1", "=A1", "=ROUND(A1,2)", "=MEDIAN(A1:D4)",
  ])
}