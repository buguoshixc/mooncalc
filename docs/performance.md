# 重算性能基准

`mooncalc perf` 在进程内生成大网格并测量 `recalc` 耗时（纯计算，不含 JSON 编解码与文件 IO）。
网格构造不计入计时；每个场景重复 `--repeat` 次取最优；结果逐场景校验一个代表格，校验失败即退出码 2。

## 复现

```bash
export PATH="$HOME/.moon/bin:$PATH"
moon build --target native --release
_build/native/release/build/cmd/main/main.exe perf                 # 默认 10000 格 × 3 次
_build/native/release/build/cmd/main/main.exe perf --cells 100000 --repeat 5
```

## 场景

| 场景 | 构造 | 考察点 |
|---|---|---|
| chain | `A1=1`，`Ai==A(i-1)+1` | 依赖链 DFS + 记忆化（深度 = 格数） |
| wide | N-1 个字面值 + 1 个 `SUM(A1:A{N-1})` | 大区域物化与聚合 |
| mixed | N/4 行 × 4 列：字面值、`*2`、加法、行内 `SUM` | 大量小公式 + 解析开销 |
| shared | 100 个字面值 + N-100 个 `SUM($A$1:$A$100)+i` | 共享区域重复引用（区域缓存命中） |

## 基线（2026-11-15）

环境：Intel Core Ultra 5 225H · WSL2（6.6.87.2-microsoft-standard-WSL2）· native release · best of 3。

| 场景 | 10k 格 | 50k 格 | 100k 格 | 吞吐（100k） |
|---|---|---|---|---|
| chain | 18.9 ms | 104 ms | 229 ms | ~437k 格/秒 |
| wide | 1.6 ms | 9.9 ms | 26.9 ms | ~3.7M 格/秒 |
| mixed | 27.5 ms | 155 ms | 328 ms | ~305k 格/秒 |
| shared | 59.2 ms | 307 ms | 601 ms | ~166k 格/秒 |

各场景随格数近似线性扩展。10 万格依赖链（DFS 深度 10 万）在 native 上安全；
wasm-gc 侧已验证 10 万格链与 8192 字符内最长二元链（约 4000 项）不爆栈
（见 docs/semantics.md「公式限制」）。

## 已做优化

- **二元链迭代求值**（`eval_binary` 左脊折叠）：左结合长链不再随项数递归，
  既是 wasm-gc 的不崩溃保证，也消除了深链的栈帧开销。
- **区域缓存**（`Ctx.range_cache`）：同一求值上下文内，同一区域只物化一次。
  单元格值在上下文内不可变，故缓存安全。shared 场景 10k 格从 130 ms 降至 59 ms（2.2×）；
  这是真实表格最常见的模式（多行公式引用同一汇总区域）。

## 口径说明

- 计时含公式解析（`recalc` 的真实成本）；重复测量复用同一网格，但每次重算都重新解析。
- 数字是单机参考值，不是跨机器承诺；CI 不以性能为门禁（避免环境抖动导致误报）。