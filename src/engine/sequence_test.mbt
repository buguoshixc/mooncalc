// SEQUENCE 单元测试；期望值全部来自 corpus/probes/sequence.results.json
// （真实 Excel 16.0.20527 探针 sq001–sq064 + p071–p079/q003/q004，共 75 条）。

fn sq_ev(formula : String) -> @value.Value {
  match @engine.eval_formula(formula, @engine.new_grid(), { now: None }) {
    Ok(out) => out.value
    Err(_) => panic()
  }
}

test "sequence normal formula uses top-left like Excel sq015-sq021" {
  assert_eq(sq_ev("=SEQUENCE(3)"), @value.Value::Num(1.0))
  assert_eq(sq_ev("=SEQUENCE(1,3)"), @value.Value::Num(1.0))
  assert_eq(sq_ev("=SEQUENCE(2,3,10,2)"), @value.Value::Num(10.0))
  assert_eq(sq_ev("=SUM(SEQUENCE(3))"), @value.Value::Num(6.0))
  assert_eq(sq_ev("=SUM(SEQUENCE(2,3))"), @value.Value::Num(21.0))
  assert_eq(sq_ev("=SEQUENCE(3)+1"), @value.Value::Num(2.0))
}

test "sequence omitted arguments take defaults sq030-sq033" {
  assert_eq(sq_ev("=SEQUENCE(3,,5)"), @value.Value::Num(5.0))
  assert_eq(sq_ev("=SEQUENCE(,2)"), @value.Value::Num(1.0))
  assert_eq(sq_ev("=SEQUENCE(3,2,,10)"), @value.Value::Num(1.0))
  assert_eq(sq_ev("=SEQUENCE(3,)"), @value.Value::Num(1.0))
  assert_eq(sq_ev("=SEQUENCE(3,,5,)"), @value.Value::Num(5.0))
}

test "sequence coercion and dimension errors sq008-sq028" {
  assert_eq(sq_ev("=SEQUENCE(2.9)"), @value.Value::Num(1.0))
  assert_eq(sq_ev("=SEQUENCE(\"3\")"), @value.Value::Num(1.0))
  assert_eq(sq_ev("=SEQUENCE(TRUE)"), @value.Value::Num(1.0))
  assert_eq(sq_ev("=SEQUENCE(0)"), @value.Value::Err(@value.XlError::Calc))
  assert_eq(sq_ev("=SEQUENCE(-0.5)"), @value.Value::Err(@value.XlError::Value))
  assert_eq(sq_ev("=SEQUENCE(0.9)"), @value.Value::Err(@value.XlError::Calc))
  assert_eq(sq_ev("=SEQUENCE(3,0)"), @value.Value::Err(@value.XlError::Calc))
  assert_eq(sq_ev("=SEQUENCE(3,-1)"), @value.Value::Err(@value.XlError::Value))
  assert_eq(sq_ev("=SEQUENCE(\"abc\")"), @value.Value::Err(@value.XlError::Value))
  assert_eq(sq_ev("=SEQUENCE(1/0)"), @value.Value::Err(@value.XlError::Div0))
  assert_eq(sq_ev("=SEQUENCE(1048577)"), @value.Value::Err(@value.XlError::Value))
  // columns 不受网格宽 16384 预检：数组本身合法，只有动态锚点放不下才 #SPILL!。
  assert_eq(sq_ev("=SUM(SEQUENCE(1,16385))"), @value.Value::Num(134242305.0))
}

test "sequence spills row-major with start and step sq001-sq014" {
  let g = @engine.new_grid()
  let layout = @engine.new_array_layout()
  layout.set_dynamic("D4", "=SEQUENCE(3,2,1,0.5)")
  let out = @engine.recalc_arrays(g, layout, { now: None })
  assert_eq(out.ranges["D4"], (3, 2))
  assert_eq(out.values["D4"], @value.Value::Num(1.0))
  assert_eq(out.values["E4"], @value.Value::Num(1.5))
  assert_eq(out.values["D5"], @value.Value::Num(2.0))
  assert_eq(out.values["E5"], @value.Value::Num(2.5))
  assert_eq(out.values["D6"], @value.Value::Num(3.0))
  assert_eq(out.values["E6"], @value.Value::Num(3.5))
}

test "sequence dynamic shape, negative step and zero step" {
  let g = @engine.new_grid()
  let layout = @engine.new_array_layout()
  layout.set_dynamic("D4", "=SEQUENCE(3,1,10,-2)")
  layout.set_dynamic("H4", "=SEQUENCE(3,1,1,0)")
  layout.set_dynamic("M4", "=SEQUENCE(2.9)")
  let out = @engine.recalc_arrays(g, layout, { now: None })
  assert_eq(out.values["D4"], @value.Value::Num(10.0))
  assert_eq(out.values["D5"], @value.Value::Num(8.0))
  assert_eq(out.values["D6"], @value.Value::Num(6.0))
  assert_eq(out.values["H4"], @value.Value::Num(1.0))
  assert_eq(out.values["H5"], @value.Value::Num(1.0))
  assert_eq(out.values["H6"], @value.Value::Num(1.0))
  assert_eq(out.ranges["M4"], (2, 1))
  assert_eq(out.values["M5"], @value.Value::Num(2.0))
}

test "sequence one-by-one result still registers a spill area sq010" {
  let g = @engine.new_grid()
  let layout = @engine.new_array_layout()
  layout.set_dynamic("D4", "=SEQUENCE(TRUE)")
  let out = @engine.recalc_arrays(g, layout, { now: None })
  assert_eq(out.values["D4"], @value.Value::Num(1.0))
  assert_eq(out.ranges["D4"], (1, 1))
  assert_false(out.values.contains("D5"))
}

test "sequence dynamic errors and bounds sq054-sq062" {
  let g = @engine.new_grid()
  let layout = @engine.new_array_layout()
  layout.set_dynamic("D4", "=SEQUENCE(0)")
  layout.set_dynamic("F4", "=SEQUENCE(-1)")
  layout.set_dynamic("H4", "=SEQUENCE(1048577)")
  layout.set_dynamic("J4", "=SEQUENCE(1,16385)")
  layout.set_dynamic("L4", "=SEQUENCE(3,0.9)")
  let out = @engine.recalc_arrays(g, layout, { now: None })
  assert_eq(out.cells["D4"].value, @value.Value::Err(@value.XlError::Calc))
  assert_eq(out.cells["F4"].value, @value.Value::Err(@value.XlError::Value))
  assert_eq(out.cells["H4"].value, @value.Value::Err(@value.XlError::Value))
  assert_eq(out.cells["J4"].value, @value.Value::Err(@value.XlError::Spill))
  assert_eq(out.cells["L4"].value, @value.Value::Err(@value.XlError::Calc))
}

test "sequence spill blocked by occupied cell sq036-sq037" {
  let g = @engine.new_grid()
  g.cells["D5"] = @engine.Cell::Literal(@value.Value::Num(99.0))
  let layout = @engine.new_array_layout()
  layout.set_dynamic("D4", "=SEQUENCE(3)")
  let out = @engine.recalc_arrays(g, layout, { now: None })
  assert_eq(out.cells["D4"].value, @value.Value::Err(@value.XlError::Spill))
  assert_false(out.values.contains("D5"))
}

test "sequence spill beyond grid edges is #SPILL! sq038-sq039" {
  let g = @engine.new_grid()
  let layout = @engine.new_array_layout()
  layout.set_dynamic("XFD4", "=SEQUENCE(1,2)")
  layout.set_dynamic("D1048575", "=SEQUENCE(3)")
  let out = @engine.recalc_arrays(g, layout, { now: None })
  assert_eq(out.cells["XFD4"].value, @value.Value::Err(@value.XlError::Spill))
  assert_eq(
    out.cells["D1048575"].value,
    @value.Value::Err(@value.XlError::Spill),
  )
}

test "sequence spill reference and implicit intersection sq040-sq044" {
  let g = @engine.new_grid()
  g.cells["E1"] = @engine.Cell::Formula("=SUM(D4:D6)")
  g.cells["F1"] = @engine.Cell::Formula("=SUM(D4#)")
  g.cells["G1"] = @engine.Cell::Formula("=D4#")
  g.cells["E5"] = @engine.Cell::Formula("=D4#")
  let layout = @engine.new_array_layout()
  layout.set_dynamic("D4", "=SEQUENCE(3)")
  let out = @engine.recalc_arrays(g, layout, { now: None })
  assert_eq(out.cells["E1"].value, @value.Value::Num(6.0))
  assert_eq(out.cells["F1"].value, @value.Value::Num(6.0))
  assert_eq(out.cells["G1"].value, @value.Value::Err(@value.XlError::Value))
  assert_eq(out.cells["E5"].value, @value.Value::Num(2.0))
}

test "sequence cse fill matches Excel sq046-sq053" {
  let g = @engine.new_grid()
  let layout = @engine.new_array_layout()
  layout.set_cse("D4", "=SEQUENCE(3)", 4, 1)
  layout.set_cse("H4", "=SEQUENCE(2,3)", 2, 2)
  layout.set_cse("M4", "=SEQUENCE(2,3)", 3, 2)
  let out = @engine.recalc_arrays(g, layout, { now: None })
  assert_eq(out.values["D4"], @value.Value::Num(1.0))
  assert_eq(out.values["D5"], @value.Value::Num(2.0))
  assert_eq(out.values["D6"], @value.Value::Num(3.0))
  assert_eq(out.values["D7"], @value.Value::Err(@value.XlError::NA))
  assert_eq(out.values["H4"], @value.Value::Num(1.0))
  assert_eq(out.values["I4"], @value.Value::Num(2.0))
  assert_eq(out.values["H5"], @value.Value::Num(4.0))
  assert_eq(out.values["I5"], @value.Value::Num(5.0))
  assert_eq(out.values["M4"], @value.Value::Num(1.0))
  assert_eq(out.values["N4"], @value.Value::Num(2.0))
  assert_eq(out.values["M5"], @value.Value::Num(4.0))
  assert_eq(out.values["N5"], @value.Value::Num(5.0))
  assert_eq(out.values["M6"], @value.Value::Err(@value.XlError::NA))
  assert_eq(out.values["N6"], @value.Value::Err(@value.XlError::NA))
}
