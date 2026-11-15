struct Args {
  cmd : String
  mut grid : String?
  mut formula : String?
  mut addr : String?
  mut now : String?
  mut iter : String?
  mut out : String?
  mut corpus : String?
  mut report : String?
  mut tol : Double
  mut clock_tol : Double
  mut filter : String?
  mut fail_under : Double
  mut cells : Int
  mut repeat : Int
}

fn usage() -> String {
  "usage:\n" +
  "  mooncalc eval --grid <grid.json> [--formula \"=...\" | --addr B1] [--now <serial|ISO>] [--iter N:C] [--out result.json]\n" +
  "  mooncalc bench --corpus <dir> [--report report.json] [--tol 1e-9] [--clock-tol 1e-6] [--filter <tag>] [--fail-under 1.0]\n" +
  "  mooncalc perf [--cells 10000] [--repeat 3]\n" +
  "  mooncalc explain --grid <grid.json> --addr B1 [--now <serial|ISO>] [--out result.json]\n" +
  "exit codes: 0 = gate met, 1 = diffs below gate, 2 = usage/IO/parse error"
}

fn parse_double_arg(s : String) -> Result[Double, String] {
  try Ok(@string.parse_double(s)) catch { _ => Err("not a number: " + s) }
}

fn parse_args(argv : Array[String]) -> Result[Args, String] {
  if argv.length() < 2 {
    return Err(usage())
  }
  let cmd = argv[1]
  if cmd != "eval" && cmd != "bench" && cmd != "perf" && cmd != "explain" {
    return Err("unknown command: " + cmd + "\n" + usage())
  }
  let a : Args = {
    cmd,
    grid: None,
    formula: None,
    addr: None,
    now: None,
    iter: None,
    out: None,
    corpus: None,
    report: None,
    tol: 1.0e-9,
    clock_tol: 1.0e-6,
    filter: None,
    fail_under: 1.0,
    cells: 10000,
    repeat: 3,
  }
  let mut i = 2
  while i < argv.length() {
    let flag = argv[i]
    if i + 1 >= argv.length() {
      return Err("missing value for " + flag)
    }
    let val = argv[i + 1]
    match flag {
      "--grid" => a.grid = Some(val)
      "--formula" => a.formula = Some(val)
      "--addr" => a.addr = Some(val)
      "--now" => a.now = Some(val)
      "--iter" => a.iter = Some(val)
      "--out" => a.out = Some(val)
      "--corpus" => a.corpus = Some(val)
      "--report" => a.report = Some(val)
      "--filter" => a.filter = Some(val)
      "--tol" =>
        match parse_double_arg(val) {
          Ok(d) => a.tol = d
          Err(m) => return Err(m)
        }
      "--clock-tol" =>
        match parse_double_arg(val) {
          Ok(d) => a.clock_tol = d
          Err(m) => return Err(m)
        }
      "--fail-under" =>
        match parse_double_arg(val) {
          Ok(d) => a.fail_under = d
          Err(m) => return Err(m)
        }
      "--cells" =>
        match parse_int_arg(val) {
          Some(v) => a.cells = v
          None => return Err("not a positive integer: " + val)
        }
      "--repeat" =>
        match parse_int_arg(val) {
          Some(v) => a.repeat = v
          None => return Err("not a positive integer: " + val)
        }
      _ => return Err("unknown flag: " + flag + "\n" + usage())
    }
    i += 2
  }
  Ok(a)
}