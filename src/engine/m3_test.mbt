// Provisional expectations for text / lookup / date families (source: manual).

test "LEFT RIGHT MID LEN" {
  assert_text(ev("=LEFT(\"hello\",2)"), "he")
  assert_text(ev("=LEFT(\"hello\")"), "h")
  assert_text(ev("=LEFT(\"hi\",9)"), "hi")
  assert_err(ev("=LEFT(\"hi\",-1)"), @value.XlError::Value)
  assert_text(ev("=RIGHT(\"hello\",2)"), "lo")
  assert_text(ev("=RIGHT(\"hi\",9)"), "hi")
  assert_text(ev("=MID(\"hello\",2,3)"), "ell")
  assert_text(ev("=MID(\"hello\",9,3)"), "")
  assert_err(ev("=MID(\"hello\",0,3)"), @value.XlError::Value)
  assert_err(ev("=MID(\"hello\",2,-1)"), @value.XlError::Value)
  assert_num(ev("=LEN(\"hello\")"), 5.0)
  assert_num(ev("=LEN(123)"), 3.0)
  assert_text(ev("=LEFT(12345,2)"), "12")
}

test "TRIM UPPER LOWER CONCAT" {
  assert_text(ev("=TRIM(\"  a  b  \")"), "a b")
  assert_text(ev("=UPPER(\"aBc\")"), "ABC")
  assert_text(ev("=LOWER(\"aBc\")"), "abc")
  assert_text(ev("=CONCAT(\"a\",1,TRUE)"), "a1TRUE")
  let g = grid([("A1", txt("x")), ("A2", txt("y"))])
  assert_text(evg("=CONCAT(A1:A2,\"z\")", g), "xyz")
}

test "VALUE and FIND" {
  assert_num(ev("=VALUE(\"12%\")"), 0.12)
  assert_num(ev("=VALUE(\" 2.5 \")"), 2.5)
  assert_err(ev("=VALUE(\"x\")"), @value.XlError::Value)
  assert_err(ev("=VALUE(TRUE)"), @value.XlError::Value)
  assert_num(ev("=FIND(\"b\",\"abc\")"), 2.0)
  assert_err(ev("=FIND(\"B\",\"abc\")"), @value.XlError::Value)
  assert_num(ev("=FIND(\"b\",\"abcb\",3)"), 4.0)
  assert_err(ev("=FIND(\"b\",\"abc\",4)"), @value.XlError::Value)
  assert_num(ev("=FIND(\"\",\"abc\")"), 1.0)
}

test "SUBSTITUTE" {
  assert_text(ev("=SUBSTITUTE(\"aaa\",\"a\",\"b\")"), "bbb")
  assert_text(ev("=SUBSTITUTE(\"aaa\",\"a\",\"b\",2)"), "aba")
  assert_err(ev("=SUBSTITUTE(\"aaa\",\"a\",\"b\",0)"), @value.XlError::Value)
  assert_text(ev("=SUBSTITUTE(\"abc\",\"\",\"x\")"), "abc")
  assert_text(ev("=SUBSTITUTE(\"aAa\",\"A\",\"b\")"), "aba")
}

test "TEXT numeric subset" {
  assert_text(ev("=TEXT(1234.567,\"#,##0.00\")"), "1,234.57")
  assert_text(ev("=TEXT(0.5,\"0%\")"), "50%")
  assert_text(ev("=TEXT(2.675,\"0.00\")"), "2.68")
  assert_text(ev("=TEXT(5,\"000\")"), "005")
  assert_text(ev("=TEXT(-5,\"0;(0)\")"), "(5)")
  assert_text(ev("=TEXT(0,\"0;0;\"\"zero\"\"\")"), "zero")
  assert_text(ev("=TEXT(1234567,\"0,,\")"), "1")
  assert_text(ev("=TEXT(5,\"General\")"), "5")
  assert_text(ev("=TEXT(\"abc\",\"0\")"), "abc")
  assert_text(ev("=TEXT(0.5,\"#.##\")"), ".5")
  assert_text(ev("=TEXT(1234.5,\"$#,##0.00\")"), "$1,234.50")
  assert_err(ev("=TEXT(5,\"yyyy\")"), @value.XlError::Value)
  assert_err(ev("=TEXT(5,\"[Red]0\")"), @value.XlError::Value)
  assert_err(ev("=TEXT(5,\"0;0;0;0\")"), @value.XlError::Value)
}

test "DATE normalization and Lotus bug" {
  assert_num(ev("=DATE(1900,1,1)"), 1.0)
  assert_num(ev("=DATE(1900,2,28)"), 59.0)
  assert_num(ev("=DATE(1900,3,1)"), 61.0)
  assert_num(ev("=DATE(1900,2,29)"), 61.0)
  assert_num(ev("=DATE(2023,1,1)"), 44927.0)
  assert_num(ev("=DATE(2024,2,29)"), 45351.0)
  assert_num(ev("=DATE(2026,13,1)"), ev_num("=DATE(2027,1,1)"))
  assert_num(ev("=DATE(2026,0,1)"), ev_num("=DATE(2025,12,1)"))
  assert_num(ev("=DATE(100,1,1)"), ev_num("=DATE(2000,1,1)"))
  assert_num(ev("=DATE(1900,1,0)"), 0.0)
  assert_err(ev("=DATE(1900,1,-1)"), @value.XlError::Num)
  assert_err(ev("=DATE(10000,1,1)"), @value.XlError::Num)
}

fn ev_num(formula : String) -> Double {
  match ev(formula) {
    @value.Value::Num(d) => d
    _ => panic()
  }
}

test "YEAR MONTH DAY including serial 0 and 60" {
  assert_num(ev("=YEAR(60)"), 1900.0)
  assert_num(ev("=MONTH(60)"), 2.0)
  assert_num(ev("=DAY(60)"), 29.0)
  assert_num(ev("=DAY(0)"), 0.0)
  assert_num(ev("=YEAR(0)"), 1900.0)
  assert_num(ev("=YEAR(61)"), 1900.0)
  assert_num(ev("=MONTH(61)"), 3.0)
  assert_num(ev("=DAY(61)"), 1.0)
  assert_num(ev("=YEAR(44927)"), 2023.0)
  assert_num(ev("=MONTH(44927)"), 1.0)
  assert_num(ev("=DAY(44927)"), 1.0)
  assert_num(ev("=YEAR(2958465)"), 9999.0)
  assert_num(ev("=DAY(2958465)"), 31.0)
  assert_err(ev("=YEAR(-1)"), @value.XlError::Num)
  assert_err(ev("=DAY(2958466)"), @value.XlError::Num)
  assert_num(ev("=YEAR(DATE(2026,11,14))"), 2026.0)
  assert_num(ev("=MONTH(DATE(2026,11,14))"), 11.0)
  assert_num(ev("=DAY(DATE(2026,11,14))"), 14.0)
}

test "TODAY NOW require injected clock" {
  let g = @engine.new_grid()
  match @engine.eval_formula("=TODAY()", g, { now: Some(45000.75) }) {
    Ok(out) => assert_num(out.value, 45000.0)
    Err(_) => panic()
  }
  match @engine.eval_formula("=NOW()", g, { now: Some(45000.75) }) {
    Ok(out) => assert_num(out.value, 45000.75)
    Err(_) => panic()
  }
  assert_err(ev("=TODAY()"), @value.XlError::Num)
  assert_err(ev("=NOW()"), @value.XlError::Num)
}

test "VLOOKUP exact and approximate" {
  let g = grid([
    ("A1", lit(1.0)), ("B1", txt("a")),
    ("A2", lit(2.0)), ("B2", txt("b")),
    ("A3", lit(3.0)), ("B3", txt("c")),
  ])
  assert_text(evg("=VLOOKUP(2,A1:B3,2,FALSE)", g), "b")
  assert_text(evg("=VLOOKUP(2.5,A1:B3,2,TRUE)", g), "b")
  assert_text(evg("=VLOOKUP(2.5,A1:B3,2)", g), "b")
  assert_err(evg("=VLOOKUP(0.5,A1:B3,2,TRUE)", g), @value.XlError::NA)
  assert_err(evg("=VLOOKUP(4,A1:B3,2,FALSE)", g), @value.XlError::NA)
  assert_err(evg("=VLOOKUP(2,A1:B3,3,FALSE)", g), @value.XlError::Ref)
  assert_err(evg("=VLOOKUP(2,A1:B3,0,FALSE)", g), @value.XlError::Value)
  let t = grid([("A1", txt("apple")), ("B1", lit(10.0))])
  assert_num(evg("=VLOOKUP(\"APPLE\",A1:B1,2,FALSE)", t), 10.0)
  let blank_ret = grid([("A1", lit(1.0))])
  assert_num(evg("=VLOOKUP(1,A1:B1,2,FALSE)", blank_ret), 0.0)
}

test "HLOOKUP" {
  let g = grid([
    ("A1", lit(1.0)), ("B1", lit(2.0)), ("C1", lit(3.0)),
    ("A2", txt("a")), ("B2", txt("b")), ("C2", txt("c")),
  ])
  assert_text(evg("=HLOOKUP(2,A1:C2,2,FALSE)", g), "b")
  assert_text(evg("=HLOOKUP(2.5,A1:C2,2,TRUE)", g), "b")
  assert_err(evg("=HLOOKUP(2,A1:C2,3,FALSE)", g), @value.XlError::Ref)
}

test "INDEX cells rows columns" {
  let g = grid([
    ("A1", lit(1.0)), ("B1", lit(2.0)),
    ("A2", lit(3.0)), ("B2", lit(4.0)),
  ])
  assert_num(evg("=INDEX(A1:B2,2,2)", g), 4.0)
  assert_num(evg("=SUM(INDEX(A1:B2,0,1))", g), 4.0)
  assert_num(evg("=SUM(INDEX(A1:B2,2,0))", g), 7.0)
  assert_err(evg("=INDEX(A1:B2,3,1)", g), @value.XlError::Ref)
  assert_err(evg("=INDEX(A1:B2,-1,1)", g), @value.XlError::Ref)
  let row = grid([("A1", lit(7.0)), ("B1", lit(8.0)), ("C1", lit(9.0))])
  assert_num(evg("=INDEX(A1:C1,2)", row), 8.0)
}

test "MATCH exact wildcard approximate descending" {
  let g = grid([
    ("A1", txt("apple")), ("A2", txt("apricot")), ("A3", txt("banana")),
  ])
  assert_num(evg("=MATCH(\"banana\",A1:A3,0)", g), 3.0)
  assert_num(evg("=MATCH(\"ap*\",A1:A3,0)", g), 1.0)
  assert_err(evg("=MATCH(\"cherry\",A1:A3,0)", g), @value.XlError::NA)
  let nums = grid([("A1", lit(1.0)), ("A2", lit(3.0)), ("A3", lit(5.0))])
  assert_num(evg("=MATCH(4,A1:A3,1)", nums), 2.0)
  assert_err(evg("=MATCH(0,A1:A3,1)", nums), @value.XlError::NA)
  let desc = grid([("A1", lit(5.0)), ("A2", lit(3.0)), ("A3", lit(1.0))])
  assert_num(evg("=MATCH(4,A1:A3,-1)", desc), 1.0)
}