浮译 · 离线词典与用法参考

本目录的 reference.sqlite 是开放资料的格式转换与筛选结果，采用 CC BY-SA 4.0。
它不包含用户的游戏台词、收藏、凭据或学习记录。软件代码的许可与本数据许可分别处理。

资料来源：
1. JMdict 日语/英语部分：James William Breen / Electronic Dictionary Research and Development Group (EDRDG)。
   https://www.edrdg.org/jmdict/j_jmdict.html
   https://www.edrdg.org/edrdg/licence.html
   使用读音、写法、词性、英文义项、使用标签，以及已有词条/义项关联的日文例句索引。
   没有内置其他语言词典，也没有生成中文释义。
2. Tatoeba 句子作者：每条例句在数据中保留 sentence_id、author、url 及许可。
   https://tatoeba.org/en/downloads
   例句按 CC BY 2.0 FR 使用；仅保留能在当前详细导出中确认作者且日文文本完全相同的记录。
   没有导入音频；没有导入英文例句译文（避免缺失其独立作者署名）。
3. OpenJLPT / Jonathan Waller：非官方 N5–N1 参考词汇等级。
   https://github.com/evanclan/OpenJLPT
   https://www.tanos.co.uk/jlpt/
   等级数据按 OpenJLPT 的 CC BY-SA 4.0 声明使用，保留对上游的署名。
   仅使用经 JMdict ID、写法和读音对应的等级。不同写法的等级不得自动合并。
   不导入 OpenJLPT 自动匹配的例句或原创语法解释。

修改：将原始数据转为只读 SQLite，建立精确写法/读音索引；按词典义项关联、作者和文本一致性筛选例句。
例句尚未独立人工审校，社区参考等级也非官方考试清单。缺失字段保持缺失，不以 AI 生成内容替代。
中文解释或练习若后续生成，将与本资料分开展示，不冒充来源原文。

版权与许可：完整文本和项目说明见 licenses/。CC BY-SA 4.0 许可链接：
https://creativecommons.org/licenses/by-sa/4.0/
Tatoeba 例句原许可： https://creativecommons.org/licenses/by/2.0/fr/
转换的词典数据及其改编版本按 CC BY-SA 4.0 提供；保留署名、许可链接与修改说明。
可以从本目录复制/导出数据库；不对这份数据施加额外技术限制。

版本与更新：reference-manifest.json 记录构建时间、实际源文件 SHA-256、来源地址及数量。
维护者定期运行：python3 scripts/import-reference-data.py --download
检查匹配和许可后重新构建、打包发布；更新只替换资料包，不迁移或清空用户的学习数据库。
