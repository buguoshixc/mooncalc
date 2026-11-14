# 在真实 Excel 中生成答案键语料（桌面版）

你是语料的权威来源。AI 无法运行 Excel，期望值必须由真实 Excel 计算。

## 准备（一次性）

1. 新建一个 Excel 工作簿，另存为 **启用宏的工作簿（.xlsm）**，
   保存到本目录（`corpus/excel/`），文件名随意（如 `generator.xlsm`）。
2. 按 `Alt+F11` 打开 VBA 编辑器 → 菜单「文件 → 导入文件」→
   选择 `generate_corpus.bas`。
3. 确认 `corpus/spec/` 下有 `.tsv` 用例规格文件（AI 提供，会持续增补）。

## 运行

1. 回到 Excel，按 `Alt+F8` → 运行 `GenerateCorpus`。
2. 宏会逐个读取 `corpus/spec/*.tsv`，在临时工作表写入输入与公式，
   强制重算，读取结果，导出到 `corpus/cases/<同名>.json`。
3. 看到「Corpus generation complete」即完成。把 `corpus/cases/` 下的
   JSON 文件回传给 AI（放入仓库同名目录即可）。

## 注意

- 宏只读写临时工作表（运行后自动删除），不动你的其他工作簿。
- 规格文件按 **UTF-8** 读取（含中文/emoji 用例），不受系统区域设置影响。
- 含 `TODAY`/`NOW` 的用例会在计算后立即捕获当时时间写入 `now` 字段，
  请确保系统时钟正常。
- **首次遇到循环引用用例时 Excel 会弹一次警告对话框，点「确定」即可**
  （同一会话只弹一次），宏会继续；结果按迭代关闭默认（环上为 0）记录。
- 若某条公式被 Excel 拒绝（spec 有 bug），宏会**跳过该条并继续**，
  id 记入 `corpus/cases/<同名>.skipped.txt`——把该文件一并回传即可。
- 每次运行覆盖同名输出；spec 增补后重跑即可。
- 计算模式会被临时设为手动以保证逐条确定性，结束（含出错）后恢复。