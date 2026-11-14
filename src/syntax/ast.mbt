pub(all) enum UnOp {
  Neg
  Pos
  Percent
} derive(Show, Debug, Eq)

pub(all) enum BinOp {
  Add
  Sub
  Mul
  Div
  Pow
  Concat
  Eq
  Ne
  Lt
  Le
  Gt
  Ge
} derive(Show, Debug, Eq)

pub(all) enum Expr {
  Lit(@value.Value)
  Ref(@value.CellAddr)
  Range(@value.CellAddr, @value.CellAddr)
  Unary(UnOp, Expr)
  Binary(BinOp, Expr, Expr)
  Call(String, Array[Expr])
} derive(Show, Debug, Eq)