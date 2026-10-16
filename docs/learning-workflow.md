# 学习协调器职责与状态归属

本轮只拆 Mac 的学习协调器，保留 `FYLearningCoordinator.h` 全部公开实例与类方法。存储、AI 分析及产品规则沿用现有实现，不重复拆分。进度与私有证据为 `.build/learning-workflow-runtime-split/PROGRESS.md`。

| 组件 | 状态与职责 |
| --- | --- |
| FYLearningCoordinator | 兼容门面、store/analyzer/tokenizer/catalog 服务引用和 persistenceErrorHandler；旧属性与内部 KVC 入口转发 |
| FYLearningSentenceWorkflow | learningEnabled/japaneseMode、sessionID、连续文本/对白/字段身份与复用、current/latest ID/version/text/translation、固定阅读、selectionGeneration；原记录、回填、跟随、选择、修正和历史保护流程 |
| FYLearningAnalysisWorkflow | 唯一 analysisGeneration 与 reviewAnalyzer；缓存资格、分析/主动复核和过期结果检查 |
| FYLearningCollectionWorkflow | 唯一 vocabularyQueue 与 vocabularyOperations；去重、非空字段合并、串行收藏、例句与语法收藏 |
| FYLearningProjection | 无状态历史分组、稳定身份查找、版本/选区/条目资格与复习索引算法 |

句子流程在原位置调用门面的 invalidateAnalysis，分析流程回包时读取当前句 owner 和当前 persistenceErrorHandler。三份按职责声明的 Source 协议只暴露该流程用到的字段、服务及方法，不存另一份 Context，不引入通用字典或事件总线。门面不生成这些24项状态的 ivar；每个属性 getter/setter 只转发到对应 owner。

异步 block 的 receiver 仍是原兼容门面：与原实现一样，任务强持有门面，完成和外部边界释放后可释放。所有原方法间调用仍通过 receiver 分派，保持覆写接缝；依赖另一类方法的选区核对保留原 class self 分派。字符串/数组的 copy、身份与词条的 strong、收藏队列的 FIFO 和事务调用保持原样；回调不新增队列跳转。

`FY_LEARNING_WORKFLOW_SOURCES` 由共享源码清单供全部消费者使用；新增 `run-learning-workflow-tests.sh` 纳入统一 Debug。关键回归直接调用真实门面，只 hold Store/analyzer 外部完成边界，覆盖固定期间新句、迟到缓存/分析、修正失败与迟到修正、跟随竞争、并发排队/失败继续/补全合并、例句来源、任务寿命与状态唯一归属。存储事务仍由旧真实 SQLite 回归验证。

阶段 A 自检：新增87项边界 O0/O2、旧学习功能 O0/O2、RuntimeOwnership 各212项 O0/O2通过。完整报告 `.build/debug/20261014T103002Z-dbf1a6/summary.json` 为209 passed + 同一粘连按钮旧缺口两次复现，source_unchanged=true，761个报告哈希匹配阶段源码，原208通过记录及77场景154次Replay关键字段保留。38搬迁正文及46字面量一致。私有队列保护变异退出2（实际提前读库3次）；生产owner哈希未变。首轮协议属性声明编译失败已定位修正，原失败记录保留，详见 `A-delivery.json` 和 PROGRESS。全程 headless，不读取玩家库/真实凭据，不发真实 API、不连设备，不安装、提交、推送或发布。最短手动检查（另行安排桌面时段）：固定一条已译句，让新句到来并分析固定句；修正原文后跟随最新句；快速收藏同词两次，核对例句及收藏结果。真实窗口/控件、设备和服务体验未由自动检查验收。
