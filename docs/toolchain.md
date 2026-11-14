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

## 已核实的 core API

- `@json.parse(StringView) -> Json raise ParseError`；`Json` 公开枚举 `Null | True | False | Number(Double, repr~ : String?) | String(String) | Array(Array[Json]) | Object(Map[String, Json])`；构造器 `Json::number/string/boolean/array/object/null`；`Json::stringify`。
- `@env.args() -> Array[String]`；`@env.exit(Int32) -> T`（退出码，无需 x/sys）。
- `@fs.read_file_to_string(String, encoding?~) -> String raise IOError`；`write_string_to_file`、`path_exists`、`read_dir`（x/fs，仅 cmd/main）。
- core 自带 `argparse` 包；本项目 CLI 参数手写解析（简单可控）。
- String 的常用方法在 `moonbitlang/core/builtin`（String 为 builtin 类型），实现文本函数时按 pkg.generated.mbti 核实。

## 待办核实（实现到对应功能时）

- builtin String 的大小写/裁剪/查找方法覆盖度（UPPER/LOWER/TRIM/FIND）。
- Double 的格式化能力（to_text 的 15 位有效数字规则）。