// M8 contract: cross-sheet references, workbook-level defined names and
// whole-column/whole-row references (declared subset). Expectations follow the
// M8 contract; real-Excel answer keys live in corpus/spec/refs.tsv (generated
// by corpus/excel/generate_corpus.bas).

fn qk(sheet : String, addr : String) -> String {
  match @value.parse_addr(addr) {
    Some(a) => @value.sheet_key(sheet, a)
    None => panic()
  }
}

fn is_parse_error(r : Result[@engine.EvalOutput, @syntax.ParseError]) -> Bool {
  match r {
    Ok(_) => false
    Err(_) => true
  }
}

test "m8: cross-sheet reference and range" {
  let g = grid([
    (qk("Data", "A1"), lit(5.0)),
    (qk("Data", "A2"), lit(2.0)),
    (qk("Data", "A3"), lit(3.0)),
  ])
  assert_num(evg("=Data!A1+1", g), 6.0)
  assert_num(evg("=SUM(Data!A1:A3)", g), 10.0)
  assert_num(evg("=Data!A1*Data!A3", g), 15.0)
  assert_num(evg("=SUM(data!a1:a3)", g), 10.0)
}

test "m8: quoted sheet names" {
  let g = grid([
    (qk("My Sheet", "A1"), lit(7.0)),
    (qk("2024Data", "A1"), lit(8.0)),
    ("O'BRIEN!A1", lit(9.0)),
  ])
  assert_num(evg("='My Sheet'!A1", g), 7.0)
  assert_num(evg("='2024Data'!A1", g), 8.0)
  assert_num(evg("='O''Brien'!A1", g), 9.0)
}

test "m8: formula host sheet is its own sheet" {
  let g = grid([
    (qk("Data", "A1"), lit(5.0)),
    (qk("Data", "B1"), f("=A1*2")),
    ("A1", lit(100.0)),
  ])
  let out = @engine.recalc(g, { now: None })
  assert_eq(out.cells[qk("Data", "B1")].value, @value.Value::Num(10.0))
  assert_eq(out.cells[qk("Data", "B1")].circular, false)
}

test "m8: missing sheet is #REF!" {
  let g = grid([("A1", lit(1.0))])
  assert_err(evg("=NoSheet!A1", g), @value.XlError::Ref)
  assert_err(evg("=SUM(NoSheet!A1:A2)", g), @value.XlError::Ref)
  assert_err(evg("=SUM(NoSheet!A:A)", g), @value.XlError::Ref)
}

test "m8: defined names" {
  let g = grid([
    (qk("Data", "A1"), lit(0.07)),
    (qk("Data", "B1"), lit(2.0)),
  ])
  g.names["RATE"] = "Data!$A$1"
  g.names["SCALE"] = "Data!$B$1"
  g.names["RATE2"] = "RATE*SCALE"
  g.names["BLOCK"] = "Data!$A$1:$B$1"
  assert_num(evg("=Rate", g), 0.07)
  assert_num(evg("=rate2", g), 0.14)
  assert_num(evg("=SUM(BLOCK)", g), 2.07)
  assert_err(evg("=MissingName", g), @value.XlError::Name)
  assert_true(is_parse_error(@engine.eval_formula("=SUM(Data!A1:RATE)", g, { now: None })))
}

test "m8: defined name cycle" {
  let g = grid([("A1", lit(1.0))])
  g.names["LOOPA"] = "LoopB"
  g.names["LOOPB"] = "LoopA"
  match @engine.eval_formula("=LoopA", g, { now: None }) {
    Ok(out) => {
      assert_eq(out.value, @value.Value::Num(0.0))
      assert_eq(out.circular, true)
    }
    Err(_) => panic()
  }
}

test "m8: whole column and whole row" {
  let g = grid([
    ("A1", lit(1.0)),
    ("A3", lit(2.0)),
    ("B1", lit(10.0)),
    ("C1", lit(20.0)),
  ])
  assert_num(evg("=SUM(A:A)", g), 3.0)
  assert_num(evg("=SUM(1:1)", g), 31.0)
  assert_num(evg("=SUM(A:B)", g), 13.0)
  assert_num(evg("=COUNT(A:A)", g), 2.0)
}

test "m8: whole column other sheet and empty default sheet" {
  let g = grid([(qk("Data", "A1"), lit(1.0)), (qk("Data", "A2"), lit(2.0))])
  assert_num(evg("=SUM(Data!A:A)", g), 3.0)
  assert_err(evg("=SUM(NoSuch!A:A)", g), @value.XlError::Ref)
  let e = @engine.new_grid()
  assert_num(evg("=SUM(A:A)", e), 0.0)
  assert_num(evg("=SUM(1:1)", e), 0.0)
}

test "m8: eval_at_key qualified" {
  let g = grid([(qk("Data", "A1"), lit(4.0)), (qk("Data", "B1"), f("=A1*2"))])
  assert_eq(
    @engine.eval_at_key("data!b1", g, { now: None }).value,
    @value.Value::Num(8.0),
  )
  assert_eq(
    @engine.eval_at_key("A1", g, { now: None }).value,
    @value.Value::Num(0.0),
  )
}

test "m8: incremental across sheets and names" {
  let g = grid([(qk("Data", "A1"), lit(1.0)), ("B1", f("=Data!A1+1"))])
  g.names["RATE"] = "Data!$A$1"
  let (st, o1) = @engine.recalc_init(g, { now: None })
  assert_eq(o1.cells["B1"].value, @value.Value::Num(2.0))
  let g2 = grid([(qk("Data", "A1"), lit(5.0)), ("B1", f("=Data!A1+1"))])
  g2.names["RATE"] = "Data!$A$1"
  let (o2, rep) = @engine.recalc_update_report(
    st,
    g2,
    [qk("Data", "A1")],
    { now: None },
  )
  assert_eq(rep.full_fallback, false)
  assert_eq(o2.cells["B1"].value, @value.Value::Num(6.0))
  assert_true(rep.recomputed.contains("B1"))
  // 名称表变化必须回退全量（名称依赖不进入格级依赖图）。
  let g3 = grid([(qk("Data", "A1"), lit(5.0)), ("B1", f("=Data!A1+1"))])
  g3.names["RATE"] = "B1"
  let g2state = grid([(qk("Data", "A1"), lit(5.0)), ("B1", f("=Data!A1+1"))])
  g2state.names["RATE"] = "Data!$A$1"
  let (st2, _) = @engine.recalc_init(g2state, { now: None })
  let (_, rep3) = @engine.recalc_update_report(
    st2,
    g3,
    [qk("Data", "A1")],
    { now: None },
  )
  assert_eq(rep3.full_fallback, true)
}

test "m8: explain across sheets" {
  let g = grid([(qk("Data", "A1"), f("=1/0")), ("B1", f("=Data!A1+1"))])
  let out = @engine.explain_at_key("B1", g, { now: None })
  assert_eq(out.target, "B1")
  match out.value {
    @value.Value::Err(e) => assert_eq(e, @value.XlError::Div0)
    _ => panic()
  }
  assert_true(out.sources.contains(qk("Data", "A1")))
}

test "m8: unsupported reference forms are parse errors" {
  let g = @engine.new_grid()
  assert_true(is_parse_error(@engine.eval_formula("=Sheet1:Sheet3!A1", g, { now: None })))
  assert_true(is_parse_error(@engine.eval_formula("=Data!SUM(A1)", g, { now: None })))
  assert_true(is_parse_error(@engine.eval_formula("=[1]Data!A1", g, { now: None })))
}

test "m8: bare numeric-leading sheet name is rejected" {
  let g = @engine.new_grid()
  assert_true(is_parse_error(@engine.eval_formula("=2024Data!A1", g, { now: None })))
  assert_true(is_parse_error(@engine.eval_formula("=Data!!A1", g, { now: None })))
}

test "m8: dependency_graph refuses whole-column/row and name cycles" {
  let g = grid([("A1", lit(1.0)), ("A3", lit(2.0)), ("B1", f("=SUM(A:A)"))])
  match @engine.dependency_graph(g) {
    Some(_) => panic()
    None => ()
  }
  let n = grid([("A1", lit(1.0)), ("B1", f("=Rate"))])
  n.names["RATE"] = "Other"
  n.names["OTHER"] = "Rate"
  match @engine.dependency_graph(n) {
    Some(_) => panic()
    None => ()
  }
}

test "m8: explain degrades to error-precedent chain when oversized" {
  let g = @engine.new_grid()
  g.cells["A1"] = f("=1/0")
  for i in 2..=300 {
    g.cells["A" + i.to_string()] = f("=A" + (i - 1).to_string() + "+1")
  }
  let out = @engine.explain_at_key("A300", g, { now: None })
  assert_true(out.steps.length() > 256)
  assert_eq(out.sources, ["A1"])
}
