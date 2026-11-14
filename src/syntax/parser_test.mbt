fn err_of(s : String) -> String {
  try @syntax.parse(s) catch {
    @syntax.ParseError(m) => m
  } noraise {
    _ => "NO ERROR"
  }
}

test "unary minus binds tighter than pow: -2^2 = (-2)^2" {
  let e = @syntax.parse("-2^2")
  assert_eq(
    e,
    @syntax.Expr::Binary(
      @syntax.BinOp::Pow,
      @syntax.Expr::Unary(@syntax.UnOp::Neg, @syntax.Expr::Lit(@value.Num(2.0))),
      @syntax.Expr::Lit(@value.Num(2.0)),
    ),
  )
}

test "pow is left associative: 2^3^2 = (2^3)^2" {
  let e = @syntax.parse("2^3^2")
  assert_eq(
    e,
    @syntax.Expr::Binary(
      @syntax.BinOp::Pow,
      @syntax.Expr::Binary(
        @syntax.BinOp::Pow,
        @syntax.Expr::Lit(@value.Num(2.0)),
        @syntax.Expr::Lit(@value.Num(3.0)),
      ),
      @syntax.Expr::Lit(@value.Num(2.0)),
    ),
  )
}

test "precedence chain snapshot" {
  inspect(@syntax.parse("1+2*3^2&\"x\"=1"), content=(#|Binary(Eq, Binary(Concat, Binary(Add, Lit(Num(1)), Binary(Mul, Lit(Num(2)), Binary(Pow, Lit(Num(3)), Lit(Num(2))))), Lit(Text(x))), Lit(Num(1)))
  ))
}

test "percent postfix" {
  inspect(@syntax.parse("-2%"), content=(#|Unary(Neg, Unary(Percent, Lit(Num(2))))
  ))
  inspect(@syntax.parse("50%*2"), content=(#|Binary(Mul, Unary(Percent, Lit(Num(50))), Lit(Num(2)))
  ))
}

test "literals" {
  inspect(@syntax.parse("=1.5e3"), content=(#|Lit(Num(1500))
  ))
  inspect(@syntax.parse("\"a\"\"b\""), content=(#|Lit(Text(a"b))
  ))
  inspect(@syntax.parse("TRUE"), content=(#|Lit(Bool(true))
  ))
  inspect(@syntax.parse("#DIV/0!"), content=(#|Lit(Err(Div0))
  ))
  inspect(@syntax.parse("#N/A"), content=(#|Lit(Err(NA))
  ))
}

test "references and ranges" {
  inspect(@syntax.parse("$A$1+B2"), content=(#|Binary(Add, Ref({row: 1, col: 1, abs_row: true, abs_col: true}), Ref({row: 2, col: 2, abs_row: false, abs_col: false}))
  ))
  inspect(@syntax.parse("B2:A1"), content=(#|Range({row: 1, col: 1, abs_row: false, abs_col: false}, {row: 2, col: 2, abs_row: false, abs_col: false})
  ))
  inspect(@syntax.parse("SUM(A1:A3,2)"), content=(#|Call(SUM, [Range({row: 1, col: 1, abs_row: false, abs_col: false}, {row: 3, col: 1, abs_row: false, abs_col: false}), Lit(Num(2))])
  ))
}

test "function name vs reference disambiguation" {
  inspect(@syntax.parse("LOG10(100)"), content=(#|Call(LOG10, [Lit(Num(100))])
  ))
  inspect(@syntax.parse("A1"), content=(#|Ref({row: 1, col: 1, abs_row: false, abs_col: false})
  ))
}

test "parse errors" {
  inspect(err_of("1+"), content=(#|unexpected end of formula
  ))
  inspect(err_of("\"unterminated"), content=(#|unterminated string literal
  ))
  inspect(err_of("#BOGUS"), content=(#|unknown error literal: #BOGUS
  ))
  inspect(err_of("A1:B2:C3"), content=(#|range endpoints must be cell references
  ))
  inspect(err_of("MyName"), content=(#|defined names are not supported: MyName
  ))
  inspect(err_of(""), content=(#|empty formula
  ))
  inspect(err_of("1 2"), content=(#|unexpected trailing tokens in formula
  ))
}