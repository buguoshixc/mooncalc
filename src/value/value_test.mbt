test "parse_addr basic and absolute" {
  let a = @value.parse_addr("B2").unwrap()
  assert_eq(a.row, 2)
  assert_eq(a.col, 2)
  assert_eq(a.abs_row, false)
  assert_eq(a.abs_col, false)
  let b = @value.parse_addr("$XFD$1048576").unwrap()
  assert_eq(b.col, 16384)
  assert_eq(b.row, 1048576)
  assert_eq(b.abs_col, true)
  assert_eq(b.abs_row, true)
  assert_eq(@value.parse_addr("AA10").unwrap().col, 27)
}

test "parse_addr rejects invalid" {
  inspect(@value.parse_addr("A0"), content="None")
  inspect(@value.parse_addr("XFE1"), content="None")
  inspect(@value.parse_addr("A1048577"), content="None")
  inspect(@value.parse_addr("ABCD1"), content="None")
  inspect(@value.parse_addr("1A"), content="None")
  inspect(@value.parse_addr("A1B"), content="None")
  inspect(@value.parse_addr(""), content="None")
}

test "addr roundtrip" {
  let a = @value.parse_addr("$C$5").unwrap()
  assert_eq(a.to_string(), "$C$5")
  assert_eq(a.key(), "C5")
  let b = @value.parse_addr("ZZ100").unwrap()
  assert_eq(b.to_string(), "ZZ100")
  assert_eq(@value.parse_addr(b.key()).unwrap(), b)
}

test "error strings" {
  assert_eq(@value.XlError::Div0.to_string(), "#DIV/0!")
  assert_eq(@value.XlError::parse("#N/A"), Some(@value.XlError::NA))
  inspect(@value.XlError::parse("#BOGUS"), content="None")
}

test "ascii case helpers" {
  assert_eq(@value.ascii_upper("aBc123"), "ABC123")
  assert_eq(@value.ascii_lower("aBc123"), "abc123")
}