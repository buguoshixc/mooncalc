// AST cache regression: cached recalc must be byte-identical to plain recalc,
// including per-cell parse_errors collection in grid insertion order.

test "parse cache: same-text formulas within one recalc" {
  let g = grid([
    ("A1", lit(1.0)),
    ("B1", f("=A1*2")),
    ("C1", f("=A1*2")),
    ("D1", f("=A1*2")),
  ])
  let out = recalc_cached(g, { now: None }, new_parse_cache())
  assert_num(out.cells["B1"].value, 2.0)
  assert_num(out.cells["C1"].value, 2.0)
  assert_num(out.cells["D1"].value, 2.0)
  assert_eq(out.parse_errors.length(), 0)
}

test "parse cache: bad formula collected per cell in insertion order" {
  let g = grid([("B1", f("=1+")), ("C1", f("=1+")), ("D1", f("=1+"))])
  let out = recalc_cached(g, { now: None }, new_parse_cache())
  assert_eq(out.parse_errors.length(), 3)
  assert_eq(out.parse_errors[0].0, "B1")
  assert_eq(out.parse_errors[1].0, "C1")
  assert_eq(out.parse_errors[2].0, "D1")
  assert_err(out.cells["B1"].value, @value.XlError::Value)
  assert_err(out.cells["C1"].value, @value.XlError::Value)
  assert_err(out.cells["D1"].value, @value.XlError::Value)
  let plain = recalc(g, { now: None })
  assert_eq(plain.parse_errors, out.parse_errors)
}

test "parse cache: recalc == recalc_cached(fresh) incl circular and parse errors" {
  let g = grid([
    ("A1", lit(1.0)),
    ("B1", f("=A1+1")),
    ("C1", f("=B1+A1")),
    ("D1", f("=D1+1")),
    ("E1", f("=1+")),
  ])
  let a = recalc(g, { now: None })
  let b = recalc_cached(g, { now: None }, new_parse_cache())
  for key, out in a.cells {
    let other = b.cells[key]
    assert_eq(out.value, other.value)
    assert_eq(out.circular, other.circular)
  }
  assert_eq(a.parse_errors, b.parse_errors)
}

test "parse cache: reuse across recalc after cell edits" {
  let g = grid([("A1", lit(1.0)), ("B1", f("=A1*2")), ("C1", f("=A1*3"))])
  let cache = new_parse_cache()
  let out1 = recalc_cached(g, { now: None }, cache)
  assert_num(out1.cells["B1"].value, 2.0)
  g.cells["A1"] = lit(5.0)
  let out2 = recalc_cached(g, { now: None }, cache)
  assert_num(out2.cells["B1"].value, 10.0)
  assert_num(out2.cells["C1"].value, 15.0)
  g.cells["B1"] = f("=A1*4")
  let out3 = recalc_cached(g, { now: None }, cache)
  assert_num(out3.cells["B1"].value, 20.0)
  cache.clear()
  let out4 = recalc_cached(g, { now: None }, cache)
  assert_num(out4.cells["B1"].value, 20.0)
}

test "parse cache: fixed formula bypasses negative entry" {
  let g = grid([("A1", f("=1+"))])
  let cache = new_parse_cache()
  let out1 = recalc_cached(g, { now: None }, cache)
  assert_eq(out1.parse_errors.length(), 1)
  g.cells["A1"] = f("=1+2")
  let out2 = recalc_cached(g, { now: None }, cache)
  assert_eq(out2.parse_errors.length(), 0)
  assert_num(out2.cells["A1"].value, 3.0)
}