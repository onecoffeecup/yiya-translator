#import <Cocoa/Cocoa.h>

NS_ASSUME_NONNULL_BEGIN

@interface FYStudyChatView : NSView
@property(nonatomic, copy, nullable) void (^onSend)(NSString *text);
@property(nonatomic, copy, nullable) void (^onClose)(void);
@property(nonatomic, copy, nullable) void (^onLatest)(void);
@property(nonatomic, copy, nullable) void (^onReturn)(void);

- (void)setContextText:(nullable NSString *)text label:(nullable NSString *)label;
- (void)setMessages:(NSArray<NSDictionary *> *)messages;
- (void)setSending:(BOOL)sending;
- (void)restoreDraftText:(NSString *)text;
// 无条件设置输入框内容（换块时清空草稿用）。
- (void)setDraftText:(NSString *)text;
// 「‹ 返回语法」只在有有效语法来源快照时出现。
- (void)setReturnVisible:(BOOL)visible;
// 侧栏内的「收起」按钮：主内容区已有唯一显隐开关时隐藏它。
- (void)setCloseVisible:(BOOL)visible;
// 供容器做命中/布局检查。
@property(nonatomic, readonly, nullable) NSButton *returnButton;
- (void)focusInput;
@end

NS_ASSUME_NONNULL_END
