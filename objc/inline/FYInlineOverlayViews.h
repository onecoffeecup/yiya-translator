#pragma once
#import <AppKit/AppKit.h>
#import "FYInlineCardPressState.h"
#import "FYInlineRenderingGeometry.h"
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
@interface FYInlineLongCardView : NSView <FYInlineCardPressStateSource, FYInlineCardPressNativeActions>
@property(nonatomic, strong, readonly, nonnull) FYInlineCardPressState *pressState;
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

FOUNDATION_EXPORT void FYInstallInlineLongCardFooter(FYInlineLongCardView *card, NSTextField *footer,
    CGFloat padding, CGFloat height, CGFloat textWidth);


NS_ASSUME_NONNULL_END
