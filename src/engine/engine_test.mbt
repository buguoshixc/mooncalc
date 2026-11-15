// Provisional expectations (source: manual). The real-Excel corpus is the
// authoritative judge; these tests guard the engine between corpus runs.

fn evg(formula : String, g : @engine.Grid) -> @value.Value {
  match @engine.eval_formula(formula, g, { now: None }) {
    Ok(out) => out.value
    Err(_) => panic()
  }
}

fn ev(formula : String) -> @value.Value {
  evg(formula, @engine.new_grid())
}

fn grid(cells : Array[(String, @engine.Cell)]) -> @engine.Grid {
  let g = @engine.new_grid()
  for (k, c) in cells {
    g.cells[k] = c
  }
  g
}

fn lit(d : Double) -> @engine.Cell {
  @engine.Cell::Literal(@value.Value::Num(d))
}

fn txt(s : String) -> @engine.Cell {
  @engine.Cell::Literal(@value.Value::Text(s))
}

fn f(src : String) -> @engine.Cell {
  @engine.Cell::Formula(src)
}

fn assert_num(v : @value.Value, d : Double) -> Unit raise {
  assert_eq(v, @value.Value::Num(d))
}

fn assert_text(v : @value.Value, s : String) -> Unit raise {
  assert_eq(v, @value.Value::Text(s))
}

fn assert_bool(v : @value.Value, b : Bool) -> Unit raise {
  assert_eq(v, @value.Value::Bool(b))
}

fn assert_err(v : @value.Value, e : @value.XlError) -> Unit raise {
  assert_eq(v, @value.Value::Err(e))
}

test "arithmetic coercion" {
  assert_num(ev("=\"3\"+4"), 7.0)
  assert_num(ev("=TRUE+1"), 2.0)
  assert_err(ev("=\"\"+1"), @value.XlError::Value)
  assert_num(ev("=\"12%\"+0"), 0.12)
  assert_num(ev("=\"1,000\"+0"), 1000.0)
  assert_err(ev("=\"$5\"+0"), @value.XlError::Value)
  assert_num(ev("=\" 2.5 \"+0"), 2.5)
  assert_num(ev("=\"1e3\"+0"), 1000.0)
  let blank = grid([("A1", @engine.Cell::Literal(@value.Value::Blank))])
  assert_num(evg("=A1+1", blank), 1.0)
  assert_err(ev("=1/0"), @value.XlError::Div0)
  assert_text(ev("=\"x\"&1"), "x1")
  assert_text(ev("=TRUE&\"\""), "TRUE")
}

test "number to text: 15 significant digits, General format" {
  assert_text(ev("=(1/3)&\"\""), "0.333333333333333")
  assert_text(ev("=(0.1+0.2)&\"\""), "0.3")
  assert_text(ev("=123456789012&\"\""), "123456789012")
  assert_text(ev("=0.00001&\"\""), "0.00001")
  assert_text(ev("=0.0001&\"\""), "0.0001")
  assert_text(ev("=1500&\"\""), "1500")
  assert_text(ev("=100000000000&\"\""), "100000000000")
  assert_text(ev("=99999999999&\"\""), "99999999999")
  assert_text(ev("=(-2.5)&\"\""), "-2.5")
  assert_text(ev("=0&\"\""), "0")
  // Fixed notation up to exponent 19 / down to -18, scientific outside.
  assert_text(ev("=1E19&\"\""), "10000000000000000000")
  assert_text(ev("=1E20&\"\""), "1E+20")
  assert_text(ev("=1.2E20&\"\""), "1.2E+20")
  assert_text(ev("=1E-18&\"\""), "0.000000000000000001")
  assert_text(ev("=1E-19&\"\""), "1E-19")
  assert_text(ev("=SQRT(2)&\"\""), "1.4142135623731")
  assert_text(ev("=123456789012345678&\"\""), "123456789012345000")
}

test "comparison: no cross-type coercion, type order, case-insensitive" {
  assert_bool(ev("=\"1\"=1"), false)
  assert_bool(ev("=\"a\"=\"A\""), true)
  assert_bool(ev("=1<\"a\""), true)
  assert_bool(ev("=\"a\"<TRUE"), true)
  assert_bool(ev("=2>10"), false)
  assert_bool(ev("=\"10\"<\"9\""), true)
  let blank = grid([("A1", @engine.Cell::Literal(@value.Value::Blank))])
  assert_bool(evg("=A1=0", blank), true)
  assert_bool(evg("=A1=\"\"", blank), true)
}

test "error propagation: leftmost wins, errors beat coercion" {
  assert_err(ev("=#N/A+#DIV/0!"), @value.XlError::NA)
  assert_err(ev("=1/0+#N/A"), @value.XlError::Div0)
  assert_err(ev("=#REF!*2"), @value.XlError::Ref)
  assert_err(ev("=\"x\"+#N/A"), @value.XlError::NA)
}

test "excel precedence at eval" {
  assert_num(ev("=-2^2"), 4.0)
  assert_num(ev("=2^3^2"), 64.0)
  assert_num(ev("=50%*2"), 1.0)
  assert_num(ev("=-2%"), -0.02)
  assert_num(ev("=1+2*3"), 7.0)
}

test "logic: lazy IF/IFERROR, eager AND/OR" {
  assert_num(ev("=IF(TRUE,1,1/0)"), 1.0)
  assert_num(ev("=IF(FALSE,1/0,2)"), 2.0)
  assert_bool(ev("=IF(1>2,1)"), false)
  assert_num(ev("=IF(\"true\",1,2)"), 1.0)
  assert_err(ev("=IF(\"x\",1,2)"), @value.XlError::Value)
  assert_num(ev("=IFERROR(1/0,7)"), 7.0)
  assert_text(ev("=IFERROR(#N/A,\"x\")"), "x")
  assert_num(ev("=IFERROR(5,7)"), 5.0)
  assert_err(ev("=AND(TRUE,1/0)"), @value.XlError::Div0)
  assert_err(ev("=OR(FALSE,1/0)"), @value.XlError::Div0)
  assert_bool(ev("=AND(TRUE,1,\"true\")"), true)
  assert_bool(ev("=OR(FALSE,0)"), false)
  assert_bool(ev("=NOT(\"TRUE\")"), false)
}

test "ROUND family: half away from zero with decimal fix" {
  assert_num(ev("=ROUND(2.675,2)"), 2.68)
  assert_num(ev("=ROUND(-2.675,2)"), -2.68)
  assert_num(ev("=ROUND(2.5,0)"), 3.0)
  assert_num(ev("=ROUND(-2.5,0)"), -3.0)
  assert_num(ev("=ROUND(1234,-2)"), 1200.0)
  assert_num(ev("=ROUND(1250,-2)"), 1300.0)
  assert_num(ev("=ROUND(0.1+0.2,2)"), 0.3)
  assert_num(ev("=ROUND(1.005,2)"), 1.01)
  assert_num(ev("=ROUND(5,-1)"), 10.0)
  assert_num(ev("=ROUND(4,-1)"), 0.0)
  assert_num(ev("=ROUNDUP(2.1,0)"), 3.0)
  assert_num(ev("=ROUNDUP(-2.1,0)"), -3.0)
  assert_num(ev("=ROUNDUP(0.001,0)"), 1.0)
  assert_num(ev("=ROUNDDOWN(2.9,0)"), 2.0)
  assert_num(ev("=ROUNDDOWN(-2.9,0)"), -2.0)
}

test "INT MOD ABS POWER SQRT" {
  assert_num(ev("=INT(-2.5)"), -3.0)
  assert_num(ev("=INT(2.9)"), 2.0)
  assert_num(ev("=MOD(-3,2)"), 1.0)
  assert_num(ev("=MOD(3,-2)"), -1.0)
  assert_err(ev("=MOD(5,0)"), @value.XlError::Div0)
  assert_num(ev("=MOD(5.5,2)"), 1.5)
  assert_num(ev("=ABS(-3)"), 3.0)
  assert_num(ev("=POWER(-8,1/3)"), -2.0)
  assert_err(ev("=POWER(-8,2/3)"), @value.XlError::Num)
  assert_err(ev("=POWER(0,0)"), @value.XlError::Num)
  assert_num(ev("=POWER(2,10)"), 1024.0)
  assert_err(ev("=SQRT(-1)"), @value.XlError::Num)
  assert_num(ev("=SQRT(9)"), 3.0)
  assert_err(ev("=0^-1"), @value.XlError::Div0)
}

test "aggregate channels: range vs direct args" {
  assert_num(ev("=SUM(\"3\",4)"), 7.0)
  assert_err(ev("=SUM(\"x\",4)"), @value.XlError::Value)
  let g = grid([
    ("A1", txt("x")),
    ("A2", @engine.Cell::Literal(@value.Value::Bool(true))),
    ("A3", lit(3.0)),
    ("A4", @engine.Cell::Literal(@value.Value::Blank)),
  ])
  assert_num(evg("=SUM(A1:A4)", g), 3.0)
  assert_num(evg("=SUM(A1:A4,\"2\")", g), 5.0)
  assert_num(evg("=COUNT(A1:A4)", g), 1.0)
  assert_num(evg("=COUNTA(A1:A4)", g), 3.0)
  assert_num(evg("=AVERAGE(A1:A4)", g), 3.0)
  assert_num(evg("=MIN(A1:A4)", g), 3.0)
  assert_num(evg("=MAX(A1:A4)", g), 3.0)
  assert_num(ev("=COUNT(\"5\",\"x\",TRUE)"), 2.0)
  assert_num(ev("=COUNTA(\"\",1)"), 2.0)
  let blank = grid([("A1", @engine.Cell::Literal(@value.Value::Blank))])
  assert_err(evg("=AVERAGE(A1)", blank), @value.XlError::Div0)
  assert_num(evg("=SUM(A1)", blank), 0.0)
  assert_num(ev("=AVERAGE(2,4)"), 3.0)
  assert_num(ev("=MIN(3,1,2)"), 1.0)
  assert_num(ev("=MAX(3,1,2)"), 3.0)
  assert_err(ev("=MIN(\"x\")"), @value.XlError::Value)
  let texts = grid([("A1", txt("a")), ("A2", txt("b"))])
  assert_num(evg("=MIN(A1:A2)", texts), 0.0)
  assert_num(ev("=MEDIAN(1,3,2)"), 2.0)
  assert_num(ev("=MEDIAN(1,3,2,4)"), 2.5)
  assert_err(ev("=MEDIAN(\"x\")"), @value.XlError::Value)
}

test "SUMIF COUNTIF SUMPRODUCT" {
  let g = grid([
    ("A1", lit(1.0)), ("A2", lit(2.0)), ("A3", lit(3.0)), ("A4", lit(4.0)),
    ("B1", lit(10.0)), ("B2", lit(20.0)), ("B3", lit(30.0)), ("B4", lit(40.0)),
  ])
  assert_num(evg("=SUMIF(A1:A4,\">2\",B1:B4)", g), 70.0)
  assert_num(evg("=SUMIF(A1:A4,2)", g), 2.0)
  assert_num(evg("=SUMIF(A1:A4,\">=3\")", g), 7.0)
  assert_num(evg("=COUNTIF(A1:A4,\">2\")", g), 2.0)
  assert_num(evg("=SUMPRODUCT(A1:A2,B1:B2)", g), 50.0)
  assert_err(evg("=SUMPRODUCT(A1:A2,B1:B3)", g), @value.XlError::Value)
  assert_err(ev("=SUMPRODUCT(2,3)"), @value.XlError::Value)
  let t = grid([
    ("A1", txt("apple")), ("A2", txt("apricot")),
    ("A3", txt("banana")), ("A4", txt("Apple")),
  ])
  assert_num(evg("=COUNTIF(A1:A4,\"ap*\")", t), 3.0)
  assert_num(evg("=COUNTIF(A1:A4,\"??????\")", t), 1.0)
  let esc = grid([("A1", txt("a*b")), ("A2", txt("axb"))])
  assert_num(evg("=COUNTIF(A1:A2,\"a~*b\")", esc), 1.0)
}

test "grid recalc: chains, diamonds, memoization" {
  let g = grid([
    ("A1", lit(1.0)),
    ("B1", f("=A1+1")),
    ("C1", f("=A1+2")),
    ("D1", f("=B1+C1")),
  ])
  let out = @engine.recalc(g, { now: None })
  assert_num(out.cells["D1"].value, 5.0)
  assert_eq(out.cells["D1"].circular, false)
  assert_eq(out.cells.length(), 3)
  assert_eq(out.parse_errors.length(), 0)
}

test "circular references evaluate to zero, flagged" {
  let g = grid([("A1", f("=B1")), ("B1", f("=A1"))])
  let out = @engine.recalc(g, { now: None })
  assert_num(out.cells["A1"].value, 0.0)
  assert_num(out.cells["B1"].value, 0.0)
  assert_eq(out.cells["A1"].circular, true)
  assert_eq(out.cells["B1"].circular, true)
  let self_ref = grid([("A1", f("=A1+1"))])
  let out2 = @engine.recalc(self_ref, { now: None })
  assert_num(out2.cells["A1"].value, 0.0)
  assert_eq(out2.cells["A1"].circular, true)
  let three = grid([
    ("A1", f("=B1")), ("B1", f("=C1")), ("C1", f("=A1")),
  ])
  let out3 = @engine.recalc(three, { now: None })
  assert_num(out3.cells["C1"].value, 0.0)
  assert_eq(out3.cells["C1"].circular, true)
  // A cell depending on a cycle is NOT itself circular.
  let dep = grid([("A1", f("=A1")), ("D1", f("=A1+5"))])
  let out4 = @engine.recalc(dep, { now: None })
  assert_num(out4.cells["D1"].value, 5.0)
  assert_eq(out4.cells["D1"].circular, false)
  assert_eq(out4.cells["A1"].circular, true)
}

test "grid parse errors are collected, cell becomes #VALUE!" {
  let g = grid([("A1", f("=1+")), ("B1", lit(2.0))])
  let out = @engine.recalc(g, { now: None })
  assert_err(out.cells["A1"].value, @value.XlError::Value)
  assert_eq(out.parse_errors.length(), 1)
  assert_eq(out.parse_errors[0].0, "A1")
}

test "references: blank outside grid, ranges, scalarization" {
  assert_num(ev("=Z99+1"), 1.0)
  let g = grid([
    ("A1", lit(1.0)), ("A2", lit(2.0)), ("B1", lit(3.0)), ("B2", lit(4.0)),
  ])
  assert_num(evg("=SUM(A1:B2)", g), 10.0)
  assert_err(evg("=A1:B2+1", g), @value.XlError::Value)
  let one = grid([("A1", lit(5.0))])
  assert_num(evg("=SUM(A1:A1)+1", one), 6.0)
}

test "registry: unknown function, arity, case-insensitive names" {
  assert_err(ev("=FOO(1)"), @value.XlError::Name)
  assert_err(ev("=IF(1)"), @value.XlError::Value)
  assert_err(ev("=ROUND(1)"), @value.XlError::Value)
  assert_err(ev("=SUM()"), @value.XlError::Value)
  assert_num(ev("=sum(1,2)"), 3.0)
}

test "parse errors use the Result channel" {
  match @engine.eval_formula("1+", @engine.new_grid(), { now: None }) {
    Err(_) => ()
    Ok(_) => panic()
  }
}
test "reference vs literal channels in aggregates" {
  let t = grid([("A1", txt("abc"))])
  assert_num(evg("=SUM(A1,4)", t), 4.0)
  assert_num(ev("=SUM(\"3\",4)"), 7.0)
  assert_err(evg("=AVERAGE(A1)", t), @value.XlError::Div0)
  assert_err(evg("=MEDIAN(A1)", t), @value.XlError::Num)
  assert_num(evg("=MIN(A1)", t), 0.0)
  assert_num(evg("=COUNT(A1)", t), 0.0)
  assert_num(ev("=COUNT(\"3\")"), 1.0)
  let b = grid([("A1", @engine.Cell::Literal(@value.Value::Blank))])
  assert_num(evg("=SUM(A1)", b), 0.0)
  assert_err(evg("=AVERAGE(A1)", b), @value.XlError::Div0)
  assert_num(evg("=COUNTA(A1)", b), 0.0)
  let bools = grid([("A1", @engine.Cell::Literal(@value.Value::Bool(true)))])
  assert_num(evg("=SUM(A1)", bools), 0.0)
  assert_num(ev("=SUM(TRUE)"), 1.0)
}

test "errors inside single-cell references propagate and are catchable" {
  let e = grid([
    ("A1", @engine.Cell::Literal(@value.Value::Err(@value.XlError::NA))),
    ("B1", f("=1/0")),
  ])
  assert_err(evg("=A1+1", e), @value.XlError::NA)
  assert_err(evg("=A1+B1", e), @value.XlError::NA)
  assert_err(evg("=B1+A1", e), @value.XlError::Div0)
  assert_num(evg("=IFERROR(A1,0)", e), 0.0)
  assert_err(evg("=SUM(A1,4)", e), @value.XlError::NA)
  assert_err(evg("=LEFT(A1,2)", e), @value.XlError::NA)
  assert_num(evg("=COUNTIF(A1,1)", e), 0.0)
  assert_num(evg("=SUMIF(A1,\">0\")", e), 0.0)
  // An error criterion matches an error cell of the same value (verified by
  // probes against Excel 2024; corpus stat-countif-0121 covers the no-match case).
  assert_num(evg("=COUNTIF(A1,A1)", e), 1.0)
}

test "AND/OR reference channel: only logicals count" {
  let g = grid([("A1", lit(1.0)), ("A2", lit(0.0))])
  assert_bool(evg("=AND(A1,A2)", g), false)
  assert_bool(evg("=OR(A1,A2)", g), true)
  let z = grid([("A1", lit(0.0))])
  assert_bool(evg("=AND(TRUE,A1)", z), false)
  let t = grid([
    ("A1", txt("TRUE")),
    ("A2", @engine.Cell::Literal(@value.Value::Bool(true))),
  ])
  assert_bool(evg("=AND(A1,A2)", t), true)
  assert_err(ev("=AND(\"x\")"), @value.XlError::Value)
}

test "COUNT/COUNTA ignore literal errors, reference errors counted separately" {
  assert_num(ev("=COUNT(#N/A)"), 0.0)
  assert_num(ev("=COUNTA(#N/A)"), 1.0)
  assert_num(ev("=COUNT(1/0)"), 0.0)
  let e = grid([
    ("A1", @engine.Cell::Literal(@value.Value::Err(@value.XlError::NA))),
  ])
  assert_num(evg("=COUNT(A1)", e), 0.0)
  assert_num(evg("=COUNTA(A1)", e), 1.0)
  assert_num(evg("=COUNT(A1,1)", e), 1.0)
}

test "formula results are never blank: blank refs display as 0" {
  let b = grid([("A1", @engine.Cell::Literal(@value.Value::Blank))])
  assert_num(evg("=A1", b), 0.0)
  assert_num(evg("=IFERROR(A1,9)", b), 0.0)
  assert_text(evg("=A1&\"\"", b), "")
  assert_bool(evg("=A1=\"\"", b), true)
  assert_num(evg("=IF(TRUE,A1,9)", b), 0.0)
}

test "unary plus is an identity operator" {
  assert_text(ev("=+\"3\""), "3")
  assert_bool(ev("=+TRUE"), true)
  assert_text(ev("=+\"abc\""), "abc")
  assert_num(ev("=+1+2"), 3.0)
  let t = grid([("A1", txt("x"))])
  assert_text(evg("=+A1", t), "x")
}

test "corpus-confirmed date text coercion and grouping" {
  assert_num(ev("=YEAR(\"2026-11-14\")"), 2026.0)
  assert_num(ev("=MONTH(\"2026/1/2\")"), 1.0)
  assert_num(ev("=DAY(\"2026-11-14 10:00\")"), 14.0)
  assert_num(ev("=\"2026-11-14\"+0"), 46340.0)
  assert_num(ev("=VALUE(\"2026-11-14 10:00\")"), 46340.0 + 10.0 / 24.0)
  assert_err(ev("=VALUE(\"11/14/2026\")"), @value.XlError::Value)
  assert_err(ev("=VALUE(\"2026-13-01\")"), @value.XlError::Value)
  assert_err(ev("=VALUE(\"2026-02-30\")"), @value.XlError::Value)
  assert_num(ev("=VALUE(\"1,000\")"), 1000.0)
  assert_num(ev("=VALUE(\"-1,000.50\")"), -1000.5)
  assert_err(ev("=VALUE(\"1,00\")"), @value.XlError::Value)
}

test "corpus-confirmed Excel DATE calendar" {
  assert_num(ev("=DATE(1900,2,29)"), 60.0)
  assert_num(ev("=DATE(1900,2,30)"), 61.0)
  assert_num(ev("=DATE(1900,3,0)"), 60.0)
  assert_num(ev("=DATE(1900,1,0)"), 0.0)
  assert_num(ev("=DATE(1900,3,-1)"), 59.0)
  assert_num(ev("=DATE(1900,12,31)"), 366.0)
  assert_num(ev("=DATE(0,1,1)"), 1.0)
  assert_err(ev("=DATE(1900,0,1)"), @value.XlError::Num)
  assert_err(ev("=DATE(10000,1,1)"), @value.XlError::Num)
}

test "corpus-confirmed UTF-16 text functions" {
  assert_num(ev("=LEN(\"😀\")"), 2.0)
  assert_num(ev("=LEN(\"a😀b\")"), 4.0)
  assert_num(ev("=FIND(\"b\",\"a😀b\")"), 4.0)
  assert_num(ev("=FIND(\"😀\",\"a😀b\")"), 2.0)
  assert_text(ev("=LEFT(\"😀abc\",2)"), "😀a")
  // MID counts UTF-16 code units (MID("a😀b",2,1) is a lone surrogate).
  assert_num(ev("=LEN(MID(\"a😀b\",2,1))"), 1.0)
  assert_num(ev("=LEN(MID(\"a😀b\",2,2))"), 2.0)
  assert_text(ev("=LOWER(\"CAFÉ\")"), "café")
  assert_text(ev("=UPPER(\"straße\")"), "STRAßE")
}

test "corpus-confirmed formats and AND/OR literals" {
  assert_text(ev("=TEXT(5,\"yyyy\")"), "1900")
  assert_text(ev("=TEXT(60,\"yyyy-mm-dd\")"), "1900-02-29")
  assert_text(ev("=TEXT(46340.5,\"yyyy-mm-dd hh:mm:ss\")"), "2026-11-14 12:00:00")
  assert_text(ev("=TEXT(2,\"ddd\")"), "Mon")
  assert_text(ev("=TEXT(0.75,\"h:mm AM/PM\")"), "6:00 PM")
  assert_err(ev("=TEXT(123,\"General\")"), @value.XlError::Value)
  assert_bool(ev("=AND(\"0\",TRUE)"), true)
  assert_bool(ev("=OR(\"0\",FALSE)"), false)
  assert_bool(ev("=AND(TRUE,\"x\")"), true)
  assert_bool(ev("=OR(FALSE,\"x\")"), false)
  let t = grid([("A1", txt("TRUE")), ("A2", @engine.Cell::Literal(@value.Value::Blank))])
  assert_err(evg("=AND(A1,A2)", t), @value.XlError::Value)
}

test "corpus-confirmed top-level INDEX array output" {
  let g = grid([
    ("A1", lit(1.0)), ("B1", lit(2.0)), ("C1", lit(3.0)),
    ("A2", lit(4.0)), ("B2", lit(5.0)), ("C2", lit(6.0)),
    ("A3", lit(7.0)), ("B3", lit(8.0)), ("C3", lit(9.0)),
  ])
  assert_num(evg("=INDEX(A1:C3,0,1)", g), 1.0)
  assert_err(evg("=INDEX(A1:C3,0,0)", g), @value.XlError::Value)
  assert_err(evg("=INDEX(A1:C3,2,0)", g), @value.XlError::Value)
  assert_num(evg("=SUM(INDEX(A1:C3,0,0))", g), 45.0)
}

test "corpus-confirmed VALUE error propagation" {
  let e = grid([("A1", @engine.Cell::Literal(@value.Value::Err(@value.XlError::NA)))])
  assert_err(evg("=VALUE(A1)", e), @value.XlError::NA)
}
