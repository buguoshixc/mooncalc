/// 公式解析失败（语法错误、不支持的引用形式、超出 Excel 公式限制）。
/// 与求值产生的错误值（`XlError`）是两条独立通道。
pub suberror ParseError {
  /// 携带人类可读的错误原因。
  ParseError(String)
}

/// Excel 公式长度上限（UTF-16 码元，与 Excel 公式栏一致）。超限返回 ParseError。
pub let max_formula_length : Int = 8192

/// Excel 公式嵌套上限（括号、一元运算符、函数调用均计入）。超限返回 ParseError。
pub let max_nesting_depth : Int = 64

struct Parser {
  tokens : Array[Token]
  mut pos : Int
  mut depth : Int
  /// 是否允许把逗号解析为引用并集。顶层与括号内为 true，函数实参为 false。
  mut allow_union : Bool
}

fn enter_nested(p : Parser) -> Unit raise ParseError {
  if p.depth >= max_nesting_depth {
    raise ParseError("formula nesting exceeds 64 levels")
  }
  p.depth += 1
}

fn peek(p : Parser) -> Token? {
  p.tokens.get(p.pos)
}

fn expect(p : Parser, t : Token, what : String) -> Unit raise ParseError {
  match peek(p) {
    Some(x) if x == t => p.pos += 1
    _ => raise ParseError("expected " + what)
  }
}

fn bin_op(s : String) -> BinOp {
  match s {
    "+" => Add
    "-" => Sub
    "*" => Mul
    "/" => Div
    "^" => Pow
    "&" => Concat
    "=" => Eq
    "<>" => Ne
    "<" => Lt
    "<=" => Le
    ">" => Gt
    ">=" => Ge
    _ => Add
  }
}

/// 交集运算符两侧必须是引用类表达式（Excel 拒绝 `=1 2`、`={1,2} {3,4}`）。
fn is_ref_expr(e : Expr) -> Bool {
  match e {
    Ref(_) | Range(_, _) | Sheet(_, _) | WholeCols(_, _) | WholeRows(_, _) | Name(_) |
    Call(_, _) | Intersect(_, _) | Union(_, _) => true
    _ => false
  }
}

fn looks_like_ref(name : String) -> Bool {
  let chars : Array[Char] = Array::from_iter(name.iter())
  let n = chars.length()
  let mut i = 0
  if i < n && chars[i] == '$' {
    i += 1
  }
  let ls = i
  while i < n && @value.is_ascii_letter(chars[i]) {
    i += 1
  }
  if i == ls || i - ls > 3 {
    return false
  }
  if i < n && chars[i] == '$' {
    i += 1
  }
  let ds = i
  while i < n && @value.is_ascii_digit(chars[i]) {
    i += 1
  }
  i > ds && i == n
}

/// 区域端点：单元格、整列（列序号）或整行（行序号）。
/// 只在 `:` 组合时用于区分三种区域形态，不进入 AST。
enum RngEnd {
  RngRef(@value.CellAddr)
  RngCol(Int)
  RngRow(Int)
}

/// 定义名称字符集：`[A-Za-z_][A-Za-z0-9_]*`（Excel 名称规则；不含 `$`、`.`）。
fn is_name_token(s : String) -> Bool {
  @value.valid_name_token(s)
}

/// 工作表名归一化（ASCII 大写）并校验合法性；非法表名在解析期即拒绝。
fn sheet_token(name : String) -> String raise ParseError {
  let up = @value.ascii_upper(name)
  if !@value.valid_sheet_name(up) {
    raise ParseError("invalid sheet name: " + name)
  }
  up
}

/// 把整数 token 还原为行序号（1..1048576）；非整数或越界返回 None。
fn row_index(d : Double) -> Int? {
  if !(d >= 1.0 && d <= @value.max_row.to_double()) {
    return None
  }
  let r = d.trunc().to_int()
  if r.to_double() != d {
    return None
  }
  Some(r)
}

/// 解析 `!` 右侧的受限主引用：`A1` / 列字母 `A` / 整数行号 `2`。
/// 列字母与行号只有在后面紧跟 `:` 时才合法（由调用方检查）。
fn parse_sheet_primary(p : Parser) -> Expr raise ParseError {
  let t = match peek(p) {
    Some(t) => t
    None => raise ParseError("unexpected end of formula")
  }
  p.pos += 1
  match t {
    Ident(name) =>
      if looks_like_ref(name) {
        match @value.parse_addr(name) {
          Some(a) => Ref(a)
          None => raise ParseError("invalid cell reference: " + name)
        }
      } else {
        match @value.parse_column(name) {
          Some(_) => Name(@value.ascii_upper(name))
          None => raise ParseError("invalid sheet reference: " + name)
        }
      }
    Number(d) => match row_index(d) {
      Some(r) => Lit(@value.Num(r.to_double()))
      None => raise ParseError("invalid row reference in sheet range")
    }
    _ => raise ParseError("invalid sheet reference")
  }
}

/// 解析 `Sheet!` 之后的引用；区域（含整列/整行）由外层 `:` 组合完成。
fn parse_sheet_qualified(p : Parser, sheet : String) -> Expr raise ParseError {
  let inner = parse_sheet_primary(p)
  match inner {
    Ref(_) => Sheet(sheet, inner)
    _ => {
      if peek(p) != Some(Colon) {
        raise ParseError("expected ':' after sheet-qualified reference")
      }
      Sheet(sheet, inner)
    }
  }
}

/// 区域端点规范化：行、列各自升序，并清除绝对引用标记（区域在值层面无绝对性）。
fn normalize_pair(
  a : @value.CellAddr,
  b : @value.CellAddr,
) -> (@value.CellAddr, @value.CellAddr) {
  let lo : @value.CellAddr = {
    row: if a.row < b.row { a.row } else { b.row },
    col: if a.col < b.col { a.col } else { b.col },
    abs_row: false,
    abs_col: false,
  }
  let hi : @value.CellAddr = {
    row: if a.row > b.row { a.row } else { b.row },
    col: if a.col > b.col { a.col } else { b.col },
    abs_row: false,
    abs_col: false,
  }
  (lo, hi)
}

fn whole_cols(c1 : Int, c2 : Int) -> Expr {
  if c1 <= c2 {
    WholeCols(c1, c2)
  } else {
    WholeCols(c2, c1)
  }
}

fn whole_rows(r1 : Int, r2 : Int) -> Expr {
  if r1 <= r2 {
    WholeRows(r1, r2)
  } else {
    WholeRows(r2, r1)
  }
}

fn rng_end(e : Expr) -> RngEnd? {
  match e {
    Ref(a) => Some(RngRef(a))
    Name(s) => match @value.parse_column(s) {
      Some(c) => Some(RngCol(c))
      None => None
    }
    Lit(v) => match v {
      @value.Value::Num(d) => match row_index(d) {
        Some(r) => Some(RngRow(r))
        None => None
      }
      _ => None
    }
    _ => None
  }
}

fn sheet_end(e : Expr) -> (String, RngEnd)? {
  match e {
    Sheet(s, inner) => match rng_end(inner) {
      Some(re) => Some((s, re))
      None => None
    }
    _ => None
  }
}

/// `:` 组合：单元格区域、整列区域（`A:B` / `Sheet!A:B`）、整行区域（`2:3` / `Sheet!2:3`）。
/// 3D 表名区域、跨表区域与其它组合一律解析期拒绝。
fn combine_range(lhs : Expr, rhs : Expr) -> Expr raise ParseError {
  match (rng_end(lhs), rng_end(rhs)) {
    (Some(RngRef(a)), Some(RngRef(b))) => {
      let (lo, hi) = normalize_pair(a, b)
      Range(lo, hi)
    }
    (Some(RngCol(c1)), Some(RngCol(c2))) => whole_cols(c1, c2)
    (Some(RngRow(r1)), Some(RngRow(r2))) => whole_rows(r1, r2)
    _ =>
      match (sheet_end(lhs), rng_end(rhs)) {
        (Some((s, RngRef(a))), Some(RngRef(b))) => {
          let (lo, hi) = normalize_pair(a, b)
          Sheet(s, Range(lo, hi))
        }
        (Some((s, RngCol(c1))), Some(RngCol(c2))) => Sheet(s, whole_cols(c1, c2))
        (Some((s, RngRow(r1))), Some(RngRow(r2))) => Sheet(s, whole_rows(r1, r2))
        _ =>
          match (sheet_end(lhs), sheet_end(rhs)) {
            (Some((s1, RngRef(a))), Some((s2, RngRef(b)))) => {
              if s1 != s2 {
                raise ParseError("3D references are not supported: " + s1 + ":" + s2)
              }
              let (lo, hi) = normalize_pair(a, b)
              Sheet(s1, Range(lo, hi))
            }
            _ => raise ParseError("range endpoints must be cell references")
          }
      }
  }
}

fn parse_prefix(p : Parser) -> Expr raise ParseError {
  let t = match peek(p) {
    Some(t) => t
    None => raise ParseError("unexpected end of formula")
  }
  p.pos += 1
  match t {
    Number(d) => Lit(@value.Num(d))
    Str(s) => Lit(@value.Text(s))
    BoolLit(b) => Lit(@value.Bool(b))
    ErrLit(e) => Lit(@value.Err(e))
    LParen => {
      enter_nested(p)
      let saved_union = p.allow_union
      p.allow_union = true
      let e = parse_expr(p, 0)
      p.allow_union = saved_union
      expect(p, RParen, "')'")
      p.depth -= 1
      e
    }
    LBrace => {
      enter_nested(p)
      let saved_union = p.allow_union
      p.allow_union = false
      let rows : Array[Array[Expr]] = []
      let mut row : Array[Expr] = []
      if peek(p) == Some(RBrace) {
        raise ParseError("empty array literal")
      }
      while true {
        row.push(parse_expr(p, 0))
        match peek(p) {
          Some(Comma) => {
            p.pos += 1
          }
          Some(Semicolon) => {
            p.pos += 1
            rows.push(row)
            row = []
          }
          Some(RBrace) => {
            p.pos += 1
            rows.push(row)
            break
          }
          _ => raise ParseError("expected ',' ';' or '}' in array literal")
        }
      }
      p.allow_union = saved_union
      p.depth -= 1
      let width = rows[0].length()
      if width == 0 {
        raise ParseError("empty array literal row")
      }
      for r in rows {
        if r.length() != width {
          raise ParseError("array literal rows must have equal length")
        }
      }
      ArrayLit(rows)
    }
    At => {
      enter_nested(p)
      let e = parse_expr(p, 79)
      p.depth -= 1
      Implicit(e)
    }
    Op("-") => {
      enter_nested(p)
      let e = parse_expr(p, 60)
      p.depth -= 1
      Unary(Neg, e)
    }
    Op("+") => {
      enter_nested(p)
      let e = parse_expr(p, 60)
      p.depth -= 1
      Unary(Pos, e)
    }
    Ident(name) => {
      if peek(p) == Some(Bang) {
        p.pos += 1
        let sheet = sheet_token(name)
        parse_sheet_qualified(p, sheet)
      } else if peek(p) == Some(LParen) {
        p.pos += 1
        enter_nested(p)
        let saved_union = p.allow_union
        p.allow_union = false
        let args : Array[Expr] = []
        if peek(p) != Some(RParen) {
          while true {
            args.push(parse_expr(p, 0))
            if peek(p) == Some(Comma) {
              p.pos += 1
            } else {
              break
            }
          }
        }
        p.allow_union = saved_union
        expect(p, RParen, "')'")
        p.depth -= 1
        Call(@value.ascii_upper(name), args)
      } else if looks_like_ref(name) {
        match @value.parse_addr(name) {
          Some(a) => Ref(a)
          None => raise ParseError("invalid cell reference: " + name)
        }
      } else if is_name_token(name) {
        Name(@value.ascii_upper(name))
      } else {
        raise ParseError("invalid reference or name: " + name)
      }
    }
    SheetName(raw) => {
      let sheet = sheet_token(raw)
      if peek(p) != Some(Bang) {
        raise ParseError("expected '!' after sheet name")
      }
      p.pos += 1
      parse_sheet_qualified(p, sheet)
    }
    _ => raise ParseError("unexpected token in formula")
  }
}

fn parse_expr(p : Parser, min_bp : Int) -> Expr raise ParseError {
  let mut lhs = parse_prefix(p)
  while true {
    let t = match peek(p) {
      Some(t) => t
      None => break
    }
    match t {
      Percent => {
        if 70 < min_bp {
          break
        }
        p.pos += 1
        lhs = Unary(Percent, lhs)
      }
      Colon => {
        if 80 < min_bp {
          break
        }
        p.pos += 1
        let rhs = parse_expr(p, 81)
        lhs = combine_range(lhs, rhs)
      }
      Intersect => {
        if 78 < min_bp {
          break
        }
        p.pos += 1
        let rhs = parse_expr(p, 79)
        if !is_ref_expr(lhs) || !is_ref_expr(rhs) {
          raise ParseError("unexpected trailing tokens in formula")
        }
        lhs = Intersect(lhs, rhs)
      }
      Comma => {
        if !p.allow_union || 76 < min_bp {
          break
        }
        p.pos += 1
        let rhs = parse_expr(p, 77)
        if !is_ref_expr(lhs) || !is_ref_expr(rhs) {
          raise ParseError("unexpected trailing tokens in formula")
        }
        lhs = Union(lhs, rhs)
      }
      Hash => {
        if 85 < min_bp {
          break
        }
        p.pos += 1
        lhs = Spill(lhs)
      }
      Op(s) => {
        let lbp = match s {
          "=" | "<>" | "<" | "<=" | ">" | ">=" => 10
          "&" => 20
          "+" | "-" => 30
          "*" | "/" => 40
          "^" => 50
          _ => -1
        }
        if lbp < 0 || lbp < min_bp {
          break
        }
        p.pos += 1
        let rhs = parse_expr(p, lbp + 1)
        lhs = Binary(bin_op(s), lhs, rhs)
      }
      _ => break
    }
  }
  lhs
}

/// 解析公式源码为 AST（前导 `=` 可有可无）。Pratt 解析，Excel 优先级，全部二元运算符左结合。
/// 超过 8192 字符或 64 层嵌套、语法错误、不支持的引用形式均抛 ParseError。
pub fn parse(input : String) -> Expr raise ParseError {
  if input.length() > max_formula_length {
    raise ParseError("formula exceeds 8192 characters")
  }
  let toks = lex(input)
  if toks.length() == 0 {
    raise ParseError("empty formula")
  }
  let p : Parser = { tokens: toks, pos: 0, depth: 0, allow_union: true }
  let e = parse_expr(p, 0)
  if p.pos != toks.length() {
    raise ParseError("unexpected trailing tokens in formula")
  }
  e
}