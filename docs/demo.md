# 端到端演示脚本

四层验证 + 四步演示，全程离线。所有命令在仓库根目录执行；`moon` 需 `export PATH="$HOME/.moon/bin:$PATH"`。

## 0. 一键全量验证

```bash
bash scripts/check.sh        # wasm-gc check/build + native build + moon test + 零 IO 守卫
bash scripts/run-bench.sh    # 过渡语料跑分（真实语料到达后改为 corpus/cases）
node scripts/smoke.mjs       # headless Chromium 冒烟（12 断言）
```

预期：`ALL CHECKS PASS`；`34/34 passed (100%)`（manual，非权威）；`SMOKE PASS`。

## 1. CLI：互引 + 错误 + 循环的网格

```bash
moon build --target native
_build/native/debug/build/cmd/main/main.exe eval --grid tests/fixtures/grid.json
```

fixture 看点（对应输出）：
- B1=`=A1*A2` → 6，B2=`=B1+1` → 7（引用链）
- C1=`=1/0` → `#DIV/0!`，C2=`=C1+1` → `#DIV/0!`（错误传播）
- D1=`=D1+1` → 0 且 `circular:true`；D2=`=D1+5` → 5 且 `circular:false`（Excel 默认循环语义）
- E1 是文本 `"3"`，E2=`=SUM(E1,4)` → 7（直接参数强制转换）

单公式与单格、时钟注入：

```bash
... eval --grid tests/fixtures/grid.json --formula '=ROUND(2.675,2)'   # 2.68（十进制修正）
... eval --grid tests/fixtures/grid.json --addr B2                     # 7
... eval --grid tests/fixtures/empty.json --formula '=TODAY()' --now 2026-11-14   # 注入时钟
... eval --grid tests/fixtures/empty.json --formula '=TODAY()'                    # #NUM!（未注入契约）
```

## 2. bench：N/X% 与逐条归因

```bash
... bench --corpus corpus/provisional --report /tmp/report.json
... bench --corpus tests/fixtures/badcorpus --fail-under 0.95; echo "exit=$?"   # 1（有差异）
```

看点：按 source 分栏（manual 非权威）、buckets（match / numeric-tolerance / value-mismatch / …）、逐条 FAIL 的 expected/actual。真实语料接入后此处展示权威 N/X%。

## 3. playground：现场改格

```bash
bash scripts/build-playground.sh
(cd playground && python3 -m http.server 8080)   # 或任意静态服务器
# 浏览器打开 http://localhost:8080/
```

现场动作：
1. 预设「circular reference → 0」：A1 显示 0 + 黄色警示，B1 显示 5。
2. 预设「error propagation」：B1/B2/C1 全红 `#DIV/0!`；把 A2 改成 5 → B1 变 0.2。
3. 预设「text-typed numbers」：B1=`SUM(A1,A2)`=7 vs B2=`SUM(A1:A2)`=4（双通道）。
4. 任意格输入 `=VLOOKUP(...)`、`=TEXT(1234.5,"#,##0.00")` 即时求值。

## 4. 矩阵与署名偏差

打开 [support-matrix.md](support-matrix.md) 与 [semantics.md](semantics.md)：45 函数状态、语料裁定项、显式契约（未注入时钟→#NUM!、子集外 TEXT→#VALUE!、非 ASCII 大小写偏差候选）。

## 退出码约定（评审可脚本化）

| 码 | 含义 |
|---|---|
| 0 | 达标 / 成功 |
| 1 | bench 有差异（低于 --fail-under） |
| 2 | 用法 / IO / 解析错误 |