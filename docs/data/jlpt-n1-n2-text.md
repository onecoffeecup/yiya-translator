# 译芽 · N1/N2 词汇文字资料包

本包整理自 egg rolls 的「JLPT N1-N5 一万词 v3.5」，供非商业学习及软件数据接入使用。原作者与上游项目未声明认可本整理包。

## 内容

共 7,260 个词条：N1 4,045 条、N2 3,215 条。包含 10,761 条例句或短语、609 条关联表达、562 条反义表达及其中文翻译。

保留日文词条、中文释义、中文词性、参考等级、作者整理频率和中日例句；移除读音字段、注音、声调及音频。日文词条和例句本身的假名仍保留。

| 文件 | 用途 |
| --- | --- |
| `n1-n2-text.json` | 软件读取，UTF-8，数据结构版本 2 |
| `n1-n2-text.txt` | 直接阅读，UTF-8，含全部中日例句和关联表达 |
| `SOURCE-NOTICE.md` | 原作者、来源、修改说明和许可要求 |
| `LICENSE-CC-BY-NC-4.0.txt` | CC BY-NC 4.0 完整许可，沿用上游 LICENSE |
| `manifest.json` | 条目数量、来源、包内文件大小与 SHA-256 |
| `SHA256SUMS.txt` | 文件完整性校验清单 |

## 来源与许可

- 原作者：**egg rolls**。
- 原项目：[5mdld/anki-jlpt-decks](https://github.com/5mdld/anki-jlpt-decks)。
- 原始文字文件：[deck-source/notes.csv](https://github.com/5mdld/anki-jlpt-decks/blob/main/deck-source/notes.csv)。
- 许可：[CC BY-NC 4.0（署名—非商业性使用 4.0 国际）](https://creativecommons.org/licenses/by-nc/4.0/)。
- 本包由译芽项目筛选、去除 HTML/注音标记并转换格式；词性缩写展开为中文。中文释义和例句沿用原资料，未由 AI 改写。

分享或修改本包时，请保留原作者署名、原项目链接、许可链接及修改说明。资料仅限非商业用途，包括不得整合进付费产品或服务。译芽代码的 MIT 许可不覆盖本包数据；不对本包添加额外限制。

## 数据读取

JSON 顶层含 `schema_version`、`source`、`counts`、`example_counts` 和 `entries`。

每个词条含 `source_id`、`word`、`meaning_zh`、`part_of_speech_zh`、`reference_level`、`frequency_group` 和 `examples`；每个例句含 `kind`、`text_ja` 与 `translation_zh`。请保留 `source_id`，并区分例句、关联表达、反义表达。

等级和频率为原作者整理的参考分类，未逐条独立审校。频率定义见 JSON 的 `source.frequency_definitions`。本包没有试卷年份、题号或完整题目，属于词汇资料；不构成完整真题库。

本包沿用现有本地整理数据，未记录原始 CSV 的提交号。校验值用于确认本包文件完整性，不表示已经核验每条释义。打包日期为 2026-10-05。

## 使用与分发

解压后，可直接打开 TXT 阅读，或由程序解析 JSON。此包不是 Anki 牌组或 Yomitan 词典格式，也尚未接入译芽正式应用的导入功能。

准备上传 GitHub 时，可将本 ZIP 和同名 `.zip.sha256` 文件作为 Release 附件，并在说明中保留上面的来源和许可。本包仅含文字资料、说明和许可。

## 本仓库中的位置

- ZIP：`output/jlpt-vocabulary/yiya-jlpt-n1-n2-text-20261005.zip`。
- ZIP 校验文件：`output/jlpt-vocabulary/yiya-jlpt-n1-n2-text-20261005.zip.sha256`。
- 解压前的完整资料目录：`output/jlpt-vocabulary/yiya-jlpt-n1-n2-text-20261005/`。
- 来源与校验清单：[jlpt-n1-n2-package.json](jlpt-n1-n2-package.json)。

`output/` 保持 Git 忽略；仓库保留本说明和清单，ZIP 可作为 Release 附件单独上传。当前仅完成本地打包，尚未发布到 GitHub。

ZIP 大小：1,020,331 字节。已验证 ZIP CRC、JSON/TXT 数量和包内数据与整理原件的逐字节一致性。

ZIP SHA-256：

```text
fb017ef68053ac74b1a82a4cd2894c258f0e8c7974fabf373fdcd51788da926e
```
