# 权威语料回传记录（provenance）

本目录 `corpus/cases/*.json` 由真实桌面 Excel 计算生成，来源可复现。

## 生成环境

| 项 | 值 |
| --- | --- |
| 生成日期 | 2026-11-14 19:53 (Asia/Shanghai) |
| Excel 版本 | Microsoft Excel 2024（Microsoft Office Home 2024, Home2024Retail） |
| 完整版本号 | 16.0.20527.20196（Click-to-Run, x64, zh-CN, Production::CC） |
| COM 报告 | Version 16.0 / Build 20527 / Windows (64-bit) NT 10.00 |
| 生成器 | `corpus/excel/generate_corpus.bas`（`GenerateCorpus`；含语法修正与时钟捕获修正） |
| 规格输入 | `corpus/spec/*.tsv`（7 文件 / 752 条） |
| 结果 | 752/752 条导出，0 条被 Excel 拒绝（无 `*.skipped.txt`） |
| 计算模式 | 宏内临时改为手动计算、逐条强制重算；结束恢复 |

## 文件清单（SHA-256 / 条数）

| 文件 | 条数 | SHA-256 |
| --- | --- | --- |
| `date.json` | 91 | `5ee33d5a6527e4f5edde555fb5f20877da7163cc1764e8342a6480d7e674af7e` |
| `generic.json` | 237 | `b3233764059aecee6f185a16a0d2a93ead7ca77495523ab8a9375f1fc4ae55d3` |
| `logic.json` | 55 | `c9340db29e0a4379e5c747588ee9216c532d40e5b182e108141e7fdea11a0d91` |
| `lookup.json` | 59 | `30c130260b930174e2979359d889a99113f8cb5730b567ddbaa4877b10f45f9d` |
| `math.json` | 110 | `5cb1a3cf9c0c043f282074643c740647204f41212757df559d3d0aef672a149c` |
| `stat.json` | 61 | `4f3577e53d2a02a182ecfcd11c6992d6a474345353479ed3978ec4d08c6b974d` |
| `text.json` | 139 | `6d5b6337b602c771085b2c9526097f6574158403b079af3d48407bae240c38dd` |
| **合计** | **752** | — |

只有含时钟用例的 `date.json` / `generic.json` 与上一版不同；确定性用例文件字节未变。

## 说明

- 文件为 UTF-8 **带 BOM**（VBA `ADODB.Stream` 行为）；CLI 读取时会剥除 BOM（`@codec.strip_utf8_bom`）。
- 数值由 VBA `CStr` 输出，有效数字上限 15 位；bench 对这类表征差单独计入
  `excel-precision` 桶（相对差 ≤1e-14，通过并披露），不掩盖真实行为差异。
- `now` 字段：宏在写入答案公式的**同一次重算**里，把 `=NOW()` 写进辅助格 `ZY1`，
  `Application.Calculate` 后读回该格序列值（15 位十进制）。因此 `now` 与答案格的
  `NOW()`/`TODAY()` 是同一计算时刻的同一 double 值，而不是 VBA `Now`（整秒截断）。
- 含 `TODAY`/`NOW` 的用例若与答案格仍有 <1e-6 天的差（例如派生比较产生的尾差），
  bench 按 `clock_tol`（绝对天数）判定并单列 `clock-tolerance` 桶。
