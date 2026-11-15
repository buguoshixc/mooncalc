// Excel formula limits: 8192 UTF-16 code units, 64 nesting levels.
// Boundary regression for the no-crash guarantee (deep input must produce a
// ParseError, never a stack overflow).

fn rep(s : String, n : Int) -> String {
  let mut out = ""
  for _ in 0..<n {
    out = out + s
  }
  out
}

fn parse_ok(s : String) -> Bool {
  try @syntax.parse(s) catch {
    _ => false
  } noraise {
    _ => true
  }
}

test "length limit: 8192 code units accepted, 8193 rejected" {
  let at_limit = "=1" + rep("+1", 4095)
  assert_eq(at_limit.length(), 8192)
  assert_true(parse_ok(at_limit))
  let over = at_limit + "0"
  assert_eq(over.length(), 8193)
  inspect(err_of(over), content=(#|formula exceeds 8192 characters
  ))
}

test "length limit counts UTF-16 code units (astral char = 2)" {
  // '=' + quote + 4094 emoji (2 units each) + quote = 8191
  let ok = "=\"" + rep("\u{1F600}", 4094) + "\""
  assert_eq(ok.length(), 8191)
  assert_true(parse_ok(ok))
  let over = "=\"" + rep("\u{1F600}", 4095) + "\""
  assert_eq(over.length(), 8193)
  inspect(err_of(over), content=(#|formula exceeds 8192 characters
  ))
}

test "paren nesting: 64 accepted, 65 rejected" {
  assert_true(parse_ok("=" + rep("(", 64) + "1" + rep(")", 64)))
  inspect(
    err_of("=" + rep("(", 65) + "1" + rep(")", 65)),
    content=(#|formula nesting exceeds 64 levels
  ),
  )
}

test "unary nesting: 64 accepted, 65 rejected" {
  assert_true(parse_ok("=" + rep("-", 64) + "1"))
  inspect(
    err_of("=" + rep("-", 65) + "1"),
    content=(#|formula nesting exceeds 64 levels
  ),
  )
}

test "call nesting: 64 accepted, 65 rejected" {
  assert_true(parse_ok(rep("SUM(", 64) + "1" + rep(")", 64)))
  inspect(
    err_of(rep("SUM(", 65) + "1" + rep(")", 65)),
    content=(#|formula nesting exceeds 64 levels
  ),
  )
}

test "nesting limit is shared across parens, unary and calls" {
  assert_true(parse_ok(rep("(", 32) + rep("SUM(", 32) + "1" + rep(")", 64)))
  inspect(
    err_of(rep("(", 33) + rep("SUM(", 32) + "1" + rep(")", 65)),
    content=(#|formula nesting exceeds 64 levels
  ),
  )
}