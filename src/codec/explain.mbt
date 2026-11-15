// JSON-in/JSON-out error explanation contract (CLI explain + wasm playground).
// Request:  {grid:{...}, addr:"B1", now?:<serial>}
// Response: {ok:true, target, value, circular, steps:[...], sources:[...], parse_error?}
//        or {ok:false, error:"..."}

fn explain_error(msg : String) -> String {
  Json::stringify(obj([("ok", Json::boolean(false)), ("error", Json::string(msg))]))
}

/// JSON 错误解释入口：请求 `{grid, addr, now?}`，响应贡献性错误传播路径。
///
/// `steps` 源→目标排序，每步 `{addr, formula, value, is_source, precedents}`；
/// `sources` 为错误源头地址（地址序）；目标解析失败时附 `parse_error`。
pub fn explain_json(input : String) -> String {
  let j = try @json.parse(input) catch {
    e => return explain_error("invalid JSON: " + e.to_string())
  }
  let grid = match j.value("grid") {
    Some(gj) =>
      match grid_from_json(gj) {
        Ok(g) => g
        Err(msg) => return explain_error(msg)
      }
    None => return explain_error("missing grid")
  }
  let addr_text = match j.value("addr") {
    Some(aj) =>
      match aj.as_string() {
        Some(s) => s
        None => return explain_error("addr must be a string")
      }
    None => return explain_error("missing addr")
  }
  let addr = match @facade.parse_addr(addr_text) {
    Some(a) => a
    None => return explain_error("invalid addr: " + addr_text)
  }
  let now : Double? = match j.value("now") {
    Some(nj) =>
      match nj.as_number() {
        Some(d) => Some(d)
        None => return explain_error("now must be a number")
      }
    None => None
  }
  let out = @facade.explain(addr, grid, { now })
  let steps : Array[Json] = []
  for s in out.steps {
    steps.push(obj([
      ("addr", Json::string(s.addr)),
      ("formula", Json::string(s.formula)),
      ("value", value_to_json(s.value)),
      ("is_source", Json::boolean(s.is_source)),
      ("precedents", Json::array(s.precedents.map(Json::string))),
    ]))
  }
  let fields : Array[(String, Json)] = [
    ("ok", Json::boolean(true)),
    ("target", Json::string(out.target)),
    ("value", value_to_json(out.value)),
    ("circular", Json::boolean(out.circular)),
    ("steps", Json::array(steps)),
    ("sources", Json::array(out.sources.map(Json::string))),
  ]
  if out.parse_error is Some(msg) {
    fields.push(("parse_error", Json::string(msg)))
  }
  Json::stringify(obj(fields))
}