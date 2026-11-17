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
  inspect(err_of(""), content=(#|empty formula
  ))
  inspect(err_of("1 2"), content=(#|unexpected trailing tokens in formula
  ))
}

test "defined names parse as Name (case-normalized)" {
  inspect(@syntax.parse("MyName"), content=(#|Name(MYNAME)
  ))
  inspect(@syntax.parse("_x1+Rate"), content=(#|Binary(Add, Name(_X1), Name(RATE))
  ))
}

test "sheet-qualified references" {
  inspect(@syntax.parse("Data!A1"), content=(#|Sheet(DATA, Ref({row: 1, col: 1, abs_row: false, abs_col: false}))
  ))
  inspect(
    @syntax.parse("'My Sheet'!$B$2:C3"),
    content=(#|Sheet(MY SHEET, Range({row: 2, col: 2, abs_row: false, abs_col: false}, {row: 3, col: 3, abs_row: false, abs_col: false}))
  ),
  )
  inspect(@syntax.parse("'O''Brien'!A1"), content=(#|Sheet(O'BRIEN, Ref({row: 1, col: 1, abs_row: false, abs_col: false}))
  ))
}

test "whole column and whole row ranges" {
  inspect(@syntax.parse("A:B"), content=(#|WholeCols(1, 2)
  ))
  inspect(@syntax.parse("B:A"), content=(#|WholeCols(1, 2)
  ))
  inspect(@syntax.parse("2:3"), content=(#|WholeRows(2, 3)
  ))
  inspect(@syntax.parse("Data!A:B"), content=(#|Sheet(DATA, WholeCols(1, 2))
  ))
  inspect(@syntax.parse("Data!3:2"), content=(#|Sheet(DATA, WholeRows(2, 3))
  ))
  inspect(err_of("Data!SUM(A1)"), content=(#|expected ':' after sheet-qualified reference
  ))
  inspect(err_of("Data!1"), content=(#|expected ':' after sheet-qualified reference
  ))
}

test "3D and cross-sheet ranges are rejected" {
  inspect(err_of("Sheet1:Sheet3!A1"), content=(#|range endpoints must be cell references
  ))
  inspect(err_of("Data!A1:Other!B2"), content=(#|3D references are not supported: DATA:OTHER
  ))
}