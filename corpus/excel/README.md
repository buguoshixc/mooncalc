# 在真实 Excel 中生成答案键语料（桌面版）

你是语料的权威来源。AI 无法运行 Excel，期望值必须由真实 Excel 计算。

## 准备（一次性）

宏把 `ThisWorkbook.Path & "\..\spec"` 当作规格目录、把 `..\cases` 当作输出目录，
因此**必须保持如下目录布局**（工作簿放在 `excel/` 子目录，而不是仓库根目录或任意文件夹）：

```
<工作目录>/
  excel/generator.xlsm      ← 带宏工作簿（本目录即 corpus/excel/）
  spec/*.tsv                ← corpus/spec/ 的拷贝
  cases/                    ← 生成输出
```

1. 新建一个 Excel 工作簿，另存为 **启用宏的工作簿（.xlsm）**，
   保存到 `corpus/excel/`（文件名随意，如 `generator.xlsm`）。
   工作簿里只保留默认空表即可；生成器会自建/自删所需工作表。
2. 按 `Alt+F11` 打开 VBA 编辑器 → 菜单「文件 → 导入文件」→
   选择 `generate_corpus.bas`（保持文件为无 BOM 的 UTF-8，否则 VBA 会忽略
   `Attribute VB_Name` 并把模块命名为「模块1」，宏名仍可用但不利于核对）。
   模块名为 `MoonCalcCorpus`。
3. 确认同级的 `spec/` 目录有 `.tsv` 用例规格文件（AI 提供，会持续增补）。
4. 若用 COM 自动化导入模块，需要 Excel「信任中心 → 宏设置 → 信任对 VBA
   工程对象模型的访问」（注册表 `AccessVBOM=1`），手工 Alt+F11 导入则不需要。

## 运行

生成器有两个入口：

| 宏 | 处理范围 | 输出 | 用途 |
| --- | --- | --- | --- |
| `GenerateCorpus` | `spec/*.tsv` 全部 | `cases/<同名>.json` | 全量重建（旧行为，重跑会覆盖旧 8 个 JSON） |
| `GenerateCorpusOne` | 只处理 `spec/refs.tsv` | `cases/refs.json` + `cases/refs.skipped.txt` | **W1 单批：不动其他 cases 文件** |

W1 只需跑 `GenerateCorpusOne`：

1. 回到 Excel，按 `Alt+F8` → 运行 `GenerateCorpusOne`。
2. 宏读取 `corpus/spec/refs.tsv`，在临时工作表中逐条写入输入与公式，
   按 grid 键里出现的表名自动 `Worksheets.Add` 建表并命名，
   强制重算，读取答案格 `ZZ1`，然后删除本用例新建的全部工作表与定义名称。
3. 结束时弹「Corpus generation complete: 1 spec file(s).」；
   只写 `corpus/cases/refs.json` 与（若有跳过）`corpus/cases/refs.skipped.txt`，
   其他 `cases/*.json` 保持不变（可核对 git 状态确认字节未变）。
4. 把 `corpus/cases/refs.json` 和 `refs.skipped.txt`（若有）回传给 AI，
   放入仓库 `corpus/cases/` 同名目录即可。

需要全量重建时再跑 `GenerateCorpus`（会覆盖全部 cases JSON）。

## 多工作表与定义名称（W1 新增）

- spec 的 grid 键可以写 `SHEET!A1`，也可以写裸 `A1`。
  - 裸地址 = 主临时表（本次运行创建的 `MC_Temp_hhmmss`）。答案格 `ZZ1`、时钟辅助格
    `ZY1` 始终在主临时表，所以被测公式里的裸引用指向主表，引用其他表必须写全名。
  - 表名按**最后一个** `!` 拆分，地址部分必须是 A1 形（列字母+行号）。
  - Excel 引号写法也接受：`'My Sheet'!A1`、`'2024Data'!A1`、`'O''Brien'!A1`；
    不需要引号的表名（如 `Data!A1`、`My Sheet!A1`）直接写即可。
  - 用例新建的工作表在该用例结束后（正常、跳过、出错三条路径）全部删除；
    每个表的地址限 A1:H20，整列引用限 A:H，整行引用行号 ≥ 2。
- spec 可选第 7 列 `names`：`Name1=Ref1|Name2=Ref2`（如
  `Rate=Data!$A$1|Big='My Sheet'!$A$1:$B$2`）。名称在计算前加入工作簿、
  读取答案后删除；未限定表名的引用（`Tax=$B$1`）指向主临时表。
  名称非法、重复或与单元格引用形冲突（如 `A1`）时该用例整个跳过。

## 注意

- 宏只读写临时工作表（运行后自动删除），不动你的其他工作簿。
- 规格文件按 **UTF-8** 读取（含中文/emoji 用例），不受系统区域设置影响。
- 含 `TODAY`/`NOW` 的用例（spec 的 `now` 列为 `capture`）会在写入答案公式的
  同一次重算里，把 `=NOW()` 写进辅助格 `ZY1`，`Application.Calculate` 后读回该格
  序列值写入 `now` 字段——与答案格的 `NOW()` 是同一计算时刻，而不是 VBA `Now`
  的整秒截断。请确保系统时钟正常。
- **首次遇到循环引用用例时 Excel 会弹一次警告对话框，点「确定」即可**
  （同一会话只弹一次），宏会继续；结果按迭代关闭默认（环上为 0）记录。
  自引用探针（`A1=f:=A1+1`，无 iter 列）就属于这种用例。
- 若某条公式被 Excel 拒绝（spec 有 bug，例如引用一个从未创建的表的裸 `=NoSheet!A1`
  可能被 Excel 直接拒绝录入），宏会**跳过该条并继续**，
  id 与原因记入 `corpus/cases/<同名>.skipped.txt`——把该文件一并回传即可。
  跳过原因会写明是 spec 非法、表名非法还是 Excel 拒绝（`excel-rejected: 错误号 描述`）。
- 每次运行覆盖同名输出；spec 增补后重跑即可。
- 计算模式会被临时设为手动以保证逐条确定性，结束（含出错）后恢复；
  迭代计算设置按用例临时调整（无 iter 列时显式关闭），读取答案后立即还原。
- **Excel 版本**：`CONCAT` 需要 Excel 2019+ / Microsoft 365；更老版本会把
  这类用例导出为 `#NAME?`（宏不报错、照常继续）。回传时请告知 Excel 版本
  （「文件 → 账户」），便于把版本差异与引擎差异分开归因。
- 生成器会显式映射动态数组错误 `#CALC!`（VBA 错误码 2050，如 TEXTJOIN
  超过 32767 字符），其余未知错误码写成 `#UNKNOWN(code)`，遇到即表示
  需要扩展 `ErrName` 与引擎错误枚举。
- 生成器与工作簿的 SHA-256、各输出文件条数/摘要、Excel 完整版本号都记录在
  [corpus/cases/PROVENANCE.md](../cases/PROVENANCE.md)。
