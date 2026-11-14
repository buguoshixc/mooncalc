# 权威语料回传记录（provenance）

本目录 `corpus/cases/*.json` 由真实桌面 Excel 计算生成，来源可复现。

## 生成环境

| 项 | 值 |
| --- | --- |
| 生成日期 | 2026-11-14 19:34 (Asia/Shanghai) |
| Excel 版本 | Microsoft Excel 2024（Microsoft Office Home 2024, Home2024Retail） |
| 完整版本号 | 16.0.20527.20196（Click-to-Run, x64, zh-CN, Production::CC） |
| COM 报告 | Version 16.0 / Build 20527 / Windows (64-bit) NT 10.00 |
| 生成器 | `corpus/excel/generate_corpus.bas`（`GenerateCorpus`，含语法修正） |
| 规格输入 | `corpus/spec/*.tsv`（7 文件 / 752 条） |
| 结果 | 752/752 条导出，0 条被 Excel 拒绝（无 `*.skipped.txt`） |
| 计算模式 | 宏内临时改为手动计算、逐条强制重算；结束恢复 |

## 文件清单（SHA-256 / 条数）

| 文件 | 条数 | SHA-256 |
| --- | --- | --- |
| `date.json` | 91 | `ebe0f0b84b5eef8647b6ea585dd8a9df209785e5e58ac1fdbc6264173e31ab3a` |
| `generic.json` | 237 | `e55926cc476a8d6f5eee65a248c7a1614ca75097637d31cbe041f1dcc1944fbe` |
| `logic.json` | 55 | `c9340db29e0a4379e5c747588ee9216c532d40e5b182e108141e7fdea11a0d91` |
| `lookup.json` | 59 | `30c130260b930174e2979359d889a99113f8cb5730b567ddbaa4877b10f45f9d` |
| `math.json` | 110 | `5cb1a3cf9c0c043f282074643c740647204f41212757df559d3d0aef672a149c` |
| `stat.json` | 61 | `4f3577e53d2a02a182ecfcd11c6992d6a474345353479ed3978ec4d08c6b974d` |
| `text.json` | 139 | `6d5b6337b602c771085b2c9526097f6574158403b079af3d48407bae240c38dd` |
| **合计** | **752** | — |

## 说明

- 文件为 UTF-8 **带 BOM**（VBA `ADODB.Stream` 行为）；CLI 读取时会剥除 BOM（`@codec.strip_utf8_bom`）。
- 数值由 VBA `CStr` 输出，有效数字上限 15 位；因此超出 15 位的 double 结果会被截断（bench 的 `numeric-tolerance` 桶即由此产生，M5 归因中）。
- `now` 字段由宏在 `Application.Calculate` 后用 VBA `Now` 捕获，精度为整秒（与 Excel `NOW()` 的重算时刻存在 <1s 偏差，M5 归因中）。
