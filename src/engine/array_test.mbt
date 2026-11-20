// CSE / dynamic array layout tests (semantics from real-Excel probes).

fn agrid(cells : Array[(String, @engine.Cell)]) -> @engine.Grid {
  let g = @engine.new_grid()
  for (k, c) in cells {
    g.cells[k] = c
  }
  g
}

test "cse fills selection and spill cells are referenceable" {
  let g = agrid([
    ("A1", @engine.Cell::Literal(@value.Value::Num(1.0))),
    ("A2", @engine.Cell::Literal(@value.Value::Num(2.0))),
    ("A3", @engine.Cell::Literal(@value.Value::Num(3.0))),
    ("E1", @engine.Cell::Formula("=SUM(D4:D6)")),
    ("E2", @engine.Cell::Formula("=D5*10")),
  ])
  let layout = @engine.new_array_layout()
  layout.set_cse("D4", "=A1:A3*2", 3, 1)
  let out = @engine.recalc_arrays(g, layout, { now: None })
  assert_eq(out.values["D4"], @value.Value::Num(2.0))
  assert_eq(out.values["D5"], @value.Value::Num(4.0))
  assert_eq(out.values["D6"], @value.Value::Num(6.0))
  assert_eq(out.cells["E1"].value, @value.Value::Num(12.0))
  assert_eq(out.cells["E2"].value, @value.Value::Num(40.0))
  assert_eq(out.ranges["D4"], (3, 1))
}

test "cse scalar fills every selected cell" {
  let g = @engine.new_grid()
  let layout = @engine.new_array_layout()
  layout.set_cse("B2", "=2", 2, 2)
  let out = @engine.recalc_arrays(g, layout, { now: None })
  assert_eq(out.values["B2"], @value.Value::Num(2.0))
  assert_eq(out.values["C2"], @value.Value::Num(2.0))
  assert_eq(out.values["B3"], @value.Value::Num(2.0))
  assert_eq(out.values["C3"], @value.Value::Num(2.0))
}

test "cse reference fills by repeating rows and columns" {
  let g = agrid([
    ("A1", @engine.Cell::Literal(@value.Value::Num(1.0))),
    ("A2", @engine.Cell::Literal(@value.Value::Num(2.0))),
  ])
  let layout = @engine.new_array_layout()
  layout.set_cse("D4", "=A1:A2", 2, 2)
  let out = @engine.recalc_arrays(g, layout, { now: None })
  assert_eq(out.values["D4"], @value.Value::Num(1.0))
  assert_eq(out.values["E4"], @value.Value::Num(1.0))
  assert_eq(out.values["D5"], @value.Value::Num(2.0))
  assert_eq(out.values["E5"], @value.Value::Num(2.0))
}

test "cse extra columns become #N/A" {
  let g = @engine.new_grid()
  let layout = @engine.new_array_layout()
  layout.set_cse("D4", "={1,2}", 1, 3)
  let out = @engine.recalc_arrays(g, layout, { now: None })
  assert_eq(out.values["D4"], @value.Value::Num(1.0))
  assert_eq(out.values["E4"], @value.Value::Num(2.0))
  assert_eq(out.values["F4"], @value.Value::Err(@value.XlError::NA))
}

test "dynamic array spills and can be referenced" {
  let g = agrid([
    ("E1", @engine.Cell::Formula("=SUM(D4:D6)")),
    ("E2", @engine.Cell::Formula("=D4#")),
  ])
  let layout = @engine.new_array_layout()
  layout.set_dynamic("D4", "={1;2;3}")
  let out = @engine.recalc_arrays(g, layout, { now: None })
  assert_eq(out.values["D4"], @value.Value::Num(1.0))
  assert_eq(out.values["D5"], @value.Value::Num(2.0))
  assert_eq(out.values["D6"], @value.Value::Num(3.0))
  assert_eq(out.cells["E1"].value, @value.Value::Num(6.0))
  assert_eq(out.ranges["D4"], (3, 1))
}

test "dynamic array blocked by occupied cell is #SPILL!" {
  let g = agrid([
    ("D5", @engine.Cell::Literal(@value.Value::Num(99.0))),
  ])
  let layout = @engine.new_array_layout()
  layout.set_dynamic("D4", "={1;2;3}")
  let out = @engine.recalc_arrays(g, layout, { now: None })
  assert_eq(out.cells["D4"].value, @value.Value::Err(@value.XlError::Spill))
  assert_false(out.values.contains("D5"))
}

test "dynamic reference and spill operator" {
  let g = agrid([
    ("A1", @engine.Cell::Literal(@value.Value::Num(10.0))),
    ("A2", @engine.Cell::Literal(@value.Value::Num(20.0))),
    ("E1", @engine.Cell::Formula("=SUM(D4#)")),
  ])
  let layout = @engine.new_array_layout()
  layout.set_dynamic("D4", "=A1:A2")
  let out = @engine.recalc_arrays(g, layout, { now: None })
  assert_eq(out.values["D4"], @value.Value::Num(10.0))
  assert_eq(out.values["D5"], @value.Value::Num(20.0))
  assert_eq(out.cells["E1"].value, @value.Value::Num(30.0))
}
