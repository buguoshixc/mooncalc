/// 一元运算符。
pub(all) enum UnOp {
  /// 一元负号（走数值强制转换）。
  Neg
  /// 一元正号（恒等运算，不强制转换）。
  Pos
  /// 后缀百分号（`50%` = 0.5，走数值强制转换）。
  Percent
} derive(Show, Debug, Eq)

/// 二元运算符（全部左结合；优先级见 docs/semantics.md）。
pub(all) enum BinOp {
  /// `+`
  Add
  /// `-`
  Sub
  /// `*`
  Mul
  /// `/`
  Div
  /// `^`（乘方）
  Pow
  /// `&`（文本连接）
  Concat
  /// `=`
  Eq
  /// `<>`
  Ne
  /// `<`
  Lt
  /// `<=`
  Le
  /// `>`
  Gt
  /// `>=`
  Ge
} derive(Show, Debug, Eq)

/// 公式 AST。解析器产物，求值器输入。
pub(all) enum Expr {
  /// 字面量（数字/文本/布尔/错误）。
  Lit(@value.Value)
  /// 单元格引用。
  Ref(@value.CellAddr)
  /// 区域引用（已归一化为左上/右下角）。
  Range(@value.CellAddr, @value.CellAddr)
  /// 限定工作表引用（表名已 ASCII 大写归一）：`Sheet("DATA", Ref(addr))`。
  /// 内层只能是 `Ref`/`Range`/`WholeCols`/`WholeRows`；裸表名必须紧跟 `!`。
  Sheet(String, Expr)
  /// 整列引用（首末列号均含，1 基）：`A:C` → `WholeCols(1, 3)`。
  WholeCols(Int, Int)
  /// 整行引用（首末行号均含，1 基）：`2:3` → `WholeRows(2, 3)`。
  WholeRows(Int, Int)
  /// 工作簿级定义名称（名称已 ASCII 大写归一，字符集 `[A-Za-z_][A-Za-z0-9_]*`）。
  Name(String)
  /// 一元运算。
  Unary(UnOp, Expr)
  /// 二元运算。
  Binary(BinOp, Expr, Expr)
  /// 函数调用（函数名已 ASCII 大写归一化）。
  Call(String, Array[Expr])
} derive(Show, Debug, Eq)