// Stateful incremental recalc entry for the wasm shell. The RecalcState is
// caller-owned (the web package keeps it across calls); the codec stays pure.
// Request:  {grid:{...}, changed?:["A1",...], now?:<serial>, reset?:bool}
// Response: evaluate_json full-grid shape + incremental:{recomputed:[...], full:bool}

/// JSON-in/JSON-out 增量重算入口：状态由调用方持有（wasm 壳层），codec 保持无状态。
///
/// 请求：`{grid:{...}, changed?:["A1",...], now?:<序列日>, reset?:bool}`；
/// `reset` 为 true、状态为空或缺 `changed` 时走 `recalc_init` 全量重建。
/// 响应：在整网格 `evaluate_json` 字段之外附加 `incremental:{recomputed:[...], full:bool}`。
/// 返回 (响应, 新状态)；请求解析失败时原样返回旧状态。
pub fn recalc_incremental_json(
  input : String,
  state : @facade.RecalcState?
) -> (String, @facade.RecalcState?) {
  let j = try @json.parse(input) catch {
    e => return (error_response("invalid JSON: " + e.to_string()), state)
  }
  let grid = match j.value("grid") {
    Some(gj) =>
      match grid_from_json(gj) {
        Ok(g) => g
        Err(msg) => return (error_response(msg), state)
      }
    None => return (error_response("missing grid"), state)
  }
  let now : Double? = match j.value("now") {
    Some(nj) =>
      match nj.as_number() {
        Some(d) => Some(d)
        None => return (error_response("now must be a number"), state)
      }
    None => None
  }
  let options : EvalOptions = { now }
  let reset = match j.value("reset") {
    Some(rj) => rj.as_bool() == Some(true)
    None => false
  }
  let changed : Array[String]? = match j.value("changed") {
    Some(cj) =>
      match cj.as_array() {
        Some(arr) => {
          let keys : Array[String] = []
          for item in arr {
            match item.as_string() {
              Some(s) =>
                match @facade.parse_addr(s) {
                  Some(a) => keys.push(a.key())
                  None =>
                    return (error_response("invalid changed addr: " + s), state)
                }
              None =>
                return (error_response("changed must be an array of strings"), state)
            }
          }
          Some(keys)
        }
        None =>
          return (error_response("changed must be an array of strings"), state)
      }
    None => None
  }
  let (out, report, new_state) = match (state, reset, changed) {
    (Some(st), false, Some(ch)) => {
      let (o, r) = @facade.recalc_update_report(st, grid, ch, options)
      (o, r, Some(st))
    }
    _ => {
      let (st, o) = @facade.recalc_init(grid, options)
      let keys : Array[String] = []
      for k, _ in o.cells {
        keys.push(k)
      }
      keys.sort()
      let rep : @facade.RecalcReport = { recomputed: keys, full_fallback: true }
      (o, rep, Some(st))
    }
  }
  let fields = recalc_response_fields(out, grid)
  fields.push((
    "incremental",
    obj([
      ("recomputed", Json::array(report.recomputed.map(Json::string))),
      ("full", Json::boolean(report.full_fallback)),
    ]),
  ))
  (Json::stringify(obj(fields)), new_state)
}