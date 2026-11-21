// 动态数组函数。SEQUENCE 的语义由 2026-11-21 真实 Excel
// (16.0.20527, zh-CN) 的 corpus/probes/sequence.tsv 75 条探针裁定。

/// 单次 SEQUENCE 的单元格资源护栏（生成 cells 前检查）。Excel 对同尺寸
/// 只受可用内存限制，探针未覆盖超大数组；这是引擎容量护栏，不是 Excel 语义。
let sequence_max_cells : Int = 16777216

/// 读取第 i 个数值实参：缺省或省略实参（Lit(Blank)）取 default。
/// 空白单元格引用是 Range(Blank)，不在此走默认，而按 to_number → 0 处理。
fn sequence_number_arg(
  vals : Array[Value],
  i : Int,
  default : Double,
) -> Result[Double, XlError] {
  if i >= vals.length() {
    return Ok(default)
  }
  match vals[i] {
    Blank => Ok(default)
    v => to_number(scalarize(v))
  }
}

/// rows/columns 维度转换：负值（含 -0.5）→ #VALUE!；非负截断；0 → #CALC!。
/// `limit` 为 0 表示不按该维度设上限（columns 不受 16384 预检）。
fn sequence_dim(
  vals : Array[Value],
  i : Int,
  default : Double,
  limit : Int,
) -> Result[Int, XlError] {
  let d = match sequence_number_arg(vals, i, default) {
    Ok(x) => x
    Err(e) => return Err(e)
  }
  if !d.is_finite() {
    return Err(XlError::Num)
  }
  if d < 0.0 {
    return Err(XlError::Value)
  }
  let n = d.trunc()
  if n == 0.0 {
    return Err(XlError::Calc)
  }
  if limit > 0 && n > limit.to_double() {
    return Err(XlError::Value)
  }
  if n > sequence_max_cells.to_double() {
    return Err(XlError::Value)
  }
  Ok(n.to_int())
}

/// `SEQUENCE(rows, [columns], [start], [step])`
///
/// 结果按行主序填充：`start + (r * columns + c) * step`。
/// normal 模式由 scalar_output_at 取左上角（不 spill）；dynamic 模式由
/// recalc_arrays 登记 spill 区域并检查 #SPILL!。columns 可超过网格宽
/// 16384（=SUM(SEQUENCE(1,16385)) = 134242305），只有动态锚点放不下时
/// 才由 recalc_arrays 报 #SPILL!。
fn fn_sequence(_ctx : Ctx, args : Array[Thunk]) -> Value {
  let vals = eager(args)
  let rows = match sequence_dim(vals, 0, 1.0, @value.max_row) {
    Ok(n) => n
    Err(e) => return Value::Err(e)
  }
  let cols = match sequence_dim(vals, 1, 1.0, 0) {
    Ok(n) => n
    Err(e) => return Value::Err(e)
  }
  if rows > sequence_max_cells / cols {
    return Value::Err(XlError::Value)
  }
  let start = match sequence_number_arg(vals, 2, 1.0) {
    Ok(x) => x
    Err(e) => return Value::Err(e)
  }
  let step = match sequence_number_arg(vals, 3, 1.0) {
    Ok(x) => x
    Err(e) => return Value::Err(e)
  }
  if !start.is_finite() || !step.is_finite() {
    return Value::Err(XlError::Num)
  }
  let cells : Array[Value] = []
  for r in 0..<rows {
    for c in 0..<cols {
      let v = start + (r * cols + c).to_double() * step
      if !v.is_finite() {
        return Value::Err(XlError::Num)
      }
      cells.push(Value::Num(v))
    }
  }
  Value::Range(RangeValue::array(rows, cols, cells))
}
