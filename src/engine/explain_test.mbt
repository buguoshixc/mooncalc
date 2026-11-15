// Explain API: contribution-aware error tracing (leftmost-wins), provisional
// expectations guarded by unit tests; playground smoke covers the JSON shell.

fn addr(s : String) -> @value.CellAddr {
  match @value.parse_addr(s) {
    Some(a) => a
    None => panic()
  }
}

test "explain: single source chain" {
  let g = grid([("A1", f("=1/0")), ("B1", f("=A1+1")), ("C1", f("=B1*2"))])
  let out = explain(addr("C1"), g, { now: None })
  assert_err(out.value, @value.XlError::Div0)
  assert_eq(out.sources, ["A1"])
  assert_eq(out.steps.length(), 3)
  assert_eq(out.steps[0].addr, "A1")
  assert_eq(out.steps[0].is_source, true)
  assert_eq(out.steps[2].addr, "C1")
  assert_eq(out.steps[2].is_source, false)
}

test "explain: leftmost error wins" {
  let g = grid([
    ("A1", f("=1/0")),
    ("A2", f("=\"x\"+1")),
    ("B1", f("=A1+A2")),
  ])
  let out = explain(addr("B1"), g, { now: None })
  assert_err(out.value, @value.XlError::Div0)
  assert_eq(out.sources, ["A1"])
  assert_eq(out.steps.length(), 2)
}

test "explain: diamond with identical errors keeps the shared source" {
  let g = grid([
    ("A1", f("=1/0")),
    ("B1", f("=A1")),
    ("C1", f("=A1")),
    ("D1", f("=B1+C1")),
  ])
  let out = explain(addr("D1"), g, { now: None })
  assert_eq(out.sources, ["A1"])
  assert_eq(out.steps.length(), 4)
  assert_eq(out.steps[3].addr, "D1")
  assert_eq(out.steps[3].is_source, false)
}

test "explain: error-ignoring function yields no steps" {
  let g = grid([("A1", f("=1/0")), ("B1", f("=COUNT(A1)"))])
  let out = explain(addr("B1"), g, { now: None })
  assert_num(out.value, 0.0)
  assert_eq(out.steps.length(), 0)
}

test "explain: IFERROR target is not an error" {
  let g = grid([("A1", f("=1/0")), ("B1", f("=IFERROR(A1,0)"))])
  let out = explain(addr("B1"), g, { now: None })
  assert_num(out.value, 0.0)
  assert_eq(out.steps.length(), 0)
}

test "explain: literal error source" {
  let g = grid([
    ("A1", @engine.Cell::Literal(@value.Value::Err(@value.XlError::Div0))),
    ("B1", f("=A1")),
  ])
  let out = explain(addr("B1"), g, { now: None })
  assert_eq(out.sources, ["A1"])
  assert_eq(out.steps[0].formula, "")
  assert_eq(out.steps[0].is_source, true)
}

test "explain: parse error target is its own source" {
  let g = grid([("A1", f("=1+"))])
  let out = explain(addr("A1"), g, { now: None })
  assert_err(out.value, @value.XlError::Value)
  assert_true(out.parse_error is Some(_))
  assert_eq(out.sources, ["A1"])
  assert_eq(out.steps.length(), 1)
}

test "explain: circular target has empty steps" {
  let g = grid([("A1", f("=A1+1"))])
  let out = explain(addr("A1"), g, { now: None })
  assert_eq(out.circular, true)
  assert_eq(out.steps.length(), 0)
}

test "explain: non-error target has empty steps" {
  let g = grid([("A1", lit(1.0)), ("B1", f("=A1+1"))])
  let out = explain(addr("B1"), g, { now: None })
  assert_num(out.value, 2.0)
  assert_eq(out.steps.length(), 0)
}

test "dependency graph: AST-level refs, ranges expanded, literals excluded" {
  let g = grid([
    ("A1", lit(1.0)),
    ("A2", lit(2.0)),
    ("B1", f("=SUM(A1:A2)+A1")),
    ("C1", f("=\"A1\"")),
  ])
  match dependency_graph(g) {
    Some(dg) => {
      assert_eq(dg.precedents["B1"], ["A1", "A2"])
      assert_eq(dg.dependents["A1"], ["B1"])
      assert_eq(dg.precedents["C1"], [])
      assert_eq(dg.precedents.length(), 2)
    }
    None => panic()
  }
}