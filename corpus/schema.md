# 答案键语料 Schema（mooncalc-corpus/1，M1 冻结）

`mooncalc-corpus/1` 的 JSON 结构保持不变；多工作表、整列/整行与定义名称、M9 数组/交集批
都是**向后兼容的增量扩展**：新增可选的 spec 第 7 列 `names`、record 字段 `names`、
`anchor`、`array`，grid 键允许 `SHEET!A1` 形态，`expected` 允许 `range` 形态。旧 9 个
`corpus/cases/*.json` 仍由同一生成器产出，字节不变；M9 数组批由 COM 探针生成器单独产出。

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
    },
    {
      "id": "refs-xsheet-0001",
      "formula": "=Data!A1",
      "grid": { "DATA!A1": 7 },
      "expected": { "type": "number", "value": 7 },
      "tags": ["xsheet", "cross-sheet"],
      "source": "excel-desktop",
      "notes": ""
    },
    {
      "id": "refs-names-0001",
      "formula": "=Rate",
      "grid": { "DATA!A1": 0.07 },
      "names": { "RATE": "Data!$A$1" },
      "expected": { "type": "number", "value": 0.07 },
      "tags": ["names", "defined-name"],
      "source": "excel-desktop",
      "notes": ""
    },
    {
      "id": "arrays-intersect-0003",
      "formula": "=A1:B2 B2:C3",
      "grid": { "A1": 1, "B2": 5, "C3": 9 },
      "anchor": "B2",
      "array": { "kind": "dynamic", "anchor": "B2", "rows": 2, "cols": 1 },
      "expected": { "type": "range", "rows": 2, "cols": 1, "values": [
        { "type": "number", "value": 5 },
        { "type": "number", "value": 8 }
      ] },
      "tags": ["probe", "dynamic", "intersection"],
      "source": "excel-desktop",
      "notes": ""
    }
  ]
}
```

### grid 键（多工作表）

- 键形态：`SHEET!A1` 或裸 `A1`。
- 裸地址 = **主临时表**（生成器本次运行创建的 `MC_Temp_hhmmss`）。答案格 `ZZ1` 与时钟
  辅助格 `ZY1` 永远在主临时表，因此被测公式里的裸引用指向主表、引用其他表必须写全名
  （Excel 语义自动如此）。
- 拆分按**最后一个** `!`：`SHEET` 可以含空格，Excel 引号写法 `'My Sheet'!A1` 也接受
  （解引号并把 `''` 还原为 `'`）。地址部分必须是 A1 形（列字母+行号，不含 `$`）。
- **归一化**：主临时表上的格（裸键或显式写主临时表名）一律输出为裸 `A1`；其他表输出为
  `SHEET!A1`，表名按 ASCII-only 大写（不使用区域相关的 `UCase`，非 ASCII 表名原样保留），
  地址部分同样大写。归一化后同一地址重复出现的用例整体 skip。
- 地址上限：**每个表** A1:H20。整列引用限 A:H；整行引用行号 ≥ 2（主表第 1 行有
  `ZZ1`/`ZY1` 辅助格，避免自引用）。

### 单元格编码（grid 的值）

| 形态 | 含义 |
| --- | --- |
| JSON 数字 | 数值单元格 |
| JSON 字符串 | 文本单元格（含文本型数字，如 `"3"`） |
| `true` / `false` | 布尔单元格 |
| `null` | 空白单元格 |
| `{"formula": "=..."}` | 公式单元格 |
| `{"error": "#N/A"}` | 错误值单元格（8 种之一，含 `#SPILL!`） |

### expected 编码

标量：`{"type": "number|text|bool|error|blank", "value": ...}`：
number→JSON 数字；text→字符串；bool→true/false；error→错误名字符串；blank→null。

数组（M9）：`{"type":"range","rows":R,"cols":C,"values":[...]}`，`values` 为行主序
标量对象（同上），长度必须等于 `R*C`；嵌套 range 拒绝。数组记录可带顶层 `anchor`
（普通公式的宿主格）与 `array` 元数据。

### 数组/CSE/动态字段（M9）

| 字段 | 形态 | 含义 |
| --- | --- | --- |
| `anchor` | `"B2"` / `"SHEET!B2"` | 普通公式的宿主格；缺省按 `ZZ1`（旧契约） |
| `array.kind` | `"cse"` / `"dynamic"` | CSE 多格 / 动态数组 |
| `array.anchor` | 地址 | 数组锚点（CSE 左上角；动态公式格） |
| `array.rows` / `array.cols` | 正整数 | CSE 选区；动态结果形状 |
| `setupArrays` | 对象数组（M9.1） | 在求主公式前构造多个数组锚点；每项 `{kind, anchor, formula, rows, cols}`，`kind` 为 `"cse"`（`rows`×`cols` 选区，必须 >0）或 `"dynamic"`（`rows`/`cols` 为 0，形状由求值决定） |

普通网格公式仍用 `formula` + `grid`；`array` 记录由 bench 的 `actual_for_array`
构造 `ArrayLayout` 后调用 `recalc_arrays`，与普通记录走同一套桶规则；带
`setupArrays` 的记录由 `actual_with_setup_arrays` 先构造多锚点布局（setup 写数组
锚点，主公式按 `array` 元数据或普通网格公式插入），再调用 `recalc_arrays`。

### 字段说明

- `now`：可选。注入时钟（Excel 序列日，含小数）。TODAY/NOW 用例必填，
  由生成器在计算后立即捕获当时 `Now` 序列值，tags 含 `clock`。
- `iter`：可选。迭代计算设置 `{"max_iterations":N,"max_change":C}`；缺失 = 迭代关闭
  （Excel 默认）。由 spec 可选第 6 列生成，bench 走 `eval_formula_iterative`。
  无 `iter` 列的用例计算时也会显式关闭迭代（读取答案后还原），保证自引用环用例
  观察到的始终是 Excel 默认行为。
- `names`：可选。仅当 spec 第 7 列声明了定义名称时出现，
  `{"NAME":"Ref",...}`：键为 ASCII-only 大写的名称，值为 spec 中写下的引用文本
  （`Data!$A$1`、`Data!$A$1:$A$2`、另一个名称，或自身/成环）。这些名称在计算前加入
  工作簿、读取答案后删除，用例之间互不影响。
- `tags`：族名 + 边界类别；`clock` 标签的记录允许配置容差（报告披露）。
- `source`：`excel-desktop`（权威）或 `manual`（过渡，非权威）。
  **bench 报告按 source 分栏；manual 通过率不得作为对外指标。**

## 用例规格 TSV（corpus/spec/*.tsv，AI 编写，Excel 填期望值）

制表符分隔 5 列，首行表头 `id	formula	grid	now	tags`；可选第 6 列 `iter`，
可选第 7 列 `names`（无 iter/names 时留空字段占位）：

```
id	formula	grid	now	tags	iter	names
```

- `formula`：含前导 `=`，写入主临时表 `ZZ1`。
- `grid`：单元格以 `|` 分隔，每格 `ADDR=spec`，`ADDR` 见上文 grid 键规则；spec 形态：
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
- `names`（可选第 7 列）：`Name1=Ref1|Name2=Ref2`。计算前以
  `ThisWorkbook.Names.Add` 加入工作簿（同名先删再加，比较不区分大小写），读取答案后
  全部删除；record 追加 `names` 字段。名称规则 `[A-Za-z_][A-Za-z0-9_]*`，且不得是
  单元格引用形（`A1`、`AB12`）或 R/C 引用形（`R1C1`），同名重复（大小写不敏感）也
  拒绝。未限定表名的引用（`$B$1`）绑定主临时表（生成器在加名称前激活主表）。
- 限制：文本值不得含 `|` 或制表符；网格地址见上文上限。

### 用例被跳过（skip）

单条用例不合法时**不中止整批**：该用例不写入 `cases/*.json`，而是在
`cases/<name>.skipped.txt` 记录一行 `id` 或 `id<TAB>原因`。会触发 skip 的情况：

- grid 键无法解析（空表名、地址不是 A1 形、缺 `=`）；
- 归一化后同一地址重复；
- 表名非法（长度不在 1..31、含 `: \ / ? * [ ] !`、含控制字符、首尾单引号）；
- 表名与工作簿中已有工作表冲突（主临时表名视为主表，不算冲突）；
- 定义名称非法 / 名称重复 / 同名已存在于工作簿且无法替换；
- Excel 在写入公式或计算时拒绝该用例（`excel-rejected: 错误号 描述`）。

新建的临时工作表与定义名称在正常、skip、错误三条路径上都会被删除/还原。

### 数组 / SEQUENCE 批（独立生成器）

数组/交集/并集/`@`/CSE/动态 spill/spill 引用记录由 `corpus/probes/arrays.tsv` 与
`corpus/probes/spill_ref.tsv` 驱动，SEQUENCE 记录由 `corpus/probes/sequence.tsv` 驱动，经
`corpus/probes/run_probes.ps1` 在真实桌面 Excel 上逐条写入并读取（`Range.Formula` /
`Formula2` / `FormulaArray`），再由 `corpus/probes/arrays_to_corpus.py` /
`sequence_to_corpus.py` **只读取** `*.results.json` 转成 `mooncalc-corpus/1`（不计算期望值）。
v3 生成器另写 `<OutPath>.meta.json` 版本指纹。来源、版本、SHA-256
与排除项见 `corpus/cases/PROVENANCE.md`。

### 当前缺口（不是书面排除）

R1C1 引用、3D 引用（`Sheet1:Sheet3!A1`）、外部工作簿链接（`[x.xlsx]`）、工作表级
定义名称仍是待补里程碑（ADR 0009），不是“语料不承诺语义”。数组字面量、
交集/并集、`@`、CSE、动态 spill、`SEQUENCE` 已由 M9/M12.1 批覆盖，不再排除；
`FILTER`/`SORT`/`SORTBY`/`UNIQUE`/`RANDARRAY` 仍是公开缺口。

## 比较策略（bench）

- **match**：默认精确相等（数值按 Double 精确比较，文本/布尔/错误按值）。
- **excel-precision**（通过、单列披露）：数值相对差 ≤1e-14。Excel/VBA 只能以 15 位
  有效数字序列化答案，该量级的差异是表征差而非行为差。
- **clock-tolerance**（通过、单列披露）：带 `clock` 标签的用例且数值**绝对差** ≤
  `--clock-tol`（默认 1e-6 天）。`now` 由生成器在同一重算中捕获，派生运算的尾差在容差内。
- **numeric-tolerance**（失败）：相对差介于 1e-14 与 `--tol`（默认 1e-9）之间，单独归因。
- 报告披露各桶计数与逐条失败（expected/actual）。
