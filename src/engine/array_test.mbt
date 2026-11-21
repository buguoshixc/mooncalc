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
  // Excel 探针 s01：E2 在 spill 区域外，普通公式的 # 按隐式交集为 #VALUE!。
  assert_eq(out.cells["E2"].value, @value.Value::Err(@value.XlError::Value))
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

test "spill reference follows implicit intersection like Excel" {
  // 探针 s01/s02/s03/s06/s05/s12/s19。
  let g = agrid([
    ("D3", @engine.Cell::Formula("=D4#")),
    ("E5", @engine.Cell::Formula("=D4#")),
    ("F1", @engine.Cell::Formula("=D4#")),
    ("G1", @engine.Cell::Formula("=@D4#")),
    ("H1", @engine.Cell::Formula("=COUNT(D4#)")),
    ("I1", @engine.Cell::Formula("=D4#+0")),
    ("J1", @engine.Cell::Formula("=SUM(D4#,1)")),
  ])
  let layout = @engine.new_array_layout()
  layout.set_dynamic("D4", "={1;2;3}")
  let out = @engine.recalc_arrays(g, layout, { now: None })
  assert_eq(out.cells["D3"].value, @value.Value::Err(@value.XlError::Value))
  // E5 行在区域内、列不在：单列引用按行隐式交集取 D5。
  assert_eq(out.cells["E5"].value, @value.Value::Num(2.0))
  assert_eq(out.cells["F1"].value, @value.Value::Err(@value.XlError::Value))
  assert_eq(out.cells["G1"].value, @value.Value::Err(@value.XlError::Value))
  assert_eq(out.cells["H1"].value, @value.Value::Num(3.0))
  assert_eq(out.cells["I1"].value, @value.Value::Err(@value.XlError::Value))
  assert_eq(out.cells["J1"].value, @value.Value::Num(7.0))
}

test "spill operator: non-spill anchor #REF!, blocked anchor #SPILL!" {
  let g1 = agrid([
    ("D4", @engine.Cell::Literal(@value.Value::Num(5.0))),
    ("F1", @engine.Cell::Formula("=D4#")),
  ])
  let out1 = @engine.recalc_arrays(g1, @engine.new_array_layout(), { now: None })
  assert_eq(out1.cells["F1"].value, @value.Value::Err(@value.XlError::Ref))

  let g2 = agrid([
    ("D5", @engine.Cell::Literal(@value.Value::Num(99.0))),
    ("F1", @engine.Cell::Formula("=D4#")),
  ])
  let layout = @engine.new_array_layout()
  layout.set_dynamic("D4", "={1;2;3}")
  let out2 = @engine.recalc_arrays(g2, layout, { now: None })
  assert_eq(out2.cells["F1"].value, @value.Value::Err(@value.XlError::Spill))
}

test "spill operator on cse anchor uses the selection rectangle" {
  // 探针 s10/s20/s21/s22：CSE 锚点同样按选区矩形解析 #。
  let g = agrid([
    ("A1", @engine.Cell::Literal(@value.Value::Num(1.0))),
    ("A2", @engine.Cell::Literal(@value.Value::Num(2.0))),
    ("A3", @engine.Cell::Literal(@value.Value::Num(3.0))),
    ("E5", @engine.Cell::Formula("=D4#")),
    ("F1", @engine.Cell::Formula("=COUNT(D4#)")),
    ("G1", @engine.Cell::Formula("=D4#")),
  ])
  let layout = @engine.new_array_layout()
  layout.set_cse("D4", "=A1:A3*1", 3, 1)
  let out = @engine.recalc_arrays(g, layout, { now: None })
  assert_eq(out.cells["E5"].value, @value.Value::Num(2.0))
  assert_eq(out.cells["F1"].value, @value.Value::Num(3.0))
  assert_eq(out.cells["G1"].value, @value.Value::Err(@value.XlError::Value))
}

test "1x1 dynamic anchor exposes a one-cell spill range" {
  // 探针 s11：D4=f2:=1 时 =D4# 仍返回 1。
  let g = agrid([("F1", @engine.Cell::Formula("=D4#"))])
  let layout = @engine.new_array_layout()
  layout.set_dynamic("D4", "=1")
  let out = @engine.recalc_arrays(g, layout, { now: None })
  assert_eq(out.cells["F1"].value, @value.Value::Num(1.0))
  assert_eq(out.ranges["D4"], (1, 1))
}

test "cse can reference a dynamic spill region" {
  // 探针 s07：CSE 公式 =D4#*1 读到动态 spill，逐格 1/2/3。
  let g = @engine.new_grid()
  let layout = @engine.new_array_layout()
  layout.set_dynamic("D4", "={1;2;3}")
  layout.set_cse("F1", "=D4#*1", 3, 1)
  let out = @engine.recalc_arrays(g, layout, { now: None })
  assert_eq(out.values["F1"], @value.Value::Num(1.0))
  assert_eq(out.values["F2"], @value.Value::Num(2.0))
  assert_eq(out.values["F3"], @value.Value::Num(3.0))
}
