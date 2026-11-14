# MoonPack

**MoonBit Agent Context Packer** — 面向 MoonBit 仓库的 token 预算上下文打包与检索评测工具。

> 状态：仓库脚手架已就绪，功能开发进行中（2026 MoonBit 年度黑客松 11 月赛参赛项目）。

## 这是什么

MoonPack 面向 MoonBit 生态的 AI 编程场景：给定一个 MoonBit 仓库、一条任务描述和一个 token 预算，自动生成“最小够用”的上下文包——仓库结构树、包级 API 摘要、依赖关系、按相关性排序的代码片段，以及可追溯的 JSON manifest——让 coding agent 少读无关代码、少浪费 token。

同时，MoonPack 内置可复现的检索评测：用真实 MoonBit 提交作为 ground truth，衡量不同打包策略的 recall@budget 与压缩比，让“上下文工程”从经验判断变成可度量、可比较的工程实践。

## 计划功能

- `moonpack pack`：按任务描述与 token 预算生成上下文包；
- `moonpack query`：仓库内符号 / API 检索；
- `moonpack eval`：检索质量评测（真实提交 ground truth + 多策略基线对比）；
- 解析层：文件树、`moon.pkg` 依赖关系、`.mbti` 接口摘要（缺失时调用 `moon info` 生成）；
- 输出 Markdown + JSON manifest，可接入任意 agent CLI，不依赖模型 API。

## 仓库状态

- [x] 仓库初始化（README / LICENSE / .gitignore）
- [x] 项目申报书（[项目申报书.md](项目申报书.md)）
- [ ] 仓库解析层
- [ ] CLI 三个子命令
- [ ] 评测 harness
- [ ] 文档与示例

## 许可证

本项目采用 MIT License，参见 [LICENSE](LICENSE)。
