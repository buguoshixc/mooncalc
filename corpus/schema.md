# 答案键语料 Schema（mooncalc-corpus/1，M1 冻结）

## JSON 文件格式（corpus/cases/*.json，由真实 Excel 生成）

```json
{
  "schema": "mooncalc-corpus/1",
  "records": [
    {
      "id": "math-round-0007",
      "formula": "=ROUND(A1,2)",
      "grid": {
        "A1": 2.675,
        "B2": "3",
        "C3": { "formula": "=B2*2" },
        "D4": { "error": "#N/A" },
        "E5": null
      },
      "now": 45000.5,
      "expected": { "type": "number", "value": 2.68 },
      "tags": ["math", "round", "boundary.float"],
      "source": "excel-desktop",
      "notes": ""
    }
  ]
}
```

### 单元格编码（grid 的值）

| 形态 | 含义 |
| --- | --- |
| JSON 数字 | 数值单元格 |
| JSON 字符串 | 文本单元格（含文本型数字，如 `"3"`） |
| `true` / `false` | 布尔单元格 |
| `null` | 空白单元格 |
| `{"formula": "=..."}` | 公式单元格 |
| `{"error": "#N/A"}` | 错误值单元格（7 种之一） |

### expected 编码

`{"type": "number|text|bool|error|blank", "value": ...}`：
number→JSON 数字；text→字符串；bool→true/false；error→错误名字符串；blank→null。

### 字段说明

- `now`：可选。注入时钟（Excel 序列日，含小数）。TODAY/NOW 用例必填，
  由生成器在计算后立即捕获当时 `Now` 序列值，tags 含 `clock`。
- `iter`：可选。迭代计算设置 `{"max_iterations":N,"max_change":C}`；缺失 = 迭代关闭
  （Excel 默认）。由 spec 可选第 6 列生成，bench 走 `eval_formula_iterative`。
- `tags`：族名 + 边界类别；`clock` 标签的记录允许配置容差（报告披露）。
- `source`：`excel-desktop`（权威）或 `manual`（过渡，非权威）。
  **bench 报告按 source 分栏；manual 通过率不得作为对外指标。**

## 用例规格 TSV（corpus/spec/*.tsv，AI 编写，Excel 填期望值）

制表符分隔 5 列（可选第 6 列 `iter`），首行表头 `id	formula	grid	now	tags`：

- `formula`：含前导 `=`。
- `grid`：单元格以 `|` 分隔，每格 `ADDR=spec`；spec 形态：
  - 裸数字（不变式小数点），如 `2.675`
  - `t:文本`（文本型数字写 `t:3`）
  - `b:1` / `b:0`（布尔）
  - `e:#N/A`（错误值）
  - `f:=公式`（公式单元格）
  - `blank`（空白）
- `now`：空（不注入）或 `capture`（生成器在同一重算中经 `=NOW()` 辅助格捕获序列值；恢复时转为 15 位十进制写入 `now`）。
- `tags`：逗号分隔。
- `iter`（可选第 6 列）：`最大次数:最大变化`（如 `100:0.001`），空 = 迭代关闭。
  生成器对该用例临时启用 `Application.Iteration/MaxIterations/MaxChange`
  （并抑制循环引用弹窗），读取答案后立即还原；record 追加 `iter` 字段。
- 限制：文本值不得含 `|` 或制表符；网格地址限 A1:H20（结果写 ZZ1，避免冲突）。

## 比较策略（bench）

- **match**：默认精确相等（数值按 Double 精确比较，文本/布尔/错误按值）。
- **excel-precision**（通过、单列披露）：数值相对差 ≤1e-14。Excel/VBA 只能以 15 位
  有效数字序列化答案，该量级的差异是表征差而非行为差。
- **clock-tolerance**（通过、单列披露）：带 `clock` 标签的用例且数值**绝对差** ≤
  `--clock-tol`（默认 1e-6 天）。`now` 由生成器在同一重算中捕获，派生运算的尾差在容差内。
- **numeric-tolerance**（失败）：相对差介于 1e-14 与 `--tol`（默认 1e-9）之间，单独归因。
- 报告披露各桶计数与逐条失败（expected/actual）。