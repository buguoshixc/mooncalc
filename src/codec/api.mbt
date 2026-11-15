// Single JSON-in/JSON-out evaluation contract shared by CLI eval and web.
// Request:  {grid:{...}, formula?:"=...", addr?:"B1", now?:<serial>}
// Response: {ok:true, results:[{target,value,circular}], parse_errors:[...]}
//        or {ok:false, error:"..."}

fn error_response(msg : String) -> String {
  Json::stringify(obj([("ok", Json::boolean(false)), ("error", Json::string(msg))]))
}

fn result_json(target : String, out : EvalOutput) -> Json {
  obj([
    ("target", Json::string(target)),
    ("value", value_to_json(out.value)),
    ("circular", Json::boolean(out.circular)),
  ])
}

/// JSON-in/JSON-out 求值入口，CLI eval 与 wasm playground 共用同一契约。
///
/// 请求：`{grid:{...}, formula?:"=...", addr?:"B1", now?:<序列日>}`；
/// 给 `formula` 求值单公式，给 `addr` 求值单格，都不给则整网格重算。
/// 响应：`{ok:true, results:[{target,value,circular}], parse_errors:[...]}`
/// 或 `{ok:false, error:"..."}`。
pub fn evaluate_json(input : String) -> String {
  let j = try @json.parse(input) catch {
    e => return error_response("invalid JSON: " + e.to_string())
  }
  let grid = match j.value("grid") {
    Some(gj) =>
      match grid_from_json(gj) {
        Ok(g) => g
        Err(msg) => return error_response(msg)
      }
    None => return error_response("missing grid")
  }
  let now : Double? = match j.value("now") {
    Some(nj) =>
      match nj.as_number() {
        Some(d) => Some(d)
        None => return error_response("now must be a number")
      }
    None => None
  }
  let options : EvalOptions = { now }
  let iter : @facade.IterOptions? = match j.value("iter") {
    Some(ij) => {
      let mi = match ij.value("max_iterations") {
        Some(nj) =>
          match nj.as_number() {
            Some(d) => d.to_int()
            None => return error_response("iter.max_iterations must be a number")
          }
        None => return error_response("iter.max_iterations required")
      }
      let mc = match ij.value("max_change") {
        Some(nj) =>
          match nj.as_number() {
            Some(d) => d
            None => return error_response("iter.max_change must be a number")
          }
        None => return error_response("iter.max_change required")
      }
      let opts : @facade.IterOptions = { max_iterations: mi, max_change: mc }
      Some(opts)
    }
    None => None
  }
  let results : Array[Json] = []
  let parse_errors : Array[Json] = []
  let mut graph : Json = Json::null()
  if j.value("formula") is Some(fj) {
    let formula = match fj.as_string() {
      Some(s) => s
      None => return error_response("formula must be a string")
    }
    let evaluated = match iter {
      Some(it) => @facade.eval_formula_iterative(formula, grid, options, it)
      None => @facade.eval_formula(formula, grid, options)
    }
    match evaluated {
      Ok(out) => results.push(result_json("formula", out))
      Err(e) => {
        let msg = match e {
          @syntax.ParseError(m) => m
        }
        return error_response("parse error: " + msg)
      }
    }
  } else if j.value("addr") is Some(aj) {
    if iter is Some(_) {
      return error_response("iter is not supported with addr")
    }
    let addr_text = match aj.as_string() {
      Some(s) => s
      None => return error_response("addr must be a string")
    }
    let addr = match @facade.parse_addr(addr_text) {
      Some(a) => a
      None => return error_response("invalid addr: " + addr_text)
    }
    results.push(result_json(addr.key(), @facade.eval_at(addr, grid, options)))
  } else {
    let out = match iter {
      Some(it) => @facade.recalc_iterative(grid, options, it)
      None => @facade.recalc(grid, options)
    }
    let keys : Array[String] = []
    for k, _ in out.cells {
      keys.push(k)
    }
    keys.sort()
    for k in keys {
      match out.cells.get(k) {
        Some(o) => results.push(result_json(k, o))
        None => ()
      }
    }
    for pe in out.parse_errors {
      parse_errors.push(obj([
        ("addr", Json::string(pe.0)),
        ("message", Json::string(pe.1)),
      ]))
    }
    match @facade.dependency_graph(grid) {
      Some(dg) => {
        let prec : Map[String, Json] = Map::new()
        for k, rs in dg.precedents {
          prec[k] = Json::array(rs.map(Json::string))
        }
        let deps : Map[String, Json] = Map::new()
        for k, rs in dg.dependents {
          deps[k] = Json::array(rs.map(Json::string))
        }
        graph = obj([
          ("precedents", Json::object(prec)),
          ("dependents", Json::object(deps)),
        ])
      }
      None => ()
    }
  }
  Json::stringify(obj([
    ("ok", Json::boolean(true)),
    ("results", Json::array(results)),
    ("parse_errors", Json::array(parse_errors)),
    ("graph", graph),
  ]))
}