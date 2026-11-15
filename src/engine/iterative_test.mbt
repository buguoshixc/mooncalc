// Iterative calculation: provisional expectations (source: manual). The
// real-Excel iter corpus (corpus/spec/iter.tsv) is the authoritative judge for
// fenceposts, iteration order and convergence details.

test "iterative: self-loop diverges to iteration count" {
  let g = grid([("A1", f("=A1+1"))])
  let out = recalc_iterative(g, { now: None }, new_iter_options())
  assert_num(out.cells["A1"].value, 100.0)
  assert_eq(out.cells["A1"].circular, true)
}

test "iterative: default recalc unchanged (circular stays 0)" {
  let g = grid([("A1", f("=A1+1"))])
  let out = recalc(g, { now: None })
  assert_num(out.cells["A1"].value, 0.0)
  assert_eq(out.cells["A1"].circular, true)
}

test "iterative: convergent self-loop" {
  let g = grid([("A1", f("=A1/2+1"))])
  let out = recalc_iterative(g, { now: None }, new_iter_options())
  match out.cells["A1"].value {
    @value.Value::Num(d) => assert_true((d - 2.0).abs() < 0.001)
    _ => panic()
  }
}

test "iterative: single iteration" {
  let g = grid([("A1", f("=A1+1"))])
  let out = recalc_iterative(
    g,
    { now: None },
    new_iter_options(max_iterations=1),
  )
  assert_num(out.cells["A1"].value, 1.0)
}

test "iterative: max_change early stop" {
  let g = grid([("A1", f("=A1+0.0005"))])
  let out = recalc_iterative(g, { now: None }, new_iter_options())
  assert_num(out.cells["A1"].value, 0.0005)
}

test "iterative: non-circular cells match recalc" {
  let g = grid([
    ("A1", lit(5.0)),
    ("B1", f("=A1*2")),
    ("C1", f("=SUM(A1:B1)")),
  ])
  let a = recalc_iterative(g, { now: None }, new_iter_options())
  let b = recalc(g, { now: None })
  assert_recalc_eq(a, b)
}

test "iterative: error cycle stable" {
  let g = grid([("A1", f("=A1/0"))])
  let out = recalc_iterative(g, { now: None }, new_iter_options())
  assert_err(out.cells["A1"].value, @value.XlError::Div0)
}

test "iterative: deterministic" {
  let g = grid([("A1", f("=A1/3+1")), ("B1", f("=A1*2"))])
  let a = recalc_iterative(g, { now: None }, new_iter_options())
  let b = recalc_iterative(g, { now: None }, new_iter_options())
  assert_recalc_eq(a, b)
}

test "iterative: eval_formula_iterative channels" {
  let g = grid([("A1", f("=A1+1"))])
  match eval_formula_iterative("=A1", g, { now: None }, new_iter_options()) {
    Ok(o) => {
      assert_num(o.value, 100.0)
      assert_eq(o.circular, true)
    }
    Err(_) => panic()
  }
  match eval_formula_iterative("=1+", g, { now: None }, new_iter_options()) {
    Ok(_) => panic()
    Err(_) => ()
  }
}