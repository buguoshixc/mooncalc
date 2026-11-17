type Json = @json.Json

fn main {
  let args = match parse_args(@sys.get_cli_args()) {
    Ok(a) => a
    Err(msg) => die(msg)
  }
  match args.cmd {
    "eval" => run_eval(args)
    "bench" => run_bench_cmd(args)
    "perf" => run_perf(args)
    "explain" => run_explain(args)
    _ => ()
  }
}

fn[T] die(msg : String) -> T {
  println(msg)
  @sys.exit(2)
  panic()
}

fn read_text(path : String) -> String {
  let text = try @fs.read_file_to_string(path) catch {
    _ => die("cannot read file: " + path)
  }
  @codec.strip_utf8_bom(text)
}

fn parse_json_or_die(text : String, path : String) -> Json {
  try @json.parse(text) catch { _ => die("invalid JSON in " + path) }
}

fn parse_iter_or_die(s : String) -> Json {
  let mut sep = -1
  for i in 0..<s.length() {
    if s[i] == ':' {
      sep = i
      break
    }
  }
  if sep < 1 || sep == s.length() - 1 {
    die("--iter expects <max_iterations>:<max_change>")
  }
  let n = match parse_int_arg(s.substring(start=0, end=sep)) {
    Some(v) => v
    None => die("--iter max_iterations not a positive integer")
  }
  let c = match parse_double_arg(s.substring(start=sep + 1, end=s.length())) {
    Ok(d) => d
    Err(m) => die("--iter max_change " + m)
  }
  let m : Map[String, Json] = Map::new()
  m["max_iterations"] = Json::number(n.to_double())
  m["max_change"] = Json::number(c)
  Json::object(m)
}

/// 把 `--names` 指向的 JSON 对象（名称 → 引用文本）并入 grid 对象的保留键 `names`。
fn inject_names(grid_json : Json, names_path : String?) -> Json {
  match names_path {
    None => grid_json
    Some(path) => {
      let names = parse_json_or_die(read_text(path), path)
      match grid_json.as_object() {
        Some(m) => {
          let m2 = m.copy()
          m2["names"] = names
          Json::object(m2)
        }
        None => die("grid must be a JSON object")
      }
    }
  }
}

fn run_eval(a : Args) -> Unit {
  let grid_path = match a.grid {
    Some(p) => p
    None => die("eval requires --grid\n" + usage())
  }
  let grid_json = inject_names(
    parse_json_or_die(read_text(grid_path), grid_path),
    a.names,
  )
  let req : Map[String, Json] = Map::new()
  req["grid"] = grid_json
  if a.formula is Some(f) {
    req["formula"] = Json::string(f)
  }
  if a.addr is Some(addr) {
    req["addr"] = Json::string(addr)
  }
  if a.now is Some(s) {
    req["now"] = Json::number(parse_now_or_die(s))
  }
  if a.iter is Some(s) {
    req["iter"] = parse_iter_or_die(s)
  }
  let response = @codec.evaluate_json(Json::stringify(Json::object(req)))
  match a.out {
    Some(path) =>
      try @fs.write_string_to_file(path, response + "\n") catch {
        _ => die("cannot write file: " + path)
      }
    None => println(response)
  }
  let j = try @json.parse(response) catch { _ => die("internal: bad response") }
  match j.value("ok") {
    Some(ok) => if ok.as_bool() == Some(true) { @sys.exit(0) } else { @sys.exit(2) }
    None => @sys.exit(2)
  }
}

fn run_explain(a : Args) -> Unit {
  let grid_path = match a.grid {
    Some(p) => p
    None => die("explain requires --grid\n" + usage())
  }
  let addr = match a.addr {
    Some(s) => s
    None => die("explain requires --addr\n" + usage())
  }
  let grid_json = inject_names(
    parse_json_or_die(read_text(grid_path), grid_path),
    a.names,
  )
  let req : Map[String, Json] = Map::new()
  req["grid"] = grid_json
  req["addr"] = Json::string(addr)
  if a.now is Some(s) {
    req["now"] = Json::number(parse_now_or_die(s))
  }
  let response = @codec.explain_json(Json::stringify(Json::object(req)))
  match a.out {
    Some(path) =>
      try @fs.write_string_to_file(path, response + "\n") catch {
        _ => die("cannot write file: " + path)
      }
    None => println(response)
  }
  let j = try @json.parse(response) catch { _ => die("internal: bad response") }
  match j.value("ok") {
    Some(ok) => if ok.as_bool() == Some(true) { @sys.exit(0) } else { @sys.exit(2) }
    None => @sys.exit(2)
  }
}

fn run_bench_cmd(a : Args) -> Unit {
  let dir = match a.corpus {
    Some(d) => d
    None => die("bench requires --corpus\n" + usage())
  }
  let entries = try @fs.read_dir(dir) catch { _ => die("cannot read directory: " + dir) }
  let names : Array[String] = Array::from_iter(entries.iter())
  names.sort()
  let records : Array[@codec.CaseRecord] = []
  for name in names {
    if name.length() < 5 || name.substring(start=name.length() - 5, end=name.length()) != ".json" {
      continue
    }
    let path = dir + "/" + name
    let j = parse_json_or_die(read_text(path), path)
    match @codec.corpus_from_json(j) {
      Ok(rs) =>
        for r in rs {
          records.push(r)
        }
      Err(msg) => die(path + ": " + msg)
    }
  }
  let rep = @codec.run_bench(records, a.tol, a.clock_tol, a.filter)
  println(render_summary(rep))
  if a.report is Some(path) {
    let text = Json::stringify(@codec.report_to_json(rep), indent=2)
    try @fs.write_string_to_file(path, text + "\n") catch {
      _ => die("cannot write file: " + path)
    }
  }
  let rate = if rep.total == 0 {
    0.0
  } else {
    rep.passed.to_double() / rep.total.to_double()
  }
  if rate >= a.fail_under { @sys.exit(0) } else { @sys.exit(1) }
}