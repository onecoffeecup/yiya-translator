#import "FYStudyChatView.h"
#import "FYLearningViews.h"

// Display cleanup only: original replies remain intact in the conversation.
static NSString *FYChatPlainReply(NSString *content) {
    NSArray *rules=@[
        @[@"(?m)^\\s*```[^\\n]*$",@""],
        @[@"(?m)^#{1,6}[ \t]+",@""],
        @[@"\\*\\*([^*\\n]+)\\*\\*",@"$1"],
        @[@"__([^_\\n]+)__",@"$1"],
        @[@"`([^`\\n]+)`",@"$1"],
        @[@"\\[([^\\]]+)\\]\\((https?://[^)]+)\\)",@"$1（$2）"],
        @[@"(?m)^[ \t]*[-*][ \t]+",@"• "]
    ];
    for(NSArray *rule in rules){NSRegularExpression *regex=[NSRegularExpression regularExpressionWithPattern:rule[0] options:0 error:NULL];content=[regex stringByReplacingMatchesInString:content options:0 range:NSMakeRange(0,content.length) withTemplate:rule[1]];}
    return [content stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

@interface FYStudyChatMessagesStackView : NSStackView
@end

@implementation FYStudyChatMessagesStackView
- (BOOL)isFlipped { return YES; }
@end

@interface FYStudyChatInputView : NSTextView
@property(nonatomic, copy) void (^sendOnReturn)(void);
@end

@implementation FYStudyChatInputView
- (BOOL)performKeyEquivalent:(NSEvent *)event {
    NSEventModifierFlags modifiers=event.modifierFlags & NSEventModifierFlagDeviceIndependentFlagsMask;
    modifiers &= ~NSEventModifierFlagCapsLock;
    if(self.window.firstResponder==self && (modifiers==NSEventModifierFlagCommand || modifiers==NSEventModifierFlagControl)){
        NSString *key=event.charactersIgnoringModifiers.lowercaseString;
        if([key isEqualToString:@"c"]){[self copy:nil];return YES;}
        if([key isEqualToString:@"v"]){[self paste:nil];return YES;}
        if([key isEqualToString:@"x"]){[self cut:nil];return YES;}
        if([key isEqualToString:@"a"]){[self selectAll:nil];return YES;}
    }
    return [super performKeyEquivalent:event];
}
- (void)keyDown:(NSEvent *)event {
    if((event.modifierFlags & NSEventModifierFlagControl) && [self performKeyEquivalent:event]){return;}
    BOOL isReturn = event.keyCode == 36 || event.keyCode == 76;
    BOOL shift = (event.modifierFlags & NSEventModifierFlagShift) != 0;
    // NSTextView tracks marked text for active IME composition. Let it consume Return.
    if (isReturn && !shift && !self.hasMarkedText && self.sendOnReturn) {
        self.sendOnReturn();
        return;
    }
    [super keyDown:event];
}
@end

@interface FYStudyChatView ()
@property(nonatomic, strong) NSTextField *contextLabel;
@property(nonatomic, strong) NSTextField *contextText;
@property(nonatomic, strong) NSStackView *messagesStack;
@property(nonatomic, strong) NSScrollView *messagesScroll;
@property(nonatomic, strong) FYStudyChatInputView *input;
@property(nonatomic, strong) FYWorkspaceButton *sendButton;
@property(nonatomic, strong) FYWorkspaceButton *inlineReturnButton;
@property(nonatomic, strong) FYWorkspaceButton *closeButton;
@property(nonatomic, strong) NSStackView *suggestionsStack;
@property(nonatomic) BOOL sending;
@property(nonatomic) BOOL messageLayoutUpdateScheduled;
@property(nonatomic) BOOL messageSizingNeeded;
@property(nonatomic) CGFloat lastMessageLayoutWidth;
@property(nonatomic) BOOL shouldScrollToLatest;
@end

@implementation FYStudyChatView

- (instancetype)initWithFrame:(NSRect)frame {
    self = [super initWithFrame:frame];
    if (!self) return nil;
    [self buildView];
    return self;
}

- (instancetype)initWithCoder:(NSCoder *)coder {
    self = [super initWithCoder:coder];
    if (!self) return nil;
    [self buildView];
    return self;
}

- (void)buildView {
    self.translatesAutoresizingMaskIntoConstraints = NO;
    self.wantsLayer = YES;
    self.layer.backgroundColor = FYAdventureColor(@"ai").CGColor;
    self.layer.cornerRadius = 14;
    self.layer.borderWidth = 1;
    self.layer.borderColor = FYAdventureColor(@"rim").CGColor;
    NSLayoutConstraint *minimumWidth = [self.widthAnchor constraintGreaterThanOrEqualToConstant:280];
    minimumWidth.priority = 750;
    minimumWidth.active = YES;

    NSStackView *root = [NSStackView new];
    root.translatesAutoresizingMaskIntoConstraints = NO;
    root.orientation = NSUserInterfaceLayoutOrientationVertical;
    root.alignment = NSLayoutAttributeLeading;
    root.distribution = NSStackViewDistributionFill;
    root.spacing = 0;
    [self addSubview:root];
    [NSLayoutConstraint activateConstraints:@[
        [root.leadingAnchor constraintEqualToAnchor:self.leadingAnchor],
        [root.trailingAnchor constraintEqualToAnchor:self.trailingAnchor],
        [root.topAnchor constraintEqualToAnchor:self.topAnchor],
        [root.bottomAnchor constraintEqualToAnchor:self.bottomAnchor]
    ]];

    NSView *header = [NSView new];
    header.translatesAutoresizingMaskIntoConstraints = NO;
    NSStackView *heading = [NSStackView new];
    heading.translatesAutoresizingMaskIntoConstraints = NO;
    heading.orientation = NSUserInterfaceLayoutOrientationVertical;
    heading.spacing = 3;
    NSTextField *eyebrow = [NSTextField labelWithString:@"一起读懂日语"];
    eyebrow.font = FYUIFont(10, NSFontWeightMedium);
    eyebrow.textColor = FYAdventureColor(@"quiet");
    NSTextField *title = [NSTextField labelWithString:@"AI 学习伙伴"];
    title.font = FYUIFont(20, NSFontWeightSemibold);
    title.textColor = FYAdventureColor(@"ink");
    [heading addArrangedSubview:eyebrow]; [heading addArrangedSubview:title];
    [header addSubview:heading];
    FYAdventureArtView *book=[FYAdventureArtView new];book.artwork=7;book.translatesAutoresizingMaskIntoConstraints=NO;
    [header addSubview:book];
    [NSLayoutConstraint activateConstraints:@[[book.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:14],
        [book.topAnchor constraintEqualToAnchor:header.topAnchor constant:14],
        [book.widthAnchor constraintEqualToConstant:42],[book.heightAnchor constraintEqualToConstant:42]]];

    FYWorkspaceButton *latest = [FYWorkspaceButton new];
    latest.translatesAutoresizingMaskIntoConstraints = NO;
    latest.title = @"引用最新句"; latest.darkSurface=YES;
    latest.font = FYUIFont(11, NSFontWeightRegular);
    latest.target = self; latest.action = @selector(latestPressed:);
    latest.accessibilityLabel = @"引用最新句";
    [header addSubview:latest];
    FYWorkspaceButton *close = [FYWorkspaceButton new];
    close.translatesAutoresizingMaskIntoConstraints = NO;
    close.title = @"收起"; close.darkSurface=YES;
    close.font = FYUIFont(11, NSFontWeightRegular);
    close.target = self; close.action = @selector(closePressed:);
    close.accessibilityLabel = @"收起 AI 学习对话";
    [header addSubview:close];
    self.closeButton = close;
    // 「‹ 返回语法」放在真正的聊天导航行（与「引用最新句／收起」同一行），
    // 给它独立的布局空间，避免被聊天视图盖住而无法命中。
    FYWorkspaceButton *back = [FYWorkspaceButton new];
    back.translatesAutoresizingMaskIntoConstraints = NO;
    back.title = @"‹ 返回语法"; back.darkSurface=YES;
    back.font = FYUIFont(11, NSFontWeightMedium);
    back.target = self; back.action = @selector(returnPressed:);
    back.accessibilityLabel = @"返回语法";
    back.hidden = YES;
    [header addSubview:back];
    self.inlineReturnButton = back;
    [NSLayoutConstraint activateConstraints:@[
        [header.heightAnchor constraintEqualToConstant:104],
        [heading.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:68],
        [heading.topAnchor constraintEqualToAnchor:header.topAnchor constant:16],
        [close.trailingAnchor constraintEqualToAnchor:header.trailingAnchor constant:-12],
        [close.bottomAnchor constraintEqualToAnchor:header.bottomAnchor constant:-8],
        [latest.trailingAnchor constraintEqualToAnchor:close.leadingAnchor constant:-7],
        [latest.centerYAnchor constraintEqualToAnchor:close.centerYAnchor],
        [back.leadingAnchor constraintEqualToAnchor:header.leadingAnchor constant:12],
        [back.centerYAnchor constraintEqualToAnchor:close.centerYAnchor]
    ]];
    [root addArrangedSubview:header];
    [header.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;

    NSBox *divider = [NSBox new]; divider.boxType = NSBoxSeparator; divider.translatesAutoresizingMaskIntoConstraints = NO;
    [root addArrangedSubview:divider];

    NSStackView *body = [NSStackView new];
    body.translatesAutoresizingMaskIntoConstraints = NO;
    body.orientation = NSUserInterfaceLayoutOrientationVertical;
    body.alignment = NSLayoutAttributeLeading;
    body.spacing = 0;
    [root addArrangedSubview:body];
    [body.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;

    FYAdventureStack *context = [FYAdventureStack new];
    context.translatesAutoresizingMaskIntoConstraints = NO;
    context.orientation = NSUserInterfaceLayoutOrientationVertical;
    context.alignment = NSLayoutAttributeLeading;
    context.spacing = 5;
    context.edgeInsets = NSEdgeInsetsMake(10, 12, 10, 12);
    context.fillColor = FYAdventureColor(@"paper");
    self.contextLabel = [NSTextField labelWithString:@"带着当前句一起问"];
    self.contextLabel.font = FYUIFont(10, NSFontWeightRegular);
    self.contextLabel.textColor = FYAdventureColor(@"quiet");
    self.contextText = [NSTextField wrappingLabelWithString:@""];
    self.contextText.font = FYJapaneseFont(13);
    self.contextText.textColor = FYAdventureColor(@"ink");
    self.contextText.maximumNumberOfLines = 0;
    self.contextText.selectable = YES;
    [context addArrangedSubview:self.contextLabel]; [context addArrangedSubview:self.contextText];
    [body addArrangedSubview:context];
    [self.contextText.widthAnchor constraintLessThanOrEqualToAnchor:context.widthAnchor constant:-24].active = YES;
    [NSLayoutConstraint activateConstraints:@[
        [context.leadingAnchor constraintEqualToAnchor:body.leadingAnchor constant:16],
        [context.trailingAnchor constraintEqualToAnchor:body.trailingAnchor constant:-16],
        [context.topAnchor constraintEqualToAnchor:body.topAnchor constant:14]
    ]];

    self.messagesStack = [FYStudyChatMessagesStackView new];
    self.messagesStack.orientation = NSUserInterfaceLayoutOrientationVertical;
    self.messagesStack.alignment = NSLayoutAttributeLeading;
    self.messagesStack.distribution = NSStackViewDistributionFill;
    self.messagesStack.spacing = 14;
    self.messagesStack.edgeInsets = NSEdgeInsetsMake(2, 0, 8, 0);
    self.messagesScroll = [NSScrollView new];
    self.messagesScroll.translatesAutoresizingMaskIntoConstraints = NO;
    self.messagesScroll.drawsBackground = NO;
    self.messagesScroll.hasHorizontalScroller = NO;
    self.messagesScroll.hasVerticalScroller = YES;
    self.messagesScroll.borderType = NSNoBorder;
    self.messagesScroll.documentView = self.messagesStack;
    [body addArrangedSubview:self.messagesScroll];
    [NSLayoutConstraint activateConstraints:@[
        [self.messagesScroll.leadingAnchor constraintEqualToAnchor:body.leadingAnchor constant:16],
        [self.messagesScroll.trailingAnchor constraintEqualToAnchor:body.trailingAnchor constant:-16],
        [self.messagesScroll.topAnchor constraintEqualToAnchor:context.bottomAnchor constant:12],
        [self.messagesScroll.bottomAnchor constraintEqualToAnchor:body.bottomAnchor]
    ]];
    [self.messagesScroll.heightAnchor constraintGreaterThanOrEqualToConstant:180].active = YES;
    [self.messagesScroll setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationVertical];
    [self.messagesScroll setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationVertical];

    NSBox *composeDivider = [NSBox new]; composeDivider.boxType = NSBoxSeparator; composeDivider.translatesAutoresizingMaskIntoConstraints = NO;
    [root addArrangedSubview:composeDivider];
    NSStackView *composer = [NSStackView new];
    composer.translatesAutoresizingMaskIntoConstraints = NO;
    composer.orientation = NSUserInterfaceLayoutOrientationVertical;
    composer.alignment = NSLayoutAttributeLeading;
    composer.spacing = 9;
    composer.edgeInsets = NSEdgeInsetsMake(12, 15, 14, 15);
    [root addArrangedSubview:composer];
    [composer.widthAnchor constraintEqualToAnchor:root.widthAnchor].active = YES;

    self.suggestionsStack = [NSStackView new];
    self.suggestionsStack.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    self.suggestionsStack.alignment = NSLayoutAttributeCenterY;
    self.suggestionsStack.spacing = 6;
    for (NSString *suggestion in @[@"解释简单一点", @"对比两个用法", @"再举个例子"]) {
        FYWorkspaceButton *button = [FYWorkspaceButton new];
        button.title = suggestion; button.darkSurface=YES; button.font = FYUIFont(10, NSFontWeightRegular);
        button.target = self; button.action = @selector(suggestionPressed:);
        button.accessibilityLabel = suggestion;
        [self.suggestionsStack addArrangedSubview:button];
    }
    [composer addArrangedSubview:self.suggestionsStack];

    FYAdventurePanel *inputShell = [FYAdventurePanel new];
    inputShell.translatesAutoresizingMaskIntoConstraints = NO;
    inputShell.fillColor=FYAdventureColor(@"paper");
    [composer addArrangedSubview:inputShell];
    self.input = [FYStudyChatInputView new];
    self.input.translatesAutoresizingMaskIntoConstraints = NO;
    self.input.font = FYUIFont(14, NSFontWeightRegular);
    self.input.textColor = FYAdventureColor(@"ink");
    self.input.insertionPointColor=FYAdventureColor(@"ink");
    self.input.backgroundColor = NSColor.clearColor;
    self.input.drawsBackground = NO;
    self.input.richText = NO;
    self.input.importsGraphics = NO;
    self.input.allowsUndo = YES;
    self.input.minSize = NSMakeSize(0, 0);
    self.input.maxSize = NSMakeSize(CGFLOAT_MAX, CGFLOAT_MAX);
    self.input.verticallyResizable = YES;
    self.input.horizontallyResizable = NO;
    self.input.textContainer.widthTracksTextView = YES;
    self.input.textContainer.containerSize = NSMakeSize(260, CGFLOAT_MAX);
    self.input.textContainerInset = NSMakeSize(2, 5);
    self.input.accessibilityLabel = @"向 AI 提问";
    self.input.accessibilityPlaceholderValue = @"问一句，不用离开游戏画面……";
    [inputShell addSubview:self.input];
    [NSLayoutConstraint activateConstraints:@[
        [self.input.leadingAnchor constraintEqualToAnchor:inputShell.leadingAnchor constant:9],
        [self.input.trailingAnchor constraintEqualToAnchor:inputShell.trailingAnchor constant:-9],
        [self.input.topAnchor constraintEqualToAnchor:inputShell.topAnchor constant:5],
        [self.input.bottomAnchor constraintEqualToAnchor:inputShell.bottomAnchor constant:-5],
        [inputShell.heightAnchor constraintGreaterThanOrEqualToConstant:78]
    ]];
    __weak typeof(self) weakSelf = self;
    self.input.sendOnReturn = ^{ [weakSelf sendCurrentText]; };

    NSStackView *actions = [NSStackView new];
    actions.translatesAutoresizingMaskIntoConstraints = NO;
    actions.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    actions.alignment = NSLayoutAttributeCenterY;
    actions.distribution = NSStackViewDistributionFill;
    actions.spacing = 8;
    NSTextField *hint = [NSTextField labelWithString:@"Enter 发送 · Shift + Enter 换行"];
    hint.font = FYUIFont(9, NSFontWeightRegular);
    hint.textColor = FYAdventureColor(@"quiet");
    self.sendButton = [FYWorkspaceButton new];
    self.sendButton.primary = YES;
    self.sendButton.title = @"发送 ↑";
    self.sendButton.font = FYUIFont(11, NSFontWeightMedium);
    self.sendButton.target = self; self.sendButton.action = @selector(sendPressed:);
    self.sendButton.accessibilityLabel = @"发送消息";
    [actions addArrangedSubview:hint]; [actions addArrangedSubview:self.sendButton];
    [composer addArrangedSubview:actions];
    [actions.widthAnchor constraintEqualToAnchor:composer.widthAnchor constant:-30].active = YES;
    [hint setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self.sendButton setContentHuggingPriority:999 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [self addInitialMessage];
}

- (void)addInitialMessage {
    [self setMessages:@[@{@"role": @"assistant", @"content": @"哪里没看懂，可以直接问我。你可以问这一句的意思，也可以问某个词为什么这样用。"}]];
}

- (NSView *)messageViewForDictionary:(NSDictionary *)message {
    NSString *role = [message[@"role"] isKindOfClass:NSString.class] ? message[@"role"] : @"assistant";
    NSString *content = [message[@"content"] isKindOfClass:NSString.class] ? message[@"content"] : @"";
    NSString *rawStatus = [message[@"status"] isKindOfClass:NSString.class] ? message[@"status"] : nil;
    NSString *status = nil;
    NSString *normalizedStatus = rawStatus.lowercaseString;
    BOOL user = [role isEqualToString:@"user"];
    if ([normalizedStatus isEqualToString:@"error"] || [normalizedStatus isEqualToString:@"failed"] || [normalizedStatus isEqualToString:@"failure"]) {
        status = user ? @"发送失败" : @"回复失败";
    } else if ([normalizedStatus isEqualToString:@"sending"] || [normalizedStatus isEqualToString:@"pending"]) {
        status = user ? @"正在发送" : @"正在回复";
    } else if ([normalizedStatus isEqualToString:@"streaming"] || [normalizedStatus isEqualToString:@"thinking"]) {
        status = @"正在回复";
    } else if (rawStatus.length && [rawStatus rangeOfCharacterFromSet:[NSCharacterSet characterSetWithCharactersInString:@"\u3400-\u9fff"]].location != NSNotFound) {
        status = rawStatus;
    }
    NSStackView *container = [NSStackView new];
    container.orientation = NSUserInterfaceLayoutOrientationVertical;
    container.alignment = user ? NSLayoutAttributeTrailing : NSLayoutAttributeLeading;
    container.spacing = 4;
    NSTextField *speaker = [NSTextField labelWithString:user ? @"你" : @"AI 学习伙伴"];
    speaker.font = FYUIFont(10, NSFontWeightRegular);
    speaker.textColor = FYAdventureColor(@"quiet");
    NSTextField *body = [NSTextField wrappingLabelWithString:user ? content : FYChatPlainReply(content)];
    body.font = FYUIFont(13, NSFontWeightRegular);
    body.textColor = FYAdventureColor(@"ink");
    body.maximumNumberOfLines = 0;
    body.preferredMaxLayoutWidth=240;
    body.selectable = YES;
    body.cell.wraps = YES;
    body.lineBreakMode = NSLineBreakByCharWrapping;
    body.cell.scrollable = NO;
    body.accessibilityLabel = user ? @"你的消息" : @"AI 回复";
    [body setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [body setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    if (status.length) {
        NSTextField *statusLabel = [NSTextField labelWithString:status];
        statusLabel.font = FYUIFont(10, NSFontWeightRegular);
        statusLabel.textColor = FYAdventureColor(@"quiet");
        [container addArrangedSubview:statusLabel];
        [statusLabel setContentCompressionResistancePriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    }
    [container addArrangedSubview:speaker];
    FYAdventurePanel *bubble = [FYAdventurePanel new];bubble.identifier=user?@"chat-user-bubble":@"chat-assistant-bubble";
    bubble.fillColor=FYAdventureColor(user?@"mint":@"paper");bubble.speechBubble=YES;
    [bubble addSubview:body];body.translatesAutoresizingMaskIntoConstraints=NO;
    [container addArrangedSubview:bubble];
    if(!user){[bubble.widthAnchor constraintEqualToAnchor:container.widthAnchor multiplier:0.94].active=YES;}
    [NSLayoutConstraint activateConstraints:@[
        [bubble.widthAnchor constraintLessThanOrEqualToAnchor:container.widthAnchor multiplier:user?0.88:0.94],
        [body.leadingAnchor constraintEqualToAnchor:bubble.leadingAnchor constant:12],
        [body.trailingAnchor constraintEqualToAnchor:bubble.trailingAnchor constant:-12],
        [body.topAnchor constraintEqualToAnchor:bubble.topAnchor constant:10],
        [body.bottomAnchor constraintEqualToAnchor:bubble.bottomAnchor constant:-10]
    ]];
    return container;
}

- (void)setFrameSize:(NSSize)newSize {
    NSSize oldSize = self.frame.size;
    [super setFrameSize:newSize];
    if (self.messagesScroll && (fabs(oldSize.width - newSize.width) > 0.5 || self.messageSizingNeeded)) {
        [self scheduleMessagesLayoutUpdate];
    }
}

- (void)viewDidMoveToWindow {
    [super viewDidMoveToWindow];
    [self scheduleMessagesLayoutUpdate];
}

- (void)scheduleMessagesLayoutUpdate {
    self.messageSizingNeeded = YES;
    if (self.messageLayoutUpdateScheduled || !self.messagesStack || !self.messagesScroll) return;
    self.messageLayoutUpdateScheduled = YES;
    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        FYStudyChatView *strongSelf = weakSelf;
        if (!strongSelf) return;
        strongSelf.messageLayoutUpdateScheduled = NO;
        // The document is frame-driven. Never constrain its width back to the
        // clip view: empty-document fitting size must not resize the window.
        CGFloat width = NSWidth(strongSelf.messagesScroll.contentView.bounds);
        if (width <= 0) return;
        BOOL widthChanged = fabs(width - strongSelf.lastMessageLayoutWidth) > 0.5;
        if (widthChanged || strongSelf.messageSizingNeeded) {
            strongSelf.messageSizingNeeded = NO;
            strongSelf.lastMessageLayoutWidth = width;
            for(NSStackView *message in strongSelf.messagesStack.arrangedSubviews){
                NSView *bubble=message.arrangedSubviews.lastObject;
                NSTextField *body=(NSTextField *)bubble.subviews.firstObject;
                if([body isKindOfClass:NSTextField.class]){
                    body.preferredMaxLayoutWidth=MAX(40,width*([bubble.identifier isEqualToString:@"chat-user-bubble"]?0.88:0.94)-24);
                    [body invalidateIntrinsicContentSize];
                }
            }
            CGFloat currentHeight = MAX(1, NSHeight(strongSelf.messagesStack.frame));
            [strongSelf.messagesStack setFrameSize:NSMakeSize(width, currentHeight)];
            CGFloat fittingHeight = MAX(1, strongSelf.messagesStack.fittingSize.height);
            NSSize targetSize = NSMakeSize(width, fittingHeight);
            NSSize oldSize = strongSelf.messagesStack.frame.size;
            if (fabs(oldSize.width - targetSize.width) > 0.5 || fabs(oldSize.height - targetSize.height) > 0.5) {
                [strongSelf.messagesStack setFrameSize:targetSize];
            }
        }
        if (strongSelf.shouldScrollToLatest) {
            strongSelf.shouldScrollToLatest = NO;
            NSClipView *clip = strongSelf.messagesScroll.contentView;
            CGFloat latestY = MAX(0, NSHeight(strongSelf.messagesStack.frame) - NSHeight(clip.bounds));
            [clip scrollToPoint:NSMakePoint(0, latestY)];
            [strongSelf.messagesScroll reflectScrolledClipView:clip];
        }
    });
}

- (void)setContextText:(NSString *)text label:(NSString *)label {
    self.contextText.stringValue = text ?: @"";
    self.contextLabel.stringValue = label.length ? label : @"带着当前句一起问";
}

- (void)setMessages:(NSArray<NSDictionary *> *)messages {
    for (NSView *view in self.messagesStack.arrangedSubviews.copy) {
        [self.messagesStack removeArrangedSubview:view];
        [view removeFromSuperview];
    }
    for (NSDictionary *message in messages) {
        if (![message isKindOfClass:NSDictionary.class]) continue;
        NSView *messageView = [self messageViewForDictionary:message];
        [self.messagesStack addArrangedSubview:messageView];
        [messageView.widthAnchor constraintEqualToAnchor:self.messagesStack.widthAnchor].active = YES;
    }
    self.shouldScrollToLatest = YES;
    [self scheduleMessagesLayoutUpdate];
}

- (void)setSending:(BOOL)sending {
    _sending = sending;
    self.sendButton.enabled = !sending;
    self.sendButton.title = sending ? @"发送中…" : @"发送 ↑";
    self.input.accessibilityHelp = sending ? @"正在发送" : nil;
}

- (void)restoreDraftText:(NSString *)text {
    if (self.input.string.length == 0 && text.length > 0) self.input.string = text;
}

- (void)setDraftText:(NSString *)text {
    self.input.string = text ?: @"";
}

- (void)setReturnVisible:(BOOL)visible {
    self.inlineReturnButton.hidden = !visible;
}

// 主内容区已有唯一的显隐开关：侧栏内的「收起」不再需要，隐藏它。
- (void)setCloseVisible:(BOOL)visible {
    self.closeButton.hidden = !visible;
}

- (NSButton *)returnButton { return self.inlineReturnButton; }

- (void)focusInput {
    if (self.window) [self.window makeFirstResponder:self.input];
}

- (void)sendCurrentText {
    if (self.sending) return;
    NSString *text = self.input.string ?: @"";
    if (text.length == 0 || [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length == 0) return;
    if (self.onSend) {
        self.onSend(text);
        // The owner sets sending synchronously only when it accepts the request.
        if (self.sending) self.input.string = @"";
    }
}
- (void)sendPressed:(id)sender { [self sendCurrentText]; }
- (void)closePressed:(id)sender { if (self.onClose) self.onClose(); }
- (void)latestPressed:(id)sender { if (self.onLatest) self.onLatest(); }
- (void)returnPressed:(id)sender { if (self.onReturn) self.onReturn(); }
- (void)suggestionPressed:(FYWorkspaceButton *)sender {
    if (self.sending) return;
    self.input.string = sender.title;
    [self.window makeFirstResponder:self.input];
    [self sendCurrentText];
}

@end
