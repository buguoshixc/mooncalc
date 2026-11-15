// Batch 4 provisional expectations (source: manual, legacy Excel docs).
// The real-Excel corpus (stat/text/math/lookup/logic.tsv) is the authoritative
// judge; adjudication-pending semantics are noted inline.

test "stdev: sample standard deviation" {
  assert_num(ev("=STDEV(2,4,4,4,5,5,7,9)"), 2.138089935299395)
  assert_num(ev("=STDEV(1,2,3,4)"), 1.2909944487358056)
  let g = grid([("A1", lit(1.0)), ("A2", lit(2.0)), ("A3", lit(3.0)), ("A4", lit(4.0))])
  assert_num(evg("=STDEV(A1:A4)", g), 1.2909944487358056)
  assert_err(ev("=STDEV(1)"), @value.XlError::Div0)
  assert_err(ev("=STDEV()"), @value.XlError::Value)
  assert_err(ev("=STDEV(\"x\")"), @value.XlError::Value)
  assert_num(ev("=STDEV(TRUE,2)"), 0.7071067811865476)
  let g2 = grid([
    ("A1", lit(1.0)),
    ("A2", txt("x")),
    ("A3", @engine.Cell::Literal(@value.Value::Bool(true))),
    ("A4", lit(3.0)),
  ])
  assert_num(evg("=STDEV(A1:A4)", g2), 1.4142135623730951)
  let g3 = grid([("A1", @engine.Cell::Literal(@value.Value::Err(@value.XlError::NA)))])
  assert_err(evg("=STDEV(A1,1)", g3), @value.XlError::NA)
  let g4 = grid([("A1", txt("x")), ("A2", @engine.Cell::Literal(@value.Value::Blank))])
  assert_err(evg("=STDEV(A1:A2)", g4), @value.XlError::Div0)
}

test "var: sample variance" {
  assert_num(ev("=VAR(1,2,3,4)"), 1.6666666666666667)
  assert_num(ev("=VAR(2,4,4,4,5,5,7,9)"), 4.571428571428571)
  assert_err(ev("=VAR(1)"), @value.XlError::Div0)
  assert_err(ev("=VAR()"), @value.XlError::Value)
}

test "percentile: inclusive interpolation" {
  let g = grid([("A1", lit(1.0)), ("A2", lit(2.0)), ("A3", lit(3.0)), ("A4", lit(4.0))])
  assert_num(evg("=PERCENTILE(A1:A4,0.5)", g), 2.5)
  assert_num(evg("=PERCENTILE(A1:A4,0)", g), 1.0)
  assert_num(evg("=PERCENTILE(A1:A4,1)", g), 4.0)
  assert_num(evg("=PERCENTILE(A1:A4,0.25)", g), 1.75)
  assert_num(evg("=PERCENTILE(A1:A1,0.3)", g), 1.0)
  assert_err(evg("=PERCENTILE(A1:A4,-0.1)", g), @value.XlError::Num)
  assert_err(evg("=PERCENTILE(A1:A4,1.1)", g), @value.XlError::Num)
  assert_err(evg("=PERCENTILE(A1:A4,\"x\")", g), @value.XlError::Value)
  let empty = grid([("A1", txt("x"))])
  assert_err(evg("=PERCENTILE(A1:A1,0.5)", empty), @value.XlError::Num)
}

test "replace: code-unit surgery" {
  assert_text(ev("=REPLACE(\"abcdef\",2,3,\"X\")"), "aXef")
  assert_text(ev("=REPLACE(\"abc\",1,0,\"X\")"), "Xabc")
  assert_text(ev("=REPLACE(\"abc\",5,1,\"X\")"), "abcX")
  assert_text(ev("=REPLACE(\"abc\",2,99,\"X\")"), "aX")
  assert_text(ev("=REPLACE(\"😀abc\",1,2,\"X\")"), "Xabc")
  assert_err(ev("=REPLACE(\"abc\",0,1,\"X\")"), @value.XlError::Value)
  assert_err(ev("=REPLACE(\"abc\",1,-1,\"X\")"), @value.XlError::Value)
}

test "search: case-insensitive with wildcards" {
  assert_num(ev("=SEARCH(\"b\",\"ABC\")"), 2.0)
  assert_num(ev("=SEARCH(\"B\",\"abc\")"), 2.0)
  assert_num(ev("=SEARCH(\"A\",\"abc\")"), 1.0)
  assert_err(ev("=SEARCH(\"z\",\"abc\")"), @value.XlError::Value)
  assert_num(ev("=SEARCH(\"b?\",\"abcd\")"), 2.0)
  assert_num(ev("=SEARCH(\"b*d\",\"abcd\")"), 2.0)
  assert_num(ev("=SEARCH(\"~*\",\"a*b\")"), 2.0)
  assert_num(ev("=SEARCH(\"\",\"abc\")"), 1.0)
  assert_num(ev("=SEARCH(\"b\",\"abc\",2)"), 2.0)
  assert_err(ev("=SEARCH(\"a\",\"abc\",2)"), @value.XlError::Value)
  assert_err(ev("=SEARCH(\"a\",\"abc\",0)"), @value.XlError::Value)
  assert_err(ev("=SEARCH(\"a\",\"abc\",5)"), @value.XlError::Value)
}

test "proper: word boundaries are non-letters" {
  assert_text(ev("=PROPER(\"hello world\")"), "Hello World")
  assert_text(ev("=PROPER(\"they're\")"), "They'Re")
  assert_text(ev("=PROPER(\"2-cent\")"), "2-Cent")
  assert_text(ev("=PROPER(\"\")"), "")
  assert_text(ev("=PROPER(\"HELLO\")"), "Hello")
  assert_text(ev("=PROPER(\"hello WORLD\")"), "Hello World")
}

test "ceiling: legacy sign combinations" {
  assert_num(ev("=CEILING(2.5,2)"), 4.0)
  assert_num(ev("=CEILING(-2.5,-2)"), -4.0)
  assert_num(ev("=CEILING(-2.5,2)"), -2.0)
  assert_err(ev("=CEILING(2.5,-2)"), @value.XlError::Num)
  assert_num(ev("=CEILING(0.3,0.1)"), 0.3)
  assert_num(ev("=CEILING(5,0)"), 0.0)
  assert_num(ev("=CEILING(-5,0)"), 0.0)
}

test "floor: legacy sign combinations" {
  assert_num(ev("=FLOOR(2.5,2)"), 2.0)
  assert_num(ev("=FLOOR(-2.5,-2)"), -2.0)
  assert_num(ev("=FLOOR(-2.5,2)"), -4.0)
  assert_err(ev("=FLOOR(2.5,-2)"), @value.XlError::Num)
  assert_num(ev("=FLOOR(0.3,0.1)"), 0.3)
  assert_num(ev("=FLOOR(7,3)"), 6.0)
}

test "choose: lazy 1-based selection" {
  assert_text(ev("=CHOOSE(2,\"a\",\"b\",\"c\")"), "b")
  assert_num(ev("=CHOOSE(1,10,20)"), 10.0)
  assert_err(ev("=CHOOSE(0,10)"), @value.XlError::Value)
  assert_err(ev("=CHOOSE(3,10,20)"), @value.XlError::Value)
  assert_num(ev("=CHOOSE(2.9,10,20,30)"), 20.0)
  assert_num(ev("=CHOOSE(1,1,1/0)"), 1.0)
  assert_num(ev("=CHOOSE(\"2\",10,20)"), 20.0)
  assert_err(ev("=CHOOSE(1/0,1,2)"), @value.XlError::Div0)
}

test "xor: parity with eager channels" {
  assert_bool(ev("=XOR(TRUE,FALSE)"), true)
  assert_bool(ev("=XOR(TRUE,TRUE)"), false)
  assert_bool(ev("=XOR(TRUE,TRUE,TRUE)"), true)
  assert_bool(ev("=XOR(FALSE,FALSE)"), false)
  assert_bool(ev("=XOR(1,0)"), true)
  assert_bool(ev("=XOR(\"TRUE\",\"FALSE\")"), true)
  assert_err(ev("=XOR(\"x\")"), @value.XlError::Value)
  assert_err(ev("=XOR()"), @value.XlError::Value)
  assert_err(ev("=XOR(TRUE,1/0)"), @value.XlError::Div0)
  let g = grid([
    ("A1", @engine.Cell::Literal(@value.Value::Bool(true))),
    ("A2", @engine.Cell::Literal(@value.Value::Bool(false))),
  ])
  assert_bool(evg("=XOR(A1:A2)", g), true)
}