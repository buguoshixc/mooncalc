# 端到端演示脚本

四层验证 + 五个演示，全程离线。所有命令在仓库根目录执行；`moon` 需 `export PATH="$HOME/.moon/bin:$PATH"`。

## 0. 一键全量验证

```bash
bash scripts/check.sh        # wasm-gc check/build + native build + moon test + 零 IO 守卫
bash scripts/run-bench.sh    # 权威语料跑分（默认 corpus/cases）
node scripts/smoke.mjs       # headless Chromium 冒烟（39 断言）
```

预期：`ALL CHECKS PASS`；`1169/1169 passed (100%)`（真实 Excel 语料）；`SMOKE PASS`。

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
... bench --corpus corpus/cases --report corpus/reports/real.json          # 1169/1169（100%）
... bench --corpus corpus/provisional                                    # 过渡语料，34/34
... bench --corpus tests/fixtures/badcorpus --fail-under 0.95; echo "exit=$?"   # 1（有差异）
```

看点：按 source 分栏、buckets（match / excel-precision / clock-tolerance / numeric-tolerance / value-mismatch / …）、逐条 FAIL 的 expected/actual。权威语料为 Excel 2024 导出的 1,169 条，当前 100% 通过（1,149 match + 3 clock-tolerance + 16 excel-precision + 1 surrogate-representation，后三个桶为可披露的表征/时钟容差；2 条奇数参数 IFS 被 Excel 拒绝录入，显式标为子集外）。

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

## 4. XLSX 读→算→写（mbtexcel 组合示例）

```bash
moon run examples/xlsx-demo --target native -- gen   # 用 mbtexcel 生成 fixture（不提交二进制）
moon run examples/xlsx-demo --target native -- run   # 读→算→写并读回断言
```

看点：
- 首个 sheet 遍历：公式格（xlsx 中不带 `=`）补前导 `=` 进网格；字面量按 number/bool/string 映射；空白跳过；错误值格按 `{"error": ...}` 映射。
- 求值走 `@codec.evaluate_json`，与 CLI/playground 完全同一份网格 JSON 契约（进程内直调，不走子进程）。
- 回写：14 个公式格用 `set_cell_formula`（公式无 `=`、缓存值传引擎结果文本）写回，11 个字面量不动；最后读回输出文件断言 39 项（公式 + 缓存值 + 字面量未改动）。
- 预期输出：`xlsx-demo verification PASS: 39/39`。
- 引擎核心零改动：IO 全部在 `examples/` 壳层，`scripts/check.sh` 的零 IO 守卫不受影响。

## 5. 矩阵与署名偏差

打开 [support-matrix.md](support-matrix.md) 与 [semantics.md](semantics.md)：60 函数状态、Excel 2024 语料裁定项（TEXT 条件分段/累计时长、EOMONTH 边界、criteria 空/错误条件、XLOOKUP 二分、TEXTJOIN `#CALC!`）、显式契约（未注入时钟→#NUM!、子集外 TEXT→#VALUE!、IFS 奇数参数被 Excel 拒录）。

## 退出码约定（评审可脚本化）

| 码 | 含义 |
|---|---|
| 0 | 达标 / 成功 |
| 1 | bench 有差异（低于 --fail-under） |
| 2 | 用法 / IO / 解析错误 |