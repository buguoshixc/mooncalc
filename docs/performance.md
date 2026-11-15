# 重算性能基准

`mooncalc perf` 在进程内生成大网格并测量 `recalc` 耗时（纯计算，不含 JSON 编解码与文件 IO）。
网格构造不计入计时；每个场景重复 `--repeat` 次取最优；结果逐场景校验一个代表格，校验失败即退出码 2。

## 复现

```bash
export PATH="$HOME/.moon/bin:$PATH"
moon build --target native --release
_build/native/release/build/buguoshixc/mooncalc/cmd/main/main.exe perf                 # 默认 10000 格 × 3 次
_build/native/release/build/buguoshixc/mooncalc/cmd/main/main.exe perf --cells 100000 --repeat 5
```

## 场景

| 场景 | 构造 | 考察点 |
|---|---|---|
| chain | `A1=1`，`Ai==A(i-1)+1` | 依赖链 DFS + 记忆化（深度 = 格数） |
| wide | N-1 个字面值 + 1 个 `SUM(A1:A{N-1})` | 大区域物化与聚合 |
| mixed | N/4 行 × 4 列：字面值、`*2`、加法、行内 `SUM` | 大量小公式 + 解析开销 |
| shared | 100 个字面值 + N-100 个 `SUM($A$1:$A$100)+i` | 共享区域重复引用（区域缓存命中） |
| dup | 100 个字面值 + N-100 个公式仅 (N-100)/100 种文本、每种重复 100 次，走 `recalc_cached`（每次重算新建缓存） | 单次重算内同文本公式 AST 去重 |
| repeat | mixed 布局构建一次，`--repeat` 次重算共享同一 `ParseCache`（热态） | 跨重算 AST 缓存（交互式编辑场景） |
| edit | mixed 布局 `recalc_init` 后改中部一个字面值格，`recalc_update` 只重算下游闭包 | 增量重算（典型交互：改一格） |
| edit-chain | chain 布局改 A1（全链脏，最坏情形） | 增量重算最坏情形 ≈ 全量（AST 缓存免重解析） |

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

### AST 缓存后复测（2026-11-15，best of 5）

| 场景 | 100k 格 | 吞吐 | 说明 |
|---|---|---|---|
| chain | 196.7 ms | ~508k 格/秒 | 原路径，无缓存开销 |
| wide | 20.7 ms | ~4.8M 格/秒 | 原路径 |
| mixed | 288.9 ms | ~346k 格/秒 | 原路径（冷态基线） |
| shared | 567.7 ms | ~176k 格/秒 | 原路径 |
| dup | 88.0 ms | ~1.14M 格/秒 | 同文本去重：shared 布局 6.5× |
| repeat | 109.1 ms | ~916k 格/秒 | 跨重算热态：mixed 冷态 2.65× |
| edit | 54.7 ms | — | 改一格只重算 3 格下游：mixed 全量 5.2× |
| edit-chain | 145.8 ms | — | 全链脏最坏情形，仍快于 chain 全量（免重解析） |

缓存是 opt-in：`recalc` 保持零开销原路径（互异文本公式不付缓存哈希成本），
`recalc_cached` 启用按公式全文的内容寻址缓存（含解析失败负缓存）。
增量重算（`recalc_init`/`recalc_update`）输出与全量逐字段一致；环、解析错误、
超大区域自动回退全量。输出组装仍是 O(格数)（完整 RecalcOutput 契约），
收益来自跳过未变格的解析与求值。

## 已做优化

- **二元链迭代求值**（`eval_binary` 左脊折叠）：左结合长链不再随项数递归，
  既是 wasm-gc 的不崩溃保证，也消除了深链的栈帧开销。
- **区域缓存**（`Ctx.range_cache`）：同一求值上下文内，同一区域只物化一次。
  单元格值在上下文内不可变，故缓存安全。shared 场景 10k 格从 130 ms 降至 59 ms（2.2×）；
  这是真实表格最常见的模式（多行公式引用同一汇总区域）。
- **公式 AST 缓存**（`ParseCache` / `recalc_cached`，opt-in）：按公式全文缓存解析
  结果（含失败消息），文本变即新键、无需失效。单次重算内同文本公式去重
  （dup 场景 6.5×），跨重算复用跳过重复解析（repeat 热态 2.65×）。
  `recalc` 走无缓存原路径，互异文本工作负载零回归。

## 口径说明

- 计时含公式解析（`recalc` 的真实成本）；重复测量复用同一网格，但每次重算都重新解析。
- dup 每次重算新建 `ParseCache`（只测单次重算内去重）；repeat 跨重算共享同一缓存（热态）。
- 数字是单机参考值，不是跨机器承诺；CI 不以性能为门禁（避免环境抖动导致误报）。