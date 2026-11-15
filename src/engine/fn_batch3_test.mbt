// Provisional expectations for the Batch-3 function additions (source:
// manual). The real-Excel corpus is the authoritative judge; these tests guard
// the engine between corpus runs and will be reconciled after adjudication.

fn err_cell(e : @value.XlError) -> @engine.Cell {
  @engine.Cell::Literal(@value.Value::Err(e))
}

fn bool_cell(b : Bool) -> @engine.Cell {
  @engine.Cell::Literal(@value.Value::Bool(b))
}

fn blank_cell() -> @engine.Cell {
  @engine.Cell::Literal(@value.Value::Blank)
}

test "XLOOKUP exact / not found / fallback / blank" {
  let g = grid([
    ("A1", txt("a")), ("A2", txt("b")), ("A3", txt("c")), ("B1", lit(10.0)),
    ("B2", lit(20.0)), ("B3", lit(30.0)),
  ])
  assert_num(evg("=XLOOKUP(\"b\",A1:A3,B1:B3)", g), 20.0)
  assert_num(evg("=XLOOKUP(\"B\",A1:A3,B1:B3)", g), 20.0)
  assert_err(evg("=XLOOKUP(\"z\",A1:A3,B1:B3)", g), @value.XlError::NA)
  assert_text(evg("=XLOOKUP(\"z\",A1:A3,B1:B3,\"miss\")", g), "miss")
  // if_not_found is lazy: a matching row never evaluates the fallback.
  assert_num(evg("=XLOOKUP(\"b\",A1:A3,B1:B3,1/0)", g), 20.0)
  let gb = grid([("A1", txt("a")), ("A2", txt("b")), ("B1", lit(1.0)), ("B2", blank_cell())])
  assert_num(evg("=XLOOKUP(\"b\",A1:A2,B1:B2)", gb), 0.0)
}

test "XLOOKUP wildcard and approximate modes" {
  let g = grid([
    ("A1", txt("a")), ("A2", txt("b1")), ("A3", txt("b2")), ("B1", lit(10.0)),
    ("B2", lit(20.0)), ("B3", lit(30.0)),
  ])
  assert_num(evg("=XLOOKUP(\"b*\",A1:A3,B1:B3,\"miss\",2)", g), 20.0)
  assert_num(evg("=XLOOKUP(\"b?\",A1:A3,B1:B3,\"miss\",2)", g), 20.0)
  assert_text(evg("=XLOOKUP(\"z*\",A1:A3,B1:B3,\"miss\",2)", g), "miss")
  let n = grid([
    ("A1", lit(1.0)), ("A2", lit(3.0)), ("A3", lit(5.0)), ("B1", lit(10.0)),
    ("B2", lit(30.0)), ("B3", lit(50.0)),
  ])
  assert_num(evg("=XLOOKUP(4,A1:A3,B1:B3,\"miss\",-1)", n), 30.0)
  assert_num(evg("=XLOOKUP(4,A1:A3,B1:B3,\"miss\",1)", n), 50.0)
  assert_num(evg("=XLOOKUP(3,A1:A3,B1:B3,\"miss\",-1)", n), 30.0)
  assert_text(evg("=XLOOKUP(0,A1:A3,B1:B3,\"miss\",-1)", n), "miss")
}

test "XLOOKUP search modes, shape errors, binary subset-out" {
  let dup = grid([
    ("A1", txt("x")), ("A2", txt("x")), ("B1", lit(1.0)), ("B2", lit(2.0)),
  ])
  assert_num(evg("=XLOOKUP(\"x\",A1:A2,B1:B2,\"miss\",0,1)", dup), 1.0)
  assert_num(evg("=XLOOKUP(\"x\",A1:A2,B1:B2,\"miss\",0,-1)", dup), 2.0)
  let g = grid([
    ("A1", lit(1.0)), ("A2", lit(3.0)), ("B1", lit(10.0)), ("B2", lit(30.0)),
  ])
  assert_err(evg("=XLOOKUP(1,A1:A2,B1:B1)", g), @value.XlError::Value)
  assert_err(evg("=XLOOKUP(1,A1:A2,B1:B2,\"miss\",0,7)", g), @value.XlError::Value)
  // Binary-search modes are adjudicated by the real-Excel corpus
  // (lookup-xlookup-0027..0030): sorted ascending/desscending vectors resolve.
  assert_num(evg("=XLOOKUP(1,A1:A2,B1:B2,\"miss\",0,2)", g), 10.0)
  assert_text(evg("=XLOOKUP(2,A1:A2,B1:B2,\"miss\",0,2)", g), "miss")
  let d = grid([
    ("A1", lit(3.0)), ("A2", lit(1.0)), ("B1", lit(30.0)), ("B2", lit(10.0)),
  ])
  assert_num(evg("=XLOOKUP(3,A1:A2,B1:B2,\"miss\",0,-2)", d), 30.0)
  assert_num(evg("=XLOOKUP(1,A1:A2,B1:B2,\"miss\",0,-2)", d), 10.0)
  // Binary + wildcard cannot be combined.
  assert_err(evg("=XLOOKUP(1,A1:A2,B1:B2,\"miss\",2,2)", g), @value.XlError::Value)
  // Non-integral match_mode is #VALUE! (corpus lookup-xlookup-0036).
  assert_err(evg("=XLOOKUP(3,A1:A2,B1:B2,\"miss\",-1.9)", g), @value.XlError::Value)
}

test "IFS lazy / no match / odd arguments" {
  assert_num(ev("=IFS(FALSE,1,TRUE,2)"), 2.0)
  assert_text(ev("=IFS(1,\"yes\")"), "yes")
  assert_num(ev("=IFS(\"TRUE\",1)"), 1.0)
  assert_err(ev("=IFS(FALSE,1)"), @value.XlError::NA)
  assert_err(ev("=IFS(FALSE,1,TRUE)"), @value.XlError::Value)
  // Only evaluated conditions matter; the winning value is lazy.
  assert_num(ev("=IFS(TRUE,1,TRUE,1/0)"), 1.0)
  assert_err(ev("=IFS(TRUE,1/0)"), @value.XlError::Div0)
  let g = grid([("A1", err_cell(@value.XlError::NA))])
  assert_err(evg("=IFS(A1,1)", g), @value.XlError::NA)
}

test "SWITCH matching / default / laziness" {
  assert_text(ev("=SWITCH(2,1,\"one\",2,\"two\",\"other\")"), "two")
  assert_text(ev("=SWITCH(3,1,\"one\",2,\"two\",\"other\")"), "other")
  assert_err(ev("=SWITCH(3,1,\"one\",2,\"two\")"), @value.XlError::NA)
  assert_text(ev("=SWITCH(\"B\",\"b\",\"hit\",\"miss\")"), "hit")
  // No wildcards in SWITCH: "a*" is a literal comparison.
  assert_text(ev("=SWITCH(\"abc\",\"a*\",\"hit\",\"miss\")"), "miss")
  // The matching result is lazy; the unmatched result must not be evaluated.
  assert_num(ev("=SWITCH(1,1,1,1,1/0)"), 1.0)
  // No match means the trailing default IS evaluated (so its error propagates).
  assert_err(ev("=SWITCH(2,1,\"a\",1/0)"), @value.XlError::Div0)
  assert_err(ev("=SWITCH(#N/A,1,\"a\")"), @value.XlError::NA)
}

test "TEXTJOIN delimiter / ignore_empty / errors / limit" {
  let g = grid([
    ("A1", txt("a")), ("A2", blank_cell()), ("A3", txt("c")),
  ])
  assert_text(evg("=TEXTJOIN(\",\",TRUE,A1:A3)", g), "a,c")
  assert_text(evg("=TEXTJOIN(\",\",FALSE,A1:A3)", g), "a,,c")
  assert_text(evg("=TEXTJOIN(\"\",TRUE,A1:A3)", g), "ac")
  assert_text(ev("=TEXTJOIN(\"-\",TRUE,\"a\",\"b\")"), "a-b")
  assert_text(evg("=TEXTJOIN(\",\",TRUE,A2)", g), "")
  assert_text(evg("=TEXTJOIN(\",\",FALSE,A2)", g), "")
  let ge = grid([("A1", txt("a")), ("A2", err_cell(@value.XlError::NA))])
  assert_err(evg("=TEXTJOIN(\",\",TRUE,A1:A2)", ge), @value.XlError::NA)
  // Excel's 32767-character result cap.
  let long = String::from_array(Array::makei(32768, _ => 'a'))
  let gl = grid([("A1", txt(long))])
  // Excel 2024 returns the dynamic-array calculation error #CALC! here
  // (adjudicated by corpus text-textjoin-0021).
  assert_err(evg("=LEN(TEXTJOIN(\"\",TRUE,A1))", gl), @value.XlError::Calc)
  let ok = String::from_array(Array::makei(32767, _ => 'a'))
  let gok = grid([("A1", txt(ok))])
  assert_num(evg("=LEN(TEXTJOIN(\"\",TRUE,A1))", gok), 32767.0)
}

test "EOMONTH month ends / leap / negative / overflow / truncation" {
  assert_num(ev("=DAY(EOMONTH(DATE(2026,11,15),0))"), 30.0)
  assert_bool(ev("=EOMONTH(DATE(2026,11,15),0)=DATE(2026,11,30)"), true)
  assert_bool(ev("=EOMONTH(DATE(2026,11,30),0)=DATE(2026,11,30)"), true)
  assert_bool(ev("=EOMONTH(DATE(2024,1,31),1)=DATE(2024,2,29)"), true)
  assert_bool(ev("=EOMONTH(DATE(2026,1,15),-1)=DATE(2025,12,31)"), true)
  assert_bool(ev("=EOMONTH(DATE(2026,11,15),14)=DATE(2028,1,31)"), true)
  assert_bool(ev("=EOMONTH(DATE(2026,11,15)+0.9,0)=DATE(2026,11,30)"), true)
  assert_err(ev("=EOMONTH(-1,0)"), @value.XlError::Num)
  assert_err(ev("=EOMONTH(1,10000001)"), @value.XlError::Num)
}
