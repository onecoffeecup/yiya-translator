#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
// Models retain the original style objects without creating or measuring them.
@class NSFont, NSParagraphStyle;
NS_ASSUME_NONNULL_BEGIN
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

NS_ASSUME_NONNULL_END
