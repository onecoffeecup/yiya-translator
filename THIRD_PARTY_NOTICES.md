# 第三方资料与署名

项目源码的 MIT 许可不覆盖下列第三方资料。现有 JMdict 只读词典与 OpenJLPT 衍生等级数据按 CC BY-SA 4.0 提供；例句保留各自作者、句子 ID、原始地址和许可。已内置资料的完整许可随资料附件及 App 一并提供。独立 N1/N2 文字资料包使用下文单独标注的 CC BY-NC 4.0。

| 资料 | 使用内容 | 来源与署名 | 许可 |
| --- | --- | --- | --- |
| JMdict | 日文写法、读音、词性、英文义项、使用标签及义项关联索引 | James William Breen / Electronic Dictionary Research and Development Group（EDRDG），[项目](https://www.edrdg.org/jmdict/j_jmdict.html)、[许可](https://www.edrdg.org/edrdg/licence.html) | CC BY-SA 4.0 |
| Tatoeba | 经作者、原句和关联词形核对的日文例句 | [Tatoeba 句子作者](https://tatoeba.org/en/downloads)，逐句保留署名与来源；未导入音频或英文译句 | CC BY 2.0 FR |
| OpenJLPT / Jonathan Waller | 经词典 ID、写法和读音对应的 N5–N1 参考等级 | [OpenJLPT](https://github.com/evanclan/OpenJLPT)、[Jonathan Waller](https://www.tanos.co.uk/jlpt/)；未导入其自动匹配例句或原创语法 | CC BY-SA 4.0（OpenJLPT 衍生数据） |

本项目将资料转换为 SQLite，并建立查询索引和进行例句筛选。资料尚未独立人工审校；参考等级不是 JLPT 官方考试清单。内置语法目录为项目原创、AI 辅助核对，等级仍待核实。

当前 JMdict 快照为 2026-10-04：218,857 个词条、11,567 条例句关联、7,683 个等级匹配词条。关联数不等于独立例句数。

来源文件、原始 SHA-256 及构建时间见 [reference-manifest.json](resources/learning/reference/reference-manifest.json)，分发文件校验值见 [reference-package.json](resources/learning/reference/reference-package.json)。详细筛选方法见 [资料 README](resources/learning/reference/README.txt)。

完整许可与上游说明：

以下相对链接用于源码目录。下载版可在 App 的「翻译服务」页展开「资料来源与许可」直接阅读说明；其中的「在 Finder 查看完整许可文件」会打开许可文件夹。完整来源和许可文本位于 `译芽.app/Contents/Resources/learning/reference`。

- [CC BY-SA 4.0](resources/learning/reference/licenses/CC-BY-SA-4.0.txt)
- [Tatoeba 使用的 CC BY 2.0 FR](resources/learning/reference/licenses/CC-BY-2.0-FR.html)
- [EDRDG 许可说明](resources/learning/reference/licenses/EDRDG-LICENSE.html)
- [OpenJLPT 许可](resources/learning/reference/licenses/OpenJLPT-LICENSE.txt) 与 [署名说明](resources/learning/reference/licenses/OpenJLPT-NOTICE.md)

公开源码和资料包不包含用户学习数据库、完整游戏资源或 JLPT 真题。README 的学习界面截图使用测试数据。

## 独立 N1/N2 词汇文字资料包

原作者为 **egg rolls**，原资料为「JLPT N1-N5 一万词 v3.5」，来源为 [5mdld/anki-jlpt-decks](https://github.com/5mdld/anki-jlpt-decks) 的 [deck-source/notes.csv](https://github.com/5mdld/anki-jlpt-decks/blob/main/deck-source/notes.csv)。上游采用 [CC BY-NC 4.0](https://creativecommons.org/licenses/by-nc/4.0/)，要求署名、提供原项目链接、说明修改情况，并限于非商业用途；不得整合进付费产品或服务。MIT 不覆盖此资料。

译芽项目筛选出 N1 4,045 条、N2 3,215 条，共 7,260 条；保留中文释义、中文词性、参考等级、作者整理频率、10,761 条例句或短语、609 条关联表达及 562 条反义表达的中日文字。移除读音、注音、声调、音频与 HTML，展开词性缩写，并转换为 JSON 和 TXT；释义和例句沿用原资料，未由 AI 改写。

资料尚未接入正式 App，也不是完整真题库；等级与频率未经逐条独立审校，没有年份和题号映射。2026-10-05 已完成独立 ZIP 打包，内含来源说明、完整许可及校验清单。包的位置与使用方式见 [资料包说明](docs/data/jlpt-n1-n2-text.md)，文件 SHA-256 见 [分发清单](docs/data/jlpt-n1-n2-package.json)。当前仅在本地准备，尚未上传 GitHub。
