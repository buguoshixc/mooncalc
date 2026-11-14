# 工具链核实记录（M0，2026-11-14）

## 版本与安装

- 安装命令：`curl -fsSL https://cli.moonbitlang.com/install/unix.sh | bash`
- `moon version`：**0.1.20261104 (940aa18 2026-11-04)**，feature flags：`rr_moon_mod,rr_moon_pkg`（新格式清单）。
- 安装位置 `~/.moon`，core 随工具链捆绑；PATH 需含 `~/.moon/bin`（安装器已写入 ~/.bashrc，非交互 shell 需显式 export）。
- native 后端使用系统 gcc 15.2，构建正常。
- 依赖：`moonbitlang/x@0.5.7`（`moon add moonbitlang/x`），仅壳层使用其 `fs` 包。

## 清单格式（已实测）

- 模块清单为 `moon.mod`（新 DSL，非 json）；包清单为 `moon.pkg`。
- 包级目标限制：`supported_targets = "native"` / `"wasm-gc"`（目标集表达式，如 `+native+wasm-gc`）；模块与包声明取交集。
- 可执行包：`pkgtype(kind: "executable")`；导出库包：`pkgtype(kind: "foreign_library")` + `#export_name("符号名")`。
- 构建产物在 `_build/<target>/<profile>/build/<pkg>/`（不是 target/）。

## wasm-gc JS 互操作（spike 实测结论）

- web 包开启 `options(link: { "wasm-gc": { "use-js-builtin-string": true } })` 后，MoonBit `String` 即 JS 字符串，导出函数 `String -> String` 可被 JS 直接调用。
- 产物 wasm 有两类导入：
  1. `_` 命名空间的 global 字符串常量——**导入名即字符串值本身**；
  2. `wasm:js-string` 的函数（concat 等）。
- Node v26 实测：`instantiate` 的 `builtins`/`importedStringConstants` 选项未自动注入上述导入；**宿主需手动提供**（见 scripts/spike.mjs 的 loadMoonWasm：遍历 Module.imports，`_` global 以名字为值注入，`wasm:js-string` 用等价 JS 实现映射）。该加载器模式将复用于 playground。
- 核心包无 println、无 @fs/@sys → 无额外宿主导入。

## M6 实测：完整引擎的 js-string 依赖与冒烟方式

- 完整引擎（含 @json codec）比 spike 多一个 `wasm:js-string.fromCharCodeArray` 导入（来自 core 的 String/Array[Char] 转换与 StringBuilder，非业务代码可控）。其参数是 wasm GC 数组引用，**JS 无法读取，纯 JS polyfill 不可行**。
- 解法：`WebAssembly.compile(bytes, { builtins: ['js-string'] })` 让宿主原生提供全部 js-string 内建。Node v26 与 Playwright Chromium 均实测支持；playground/loader.js 先走原生路径，失败再回退 JS polyfill（仅覆盖不含 fromCharCodeArray 的模块，如 spike），并给出明确报错。
- headless 冒烟不能用 `--dump-dom`（不等 top-level await 模块）也不能用 `--virtual-time-budget`（虚拟时间在 wasm 编译/求值的真实 CPU 工作期间耗尽，DOM 提前倾倒）。scripts/smoke.mjs 改用 **CDP**：`--remote-debugging-port` + Node 内置 WebSocket 轮询 `Runtime.evaluate` 直到 `#done` 出裁决，零 npm 依赖。
- 交互验证同样走 CDP：预设切换、单元格编辑、错误面板均实测正确（错误传播 #DIV/0!、循环引用 0+警示、编辑后 120ms 防抖重算）。

## 已核实的 core API

- `@json.parse(StringView) -> Json raise ParseError`；`Json` 公开枚举 `Null | True | False | Number(Double, repr~ : String?) | String(String) | Array(Array[Json]) | Object(Map[String, Json])`；构造器 `Json::number/string/boolean/array/object/null`；`Json::stringify`。
- `@env.args() -> Array[String]`；`@env.exit(Int32) -> T`（退出码，无需 x/sys）。
- `@fs.read_file_to_string(String, encoding?~) -> String raise IOError`；`write_string_to_file`、`path_exists`、`read_dir`（x/fs，仅 cmd/main）。
- core 自带 `argparse` 包；本项目 CLI 参数手写解析（简单可控）。
- String 的常用方法在 `moonbitlang/core/builtin`（String 为 builtin 类型），实现文本函数时按 pkg.generated.mbti 核实。

## 待办核实（实现到对应功能时）

- builtin String 的大小写/裁剪/查找方法覆盖度（UPPER/LOWER/TRIM/FIND）。
- Double 的格式化能力（to_text 的 15 位有效数字规则）。
## 网络环境：GitHub 推送路由（2026-11-14 实测）

- 本 WSL2 环境 **github.com:443 被阻断**（TLS 连接被切断，curl 超时 HTTP 000）；`git push`/`git fetch` 走 origin 的 HTTPS URL 均失败。
- 可达路由：`api.github.com`（HTTPS 200，~0.3s）、`ssh.github.com:443` 与 `github.com:22`（TCP 通）。
- 解法：经 gh API 注册**仓库级 write deploy key**（`~/.ssh/mooncalc_deploy`，key id 169865712），用 `scripts/push.sh` 走 `ssh://git@ssh.github.com:443` 推送，commit SHA 完整保真；fetch 同样被阻断，脚本推送后手动同步 `refs/remotes/origin/main`。
- gh CLI 已认证（buguoshixc，repo scope），API 调用不受影响。
