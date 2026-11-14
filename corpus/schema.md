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
- `tags`：族名 + 边界类别；`clock` 标签的记录允许配置容差（报告披露）。
- `source`：`excel-desktop`（权威）或 `manual`（过渡，非权威）。
  **bench 报告按 source 分栏；manual 通过率不得作为对外指标。**

## 用例规格 TSV（corpus/spec/*.tsv，AI 编写，Excel 填期望值）

制表符分隔 5 列，首行表头 `id	formula	grid	now	tags`：

- `formula`：含前导 `=`。
- `grid`：单元格以 `|` 分隔，每格 `ADDR=spec`；spec 形态：
  - 裸数字（不变式小数点），如 `2.675`
  - `t:文本`（文本型数字写 `t:3`）
  - `b:1` / `b:0`（布尔）
  - `e:#N/A`（错误值）
  - `f:=公式`（公式单元格）
  - `blank`（空白）
- `now`：空（不注入）或 `capture`（生成器捕获当时 Now）。
- `tags`：逗号分隔。
- 限制：文本值不得含 `|` 或制表符；网格地址限 A1:H20（结果写 ZZ1，避免冲突）。

## 比较策略（bench）

- 默认精确相等（数值按 Double 精确比较，文本/布尔/错误按值）。
- 相对差 < `--tol`（默认 1e-9）的数值差异单列 `numeric-tolerance` 桶：
  计为失败但单独归因展示。
- `clock` 标签记录用可配置容差并在报告披露。