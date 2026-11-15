// Robustness regression: any formula within the Excel limits must evaluate
// without overflowing the stack on either backend, and no input (valid or
// malformed) may panic. The fuzz loops are deterministic (xorshift32).

fn rep(s : String, n : Int) -> String {
  let mut out = ""
  for _ in 0..<n {
    out = out + s
  }
  out
}

test "long left-associative chain evaluates within the length limit" {
  // 4000 terms, 7999 code units: the old recursive eval overflowed wasm-gc
  // at ~1000 terms.
  assert_num(ev("=1" + rep("+1", 3999)), 4000.0)
  // Mixed operators along the spine.
  assert_num(ev("=1" + rep("+2*3", 1000)), 6001.0)
  // References along the spine.
  let g = grid([("A1", lit(2.0))])
  assert_num(evg("=A1" + rep("+A1", 1999), g), 4000.0)
}

test "long concat chain" {
  assert_text(ev("=\"a\"" + rep("&\"b\"", 1300)), "a" + rep("b", 1300))
}

test "error propagation in long chains: leftmost error wins" {
  assert_err(ev("=1/0" + rep("+1", 100)), @value.XlError::Div0)
  assert_err(
    ev("=1" + rep("+1", 100) + "+1/0" + rep("+1", 100)),
    @value.XlError::Div0,
  )
  assert_err(
    ev("=1" + rep("+1", 100) + "+\"x\""),
    @value.XlError::Value,
  )
}

test "nesting at the 64-level limit evaluates" {
  assert_num(ev(rep("SUM(", 64) + "1" + rep(")", 64)), 1.0)
  assert_num(ev(rep("(", 64) + "1+2" + rep(")", 64)), 3.0)
  assert_num(ev("=" + rep("-", 64) + "1"), 1.0)
}

test "long postfix percent chain does not overflow" {
  // % is postfix and bypasses the nesting counter; 2000 percents used to
  // overflow the wasm-gc stack via recursive Unary evaluation.
  assert_num(ev("=1" + rep("%", 2000)), 0.0)
  // Worst case within the length contract: exactly 8192 code units.
  assert_num(ev("=1" + rep("%", 8190)), 0.0)
  let g = grid([("A1", lit(100.0))])
  assert_num(evg("=A1" + rep("%", 2000), g), 0.0)
}

test "percent chain semantics unchanged by the iterative fold" {
  assert_num(ev("=100%%"), 0.01)
  assert_num(ev("=-50%"), -0.5)
  assert_num(ev("=+\"3\"%"), 0.03)
  assert_num(ev("=1+1" + rep("%", 2000)), 1.0)
  assert_err(ev("=\"x\"" + rep("%", 2000)), @value.XlError::Value)
}

fn xorshift(x : UInt) -> UInt {
  let mut v = x
  v = v ^ (v << 13)
  v = v ^ (v >> 17)
  v = v ^ (v << 5)
  v
}

let fuzz_alphabet : Array[Char] = [
  '0', '1', '2', '3', '4', '5', '6', '7', '8', '9', '+', '-', '*', '/', '^',
  '&', '=', '<', '>', '%', '(', ')', ',', '.', '$', '"', '!', '#', ' ', 'A',
  'B', 'C', 'E', 'F', 'I', 'L', 'M', 'N', 'O', 'R', 'S', 'T', 'U', 'V', 'W',
  'X', ':', 'a', 'e', 't',
]

fn fuzz_grid() -> @engine.Grid {
  grid([
    ("A1", lit(1.0)),
    ("A2", txt("x")),
    ("A3", @engine.Cell::Literal(@value.Value::Bool(true))),
    ("B1", f("=A1+1")),
    ("C1", f("=C1")),
  ])
}

// Returns true when the formula parsed (evaluation may still yield an error
// value); a panic anywhere fails the test.
fn fuzz_eval(formula : String) -> Bool {
  match @engine.eval_formula(formula, fuzz_grid(), { now: None }) {
    Ok(_) => true
    Err(_) => false
  }
}

test "fuzz: random token soup never panics" {
  let mut s : UInt = 0x9E3779B9U
  let mut parsed = 0
  for _ in 0..<2000 {
    s = xorshift(s)
    let len = (s % 120U).reinterpret_as_int()
    let mut formula = ""
    for _ in 0..<len {
      s = xorshift(s)
      let c = fuzz_alphabet[(s % fuzz_alphabet.length().reinterpret_as_uint()).reinterpret_as_int()]
      formula = formula + c.to_string()
    }
    if fuzz_eval(formula) {
      parsed += 1
    }
  }
  assert_true(parsed > 0)
}

test "fuzz: mutated seed formulas never panic" {
  let seeds = [
    "=SUM(A1:A3,2)",
    "=IF(A1>0,\"yes\",\"no\")",
    "=VLOOKUP(2,A1:B3,2,FALSE)",
    "=TEXT(A1,\"0.00\")",
    "=DATE(2024,2,29)",
    "=A1&\"x\"",
    "=LEFT(\"abc\",2)",
    "=ROUND(1.2345,2)",
    "=MATCH(2,A1:A3,0)",
    "=INDEX(A1:B2,1,2)",
    "=NOW()",
    "=IFS(A1>0,1,TRUE,2)",
    "=XLOOKUP(1,A1:A3,A1:A3)",
    "=SUMPRODUCT(A1:A3,A1:A3)",
    "=EOMONTH(A1,1)",
    "=1+2*3^2&\"x\"=1",
    "=100%%%+2",
  ]
  let mut s : UInt = 0x12345678U
  let mut parsed = 0
  for _ in 0..<1500 {
    s = xorshift(s)
    let seed = seeds[(s % seeds.length().reinterpret_as_uint()).reinterpret_as_int()]
    s = xorshift(s)
    let nmut = 1 + (s % 3U).reinterpret_as_int()
    let mut formula = seed
    for _ in 0..<nmut {
      s = xorshift(s)
      let kind = (s % 3U).reinterpret_as_int()
      s = xorshift(s)
      let cs : Array[Char] = Array::from_iter(formula.iter())
      if cs.length() == 0 {
        break
      }
      let pos = (s % cs.length().reinterpret_as_uint()).reinterpret_as_int()
      s = xorshift(s)
      let rc = fuzz_alphabet[(s % fuzz_alphabet.length().reinterpret_as_uint()).reinterpret_as_int()]
      let mut out = ""
      for i, c in cs {
        if i == pos {
          match kind {
            0 => out = out + rc.to_string()
            1 => ()
            _ => {
              out = out + rc.to_string()
              out = out + c.to_string()
            }
          }
        } else {
          out = out + c.to_string()
        }
      }
      formula = out
    }
    if fuzz_eval(formula) {
      parsed += 1
    }
  }
  assert_true(parsed > 0)
}