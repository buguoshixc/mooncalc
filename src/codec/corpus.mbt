// Corpus record decoding (mooncalc-corpus/1).

/// 语料用例（mooncalc-corpus/1 schema，见 corpus/schema.md）。
pub(all) struct CaseRecord {
  /// 用例唯一标识（如 `math-round-0001`）。
  id : String
  /// 被求值的公式。
  formula : String
  /// 输入单元格网格。
  grid : Grid
  /// 注入时钟（Excel 序列日）；`clock` 标签用例由生成器经 `=NOW()` 辅助格捕获。
  now : Double?
  /// 权威期望值（真实 Excel 计算结果）。
  expected : Value
  /// 分类标签（族、边界、clock 等）。
  tags : Array[String]
  /// 来源（`excel-2024` 权威 / `manual` 过渡）。
  source : String
  /// 裁定备注（可空）。
  notes : String
  /// 迭代计算设置（spec 可选第 6 列 `iter`）；`None` = 迭代关闭（Excel 默认）。
  iter : @facade.IterOptions?
} derive(Show, Debug)

fn decode_record(j : Json) -> CaseRecord raise CodecError {
  let id = jstr(jfield(j, "id"))
  let formula = jstr(jfield(j, "formula"))
  let grid = decode_grid(jfield(j, "grid"))
  let now = match j.value("now") {
    Some(nj) => Some(jnum(nj))
    None => None
  }
  let expected = decode_value(jfield(j, "expected"))
  let tags : Array[String] = match j.value("tags") {
    Some(tj) =>
      match tj.as_array() {
        Some(arr) => {
          let out : Array[String] = []
          for t in arr {
            out.push(jstr(t))
          }
          out
        }
        None => raise CodecError("tags must be an array")
      }
    None => []
  }
  let source = jstr(jfield(j, "source"))
  let notes = match j.value("notes") {
    Some(nj) => jstr(nj)
    None => ""
  }
  let iter = match j.value("iter") {
    Some(ij) => {
      let mi = match ij.value("max_iterations") {
        Some(nj) => jnum(nj).to_int()
        None => raise CodecError("iter.max_iterations required")
      }
      let mc = match ij.value("max_change") {
        Some(nj) => jnum(nj)
        None => raise CodecError("iter.max_change required")
      }
      let opts : @facade.IterOptions = { max_iterations: mi, max_change: mc }
      Some(opts)
    }
    None => None
  }
  { id, formula, grid, now, expected, tags, source, notes, iter }
}

/// JSON → 单条语料用例；字段缺失/类型不符返回 `Err(消息)`。
pub fn record_from_json(j : Json) -> Result[CaseRecord, String] {
  try Ok(decode_record(j)) catch {
    CodecError(m) => Err(m)
  }
}

fn decode_corpus(j : Json) -> Array[CaseRecord] raise CodecError {
  let schema = jstr(jfield(j, "schema"))
  if schema != "mooncalc-corpus/1" {
    raise CodecError("unsupported corpus schema: " + schema)
  }
  let arr = match jfield(j, "records").as_array() {
    Some(a) => a
    None => raise CodecError("records must be an array")
  }
  let out : Array[CaseRecord] = []
  for r in arr {
    out.push(decode_record(r))
  }
  out
}

/// JSON → 语料文件（校验 `schema == "mooncalc-corpus/1"`，逐条解码 `records`）。
pub fn corpus_from_json(j : Json) -> Result[Array[CaseRecord], String] {
  try Ok(decode_corpus(j)) catch {
    CodecError(m) => Err(m)
  }
}