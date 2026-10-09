#pragma once
//  界面贴译的自适应分组与布局组件。
//
//  设计边界（本文件只做这两件事，不碰其它系统）：
//    · FYInlineGrouper  —— 把 OCR 行按几何与阅读连续性并成文本块；
//    · FYInlineLayoutEngine —— 对同一帧的全部块统一安排译文位置。
//
//  坐标约定：
//    · 分组（FYInlineTextLine / FYInlineTextBlock）使用**归一化页面坐标**：
//      原点左下、0..1，与 Vision 的 boundingBox 一致；判定只用相对量（局部行高、
//      行距、横向重叠），因此与图像尺寸、缩放无关。
//    · 布局（FYInlineLayoutRequest.sourceFrame / viewport / 结果 frame）使用**显示区域
//      坐标**（AppKit 屏幕坐标，y 向上）。调用方必须先把 OCR 框换算到同一个显示区域，
//      映射不可用属于上游状态，不由布局器猜测。
//
//  刻意不做的事：不认页面类型、不认示例文案、不写死屏幕坐标、不按字符数当几何证据。

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <AppKit/AppKit.h>

// 短贴片视图负责拖动事件与反馈（边框加粗），不设置窗口的鼠标穿透策略。
// 窗口 ignoresMouseEvents 由主协调器控制：默认 YES，Option 按下时切为可交互；
// 协调器同步 dragEnabled / showsDragHint，本视图在允许时处理拖动。
@interface FYInlinePatchView : NSView
@property(nonatomic, copy) void (^ _Nullable onDragBegan)(void);
@property(nonatomic, copy) void (^ _Nullable onDragEnded)(void);
@property(nonatomic) BOOL dragEnabled;
@property(nonatomic) BOOL showsDragHint;
@property(nonatomic) BOOL windowDragEnabled;
@property(nonatomic, strong, nullable) NSColor *dragHintColor;
@property(nonatomic, strong, nullable) NSColor *normalBorderColor;
@end

// 长译文卡：标题栏可拖动整卡；正文区域用于滚动与点击打开学习。
// 拖动与点击必须分开：标题栏按下即进入窗口拖动；正文按下后位移超过阈值就不再算点击。
@interface FYInlineLongCardView : NSView
@property(nonatomic, copy) void (^ _Nullable onClick)(void);
@property(nonatomic, copy) void (^ _Nullable onHover)(BOOL inside);
/// 拖动开始/结束：开始用于占住拖动状态（避免 Option 松开把面板变回穿透），结束用于记录新偏移。
@property(nonatomic, copy) void (^ _Nullable onDragBegan)(void);
@property(nonatomic, copy) void (^ _Nullable onDragEnded)(void);
// 当前是否展示了「已选中」标识（用于判断就地更新时要不要重建内容）。
@property(nonatomic) BOOL showsSelectedBadge;
// 紧凑入口（空间放不下可读正文时）：点击展开完整阅读卡，而不是生成细条。
@property(nonatomic) BOOL compactEntry;
// 标题栏高度（flipped 坐标，y < 该值算标题栏）；默认 55。
@property(nonatomic) CGFloat titleBarHeight;
// 布局器给出的稳定块身份（点击/选中/学习快照都用它）。
@property(nonatomic, copy, nullable) NSString *stableBlockID;
// 展开的完整阅读卡：标题栏右侧显示可见的「收起」按钮（Esc 之外的入口）。
@property(nonatomic, copy) void (^ _Nullable onCollapse)(void);
@property(nonatomic, readonly) BOOL showsCollapseControl;
@property(nonatomic, nullable, weak, readonly) NSButton *collapseButton;
// 「已选中」标识视图：收起按钮出现时要往左让位（NSView.tag 是只读的，不能用它标记）。
@property(nonatomic, nullable, weak) NSView *selectedBadgeBox;
// 折叠入口的三行（测试与可读性断言直接读它们，确保提示真的画在卡上而不是只在 tooltip 里）。
@property(nonatomic, nullable, weak) NSTextField *foldedEntryHintLabel;
@property(nonatomic, nullable, weak) NSTextField *foldedEntryActionLabel;
// 展开卡底部提示（其他贴译已暂时隐藏 / Esc 收起）。
@property(nonatomic, nullable, weak) NSTextField *expandedFooterLabel;
- (void)installCollapseControl;
// 测试/无窗口环境下关闭真实窗口拖动，只走判定逻辑。
@property(nonatomic) BOOL windowDragEnabled;
@property(nonatomic) NSPoint pressPoint;
@property(nonatomic) BOOL pressMovedBeyondThreshold;
// 「收起」按钮按下中（卡片自己跟踪，见 pointIsInCollapseControl:）。
@property(nonatomic) BOOL collapsePressed;
- (BOOL)pointIsInCollapseControl:(NSPoint)localPoint;
- (BOOL)pointIsInTitleBar:(NSPoint)localPoint;
@end

NS_ASSUME_NONNULL_BEGIN

// Presentation text policy: join wrapped lines, preserve blank-line paragraphs.
FOUNDATION_EXPORT NSString *FYInlineNormalizeTranslationParagraphs(NSString * _Nullable text);
FOUNDATION_EXPORT CGFloat FYInlineLongCardLineHeight(CGFloat ascender, CGFloat descender, CGFloat leading);
FOUNDATION_EXPORT CGFloat FYInlineLongCardMinimumHeight(CGFloat lineHeight);
FOUNDATION_EXPORT CGFloat FYInlineLongCardBodyViewport(CGFloat cardHeight);
FOUNDATION_EXPORT NSSize FYInlineLongCardSize(NSSize proposed, BOOL compact);
FOUNDATION_EXPORT void FYApplyInlineLongCardBody(NSString * _Nullable translation, NSTextField *label,
    CGFloat cardWidth, CGFloat padding, NSFont *font, NSParagraphStyle *style, NSColor *textColor);

FOUNDATION_EXPORT NSScrollView *FYCreateInlineLongCardBodyScroll(NSString * _Nullable translation,
    NSRect viewport, CGFloat cardWidth, CGFloat padding, NSFont *font, NSParagraphStyle *style, NSColor *textColor);

FOUNDATION_EXPORT void FYInstallInlineFoldedEntry(FYInlineLongCardView *card, CGFloat cardWidth, CGFloat padding,
    NSString *title, NSString *hint, NSString *action, NSFont *titleFont, NSFont *hintFont,
    NSColor *titleColor, NSColor *hintColor, NSColor *actionColor,
    NSTextField *(^labelFactory)(NSString *, NSFont *, NSColor *));

FOUNDATION_EXPORT void FYInstallInlineLongCardHeader(FYInlineLongCardView *card, CGFloat cardWidth,
    CGFloat padding, CGFloat titleBand, BOOL selected, NSTextField *title, NSTextField *badge,
    NSColor *badgeColor, NSColor *ruleColor);

FOUNDATION_EXPORT NSRect FYInlineLongCardBodyFrame(CGFloat width, CGFloat height, CGFloat padding, CGFloat titleBandHeight);
FOUNDATION_EXPORT void FYInstallInlineLongCardFooter(FYInlineLongCardView *card, NSTextField *footer,
    CGFloat padding, CGFloat height, CGFloat textWidth);

#pragma mark - 输入行

/// 一行 OCR 文本。保留原文、矩形、识别置信度与来源下标。
@interface FYInlineTextLine : NSObject
@property (nonatomic, copy) NSString *text;
/// 归一化页面坐标（原点左下）。
@property (nonatomic) CGRect rect;
/// Vision 置信度 0..1；无法取得时填 0。
@property (nonatomic) CGFloat confidence;
/// 调用方原始输入下标，便于回溯到具体 OCR 结果。
@property (nonatomic) NSInteger sourceIndex;
+ (instancetype)lineWithText:(NSString *)text
                        rect:(CGRect)rect
                  confidence:(CGFloat)confidence
                 sourceIndex:(NSInteger)sourceIndex;
@end

#pragma mark - 文本块

typedef NS_ENUM(NSInteger, FYInlineBlockKind) {
    FYInlineBlockKindShort = 0,  // 短标签／菜单项／按钮：穿透小贴片
    FYInlineBlockKindLong = 1,   // 连续正文：可点击的阅读卡
};

/// 分组后的文本块。
/// 注意：boundingBox 表示**文字位置**，不等于已经识别出完整游戏面板；
/// 布局只把其它块的文字区域当作“不可遮挡区域”，未检测到文字不等于那里没有控件。
@interface FYInlineTextBlock : NSObject
/// 稳定身份（文本 + 量化行框）。同一文字出现在不同位置时身份不同。
@property (nonatomic, copy) NSString *blockID;
/// 保留 OCR 原始换行：同一行内的片段用空格，换行用 \n。
@property (nonatomic, copy) NSString *text;
@property (nonatomic, copy) NSArray<NSString *> *lineTexts;
@property (nonatomic, copy) NSArray<NSValue *> *lineBoxes;      // 归一化
@property (nonatomic, copy) NSArray<NSNumber *> *lineConfidences;
@property (nonatomic, copy) NSArray<NSNumber *> *sourceIndices;
@property (nonatomic) CGRect boundingBox;                        // 归一化并集
@property (nonatomic) FYInlineBlockKind kind;
/// 分组的把握程度 0..1：单行 1.0；多行取每次合并证据的最小值。
@property (nonatomic) CGFloat groupingConfidence;
@property (nonatomic) NSInteger readingOrder;
/// 行数（= lineTexts.count）。
@property (nonatomic, readonly) NSInteger lineCount;
@end

#pragma mark - 分组器

@interface FYInlineGrouper : NSObject
/// 一个块允许的最大高度（归一化）。超过就不再并——防止把整屏竖排条目并成一大段。
/// 真正的防跨栏/防菜单合并靠列间隙、字号与正文证据判定；这个上限只挡“整屏竖直全并”。
@property (nonatomic) CGFloat maxBlockHeightFraction;   // 默认 0.55
/// 小于这个字符数的行直接丢弃（OCR 噪声）。
@property (nonatomic) NSInteger minimumCharacters;      // 默认 2
/// 可选：调用方的“这是按钮/菜单词”判定（例如「戻る」「詳細」），命中即按短标签处理。
@property (nonatomic, copy, nullable) BOOL (^shortLabelDetector)(NSString *normalizedText);
+ (instancetype)defaultGrouper;

/// 文本 + 位置联合去重：同一处重复识别只留置信度更高的一条，
/// **不同位置**的相同文字必须都保留。
- (NSArray<FYInlineTextLine *> *)deduplicatedLines:(NSArray<FYInlineTextLine *> *)lines;
/// 分组主入口。返回按阅读顺序排列的块。
- (NSArray<FYInlineTextBlock *> *)blocksFromLines:(NSArray<FYInlineTextLine *> *)lines;
/// 单块分类（导出给调用方复用同一套判定）。
- (FYInlineBlockKind)kindForLines:(NSArray<FYInlineTextLine *> *)lines
                       normalized:(nullable NSString *)normalizedText;
@end

#pragma mark - 布局输入

/// 一个待排版的块：块身份 + 译文 + 已换算到显示区域的原文框。
@interface FYInlineLayoutRequest : NSObject
@property (nonatomic, strong) FYInlineTextBlock *block;
@property (nonatomic, copy) NSString *translation;
/// 显示区域坐标下的原文矩形。
@property (nonatomic) CGRect sourceFrame;
/// 用户手动拖动过的块：按「相对原文框原点的偏移」定位，布局器不再为它挑候选，
/// 只做可见区域夹取。偏移由调用方保存，块消失后自行丢弃。
@property (nonatomic) BOOL manuallyPlaced;
@property (nonatomic) CGSize manualOffset;
+ (instancetype)requestWithBlock:(FYInlineTextBlock *)block
                     translation:(NSString *)translation
                     sourceFrame:(CGRect)sourceFrame;
@end

#pragma mark - 布局结果

typedef NS_ENUM(NSInteger, FYInlineDisplayMode) {
    FYInlineDisplayModeShortLabel = 0,     // 穿透小贴片
    FYInlineDisplayModeFullCard = 1,       // 完整长卡（正文全部可见）
    FYInlineDisplayModeScrollingCard = 2,  // 长卡，正文超出视口、卡内滚动
    FYInlineDisplayModeCompactEntry = 3,   // 空间不足：「查看译文」紧凑入口
    FYInlineDisplayModeUnplaceable = 4,    // 连紧凑入口都没有合法位置
};

typedef NS_ENUM(NSInteger, FYInlineAnchor) {
    FYInlineAnchorNone = 0,
    FYInlineAnchorBelow,        // 原文下方近邻（默认首选）
    FYInlineAnchorAbove,        // 原文上方近邻
    FYInlineAnchorRight,        // 原文右侧近邻
    FYInlineAnchorLeft,         // 原文左侧近邻
    FYInlineAnchorOverlay,      // 只覆盖原文自身正文区域
    FYInlineAnchorCompactEntry, // 紧凑入口
    FYInlineAnchorManual,       // 用户拖动后的位置
};

/// 一块的最终排版。字体/段落样式由布局器给出，渲染必须直接使用它们，
/// 保证「测量与绘制共用同一份样式」。
@interface FYInlinePlacement : NSObject
@property (nonatomic, copy) NSString *blockID;      // 已按帧间匹配稳定化
@property (nonatomic, copy) NSString *sourceBlockID; // 本帧分组给出的原始身份
@property (nonatomic, strong) FYInlineTextBlock *block;
@property (nonatomic, copy) NSString *translation;
@property (nonatomic) NSInteger readingOrder;
@property (nonatomic) CGRect sourceFrame;           // 显示坐标
@property (nonatomic) CGRect translationFrame;      // 面板 frame（显示坐标）
/// Diagnostic evidence from the production candidate generator, before collision avoidance.
@property (nonatomic) CGRect initialTranslationFrame;
@property (nonatomic, copy) NSArray<NSDictionary *> *candidateDiagnostics;
/// Finite automatic-origin envelope, in screen points. Manual placements are exempt.
@property (nonatomic) CGRect automaticOriginBounds;
@property (nonatomic) FYInlineDisplayMode mode;
@property (nonatomic) FYInlineAnchor anchor;
/// 这一块的位置来自用户手动拖动（布局器只做了可见区域夹取）。
@property (nonatomic) BOOL manuallyPlaced;
/// 选择原因，人可读（例如「原文下方近邻，无遮挡」／「下方与上方都被遮挡，改为覆盖自身」）。
@property (nonatomic, copy) NSString *reason;
/// 被排除的候选及原因，供诊断与失败样本报告。
@property (nonatomic, copy) NSArray<NSString *> *rejectedCandidates;
@property (nonatomic) CGFloat groupingConfidence;
@property (nonatomic) BOOL matchedPreviousFrame;

// 绘制参数（短贴片与长卡共用同一份测量结果）
@property (nonatomic, strong) NSFont *font;
@property (nonatomic, strong) NSParagraphStyle *paragraphStyle;
@property (nonatomic) CGFloat panelPadding;
@property (nonatomic) CGFloat titleBandHeight;      // 展开阅读卡的标题带；普通贴译为 0
@property (nonatomic) CGFloat cornerRadius;
/// 短贴片：正文标签在面板内的相对矩形（AppKit 坐标，y 向上）。
@property (nonatomic) CGRect labelFrame;
/// 长卡：正文视口在卡内的相对矩形（FYInlineLongCardView 是 flipped，y 向下）。
@property (nonatomic) CGRect bodyViewportFrame;
/// 正文完整测量高度（文档高度），用于滚动范围。
@property (nonatomic) CGFloat measuredContentHeight;
/// 正文视口高度。
@property (nonatomic) CGFloat bodyViewportHeight;
/// 正文是否需要滚动。
@property (nonatomic) BOOL scrollable;
@property (nonatomic) BOOL compactEntry;
/// 折叠入口的三行文案：块标题 / 收起原因 / 「点击展开」动作。
/// 由布局器按同一份字体测量并写进结果，渲染端直接用，保证"量出来的"就是"画出来的"。
@property (nonatomic, copy) NSString *entryTitle;
@property (nonatomic, copy) NSString *entryHint;
@property (nonatomic, copy) NSString *entryAction;
/// YES = 放不下的实际原因是周围空间拥挤（不是文本过长），提示文案不同。
@property (nonatomic) BOOL entryReasonCrowded;
/// YES = 这张卡是"点入口展开出来的阅读卡"：顶部显示块标题。
/// 普通贴译长卡只显示译文，不预留标题带。
@property (nonatomic) BOOL expandedReading;
/// 这一块试过的长卡候选组合（宽/字号/内边距/标题带/结果/冲突块），用于诊断：
/// 区分"文字太长"、"可用空间不足"和"重复块造成假冲突"。
@property (nonatomic, copy) NSArray<NSString *> *variantDiagnostics;
/// 最终采用的长卡候选序号与字号（0 表示首选组合）。
@property (nonatomic) NSUInteger chosenVariant;
@property (nonatomic) CGFloat chosenBodyFontSize;
/// 长卡（完整/滚动）的测量尺寸；只用于诊断与对照。
@property (nonatomic) CGSize longCardSize;
/// 紧凑入口**按内容测量**出来的尺寸（字体 + 标题宽度 + 内边距），不继承长卡宽度。
@property (nonatomic) CGSize compactEntrySize;
@end

@interface FYInlineLayoutResult : NSObject
/// 与输入请求同序，含 unplaceable（便于上报“暂不可放置”的块）。
@property (nonatomic, copy) NSArray<FYInlinePlacement *> *placements;
/// 需要真正显示面板的（排除 unplaceable）。
@property (nonatomic, copy) NSArray<FYInlinePlacement *> *visiblePlacements;
@property (nonatomic, copy) NSArray<NSString *> *unplaceableBlockIDs;
@property (nonatomic, copy) NSArray<NSString *> *compactEntryBlockIDs;
/// 与上一帧相比是否有变化（位置/尺寸/模式/译文任一变化）。
@property (nonatomic) BOOL changedFromPrevious;
@property (nonatomic) NSUInteger revision;
@property (nonatomic) NSUInteger layoutPassCount;
- (nullable FYInlinePlacement *)placementForBlockID:(NSString *)blockID;
@end

#pragma mark - 布局引擎

@interface FYInlineLayoutEngine : NSObject
+ (instancetype)defaultEngine;
/// Opt-in structured candidate evidence. Does not alter scoring or placement.
@property (nonatomic) BOOL collectsLayoutDiagnostics;
/// P0 only: measure and return the first production candidate, without avoidance/history.
- (FYInlinePlacement *)initialPlacementForRequest:(FYInlineLayoutRequest *)request viewport:(CGRect)viewport;

// —— 字号与排版（测量与绘制共用） ——
@property (nonatomic) CGFloat shortFontSize;        // 16
@property (nonatomic) CGFloat coverFontSize;        // 17（长原文/多行原文的覆盖式贴片）
@property (nonatomic) CGFloat longBodyFontSize;     // 19
@property (nonatomic) CGFloat longTitleFontSize;    // 14
@property (nonatomic) CGFloat longLineSpacing;      // 8
@property (nonatomic) NSInteger minimumBodyLines;   // 长文滚动时的最少可见行数，默认 3；短译文按内容收紧
@property (nonatomic) CGFloat cardMaxWidth;         // 560
@property (nonatomic) CGFloat cardWidthFraction;    // 0.52
@property (nonatomic) CGFloat cardWideFraction;     // 0.62（需要更宽才能减少滚动时）
@property (nonatomic) CGFloat cardMaxHeight;        // 330
@property (nonatomic) CGFloat cardHeightFraction;
/// 正文可读下限：逐档缩字不会低于这个值（默认 15pt）。
@property (nonatomic) CGFloat minimumLongBodyFontSize;
/// 长卡最小宽度（可读下限，默认 160pt）；宽度候选不得低于它，但也不再强制 300pt。
@property (nonatomic) CGFloat minimumCardWidth;
/// 长块尝试过的候选组合（诊断用，最近一次 layoutRequests 的结果）。
@property (nonatomic, copy) NSArray<NSString *> *lastVariantDiagnostics;   // 0.55
@property (nonatomic) CGFloat viewportMargin;       // 8
@property (nonatomic) CGFloat panelGap;             // 4
@property (nonatomic) CGFloat compactEntryHeight;   // 34
/// 紧凑入口（「查看译文」）的标题文案、字号与左右内边距。
/// 测量与绘制必须共用这一份：渲染端读 compactEntryTitle / compactEntryFont 画同一个字符串，
/// 否则"测出来的宽度"和"画出来的文字"会再次不一致。
@property (nonatomic, copy) NSString *compactEntryTitle;        // 兼容旧名：折叠入口动作文案
@property (nonatomic) CGFloat compactEntryFontSize;             // 13
@property (nonatomic) CGFloat compactEntryHorizontalPadding;    // 8
/// 折叠入口文案：没有可靠标题时用的占位标题，以及两种收起原因。
@property (nonatomic, copy) NSString *foldedEntryFallbackTitle;     // 「这段译文」
@property (nonatomic, copy) NSString *foldedEntryHintTooLong;       // 「文本过长，已收起」
@property (nonatomic, copy) NSString *foldedEntryHintCrowded;       // 「空间不足，已收起」
/// 帧间稳定容差（pt）：上一帧已用同一锚定方向时，允许 1~3px 级别的细缝冲突不算遮挡，
/// 避免 OCR 抖动让贴片在下方/上方之间跳；新出现的块（没有上一帧）不受此容差影响。
@property (nonatomic) CGFloat stabilityTolerance;       // 默认 3
/// 短贴片最大宽度占画面宽比例（0.42）与上限（360）。
@property (nonatomic) CGFloat shortWidthFraction;
@property (nonatomic) CGFloat shortMaxWidth;
/// 注入主题字体（生产用 FYUIFont；不注入时用华文圆体，失败回退系统字体）。
@property (nonatomic, copy, nullable) NSFont * (^fontProvider)(CGFloat size, NSFontWeight weight);

/// 统一排版：先为每块生成有限候选、剔除不合法候选，再在合法候选里比较评分。
- (FYInlineLayoutResult *)layoutRequests:(NSArray<FYInlineLayoutRequest *> *)requests
                                viewport:(CGRect)viewport
                                previous:(nullable FYInlineLayoutResult *)previous;

/// 短贴片正文的字体与段落样式（短标签 16pt / 覆盖式 17pt，行距 3）。
- (NSFont *)shortBodyFontForCover:(BOOL)cover;
- (NSParagraphStyle *)shortParagraphStyle;
/// 长卡正文与标题的字体、段落样式（行距 8），绘制必须与测量用同一份。
- (NSFont *)longBodyFont;
- (NSParagraphStyle *)longBodyParagraphStyle;
- (NSFont *)longTitleFont;
/// 紧凑入口的字体（semibold），测量与绘制共用。
- (NSFont *)compactEntryFont;
/// 紧凑入口按内容测量的尺寸：标题文字宽度 + 左右内边距，高度不小于 compactEntryHeight；
/// 上限是可见区域内能放下的宽度。**不继承长卡宽度**。
- (CGSize)compactEntrySizeForViewport:(CGRect)viewport;
/// 长卡的有限候选组合（宽 × 修饰 × 字号），顺序即优先级；诊断与测试都用它。
- (NSArray<NSDictionary *> *)longCardVariantsForRequest:(FYInlineLayoutRequest *)request viewport:(CGRect)viewport;
/// 折叠入口（标题 / 提示 / 点击展开 三行）按内容测量的尺寸。
- (CGSize)foldedEntrySizeForViewport:(CGRect)viewport title:(nullable NSString *)title
                                hint:(nullable NSString *)hint;
/// 同上，但动作行可显式给空串（单行总入口按一行量尺寸）。
- (CGSize)foldedEntrySizeForViewport:(CGRect)viewport title:(nullable NSString *)title
                                hint:(nullable NSString *)hint action:(nullable NSString *)action;
/// 折叠入口的字体（测量与绘制共用）。
- (NSFont *)foldedEntryHintFont;
/// 从块文本里取一个"短标题"：只在首行确实像标题时才用，否则返回 nil（调用方用占位标题）。
+ (nullable NSString *)shortTitleForBlockText:(NSString *)text;

/// 单块测量（给定宽度下的完整正文高度）。渲染器复用同一份样式计算文档高度。
- (CGFloat)measuredBodyHeight:(NSString *)translation
                     placement:(FYInlinePlacement *)placement
                         width:(CGFloat)width;
/// 普通长文滚动卡的最小可读高度（内边距 + N 行正文）；短译文不强制此高度。
- (CGFloat)minimumCardHeight;
@end

#pragma mark - 帧间块匹配

/// 帧间匹配：文本相似 + 位置重叠，避免一两像素抖动就换身份。
@interface FYInlineBlockMatcher : NSObject
/// 文本相似度 0..1（字符二元组 Dice 系数），对 OCR 小抖动稳健。
/// 稳定身份：文本 + 量化行框（同一文字出现在不同位置时身份不同）。
+ (NSString *)blockIDForText:(NSString *)text lineBoxes:(NSArray<NSValue *> *)lineBoxes;
+ (CGFloat)textSimilarity:(NSString *)left right:(NSString *)right;
/// 两个矩形（同一坐标系）的重叠比例，取相对较小面积的比例 0..1。
+ (CGFloat)overlapRatio:(CGRect)left right:(CGRect)right;
/// 判断新块是否对应上一帧的某个排版；是则返回上一帧的 blockID（稳定身份）。
+ (nullable NSString *)stableBlockIDForBlock:(FYInlineTextBlock *)block
                                        text:(NSString *)text
                                 sourceFrame:(CGRect)sourceFrame
                               previousResult:(nullable FYInlineLayoutResult *)previous;
@end

NS_ASSUME_NONNULL_END
