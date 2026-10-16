#pragma once
#import "FYInlineTextModels.h"
#import "FYInlineGrouping.h"
NS_ASSUME_NONNULL_BEGIN
/// Foundation/CG owns calculation and configuration. Geometry helpers need no
/// native objects; full text layout is used through the native Engine subclass,
/// whose synchronous measurement actions preserve the concrete receiver.
@interface FYInlineLayoutCalculator : NSObject
+ (instancetype)defaultCalculator;
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
FOUNDATION_EXPORT void FYConfigureInlineLayoutDefaults(FYInlineLayoutCalculator *calculator);
NS_ASSUME_NONNULL_END
