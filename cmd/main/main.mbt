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

fn run_eval(a : Args) -> Unit {
  let grid_path = match a.grid {
    Some(p) => p
    None => die("eval requires --grid\n" + usage())
  }
  let grid_json = parse_json_or_die(read_text(grid_path), grid_path)
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