# 端到端演示脚本

四层验证 + 六个演示，全程离线。所有命令在仓库根目录执行；`moon` 需 `export PATH="$HOME/.moon/bin:$PATH"`。

## 0. 一键全量验证

```bash
bash scripts/check.sh        # wasm-gc check/build + native build + moon test + 零 IO 守卫
bash scripts/run-bench.sh    # 权威语料跑分（默认 corpus/cases）
node scripts/smoke.mjs       # headless Chromium 冒烟（39 断言）
```

预期：`ALL CHECKS PASS`（182 项单测，native + wasm-gc）；`1603/1603 passed (100%)`（真实 Excel 语料：旧批 1,267 + M9 数组批 238 + spill 引用批 23 + SEQUENCE 批 75）；`SMOKE PASS`。

## 1. CLI：互引 + 错误 + 循环的网格

```bash
moon build --target native
_build/native/debug/build/buguoshixc/mooncalc/cmd/main/main.exe eval --grid tests/fixtures/grid.json
```

fixture 看点（对应输出）：
- B1=`=A1*A2` → 6，B2=`=B1+1` → 7（引用链）
- C1=`=1/0` → `#DIV/0!`，C2=`=C1+1` → `#DIV/0!`（错误传播）
- D1=`=D1+1` → 0 且 `circular:true`；D2=`=D1+5` → 5 且 `circular:false`（Excel 默认循环语义）
- E1 是文本 `"3"`，E2=`=SUM(E1,4)` → 4（引用通道忽略文本）vs E3=`=SUM("3",4)` → 7（字面量强制转换）

单公式与单格、时钟注入：

```bash
... eval --grid tests/fixtures/grid.json --formula '=ROUND(2.675,2)'   # 2.68（十进制修正）
... eval --grid tests/fixtures/grid.json --addr B2                     # 7
... eval --grid tests/fixtures/empty.json --formula '=TODAY()' --now 2026-11-14   # 注入时钟
... eval --grid tests/fixtures/empty.json --formula '=TODAY()'                    # #NUM!（未注入契约）
```

## 2. bench：N/X% 与逐条归因

```bash
... bench --corpus corpus/cases --report corpus/reports/real.json          # 1603/1603（100%）
... bench --corpus corpus/provisional                                    # 过渡语料，34/34
... bench --corpus tests/fixtures/badcorpus --fail-under 0.95; echo "exit=$?"   # 1（有差异）
```

看点：按 source 分栏、buckets（match / excel-precision / clock-tolerance / numeric-tolerance / value-mismatch / …）、逐条 FAIL 的 expected/actual。权威语料为桌面 Excel 2024/2610 导出的 **1,603 条**（旧 1,267：1,169 旧语料 + 98 条 M8 refs 批；M9 数组批 238 条 + spill 引用批 23 条 + SEQUENCE 批 75 条），当前 100% 通过（1,583 match + 3 clock-tolerance + 16 excel-precision + 1 surrogate-representation，后三个桶为可披露的表征/时钟容差；2 条奇数参数 IFS 与 3 条非法/重复定义名称被 Excel 拒绝录入，按非法输入处理；5 条非稳态旧探针另存 `corpus/excluded/`，不计入分母；数组批 p014/p015/p126 排除理由见 PROVENANCE）。

M8 引用语义的差分探针（12 条，含定义名称、跨表环、200 格链）：

```bash
... bench --corpus corpus/probes
```

MoonCalc 通过 10/12：未过的 `SUMSQ`/`COUNTBLANK` 尚未实现（返回 `#NAME?`，M10 缺口），语义探针 10/10。

## 3. playground：现场改格

```bash
bash scripts/build-playground.sh
(cd playground && python3 -m http.server 8080)   # 或任意静态服务器
# 浏览器打开 http://localhost:8080/
```

现场动作：
1. 预设「circular reference → 0」：A1 显示 0 + 黄色警示，B1 显示 5。
2. 预设「error propagation」：B1/B2/C1 全红 `#DIV/0!`；把 A2 改成 5 → B1 变 0.2。选中 C1（错误格）时，依赖图沿引用上溯到错误源 B1，详情面板给出传播链与源公式。
3. 预设「text-typed numbers」：B1=`SUM(A1,4)`=4（引用通道忽略文本）vs B2=`SUM("3",4)`=7（字面量转换）。
4. 依赖图：选中任意格，蓝色底纹=precedents（它引用的格，传递闭包），绿色底纹=dependents（引用它的格）；详情面板列出直接前驱/后继。
5. 新函数预设：XLOOKUP（精确/通配符/未命中回退）、IFS（惰性条件）、SWITCH（值匹配）、TEXTJOIN（跳空拼接）、EOMONTH（月末/闰年/负月）。
6. 新 TEXT 预设：科学计数 `0.00E+00`、累计时长 `[h]:mm`、条件分段 `[>100]"big";"small"`。
7. 任意格输入 `=VLOOKUP(...)`、`=TEXT(1234.5,"#,##0.00")` 即时求值。
8. 迭代计算：预设「circular → converge (iterative)」+ 勾选「Iterative calculation」→ A1/B1 从 0 收敛到 ≈20/≈10（Excel 默认 ≤100 次、最大变化 0.001），计数器显示 `3/3 · iterative`；取消勾选回到环上 = 0。
9. 增量重算：预设「error propagation」后在 E1 加 `=7*7`，再改 A1 → 计数器 `3/4 · incremental`（只重算 B1/B2/C1，E1 不重算）；引入环或解析错误时自动回退 `full rebuild`，计数器如实报告。

## 4. XLSX 读→算→写（mbtexcel 组合示例，M8 多表版）

```bash
moon run examples/xlsx-demo --target native -- gen   # 用 mbtexcel 生成 3 表 fixture（不提交二进制）
moon run examples/xlsx-demo --target native -- run   # 读→算→写并读回断言
```

看点（L3 验收：多表工作簿读→算→写逐格对照）：

- **3 个表**：`Input`（字面量/查找表/错误值）、`Calc`（跨表公式）、`My Sheet`（带空格表名，引用写作 `'My Sheet'!A1`）。
- **遍历全部 sheet**：单元格键按 M8 契约归一为 `SHEET!A1`（ASCII 大写表名，与 CLI/playground 同一契约）；公式格（xlsx 中不带 `=`）补前导 `=` 进网格；字面量按 number/bool/string 映射；空白跳过；错误值格按 `{"error": ...}` 映射。
- **定义名称从工作簿读出**：`wb.defined_names()` → `grid.names`（`Rate→Input!$B$1`、`Tax→Input!$B$2`、`Qty→Input!$A$2:$A$4`），与 CLI `--names` 走同一字段。
- **公式覆盖**：跨表引用 `Input!A2:A4`、整列 `Input!A:A`、整行 `Input!2:2`、带引号跨表区域 `'My Sheet'!A1:A2`、名称 `A1*Rate` / `SUM(Qty)`、跨表查找表 `VLOOKUP(...,Input!E1:F3,...)`、跨表错误传播 `Input!H1+1 → #N/A`。
- **回写**：16 个公式格用 `set_cell_formula`（公式无 `=`、缓存值传引擎结果文本）按宿主表写回，17 个字面量不动；读回输出文件断言 65 项（公式 + 缓存值 + 字面量未改动 + 16 个关键格的已知结果）。
- 预期输出：`xlsx-demo verification PASS: 65/65`，前缀 `xlsx-demo: sheets=3 formulas=16 literals=17 names=3`。
- 引擎核心零改动：IO 全部在 `examples/` 壳层，`scripts/check.sh` 的零 IO 守卫不受影响。

### 4.1 数组版：交集 / 隐式交集 / CSE / 动态 spill / SEQUENCE（M9 + M12.1）

```bash
moon run examples/array-demo --target native -- gen
moon run examples/array-demo --target native -- run
```

看点（45 项逐格断言）：

- `Data` 表 A1:C3 = 1..9；`Report` 表 13 个公式：
  - `A1 =SUM(Data!A1:B2 Data!B2:C3)` → 5（交集 B2）；
  - `A2 =Data!A1:A3` → 4、`C3 =Data!A1:C1` → 3（普通公式的隐式交集，宿主行/列）；
  - `A3 =@Data!A1:C1` → 1（显式 `@`）；
  - `A4 =SUM((Data!A1:A2,Data!B1:B2))` → 12（并集聚合）；
  - `A5 ={1,2;3,4}` → 1，`B1 =SUM({1,2}+{10;20})` → 66（数组字面量/广播）；
  - `A7 =Data!A1:C3` → `#VALUE!`（2D 宿主不在区域内）；
  - CSE `D4:E5 =Data!A1:B2*2` → `[[2,4],[8,10]]`，回写 `t="array" ref="D4:E5"`，followers 按数值/布尔/文本类型回写（数值格不再写成共享字符串）；
  - 动态 `G4 =Data!A1:B2+10` → spill `G4:H5 = [[11,12],[14,15]]`，followers 同样按值类型回写；
  - 普通公式 `E1 =SUM(G4#)` → 52，把 spill 引用通道纳入读→算→写链路；
  - SEQUENCE 动态锚点 `J4 =SEQUENCE(3)` → spill `J4:J6 = [1;2;3]`；普通公式 `E2 =SUM(J4#)` → 6，第二个锚点同样走读→算→写。
- 读回断言：公式、缓存值、followers、CSE `formula_type=Array`/`range_ref`、Data 字面量未改动；followers 与 `E1`/`E2` 按 `Value`相等性比对（数值即数值）；共 45 项。
- **诚实限制**：mbtexcel 0.3.2 可写 CSE 的 `t="array"`/`ref`，但没有动态 spill 元数据；动态数组只写单元格值，不能声称写了 Excel 的动态数组元数据。mbtexcel 对公式格仍只支持文本缓存值（本题 `D4`/`G4`/`J4`/`E1`/`E2` 读回是共享字符串），followers 已是真正的数值/布尔/文本格。
- 预期输出：`array-demo: formulas=13 checks=45 failures=0`。

## 5. 矩阵与署名偏差

打开 [support-matrix.md](support-matrix.md) 与 [semantics.md](semantics.md)：62 函数状态、M9 数组/交集语义、M12.1 SEQUENCE 契约、Excel 2024 语料裁定项（TEXT 条件分段/累计时长、EOMONTH 边界、criteria 空/错误条件、XLOOKUP 二分、TEXTJOIN `#CALC!`）、公开契约（未注入时钟→#NUM!、当前未覆盖的 TEXT 格式→#VALUE!、IFS 奇数参数属 Excel 拒录的非法输入）。

## 退出码约定（评审可脚本化）

| 码 | 含义 |
|---|---|
| 0 | 达标 / 成功 |
| 1 | bench 有差异（低于 --fail-under） |
| 2 | 用法 / IO / 解析错误 |