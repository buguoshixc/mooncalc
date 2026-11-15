// Content-addressed formula parse cache: full formula text -> AST or parse
// error message. Edited text produces a new key, so no invalidation is needed.

enum CachedAst {
  Ast(@syntax.Expr)
  Bad(String)
}

/// 调用方持有的公式 AST 缓存：按公式全文缓存解析结果（含解析失败消息）。
///
/// 跨多次 `recalc_cached` 复用可跳过重复解析（如 playground 击键重算）。
/// 公式文本变化即产生新键，无需手动失效；缓存随不同公式文本数增长，
/// 长期持有的调用方可用 `clear` 释放。
pub struct ParseCache {
  priv entries : Map[String, CachedAst]
}

/// 创建一个空的公式 AST 缓存。
pub fn new_parse_cache() -> ParseCache {
  { entries: Map::new() }
}

/// 清空缓存（释放内存；后续重算会重新解析）。
pub fn ParseCache::clear(self : ParseCache) -> Unit {
  self.entries.clear()
}

/// 按依赖关系重算整个网格，复用调用方持有的 AST 缓存。语义与 `recalc` 完全一致。
///
/// 循环引用复刻 Excel 默认（迭代计算关闭）：环上单元格结果为 0，元数据 `circular: true`。
pub fn recalc_cached(
  grid : Grid,
  options : EvalOptions,
  cache : ParseCache
) -> RecalcOutput {
  recalc_impl(grid, options, Some(cache.entries)).0
}

// Shared recalc loop; also exposes the raw (pre-scalarization) value cache for
// incremental recalculation, which prefills clean cells with raw values.
fn recalc_impl(
  grid : Grid,
  options : EvalOptions,
  ast_cache : Map[String, CachedAst]?
) -> (RecalcOutput, Map[String, Value]) {
  let ctx = new_ctx(grid, options, ast_cache)
  let out : Map[String, EvalOutput] = Map::new()
  for key, cell in grid.cells {
    match cell {
      Formula(_) => {
        let v = scalar_output(cell_value(ctx, key))
        out[key] = { value: v, circular: ctx.circular.contains(key) }
      }
      Literal(_) => ()
    }
  }
  ({ cells: out, parse_errors: ctx.parse_errors }, ctx.cache)
}

// Cached parse for dependency extraction: Bad entries yield None (no refs).
fn ParseCache::parse(self : ParseCache, src : String) -> @syntax.Expr? {
  match self.entries.get(src) {
    Some(Ast(e)) => Some(e)
    Some(Bad(_)) => None
    None =>
      try @syntax.parse(src) catch {
        @syntax.ParseError(msg) => {
          self.entries[src] = Bad(msg)
          None
        }
      } noraise { e => {
        self.entries[src] = Ast(e)
        Some(e)
      } }
  }
}