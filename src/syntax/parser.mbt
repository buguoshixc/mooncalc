pub suberror ParseError {
  ParseError(String)
}

struct Parser {
  tokens : Array[Token]
  mut pos : Int
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
      let e = parse_expr(p, 0)
      expect(p, RParen, "')'")
      e
    }
    Op("-") => Unary(Neg, parse_expr(p, 60))
    Op("+") => parse_expr(p, 60)
    Ident(name) => {
      if peek(p) == Some(LParen) {
        p.pos += 1
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
        expect(p, RParen, "')'")
        Call(@value.ascii_upper(name), args)
      } else if looks_like_ref(name) {
        match @value.parse_addr(name) {
          Some(a) => Ref(a)
          None => raise ParseError("invalid cell reference: " + name)
        }
      } else {
        raise ParseError("defined names are not supported: " + name)
      }
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
        let rhs = parse_prefix(p)
        match (lhs, rhs) {
          (Ref(a), Ref(b)) => {
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
            lhs = Range(lo, hi)
          }
          _ => raise ParseError("range endpoints must be cell references")
        }
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

pub fn parse(input : String) -> Expr raise ParseError {
  let toks = lex(input)
  if toks.length() == 0 {
    raise ParseError("empty formula")
  }
  let p : Parser = { tokens: toks, pos: 0 }
  let e = parse_expr(p, 0)
  if p.pos != toks.length() {
    raise ParseError("unexpected trailing tokens in formula")
  }
  e
}