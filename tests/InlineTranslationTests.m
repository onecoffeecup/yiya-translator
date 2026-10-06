#define main FuyiAppMain
#import "../objc/LiveCaptionTranslator.m"
#undef main

static OCRTextItem *Item(NSString *text, CGRect box) {
    OCRTextItem *item = [[OCRTextItem alloc] init];
    item.text = text;
    item.boundingBox = box;
    return item;
}

// 贴译正文的文字不透明度（外观规范：背景 0.85、文字完全不透明）。
// 正文是用 attributedStringValue 设置的，所以优先读属性里的前景色，再退回 textColor。
static CGFloat InlineTextAlpha(NSTextField *label) {
    if (![label isKindOfClass:NSTextField.class] || label.attributedStringValue.length == 0) {
        return label.textColor.alphaComponent;
    }
    NSColor *color = [label.attributedStringValue attribute:NSForegroundColorAttributeName atIndex:0 effectiveRange:NULL];
    return color ? color.alphaComponent : label.textColor.alphaComponent;
}

static CGFloat themedLabelTextAlpha(NSPanel *panel) {
    NSTextField *label = (NSTextField *)panel.contentView.subviews.firstObject;
    return InlineTextAlpha(label);
}

// 数 caption label 被重新赋 font 的次数（updateCaptionAppearance 每次都会赋值 → 触发重排）
@interface CountingLabel : NSTextField
@property(nonatomic) NSInteger fontSetCount;
@end

@implementation CountingLabel
- (void)setFont:(NSFont *)font {
    self.fontSetCount += 1;
    [super setFont:font];
}
@end

@interface WindowRecoveryTestApp : AppDelegate
@property(nonatomic, strong) NSArray<WindowItem *> *testWindows;
@end

@implementation WindowRecoveryTestApp
- (NSArray<WindowItem *> *)availableWindowItems { return self.testWindows; }
- (CGImageRef)copyFullCapturedImageForWindow:(uint32_t)windowID { return nil; }
@end

static WindowItem *TestWindow(uint32_t windowID, NSString *name) {
    WindowItem *item = [[WindowItem alloc] init];
    item.windowID = windowID;
    item.displayName = name;
    item.bounds = CGRectMake(0, 0, 800, 600);
    return item;
}

static void Check(BOOL condition, NSString *message) {
    if (!condition) {
        NSLog(@"FAIL: %@", message);
        exit(1);
    }
}

int main(void) {
    @autoreleasepool {
        [NSApplication sharedApplication];
        AppDelegate *app = [[AppDelegate alloc] init];
        app.captionFontSizeSlider = [NSSlider sliderWithValue:30 minValue:12 maxValue:48 target:nil action:nil];
        app.captionOpacitySlider = [NSSlider sliderWithValue:0.7 minValue:0 maxValue:1 target:nil action:nil];

        NSArray *items = @[
            Item(@"季節は秋へ。ファッションも", CGRectMake(0.32, 0.66, 0.22, 0.031)),
            Item(@"秋仕様に切り替えて", CGRectMake(0.32, 0.62, 0.19, 0.031)),
            Item(@"右側の別の会話です", CGRectMake(0.68, 0.62, 0.20, 0.031)),
            Item(@"映画公演スケジュール", CGRectMake(0.07, 0.57, 0.20, 0.028)),
            Item(@"イベント公演スケジュール", CGRectMake(0.07, 0.49, 0.23, 0.028))
        ];
        NSArray<OCRTextItem *> *blocks = [app mergedInlineTextItemsFromItems:items];
        Check(blocks.count == 4, @"paragraph lines should merge without crossing columns or menu rows");
        Check([blocks[0].text containsString:@"\n"], @"paragraph should preserve a line break");
        Check(CGRectGetMaxX(blocks[0].boundingBox) < 0.60, @"left paragraph should stay in its column");

        // 长短块分类：连续正文是大卡，短按钮/独立短条目保持穿透小贴片。
        NSArray<OCRTextItem *> *longParagraph = @[
            Item(@"この春の新作コレクションをご紹介します。", CGRectMake(0.12, 0.70, 0.50, 0.032)),
            Item(@"お好みのアイテムをぜひ手に取ってご覧ください。", CGRectMake(0.12, 0.66, 0.52, 0.032)),
            Item(@"店頭では限定の特典もご用意しております。", CGRectMake(0.12, 0.62, 0.51, 0.032))
        ];
        NSArray<OCRTextItem *> *longBlocks = [app mergedInlineTextItemsFromItems:longParagraph];
        Check(longBlocks.count == 1 && longBlocks[0].blockKind == InlineBlockKindLong,
              @"continuous multi-line prose must merge into one long card");
        Check(longBlocks[0].lineCount == 3, @"long block must retain its source lines for diagnostics");

        NSArray<OCRTextItem *> *buttonColumn = @[
            Item(@"詳細", CGRectMake(0.80, 0.70, 0.08, 0.024)),
            Item(@"戻る", CGRectMake(0.80, 0.66, 0.07, 0.024)),
            Item(@"更新", CGRectMake(0.80, 0.62, 0.07, 0.024))
        ];
        NSArray<OCRTextItem *> *buttonBlocks = [app mergedInlineTextItemsFromItems:buttonColumn];
        Check(buttonBlocks.count == 3, @"stacked short buttons must stay separate entries");
        for (OCRTextItem *block in buttonBlocks) { Check(block.blockKind == InlineBlockKindShort, @"a short button must classify as a passthrough patch"); }

        OCRTextItem *singleLabel = Item(@"公演日程", CGRectMake(0.07, 0.72, 0.12, 0.028));
        singleLabel = [app mergedInlineTextItemsFromItems:@[singleLabel]].firstObject;
        Check(singleLabel.blockKind == InlineBlockKindShort, @"a single short label must stay a small patch");

        OCRTextItem *singleLong = Item(@"このたびはご来店いただき誠にありがとうございます。", CGRectMake(0.10, 0.72, 0.46, 0.032));
        singleLong = [app mergedInlineTextItemsFromItems:@[singleLong]].firstObject;
        Check(singleLong.blockKind == InlineBlockKindLong, @"a single long line must classify as a long card");

        // 同一行被 OCR 切成两段的小片段必须并回一行，不能留下残缺孤立片段。
        // 这里按几何判定（同行 + 紧邻），不针对任何具体文案写死过滤。
        OCRTextItem *splitHead = Item(@"（恋愛モード", CGRectMake(.30, .50, .14, .030));
        OCRTextItem *splitTail = Item(@"）を選ぶ", CGRectMake(.445, .50, .07, .030));
        NSArray<OCRTextItem *> *splitMerged = [app mergedInlineTextItemsFromItems:@[splitHead, splitTail]];
        Check(splitMerged.count == 1 && [splitMerged.firstObject.text containsString:@"恋愛"] &&
              [splitMerged.firstObject.text containsString:@"選ぶ"],
              @"a line split by OCR must merge, not leave an orphan fragment like （恋愛");
        // 不同行的两个短条目仍然保持分开（菜单项不能被并成一段）
        OCRTextItem *menuTop = Item(@"公演日程", CGRectMake(.05, .80, .13, .026));
        OCRTextItem *menuBottom = Item(@"イベント", CGRectMake(.05, .72, .13, .026));
        NSArray<OCRTextItem *> *menuMerged = [app mergedInlineTextItemsFromItems:@[menuTop, menuBottom]];
        Check(menuMerged.count == 2, @"two stacked menu entries must stay separate blocks");

        NSRect window = NSMakeRect(0, 0, 1000, 700);
        NSPanel *shortPanel = [app inlinePanelForTranslation:@"电影公演日程"
                                                   sourceText:@"映画公演スケジュール"
                                                  sourceFrame:NSMakeRect(70, 400, 200, 24)
                                                  windowFrame:window];
        Check(NSWidth(shortPanel.frame) < 180, @"short translation box should fit its text");

        NSString *longText = @"季节转入秋天，时尚也换上秋装。可爱的装扮依然适合成熟的风格，大家都可以找到喜欢的搭配。";
        NSPanel *longPanel = [app inlinePanelForTranslation:longText
                                                  sourceText:@"季節は秋へ。\nファッションも秋仕様に切り替えて"
                                                 sourceFrame:NSMakeRect(320, 400, 260, 60)
                                                 windowFrame:window];
        NSTextField *label = (NSTextField *)longPanel.contentView.subviews.firstObject;
        Check(NSWidth(longPanel.frame) <= 372, @"inline panel must stay within the inline max width instead of overflowing");
        Check(NSHeight(longPanel.frame) > 60, @"wrapped translation should grow vertically");
        Check(label.maximumNumberOfLines == 0 && label.cell.wraps, @"translation label should wrap without a line limit");
        Check(label.font.pointSize >= 15, @"inline translation must keep a readable font size instead of shrinking to fit");

        // —— 贴译主题必须与字幕外观设置分开 ——
        // 把字幕切成「黑底白字 + 低透明度」，贴译仍必须是奶油棕，不能被旧字幕样式覆盖。
        app.captionThemeControl = [NSSegmentedControl segmentedControlWithLabels:@[@"黑底白字", @"白底黑字", @"粉底深字", @"译芽花境"] trackingMode:NSSegmentSwitchTrackingSelectOne target:nil action:nil];
        app.captionThemeControl.selectedSegment = 0;
        app.captionOpacitySlider = [NSSlider sliderWithValue:0.2 minValue:0 maxValue:1 target:nil action:nil];
        NSPanel *themedPanel = [app inlinePanelForTranslation:@"电影公演日程"
                                                 sourceText:@"映画公演スケジュール"
                                                sourceFrame:NSMakeRect(70, 400, 200, 24)
                                                windowFrame:window];
        NSColor *inlineFill = themedPanel.contentView.layer.backgroundColor ? [NSColor colorWithCGColor:themedPanel.contentView.layer.backgroundColor] : nil;
        NSColor *cream = FYAdventureColor(@"cream");
        NSColor *ink = FYAdventureColor(@"ink");
        // 贴译底色 alpha 跟随应用现有「背景透明度」设置（本轮用户要求：不写死、不加第二套设置）；
        // 颜色本身必须仍是贴译主题的奶油色，绝不能被子字幕的黑底主题带偏；文字保持完全不透明。
        Check(inlineFill != nil && fabs(inlineFill.redComponent - cream.redComponent) < 0.03 &&
              fabs(inlineFill.greenComponent - cream.greenComponent) < 0.03 &&
              fabs(inlineFill.alphaComponent - 0.2) < 0.03,
              [NSString stringWithFormat:@"inline patch must keep the cream fill and follow the background-opacity setting (alpha %.2f)", inlineFill.alphaComponent]);
        Check(themedLabelTextAlpha(themedPanel) >= 0.99, @"inline patch text must stay fully opaque");
        NSTextField *themedLabel = (NSTextField *)themedPanel.contentView.subviews.firstObject;
        Check([themedLabel.textColor isEqual:ink], @"inline patch text must be the theme brown, not caption white");
        Check(themedPanel.ignoresMouseEvents, @"short patches must keep click-through");
        Check(fabs(NSMinX(themedPanel.frame) - 70) < 2 && NSMaxY(themedPanel.frame) <= 401,
              @"a short patch must sit below its source line, left-aligned");

        // —— 长阅读卡：奶油近实底 + 「中文译文」标题 + 正文滚动 ——
        OCRTextItem *longItem = [OCRTextItem new];
        longItem.text = @"複数の段落からなる長い本文です。\n行が続きます。\nさらに続きます。";
        longItem.boundingBox = CGRectMake(0.2, 0.2, 0.5, 0.12);
        longItem.lineBoxes = @[[NSValue valueWithRect:CGRectMake(0.2, 0.2, 0.5, 0.04)],
                               [NSValue valueWithRect:CGRectMake(0.2, 0.25, 0.5, 0.04)],
                               [NSValue valueWithRect:CGRectMake(0.2, 0.30, 0.5, 0.04)]];
        longItem.lineCount = 3;
        longItem.blockKind = InlineBlockKindLong;
        NSPanel *longCard = [app inlineLongPanelForTranslation:@"这是一段很长的中文译文，用来验证长阅读卡的标题、内边距、行距与滚动区域。内容需要足够长才会超过卡片最大高度，从而出现可滚动范围。再多写一些，确保真的产生滚动。" item:longItem frame:NSMakeRect(120, 120, 380, 150)];
        Check(!longCard.ignoresMouseEvents, @"the long reading card must accept its own clicks");
        NSScrollView *cardScroll = nil; NSTextField *cardTitle = nil;
        for (NSView *child in longCard.contentView.subviews) {
            if ([child isKindOfClass:NSScrollView.class]) { cardScroll = (NSScrollView *)child; }
            if ([child isKindOfClass:NSTextField.class] && [((NSTextField *)child).stringValue isEqualToString:@"中文译文"]) { cardTitle = (NSTextField *)child; }
        }
        Check(cardTitle != nil, @"the long card must show the 中文译文 heading");
        Check(cardScroll != nil && [cardScroll.documentView isKindOfClass:NSTextField.class], @"the long card body must live in a scrollable area");
        Check(cardScroll.documentView.frame.size.height > cardScroll.contentView.bounds.size.height,
              @"a long translation must actually overflow its card so it can scroll");
        NSTextField *cardBody = (NSTextField *)cardScroll.documentView;
        Check(cardBody.font.pointSize >= 18, @"the long reading card must use the readable body size, not shrink to fit");
        // OCR 的单行折行不能机械变成译文段落：单个换行应与连写时排版一致。
        OCRTextItem *wrapItem = [OCRTextItem new];
        wrapItem.text = @"行折りテスト。";wrapItem.boundingBox = CGRectMake(.2,.2,.5,.1);
        wrapItem.lineBoxes = @[[NSValue valueWithRect:CGRectMake(.2,.2,.5,.04)],[NSValue valueWithRect:CGRectMake(.2,.25,.5,.04)]];
        wrapItem.lineCount = 2;wrapItem.blockKind = InlineBlockKindLong;
        NSPanel *wrapped = [app inlineLongPanelForTranslation:@"第一句话在这里结束。\n第二句话还在同一段。" item:wrapItem frame:NSMakeRect(120,120,380,150)];
        NSPanel *joined = [app inlineLongPanelForTranslation:@"第一句话在这里结束。第二句话还在同一段。" item:wrapItem frame:NSMakeRect(120,120,380,150)];
        CGFloat wrappedHeight = 0, joinedHeight = 0;
        for (NSView *child in wrapped.contentView.subviews) { if ([child isKindOfClass:NSScrollView.class]) { wrappedHeight = NSHeight(((NSScrollView *)child).documentView.frame); } }
        for (NSView *child in joined.contentView.subviews) { if ([child isKindOfClass:NSScrollView.class]) { joinedHeight = NSHeight(((NSScrollView *)child).documentView.frame); } }
        Check(wrappedHeight > 0 && fabs(wrappedHeight - joinedHeight) < 1,
              @"a single OCR line break must not be turned into a translation paragraph");
        NSColor *cardFill = [NSColor colorWithCGColor:longCard.contentView.layer.backgroundColor];
        // 长卡与短贴片共用同一底色与同一透明度设置；文字仍完全不透明。
        Check(fabs(cardFill.redComponent - cream.redComponent) < 0.03 && fabs(cardFill.alphaComponent - 0.2) < 0.03,
              [NSString stringWithFormat:@"the long card must use the same cream fill and the same opacity setting (alpha %.2f)", cardFill.alphaComponent]);
        Check(InlineTextAlpha(cardBody) >= 0.99, @"the long card body text must stay fully opaque");

        // 编号解析：正常编号要按序号回填
        NSArray<NSString *> *numbered = [app parseNumberedTranslations:@"1. 第一句\n2. 第二句\n3. 第三句" expectedCount:3];
        Check(numbered.count == 3, @"numbered reply should produce one result per item");
        Check([numbered[0] isEqualToString:@"第一句"] && [numbered[2] isEqualToString:@"第三句"], @"numbered reply should map by index");

        // 编号解析：模型丢了编号时必须返回空数组，不能把同一段话复制给每一条
        NSArray<NSString *> *unnumbered = [app parseNumberedTranslations:@"季节转入秋天，时尚也换上秋装。" expectedCount:5];
        Check(unnumbered.count == 0, @"unnumbered reply must not be fanned out to every item");

        // 编号解析：同一个编号下的续行要拼接而不是覆盖
        NSArray<NSString *> *continued = [app parseNumberedTranslations:@"1. 第一行\n第二行\n2. 第二句" expectedCount:2];
        Check([continued[0] containsString:@"\n"], @"continuation lines should append to the same item");

        // 回显过滤：整段都是原文回显时不能把原文当译文显示
        app.languageControl = [NSSegmentedControl segmentedControlWithLabels:@[@"日语", @"英语"] trackingMode:NSSegmentSwitchTrackingSelectOne target:nil action:nil];
        app.languageControl.selectedSegment = 0;
        NSString *echoed = [app displayableTranslation:@"季節は秋へ。ファッションも秋仕様に切り替えて" sourceText:@"季節は秋へ。ファッションも秋仕様に切り替えて"];
        Check(![echoed containsString:@"季節"], @"source echo must not be shown as a translation");
        NSString *mixed = [app displayableTranslation:@"原文: 季節は秋へ\n秋天到了，时尚也换上秋装。" sourceText:@"季節は秋へ"];
        Check([mixed containsString:@"秋天"], @"genuine translation lines should survive echo filtering");

        // 自动判别：典型剧情对白（底部一两句大字）应判为对白
        NSArray<OCRTextItem *> *dialogueFrame = @[
            Item(@"季節は秋へ。ファッションも秋仕様に", CGRectMake(0.00, 0.18, 0.60, 0.035)),
            Item(@"切り替えていきましょう", CGRectMake(0.00, 0.24, 0.42, 0.035))
        ];
        Check(DetectContentModeForBlocks(dialogueFrame, ContentModeDialogue) == ContentModeDialogue,
              @"bottom dialogue lines should be classified as dialogue");

        // 自动判别：对白里夹一个角落时间戳仍然是对白
        NSArray<OCRTextItem *> *dialogueWithTimestamp = @[
            Item(@"季節は秋へ。ファッションも秋仕様に切り替えて", CGRectMake(0.00, 0.18, 0.60, 0.035)),
            Item(@"新しいシーズンを楽しみましょう", CGRectMake(0.00, 0.24, 0.42, 0.035)),
            Item(@"12:34", CGRectMake(0.92, 0.95, 0.05, 0.02))
        ];
        Check(DetectContentModeForBlocks(dialogueWithTimestamp, ContentModeUI) == ContentModeDialogue,
              @"a corner timestamp must not flip dialogue into interface mode");

        // 回归：真实截图 #1（Town 街景 + 底部对白框）的 OCR 几何。
        // 街景招牌很多且都是小框，旧实现会把整帧误判成 UI，并把招牌一起送去翻译。
        NSArray<OCRTextItem *> *townScene = @[
            Item(@"HIABATANI STE", CGRectMake(0.39, 0.90, 0.21, 0.086)),
            Item(@"会話", CGRectMake(0.45, 0.89, 0.04, 0.049)),
            Item(@"E-FROG", CGRectMake(0.40, 0.84, 0.04, 0.044)),
            Item(@"珈琲喫茶 MOUMOU", CGRectMake(0.51, 0.59, 0.12, 0.036)),
            Item(@"MOUMOU", CGRectMake(0.65, 0.57, 0.06, 0.034)),
            Item(@"River Books", CGRectMake(0.14, 0.54, 0.10, 0.031)),
            Item(@"ほしの", CGRectMake(0.23, 0.26, 0.07, 0.041)),
            Item(@"これでプレゼントはOK。", CGRectMake(0.24, 0.18, 0.27, 0.056)),
            Item(@"HIABATAN ST®", CGRectMake(0.41, 0.09, 0.13, 0.031)),
            Item(@"从3岁开始", CGRectMake(0.44, 0.05, 0.08, 0.034))
        ];
        Check(DetectContentModeForBlocks(townScene, ContentModeUI) == ContentModeDialogue,
              @"a town scene with a bottom dialogue box must be dialogue, not interface");

        NSArray<OCRTextItem *> *townBand = SubtitleBandItemsFromBlocks(townScene);
        NSMutableArray<NSString *> *townPayload = [NSMutableArray array];
        for (OCRTextItem *item in townBand) { [townPayload addObject:item.text]; }
        NSString *townText = [townPayload componentsJoinedByString:@"\n"];
        Check([townText containsString:@"プレゼント"], @"dialogue text should be inside the band");
        Check(![townText containsString:@"MOUMOU"], @"shop signs must not be sent as dialogue");
        Check(![townText containsString:@"River"], @"a shop sign that only barely overlaps must be excluded");
        Check(![townText containsString:@"E-FROG"], @"poster text must not be sent as dialogue");

        // 回归：真实截图 #2（教室 + 两个选项 + 被录音条遮住一半的对白）。
        // 选项框在画面中部偏上，且比最宽的那条对白更窄——旧实现会把两个选项整段丢掉。
        NSArray<OCRTextItem *> *choiceScene = @[
            Item(@"うん、空いてるよ", CGRectMake(0.15, 0.91, 0.28, 0.061)),
            Item(@"ちょっと用事があって・・・・・・", CGRectMake(0.15, 0.70, 0.42, 0.053)),
            Item(@"七ツ森", CGRectMake(0.09, 0.34, 0.11, 0.053)),
            Item(@"今度の日曜日。", CGRectMake(0.11, 0.24, 0.24, 0.068))
        ];
        Check(DetectContentModeForBlocks(choiceScene, ContentModeUI) == ContentModeDialogue,
              @"a choice screen with a mis-read dialogue line must still be dialogue");

        // 这一帧要分成：对白（含被遮住的半行）进字幕窗，两个选项贴边。
        // 注意 band 只负责“对白那一簇”，选项是在 split 里补进来的（它们在画面上方、离得远）。
        NSArray<OCRTextItem *> *choiceBand = SubtitleBandItemsFromBlocks(choiceScene);
        NSMutableArray<OCRTextItem *> *choiceDialogue = [NSMutableArray array];
        NSMutableArray<OCRTextItem *> *choiceOptions = [NSMutableArray array];
        SplitDialogueAndOptionsFromItems(choiceBand, choiceScene, choiceDialogue, choiceOptions);
        NSMutableArray<NSString *> *choiceDialogueTexts = [NSMutableArray array];
        for (OCRTextItem *item in choiceDialogue) { [choiceDialogueTexts addObject:item.text]; }
        NSMutableArray<NSString *> *choiceOptionTexts = [NSMutableArray array];
        for (OCRTextItem *item in choiceOptions) { [choiceOptionTexts addObject:item.text]; }

        Check([choiceDialogueTexts containsObject:@"今度の日曜日。"],
              @"the dialogue line must reach the caption");
        Check([choiceOptionTexts containsObject:@"うん、空いてるよ"], @"the upper choice option must be translated inline");
        Check([choiceOptionTexts containsObject:@"ちょっと用事があって・・・・・・"],
              @"the lower choice option must also be translated inline");
        Check(![choiceDialogueTexts containsObject:@"O KB"] && ![choiceOptionTexts containsObject:@"O KB"],
              @"the macOS volume HUD must not be translated");

        // 回归（2026-10-04 现场帧）：说话人名字框 `萩尾九段` 单独成一簇时被当成「选项」，
        // 学习库里就多出一条只写名字的「最近台词」，把 5 条额度从真台词那里挤掉。
        // 名字框必须并回对白，真正的选项不受影响。
        NSArray<OCRTextItem *> *speakerScene = @[
            Item(@"萩尾九段", CGRectMake(0.25, 0.55, 0.16, 0.045)),
            Item(@"これでプレゼントはOK。", CGRectMake(0.27, 0.38, 0.30, 0.050)),
            Item(@"我の手落ちだ", CGRectMake(0.27, 0.28, 0.22, 0.050))
        ];
        NSArray<OCRTextItem *> *speakerBand = SubtitleBandItemsFromBlocks(speakerScene);
        NSMutableArray<OCRTextItem *> *speakerDialogue = [NSMutableArray array];
        NSMutableArray<OCRTextItem *> *speakerOptions = [NSMutableArray array];
        SplitDialogueAndOptionsFromItems(speakerBand, speakerScene, speakerDialogue, speakerOptions);
        NSMutableArray<NSString *> *speakerDialogueTexts = [NSMutableArray array];
        for (OCRTextItem *item in speakerDialogue) { [speakerDialogueTexts addObject:item.text]; }
        Check([speakerDialogueTexts containsObject:@"萩尾九段"] && [speakerDialogueTexts containsObject:@"我の手落ちだ"],
              @"a speaker name plate must join the dialogue, not become an option row");
        Check(speakerOptions.count == 0, @"the speaker name plate must not be recorded as an option");
        Check(DialogueFrameIsSpeakerLabelOnly(@[@"萩尾九段"]) &&
              DialogueFrameIsSpeakerLabelOnly(@[@"＜だん", @"萩尾九段"]) &&
              DialogueFrameIsSpeakerLabelOnly(@[@"かたぎりし、ゆうの", @"片霧秋兵"]),
              @"a frame holding only the speaker box must not become a history row");
        Check(!DialogueFrameIsSpeakerLabelOnly(@[@"萩尾九段", @"我の手落ちだ"]) &&
              !DialogueFrameIsSpeakerLabelOnly(@[@"はい"]) &&
              !DialogueFrameIsSpeakerLabelOnly(@[@"うん、空いてるよ"]) &&
              !DialogueFrameIsSpeakerLabelOnly(@[@"どれど……"]),
              @"real short lines must still be recorded");

        // 纯街景（没有对白框）不应产出字幕带
        NSArray<OCRTextItem *> *signageOnly = @[
            Item(@"珈琲喫茶 MOUMOU", CGRectMake(0.51, 0.59, 0.12, 0.036)),
            Item(@"River Books", CGRectMake(0.14, 0.54, 0.10, 0.031)),
            Item(@"E-FROG", CGRectMake(0.40, 0.84, 0.04, 0.044))
        ];
        Check(SubtitleBandItemsFromBlocks(signageOnly).count == 0,
              @"pure signage should not produce a subtitle band");

        // 真实截图 #3：文本密集的新闻列表页（左侧菜单 + 右侧条目 + 右下「戻る」）。
        // 这种页面没有对白框，但有若干条很宽的行 —— 只按“有没有宽行”会误判成对白。
        // 判据：UI 按钮词 + “实质行”数量（实测 8 行 vs 对白帧 3 行）。
        NSArray<OCRTextItem *> *newsPage = @[
            Item(@"はばたきNEWS", CGRectMake(0.07, 0.71, 0.13, 0.034)),
            Item(@"映画公演スケジュール", CGRectMake(0.08, 0.60, 0.18, 0.031)),
            Item(@"イベント公演スケジュール", CGRectMake(0.07, 0.49, 0.20, 0.034)),
            Item(@"12星座占い", CGRectMake(0.07, 0.39, 0.10, 0.031)),
            Item(@"ミチヒカ◆ルーム", CGRectMake(0.07, 0.28, 0.15, 0.034)),
            Item(@"掘り出し物を探しにフリマへ行こう！", CGRectMake(0.38, 0.42, 0.34, 0.052)),
            Item(@"ナイトパレードで特別な夜を", CGRectMake(0.38, 0.25, 0.26, 0.039)),
            Item(@"「現代アート展」開催", CGRectMake(0.39, 0.61, 0.19, 0.039)),
            Item(@"詳細", CGRectMake(0.87, 0.62, 0.04, 0.036)),
            Item(@"詳細", CGRectMake(0.87, 0.43, 0.05, 0.036)),
            Item(@"戻る", CGRectMake(0.93, 0.01, 0.06, 0.037)),
            Item(@"今月のNEWSを見る", CGRectMake(0.01, 0.01, 0.16, 0.036))
        ];
        Check(DetectContentModeForBlocks(newsPage, ContentModeDialogue) == ContentModeUI,
              @"a dense news/list page must be interface (goes to full-screen inline translation)");
        Check(UITokenHitCount(newsPage) >= 2, @"the news page should be recognised by its UI buttons");

        // 对白帧不带 UI 按钮词，也不会被“文本密集”规则误伤
        Check(UITokenHitCount(choiceScene) == 0, @"a dialogue/choice frame carries no UI button words");
        Check(UITokenHitCount(townScene) == 0, @"a town dialogue frame carries no UI button words");

        // 对白帧的文本框天然贴着画面底部，不能因为“贴边文字多”就判成 UI。
        // 曾经有条规则是 edgeCount>=2 且没有宽行 → UI，把城镇对白帧误伤了。
        NSArray<OCRTextItem *> *bottomHeavyDialogue = @[
            Item(@"HIABATAN ST®", CGRectMake(0.41, 0.06, 0.13, 0.031)),
            Item(@"从3岁开始", CGRectMake(0.44, 0.02, 0.08, 0.034)),
            Item(@"4岁起", CGRectMake(0.45, 0.01, 0.05, 0.031)),
            Item(@"会話", CGRectMake(0.45, 0.93, 0.04, 0.049)),
            Item(@"これでプレゼントはOK。", CGRectMake(0.24, 0.18, 0.27, 0.056)),
            Item(@"ほしの", CGRectMake(0.23, 0.26, 0.07, 0.041))
        ];
        Check(DetectContentModeForBlocks(bottomHeavyDialogue, ContentModeUI) == ContentModeDialogue,
              @"a dialogue frame with text at the bottom edge must NOT become interface mode");

        // 真实短句帧：姓名牌「？？？」未被 OCR 识别，只剩无标点台词和右下操作提示。
        OCRTextItem *unpunctuatedLine = Item(@"そこまで", CGRectMake(0.330, 0.230, 0.101, 0.049));
        OCRTextItem *cornerHelp = Item(@"8操作説明", CGRectMake(0.890, 0.003, 0.103, 0.049));
        NSArray<OCRTextItem *> *singleShortFrame = @[unpunctuatedLine, cornerHelp];
        Check(DetectContentModeForBlocks(singleShortFrame, ContentModeUI) == ContentModeDialogue,
              @"a short unpunctuated line in the dialogue box must switch from UI to caption mode");
        NSArray<OCRTextItem *> *singleShortBand = SubtitleBandItemsFromBlocks(singleShortFrame);
        Check([singleShortBand containsObject:unpunctuatedLine] && ![singleShortBand containsObject:cornerHelp],
              @"the subtitle band must contain the short line, not the corner help button");
        NSMutableArray<OCRTextItem *> *singleShortDialogue = [NSMutableArray array];
        NSMutableArray<OCRTextItem *> *singleShortOptions = [NSMutableArray array];
        SplitDialogueAndOptionsFromItems(singleShortBand, singleShortFrame, singleShortDialogue, singleShortOptions);
        AppDelegate *singleShortApp = [[AppDelegate alloc] init];
        Check([singleShortDialogue containsObject:unpunctuatedLine] &&
              ![singleShortApp shouldIgnoreInlineText:unpunctuatedLine.text
                                           normalized:NormalizeForComparison(unpunctuatedLine.text)
                                          boundingBox:unpunctuatedLine.boundingBox strict:YES],
              @"the short dialogue line must survive both band splitting and strict noise filtering");
        Check(IsCornerHelpButton(cornerHelp) && !IsCornerHelpButton(unpunctuatedLine),
              @"a lower-right help label must not be sent as dialogue text");
        OCRTextItem *partialLine = Item(@"そこ", CGRectMake(0.330, 0.230, 0.052, 0.049));
        Check(DetectContentModeForBlocks(@[partialLine, cornerHelp], ContentModeDialogue) == ContentModeDialogue,
              @"a transient partial OCR result must not switch back to UI mode");
        Check(DetectContentModeForBlocks(@[cornerHelp], ContentModeDialogue) == ContentModeDialogue,
              @"a corner help button alone must not switch a dialogue scene to UI mode");
        OCRTextItem *nameNoise = Item(@"ことと", CGRectMake(0.30, 0.193, 0.09, 0.044));
        Check(![singleShortApp shouldIgnoreInlineText:nameNoise.text
                                           normalized:NormalizeForComparison(nameNoise.text)
                                          boundingBox:nameNoise.boundingBox strict:YES],
              @"short hiragana lines are no longer deleted by shape (completeness over noise suppression)");

        // 实际录影帧：姓名和台词上的注音是三块小 OCR 框，不应凑成“密集短文本 UI”。
        NSArray<OCRTextItem *> *furiganaDialogue = @[
            Item(@"有馬 一", CGRectMake(0.285, 0.303, 0.094, 0.055)),
            Item(@"ありま", CGRectMake(0.290, 0.352, 0.039, 0.020)),
            Item(@"はじめ", CGRectMake(0.329, 0.349, 0.049, 0.027)),
            Item(@"...帝国軍内でも", CGRectMake(0.247, 0.209, 0.209, 0.091)),
            Item(@"秘密裏に行われる儀式だ", CGRectMake(0.280, 0.156, 0.277, 0.050)),
            Item(@"さいえいぶんたい", CGRectMake(0.284, 0.124, 0.092, 0.032)),
            Item(@"精鋭分隊の出る幕はないだろう", CGRectMake(0.284, 0.083, 0.340, 0.050)),
            Item(@"8操作説明", CGRectMake(0.893, 0.003, 0.103, 0.040))
        ];
        Check(!LooksLikeUIFrame(furiganaDialogue), @"furigana over dialogue must not trigger the small-box UI rule");
        Check(DetectContentModeForBlocks(furiganaDialogue, ContentModeUI) == ContentModeDialogue,
              @"dialogue with furigana and a corner help button must use the caption route");
        Check(IsFuriganaNearLargerLine(furiganaDialogue[1], furiganaDialogue) &&
              IsFuriganaNearLargerLine(furiganaDialogue[5], furiganaDialogue) &&
              !IsFuriganaNearLargerLine(furiganaDialogue.lastObject, furiganaDialogue),
              @"only nearby reading annotations should be excluded from dialogue translation");
        OCRTextItem *noisyReading = Item(@"さいえいぶんた！", CGRectMake(0.284, 0.124, 0.092, 0.032));
        Check(IsFuriganaNearLargerLine(noisyReading, furiganaDialogue),
              @"a punctuation OCR error in furigana must not become a subtitle line");

        // 按钮词必须精确匹配：早期 containsString 会让 "River Books" 命中 "ok"、
        // 让对白「これでプレゼントはOK。」也命中 "ok"，把对白帧误判成 UI。
        Check(!TextHitsUIToken(@"River Books"), @"'ok' inside 'Books' must not count as a UI token");
        Check(!TextHitsUIToken(@"これでプレゼントはOK。"), @"'OK' inside a dialogue line must not count as a UI token");
        Check(TextHitsUIToken(@"詳細"), @"a real UI button word must still be detected");
        Check(TextHitsUIToken(@"戻る"), @"a real UI button word must still be detected");
        Check(TextHitsUIToken(@"OK"), @"a standalone 'OK' button should count");

        // 回归：任何旧存档（mode=0/1/-1，或旧版 autoModeEnabled/manualMode）都必须被忽略，
        // 内容模式始终自动判别，不再恢复手动指定。
        {
            NSUserDefaults *saved = [NSUserDefaults standardUserDefaults];
            NSDictionary *backup = [[saved objectForKey:@"LiveCaptionTranslator.settings.v1"] copy];
            for (NSDictionary *legacy in @[@{@"mode": @(0), @"language": @(0)},
                                           @{@"mode": @(-1)},
                                           @{@"autoModeEnabled": @NO, @"manualMode": @(1), @"language": @(0)}]) {
                [saved setObject:legacy forKey:@"LiveCaptionTranslator.settings.v1"];
                AppDelegate *legacyApp = [[AppDelegate alloc] init];
                legacyApp.languageControl = [NSSegmentedControl segmentedControlWithLabels:@[@"日", @"英"] trackingMode:NSSegmentSwitchTrackingSelectOne target:nil action:nil];
                [legacyApp createCaptionWindow];
                [legacyApp loadSettings];
                Check([legacyApp autoContentModeEnabled] && [legacyApp effectiveModeSegment] == ContentModeDialogue,
                      @"any legacy mode archive must be ignored so auto detection stays on");
                [legacyApp.captionPanel orderOut:nil];
            }
            if (backup) { [saved setObject:backup forKey:@"LiveCaptionTranslator.settings.v1"]; }
            else { [saved removeObjectForKey:@"LiveCaptionTranslator.settings.v1"]; }
        }

        // 设置保存/重载不再写也不读手动模式；重启后仍从自动判别（对白起步）开始。
        {
            NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
            NSDictionary *backup = [[defaults objectForKey:SettingsKey] copy];
            AppDelegate *settingsApp = [[AppDelegate alloc] init];
            [settingsApp createMainWindow];
            [settingsApp.mainWindow setContentSize:NSMakeSize(980, 660)];
            [settingsApp.mainWindow.contentView layoutSubtreeIfNeeded];
            NSScrollView *liveScroll = (NSScrollView *)settingsApp.pages[0];
            Check(liveScroll.documentView.isFlipped, @"workbench document must open at its top edge");
            Check(fabs(NSHeight(settingsApp.framePreview.superview.frame) -
                       NSWidth(settingsApp.framePreview.superview.frame) * 0.5625) < 2,
                  @"preview must keep its 16:9 aspect ratio");
            Check(fabs(NSWidth(liveScroll.documentView.frame) - NSWidth(liveScroll.contentView.bounds)) < 2,
                  @"the 980-point workbench must fit the clip width without horizontal scrolling");
            [settingsApp createCaptionWindow];
            [settingsApp loadSettings];
            [settingsApp saveSettings:nil];
            NSDictionary *written = [defaults objectForKey:SettingsKey];
            Check(written[@"autoModeEnabled"] == nil && written[@"manualMode"] == nil && written[@"mode"] == nil,
                  @"saved settings must no longer persist any manual mode fields");
            AppDelegate *reloaded = [[AppDelegate alloc] init];
            [reloaded createMainWindow];
            [reloaded createCaptionWindow];
            [reloaded loadSettings];
            Check([reloaded autoContentModeEnabled] && [reloaded effectiveModeSegment] == ContentModeDialogue,
                  @"reload must always start in auto-detection dialogue mode");

            CGColorSpaceRef color = CGColorSpaceCreateDeviceRGB();
            CGContextRef bitmap = CGBitmapContextCreate(NULL, 16, 9, 8, 16 * 4, color,
                                                         kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
            CGColorSpaceRelease(color);
            CGContextSetRGBFillColor(bitmap, 0.2, 0.7, 0.4, 1);
            CGContextFillRect(bitmap, CGRectMake(0, 0, 16, 9));
            CGImageRef sample = CGBitmapContextCreateImage(bitmap);
            CGContextRelease(bitmap);
            [settingsApp updatePreviewFromImage:sample generation:settingsApp.translationGeneration];
            CGImageRelease(sample);
            NSDate *deadline = [NSDate dateWithTimeIntervalSinceNow:2];
            while (!settingsApp.framePreview.image && [deadline timeIntervalSinceNow] > 0) {
                [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.01]];
            }
            Check(settingsApp.framePreview.image != nil && settingsApp.previewPlaceholder.hidden,
                  @"existing capture should produce a visible preview");
            NSImage *pausedPreview = settingsApp.framePreview.image;
            [settingsApp stop];
            Check(settingsApp.framePreview.image == pausedPreview, @"pause must retain the last preview frame");
            [settingsApp resetForSelectedWindowChange];
            Check(settingsApp.framePreview.image == nil && !settingsApp.previewPlaceholder.hidden,
                  @"switching target window must clear stale preview");
            [settingsApp showPreviewUnavailable:@"无法预览：请检查屏幕录制权限"];
            Check([settingsApp.previewPlaceholder.stringValue containsString:@"权限"],
                  @"permission failure must be explained inside the preview");
            CGColorSpaceRef staleColor = CGColorSpaceCreateDeviceRGB();
            CGContextRef staleBitmap = CGBitmapContextCreate(NULL, 8, 8, 8, 8 * 4, staleColor,
                                                              kCGImageAlphaPremultipliedFirst | kCGBitmapByteOrder32Little);
            CGColorSpaceRelease(staleColor);
            CGImageRef staleImage = CGBitmapContextCreateImage(staleBitmap);
            CGContextRelease(staleBitmap);
            [settingsApp updatePreviewFromImage:staleImage generation:settingsApp.translationGeneration];
            CGImageRelease(staleImage);
            settingsApp.translationGeneration += 1;
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
            Check(settingsApp.framePreview.image == nil, @"a stale preview worker must not repaint after generation changes");
            settingsApp.apiKeyField.stringValue = @"";
            [settingsApp testTranslation:nil];
            [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
            Check([settingsApp.serviceStatusLabel.stringValue isEqualToString:@"服务测试失败"] &&
                  settingsApp.serviceErrorLabel.stringValue.length > 0,
                  @"a failed service test must be visible near service settings");
            [settingsApp serviceSettingsChanged];
            Check([settingsApp.serviceStatusLabel.stringValue isEqualToString:@"服务未测试"],
                  @"changing service settings must invalidate an old test result");
            if (backup) { [defaults setObject:backup forKey:SettingsKey]; }
            else { [defaults removeObjectForKey:SettingsKey]; }
            [settingsApp.captionPanel orderOut:nil];
            [reloaded.captionPanel orderOut:nil];
        }

        // 回归：模式判别不能依赖“这一帧要不要翻译”。
        // 曾经把模式提交放在去重闸门（文本未变化 / 等待翻译返回 / 等待文本稳定）之后，
        // 闸门一命中就 return —— 模式永远提交不了，一直卡在初始的「对白」，
        // 结果整屏新闻条目被塞进字幕窗。这里验证“连续两帧同类”就能提交，不牵扯去重。
        app.detectedModeSegment = ContentModeDialogue;
        app.candidateModeSegment = -1;
        app.candidateModeHits = 0;
        Check([app stableContentModeForBlocks:newsPage] == ContentModeDialogue,
              @"first interface frame: mode should not flip yet");
        Check([app stableContentModeForBlocks:newsPage] == ContentModeUI,
              @"second consecutive interface frame: mode MUST commit to interface");

        // 短标签菜单帧（用来验证滞回切换）
        NSArray<OCRTextItem *> *uiFrame = @[
            Item(@"公演日程", CGRectMake(0.07, 0.72, 0.12, 0.028)),
            Item(@"イベント", CGRectMake(0.07, 0.64, 0.14, 0.028)),
            Item(@"詳細", CGRectMake(0.86, 0.60, 0.07, 0.022)),
            Item(@"戻る", CGRectMake(0.03, 0.68, 0.05, 0.022)),
            Item(@"更新", CGRectMake(0.60, 0.66, 0.05, 0.022)),
            Item(@"メニュー", CGRectMake(0.80, 0.70, 0.09, 0.022))
        ];

        // 自动判别：必须连续两帧一致才切换，单帧抖动不能改模式
        app.detectedModeSegment = ContentModeDialogue;
        app.candidateModeSegment = -1;
        app.candidateModeHits = 0;
        NSInteger firstFrame = [app stableContentModeForBlocks:uiFrame];
        Check(firstFrame == ContentModeDialogue, @"a single interface frame must not switch the mode yet");
        NSInteger secondFrame = [app stableContentModeForBlocks:uiFrame];
        Check(secondFrame == ContentModeUI, @"two matching interface frames should commit the switch");
        NSInteger backToDialogue = [app stableContentModeForBlocks:dialogueFrame];
        Check(backToDialogue == ContentModeUI, @"one dialogue frame must not immediately switch back");
        NSInteger dialogueCommitted = [app stableContentModeForBlocks:dialogueFrame];
        Check(dialogueCommitted == ContentModeDialogue, @"two matching dialogue frames should switch back");

        // 自动判别始终生效：有效模式直接取判别结果，并决定对应提示词。
        app.detectedModeSegment = ContentModeDialogue;
        Check([app effectiveModeSegment] == ContentModeDialogue, @"detected dialogue mode must drive translation");
        Check([[app systemPrompt] containsString:@"字幕实时翻译器"], @"dialogue mode must use the dialogue prompt");
        app.detectedModeSegment = ContentModeUI;
        Check([app effectiveModeSegment] == ContentModeUI, @"detected interface mode must drive translation");
        Check([[app systemPrompt] containsString:@"界面与公告文本翻译器"], @"interface mode must use the interface prompt");

        // 控件还没创建时写状态/错误不得崩溃（历史上 setStatus: 是直接赋值）
        AppDelegate *bare = [[AppDelegate alloc] init];
        [bare setStatus:@"早期状态"];
        [bare showError:@"早期错误"];
        [bare updateCurrentWindowLabel];
        Check(YES, @"label writers must tolerate not-yet-created controls");

        // 对白 / 选项拆分（坐标取自真实截图实测的 OCR 结果）：
        // 上方两个选项贴边翻译，下方对白框进悬浮字幕窗。
        // 注意第二个选项因为带「・・・・・・」会比対白更宽 —— 不能只按“最宽”挑锚点。
        NSArray<OCRTextItem *> *splitFrame2 = @[
            Item(@"うん、空いてるよ", CGRectMake(0.15, 0.91, 0.28, 0.061)),
            Item(@"ちょっと用事があって・・・・・・", CGRectMake(0.15, 0.70, 0.42, 0.053)),
            Item(@"七ツ森", CGRectMake(0.09, 0.34, 0.11, 0.053)),
            Item(@"今度の日曜日。", CGRectMake(0.11, 0.24, 0.24, 0.068))
        ];
        NSArray<OCRTextItem *> *splitBand2 = SubtitleBandItemsFromBlocks(splitFrame2);
        NSMutableArray<OCRTextItem *> *splitDialogue2 = [NSMutableArray array];
        NSMutableArray<OCRTextItem *> *splitOptions2 = [NSMutableArray array];
        SplitDialogueAndOptionsFromItems(splitBand2, splitFrame2, splitDialogue2, splitOptions2);
        NSMutableArray<NSString *> *splitDialogueTexts = [NSMutableArray array];
        for (OCRTextItem *item in splitDialogue2) { [splitDialogueTexts addObject:item.text]; }
        NSMutableArray<NSString *> *splitOptionTexts = [NSMutableArray array];
        for (OCRTextItem *item in splitOptions2) { [splitOptionTexts addObject:item.text]; }

        Check([splitDialogueTexts containsObject:@"今度の日曜日。"],
              @"the dialogue box text must go to the caption");
        Check(![splitDialogueTexts containsObject:@"ちょっと用事があって・・・・・・"],
              @"a choice option must NOT be shown in the caption even if it is the widest line");
        Check([splitOptionTexts containsObject:@"うん、空いてるよ"], @"the first choice option must be translated inline");
        Check([splitOptionTexts containsObject:@"ちょっと用事があって・・・・・・"],
              @"the second choice option must ALSO be translated inline");

        // 连续多行对白之间没有大缝 → 整段都进字幕窗，不能误判成选项
        NSArray<OCRTextItem *> *continuousDialogue = @[
            Item(@"今日はいい天気ですね", CGRectMake(0.10, 0.30, 0.50, 0.04)),
            Item(@"そうですね、散歩でも", CGRectMake(0.10, 0.26, 0.50, 0.04)),
            Item(@"行きましょうか", CGRectMake(0.10, 0.22, 0.35, 0.04))
        ];
        NSArray<OCRTextItem *> *contBand = SubtitleBandItemsFromBlocks(continuousDialogue);
        NSMutableArray<OCRTextItem *> *contDialogue = [NSMutableArray array];
        NSMutableArray<OCRTextItem *> *contOptions = [NSMutableArray array];
        SplitDialogueAndOptionsFromItems(contBand, continuousDialogue, contDialogue, contOptions);
        Check(contDialogue.count == 3 && contOptions.count == 0,
              @"three tightly spaced dialogue lines must all go to the caption");

        // 单个选项 + 单个对白
        NSArray<OCRTextItem *> *oneChoice = @[
            Item(@"はい", CGRectMake(0.30, 0.70, 0.15, 0.04)),
            Item(@"それでは始めましょう", CGRectMake(0.20, 0.20, 0.50, 0.05))
        ];
        NSArray<OCRTextItem *> *oneBand = SubtitleBandItemsFromBlocks(oneChoice);
        NSMutableArray<OCRTextItem *> *oneDialogue = [NSMutableArray array];
        NSMutableArray<OCRTextItem *> *oneOptions = [NSMutableArray array];
        SplitDialogueAndOptionsFromItems(oneBand, oneChoice, oneDialogue, oneOptions);
        Check(oneDialogue.count == 1 && [oneDialogue.firstObject.text containsString:@"始めましょう"],
              @"the single lower line is the dialogue");
        Check(oneOptions.count == 1 && [oneOptions.firstObject.text isEqualToString:@"はい"],
              @"the single upper line is an option");

        // 只有一行时当作对白（进字幕窗）
        NSMutableArray<OCRTextItem *> *singleDialogue = [NSMutableArray array];
        NSMutableArray<OCRTextItem *> *singleOptions = [NSMutableArray array];
        SplitDialogueAndOptionsFromItems(@[Item(@"こんにちは", CGRectMake(0.2, 0.2, 0.4, 0.05))],
                                         @[Item(@"こんにちは", CGRectMake(0.2, 0.2, 0.4, 0.05))],
                                         singleDialogue, singleOptions);
        Check(singleDialogue.count == 1 && singleOptions.count == 0, @"a lone line is treated as dialogue");

        // 字幕窗闪烁的根因：只有状态字符串变了（每帧的 OCR 计时都不一样），
        // 旧代码却照样跑 updateCaptionAppearance（重新赋 font → 触发重排）+ resize。
        // 用一个稳定的判据：updateCaptionAppearance 每次都会新建 NSFont，指针必然变化。
        AppDelegate *captionApp = [[AppDelegate alloc] init];
        [captionApp createCaptionWindow];
        // 换成一个可计数的 label（updateCaptionAppearance 会重设它的 font）
        CountingLabel *countingLabel = [[CountingLabel alloc] initWithFrame:NSMakeRect(0, 0, 400, 80)];
        countingLabel.maximumNumberOfLines = 5;
        captionApp.captionTextLabel = countingLabel;

        [captionApp updateCaptionWindowWithText:@"第一句" status:@"状态A"];
        NSInteger fontsAfterFirst = countingLabel.fontSetCount;
        Check(fontsAfterFirst >= 1, @"first update should apply the caption appearance");

        // 文本不变、只有状态变（每帧的 OCR 计时都不同）：不应重排版面
        [captionApp updateCaptionWindowWithText:@"第一句" status:@"状态B·OCR 0.2s"];
        Check(countingLabel.fontSetCount == fontsAfterFirst,
              @"status-only change must NOT re-apply the caption font (this caused the flicker)");
        NSUInteger captionTextFields = 0;
        for (NSView *view in captionApp.captionContainer.subviews) {
            if ([view isKindOfClass:NSTextField.class] && view != captionApp.captionBrandLabel) { captionTextFields++; }
        }
        Check([captionApp.captionBrandLabel.stringValue isEqualToString:@"译芽 · 当前译文"], @"caption branding must stay static when runtime status changes");
        Check(captionTextFields == 1 && captionApp.captionHideButton.superview == captionApp.captionContainer,
              @"game caption contains one translated text field and a hide control, without a runtime status line");

        // 完全相同的内容：也不应重排
        [captionApp updateCaptionWindowWithText:@"第一句" status:@"状态B·OCR 0.2s"];
        Check(countingLabel.fontSetCount == fontsAfterFirst, @"identical content must not re-apply appearance");

        // 模型换了种说法（意思一样、只差一个字）也不应重画。
        // 这两句的相似度正好 0.90，落在阈值边界上。
        [captionApp updateCaptionWindowWithText:@"这里有点事要办……" status:@"状态B·OCR 0.2s"];
        NSInteger fontsBeforeParaphrase = countingLabel.fontSetCount;
        [captionApp updateCaptionWindowWithText:@"这里有点事情要办……" status:@"状态B·OCR 0.2s"];
        Check(countingLabel.fontSetCount == fontsBeforeParaphrase,
              @"a near-identical paraphrase must NOT repaint the caption (model wording jitter)");
        Check([countingLabel.stringValue isEqualToString:@"这里有点事要办……"],
              @"the already-shown wording should be kept when the new one is nearly identical");

        // 文本真的变了：必须重新应用外观
        [captionApp updateCaptionWindowWithText:@"完全不同的另一句" status:@"状态C"];
        Check(countingLabel.fontSetCount == fontsBeforeParaphrase + 1, @"clearly different text must re-apply appearance");
        Check([countingLabel.stringValue isEqualToString:@"完全不同的另一句"], @"caption should show the new text");
        [captionApp.captionPanel orderOut:nil];

        // 贴译面板：内容没变时必须复用同一个 NSPanel，不能 close + 重建（闪烁的根因）
        AppDelegate *inlineApp = [[AppDelegate alloc] init];
        inlineApp.inlineTranslationPanels = [NSMutableArray array];
        inlineApp.inlineTranslationCache = [NSMutableDictionary dictionary];
        inlineApp.captionFontSizeSlider = [NSSlider sliderWithValue:30 minValue:12 maxValue:48 target:nil action:nil];
        WindowItem *fakeWindow = [[WindowItem alloc] init];
        fakeWindow.windowID = 4242;
        fakeWindow.displayName = @"Fake";
        fakeWindow.bounds = CGRectMake(0, 0, 1000, 700);
        inlineApp.windows = [NSMutableArray arrayWithObject:fakeWindow];
        // windowPopup.selectedItem 取不到真实 item 时也要能工作：直接给个空菜单
        inlineApp.windowPopup = [[NSPopUpButton alloc] init];
        [inlineApp.windowPopup addItemWithTitle:@"Fake"];
        inlineApp.windowPopup.menu.itemArray.firstObject.representedObject = @(4242);

        NSArray<OCRTextItem *> *optionItems = @[
            Item(@"うん、空いてるよ", CGRectMake(0.26, 0.72, 0.19, 0.067)),
            Item(@"ちょっと用事があって・・・・・・", CGRectMake(0.15, 0.70, 0.42, 0.053))
        ];
        NSArray<NSString *> *optionTranslations = @[@"嗯，有空哦", @"稍微有点事……"];

        [inlineApp showInlineTranslations:optionTranslations forItems:optionItems];
        NSUInteger panelsAfterFirst = inlineApp.inlineTranslationPanels.count;
        NSPanel *firstPanel = inlineApp.inlineTranslationPanels.firstObject;
        Check(panelsAfterFirst == 2, @"two options should produce two inline panels");

        [inlineApp showInlineTranslations:optionTranslations forItems:optionItems];
        Check(inlineApp.inlineTranslationPanels.count == panelsAfterFirst,
              @"unchanged content must keep the same number of panels");
        Check(inlineApp.inlineTranslationPanels.firstObject == firstPanel,
              @"unchanged content MUST reuse the same NSPanel instances (no close+recreate = no flicker)");

        // 译文变了、或选项被高亮导致 OCR 结果抖动时，必须**复用同一个面板窗口**原地改字，
        // 而不是 close + 新建 —— 后者就是用户看到的“选项在闪”。
        NSPanel *firstPanelBeforeChange = inlineApp.inlineTranslationPanels.firstObject;
        [inlineApp showInlineTranslations:@[@"嗯，有时间", @"有点小事……"] forItems:optionItems];
        Check(inlineApp.inlineTranslationPanels.count == 2, @"changed content should still render two panels");
        Check(inlineApp.inlineTranslationPanels.firstObject == firstPanelBeforeChange,
              @"changed translation MUST update the same NSPanel in place (no close+recreate = no flicker)");
        NSTextField *updatedLabel = (NSTextField *)inlineApp.inlineTranslationPanels.firstObject.contentView.subviews.firstObject;
        Check([updatedLabel.stringValue containsString:@"时间"], @"changed translation must be shown");

        // 位置变化也应原地移动，不重建
        NSPanel *panelBeforeMove = inlineApp.inlineTranslationPanels.firstObject;
        NSArray<OCRTextItem *> *movedItems = @[
            Item(@"うん、空いてるよ", CGRectMake(0.28, 0.70, 0.19, 0.067)),
            Item(@"ちょっと用事があって・・・・・・", CGRectMake(0.15, 0.70, 0.42, 0.053))
        ];
        [inlineApp showInlineTranslations:@[@"嗯，有时间", @"有点小事……"] forItems:movedItems];
        Check(inlineApp.inlineTranslationPanels.firstObject == panelBeforeMove,
              @"a moved option must reposition the same panel, not rebuild it");
        [inlineApp clearInlineTranslationPanels];

        // 截屏不能改变自己浮窗的可见性。
        // 曾经每轮截屏前 hide、截完恢复，hide/orderFront 会把窗口移出再移入 → 用户看到闪烁。
        AppDelegate *captureApp = [[AppDelegate alloc] init];
        [captureApp createCaptionWindow];
        [captureApp.captionPanel orderFrontRegardless];
        BOOL captionVisibleBeforeCapture = captureApp.captionPanel.isVisible;
        captureApp.inlineTranslationPanels = [NSMutableArray array];
        NSUInteger captureCalls = FYTestCaptureCount();
        for (NSInteger i = 0; i < 3; i++) {
            CGImageRef first = [captureApp copyFullCapturedImageForWindow:4242];
            CGImageRef second = [captureApp copyFullCapturedImageForWindow:0];
            Check(first != NULL && second != NULL, @"isolated capture supplies synthetic images");
            CGImageRelease(first); CGImageRelease(second);
        }
        Check(FYTestCaptureCount() == captureCalls + 6, @"all capture calls reach the synthetic boundary");
        Check(captureApp.captionPanel.isVisible == captionVisibleBeforeCapture,
              @"capturing must NOT hide or re-show our own overlay windows (that caused the flicker)");
        [captureApp.captionPanel orderOut:nil];

        WindowRecoveryTestApp *recoveryApp = [[WindowRecoveryTestApp alloc] init];
        [recoveryApp createMainWindow];
        recoveryApp.windows = [NSMutableArray arrayWithObject:TestWindow(101, @"QuickTime Player - 录影")];
        [recoveryApp.windowPopup addItemWithTitle:@"QuickTime Player - 录影"];
        recoveryApp.windowPopup.selectedItem.representedObject = @(101);
        recoveryApp.running = YES;
        recoveryApp.testWindows = @[TestWindow(202, @"QuickTime Player - 录影"), TestWindow(303, @"Safari - 其他窗口")];
        [recoveryApp timerFired:nil];
        Check([recoveryApp selectedWindowID] == 202,
              @"a recreated target window must be selected automatically after capture fails");
        Check([recoveryApp.runStateLabel.stringValue containsString:@"等待目标窗口"],
              @"capture failure must not be shown as actively translating");
        recoveryApp.testWindows = @[TestWindow(303, @"Safari - 其他窗口")];
        recoveryApp.lastWindowRecoveryAttemptDate = nil;
        [recoveryApp timerFired:nil];
        Check([recoveryApp selectedWindowID] == 202,
              @"automatic recovery must not silently switch to an unrelated window");
        [recoveryApp stop];

        recoveryApp.testWindows = @[TestWindow(404, @"QuickTime Player - 打开"), TestWindow(505, @"QuickTime Player - 录影")];
        [recoveryApp refreshWindows:nil];
        Check([recoveryApp selectedWindowID] == 505,
              @"default QuickTime selection must prefer recording content over its open dialog");
        [recoveryApp.windowPopup selectItemWithTitle:@"QuickTime Player - 打开"];
        recoveryApp.testWindows = @[TestWindow(505, @"QuickTime Player - 录影"), TestWindow(606, @"Safari - 其他窗口")];
        recoveryApp.lastWindowRecoveryAttemptDate = nil;
        Check([recoveryApp recoverWindowSelectionIfRecreated] && [recoveryApp selectedWindowID] == 505,
              @"a vanished QuickTime open dialog must rebind to its recording window");
        recoveryApp.windows = [NSMutableArray arrayWithObject:TestWindow(707, @"QuickTime Player - 打开")];
        [recoveryApp.windowPopup removeAllItems];
        [recoveryApp.windowPopup addItemWithTitle:@"QuickTime Player - 打开"];
        recoveryApp.windowPopup.selectedItem.representedObject = @(707);
        recoveryApp.testWindows = @[TestWindow(808, @"QuickTime Player - 录影"), TestWindow(909, @"QuickTime Player - Movie Recording")];
        recoveryApp.lastWindowRecoveryAttemptDate = nil;
        Check(![recoveryApp recoverWindowSelectionIfRecreated] && [recoveryApp selectedWindowID] == 707,
              @"automatic recovery must not guess between multiple recording windows");

        AppDelegate *serviceApp = [[AppDelegate alloc] init];
        [serviceApp createMainWindow];
        serviceApp.baseURLField.stringValue = @"gpt";
        Check([serviceApp chatCompletionsURL] == nil,
              @"a relative Base URL must fail validation before any request is sent");
        serviceApp.baseURLField.stringValue = @"https://api.deepseek.com";
        Check([[[serviceApp chatCompletionsURL] absoluteString] isEqualToString:@"https://api.deepseek.com/chat/completions"],
              @"a valid service URL must keep the existing chat-completions endpoint");
        [serviceApp showError:@"Base URL 无效"];
        Check(!serviceApp.liveErrorLabel.hidden && [serviceApp.liveErrorLabel.stringValue containsString:@"Base URL"],
              @"translation errors must stay visible on the live workbench");
        [serviceApp showError:@""];
        Check(serviceApp.liveErrorLabel.hidden, @"the live error must clear after a successful result");

        // 回归：停止翻译必须把贴译面板收干净。
        // 面板由定时循环负责清理，循环一停就没人管 —— 用户会看到译文一直留在屏幕上。
        AppDelegate *stopApp = [[AppDelegate alloc] init];
        stopApp.inlineTranslationPanels = [NSMutableArray array];
        stopApp.inlineTranslationCache = [NSMutableDictionary dictionary];
        stopApp.captionFontSizeSlider = [NSSlider sliderWithValue:30 minValue:12 maxValue:48 target:nil action:nil];
        WindowItem *stopWindow = [[WindowItem alloc] init];
        stopWindow.windowID = 777;
        stopWindow.displayName = @"Fake";
        stopWindow.bounds = CGRectMake(0, 0, 1000, 700);
        stopApp.windows = [NSMutableArray arrayWithObject:stopWindow];
        stopApp.windowPopup = [[NSPopUpButton alloc] init];
        [stopApp.windowPopup addItemWithTitle:@"Fake"];
        stopApp.windowPopup.menu.itemArray.firstObject.representedObject = @(777);
        [stopApp createCaptionWindow];
        [stopApp showInlineTranslations:@[@"嗯，有空哦"] forItems:@[Item(@"うん、空いてるよ", CGRectMake(0.26, 0.72, 0.19, 0.067))]];
        Check(stopApp.inlineTranslationPanels.count == 1, @"sanity: one inline panel should exist before stopping");
        [stopApp stop];
        Check(stopApp.inlineTranslationPanels.count == 0,
              @"stopping translation MUST close every inline panel (otherwise translations stay on screen)");
        Check(stopApp.timer == nil, @"stopping translation should invalidate the timer");
        stopApp.running = YES;
        [stopApp handleInlineTranslationResult:@[@"迟到译文"]
                                      forItems:@[Item(@"遅い", CGRectMake(0.26, 0.72, 0.19, 0.067))]
                                         error:nil failureStatus:@"出错" successPrefix:@"已更新"];
        [stopApp stop];
        [[NSRunLoop currentRunLoop] runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.05]];
        Check(stopApp.inlineTranslationPanels.count == 0, @"a queued inline result must not redraw after stop");
        [stopApp.captionPanel orderOut:nil];

        // 回归：界面模式的重复请求节流必须明显短于对白模式。
        // 曾经统一 4 秒，用户滑动界面要等满 4 秒才开始翻译（实测“5 秒后才翻出来”）。
        AppDelegate *throttleApp = [[AppDelegate alloc] init];
        Check([throttleApp translationAttemptThrottleForMode:ContentModeUI] <= 1.5,
              @"interface mode must retry quickly (users are actively scrolling)");
        Check([throttleApp translationAttemptThrottleForMode:ContentModeDialogue] >= 3.0,
              @"dialogue mode should still throttle hard against OCR jitter");
        Check([throttleApp translationAttemptThrottleForMode:ContentModeUI] <
              [throttleApp translationAttemptThrottleForMode:ContentModeDialogue],
              @"interface throttle must be strictly shorter than dialogue throttle");

        // 回归：实时模型必须独立于“模型名”。
        // 之前只有“模型名”一个字段，用户挂了推理模型（deepseek-v4-pro）后，
        // 实时翻译每轮要等 20+ 秒、还只回思考内容 —— 等于没有译文。
        AppDelegate *modelApp = [[AppDelegate alloc] init];
        modelApp.modelField = [[NSTextField alloc] init];
        modelApp.modelField.stringValue = @"deepseek-v4-pro";
        modelApp.realtimeModelField = [[NSTextField alloc] init];
        modelApp.realtimeModelField.stringValue = @"deepseek-flash";
        Check([modelApp.modelField.stringValue isEqualToString:@"deepseek-v4-pro"],
              @"sanity: the high-quality model field should hold the reasoning model");
        Check([modelApp.realtimeModelField.stringValue isEqualToString:@"deepseek-flash"],
              @"the realtime model must be able to hold a fast model independently");

        // 回归：界面模式不能套用对白模式的“噪声词表”。
        // 之前两者共用一张忽略表，导致「No. 48 5/1更新」被 “更新” 命中而整条不翻，
        // 「詳細」「戻る」这类按钮也永远不翻 —— 用户直接看到漏文本。
        AppDelegate *filterApp = [[AppDelegate alloc] init];
        NSArray<OCRTextItem *> *uiTexts = @[
            Item(@"No. 48 5/1更新", CGRectMake(0.40, 0.32, 0.14, 0.039)),
            Item(@"詳細", CGRectMake(0.87, 0.27, 0.04, 0.034)),
            Item(@"掘り出し物を探しにフリマへ行こう！", CGRectMake(0.38, 0.24, 0.34, 0.049)),
            Item(@"9/1更新", CGRectMake(0.84, 0.81, 0.06, 0.034))
        ];
        NSArray<OCRTextItem *> *uiKept = [filterApp filteredInlineTextItems:uiTexts strict:NO];
        NSMutableArray<NSString *> *uiKeptTexts = [NSMutableArray array];
        for (OCRTextItem *item in uiKept) { [uiKeptTexts addObject:item.text]; }
        Check([uiKeptTexts containsObject:@"No. 48 5/1更新"],
              @"interface mode must keep list rows like 'No. 48 5/1更新' (the word 更新 is not noise there)");
        Check([uiKeptTexts containsObject:@"詳細"], @"interface mode must keep button labels like 詳細");
        Check([uiKeptTexts containsObject:@"9/1更新"], @"interface mode must keep update badges");
        Check([uiKeptTexts containsObject:@"掘り出し物を探しにフリマへ行こう！"], @"interface mode must keep item body text");

        // 对白模式仍然要丢掉这些，避免把菜单/按钮混进字幕
        NSArray<OCRTextItem *> *dialogueKept = [filterApp filteredInlineTextItems:uiTexts strict:YES];
        NSMutableArray<NSString *> *dialogueTexts = [NSMutableArray array];
        for (OCRTextItem *item in dialogueKept) { [dialogueTexts addObject:item.text]; }
        Check(![dialogueTexts containsObject:@"詳細"], @"dialogue mode should still drop button labels");
        Check(![dialogueTexts containsObject:@"No. 48 5/1更新"], @"dialogue mode should still drop list rows");
        Check([dialogueTexts containsObject:@"掘り出し物を探しにフリマへ行こう！"], @"dialogue mode keeps real sentences");

        // 回归：按钮类文字必须排在队尾，且不能挤掉正文。
        // 贴译按这个顺序逐条生成，按钮排最后就不会和正文抢显示位置。
        // 注意每条文本要唯一 —— 相同文本会被去重，那样就测不到上限行为。
        AppDelegate *orderApp = [[AppDelegate alloc] init];
        NSMutableArray<OCRTextItem *> *buttonMixSample = [NSMutableArray array];
        for (NSUInteger i = 0; i < 12; i++) {
            [buttonMixSample addObject:Item([NSString stringWithFormat:@"本文の長い行その%luです", (unsigned long)i],
                                            CGRectMake(0.35, 0.85 - 0.05 * i, 0.30, 0.04))];
        }
        NSArray<NSString *> *buttonLabels = @[@"詳細", @"戻る", @"閉じる", @"次へ",
                                              @"決定", @"設定", @"メニュー", @"スキップ"];
        for (NSUInteger i = 0; i < buttonLabels.count; i++) {
            [buttonMixSample addObject:Item(buttonLabels[i], CGRectMake(0.87, 0.80 - 0.05 * i, 0.04, 0.03))];
        }
        Check(buttonMixSample.count == 20, @"sanity: the ordering sample should contain 20 unique items");

        NSArray<OCRTextItem *> *ordered = [orderApp filteredInlineTextItems:buttonMixSample strict:NO];
        Check(ordered.count == 20, @"all 20 unique items should survive the cap");
        NSInteger firstButtonIndex = -1;
        NSInteger lastContentIndex = -1;
        for (NSUInteger i = 0; i < ordered.count; i++) {
            BOOL isButton = [orderApp isButtonLikeInlineText:NormalizeForComparison(ordered[i].text)];
            if (isButton && firstButtonIndex < 0) { firstButtonIndex = (NSInteger)i; }
            if (!isButton) { lastContentIndex = (NSInteger)i; }
        }
        Check(firstButtonIndex > 0 && lastContentIndex >= 0, @"the sample should contain both buttons and content");
        Check(lastContentIndex < firstButtonIndex,
              @"button labels must all come AFTER every content line (buttons sorted to the end)");

        // 按钮不能挤掉正文：13 条正文 + 12 个按钮、上限 20 → 正文全部保留，按钮只补 7 个
        NSMutableArray<OCRTextItem *> *crowded = [NSMutableArray array];
        for (NSUInteger i = 0; i < 13; i++) {
            [crowded addObject:Item([NSString stringWithFormat:@"長い本文その%lu行目です", (unsigned long)i],
                                    CGRectMake(0.30, 0.90 - 0.04 * i, 0.32, 0.035))];
        }
        for (NSUInteger i = 0; i < 12; i++) {
            [crowded addObject:Item([NSString stringWithFormat:@"項目%lu", (unsigned long)i],
                                    CGRectMake(0.85, 0.85 - 0.04 * i, 0.06, 0.03))];
        }
        NSArray<OCRTextItem *> *crowdedKept = [orderApp filteredInlineTextItems:crowded strict:NO];
        NSUInteger keptContent = 0;
        NSUInteger keptButtons = 0;
        for (OCRTextItem *item in crowdedKept) {
            if ([orderApp isButtonLikeInlineText:NormalizeForComparison(item.text)]) { keptButtons += 1; }
            else { keptContent += 1; }
        }
        // 只断言“规律”而不是精确条数：条数受去重和评分影响，硬编码会变成脆弱测试
        Check(keptContent + keptButtons <= 20, @"the cap should never exceed 20 items");
        if (keptButtons > 0) {
            NSInteger firstBtn = -1;
            NSInteger lastContent = -1;
            for (NSUInteger i = 0; i < crowdedKept.count; i++) {
                BOOL isButton = [orderApp isButtonLikeInlineText:NormalizeForComparison(crowdedKept[i].text)];
                if (isButton && firstBtn < 0) { firstBtn = (NSInteger)i; }
                if (!isButton) { lastContent = (NSInteger)i; }
            }
            Check(lastContent < firstBtn, @"buttons must never appear before content lines");
        }

        // 回归：贴译面板之间不许互相遮挡。
        // 弹窗里几行正文都是全宽覆盖式面板、又各自贴着原文，很容易重叠；
        // 后画的会把先画的整句盖住 —— 用户看到的就是“少了一句”。
        AppDelegate *overlapApp = [[AppDelegate alloc] init];
        overlapApp.inlineTranslationPanels = [NSMutableArray array];
        overlapApp.inlineTranslationCache = [NSMutableDictionary dictionary];
        overlapApp.captionFontSizeSlider = [NSSlider sliderWithValue:30 minValue:12 maxValue:48 target:nil action:nil];
        overlapApp.captionOpacitySlider = [NSSlider sliderWithValue:0.58 minValue:0 maxValue:1 target:nil action:nil];
        WindowItem *overlapWindow = [[WindowItem alloc] init];
        overlapWindow.windowID = 555;
        overlapWindow.displayName = @"Fake";
        overlapWindow.bounds = CGRectMake(0, 38, 1710, 963);
        overlapApp.windows = [NSMutableArray arrayWithObject:overlapWindow];
        overlapApp.windowPopup = [[NSPopUpButton alloc] init];
        [overlapApp.windowPopup addItemWithTitle:@"Fake"];
        overlapApp.windowPopup.menu.itemArray.firstObject.representedObject = @(555);

        NSArray<OCRTextItem *> *tallItems = @[
            Item(@"充満意外不知約昆虫知識がいっぱい！キッズも楽", CGRectMake(0.27, 0.52, 0.48, 0.044)),
            Item(@"世界中の珍しい昆虫をたくさん見られるチャンス！", CGRectMake(0.27, 0.41, 0.48, 0.049)),
            Item(@"ぜひ博物館へ。", CGRectMake(0.27, 0.29, 0.20, 0.035)),
            Item(@"も開催予定です。たった一日で、", CGRectMake(0.27, 0.44, 0.40, 0.030))
        ];
        NSArray<NSString *> *tallTranslations = @[@"充满意外不知的昆虫知识！孩子们也开心",
                                                  @"观察世界上珍贵昆虫的好机会！",
                                                  @"请借此机会来博物馆。",
                                                  @"也将举办收尾活动。仅一天，"];
        [overlapApp showInlineTranslations:tallTranslations forItems:tallItems];
        NSMutableArray<NSValue *> *panelFrames = [NSMutableArray array];
        for (NSPanel *panel in overlapApp.inlineTranslationPanels) {
            [panelFrames addObject:[NSValue valueWithRect:panel.frame]];
        }
        Check(panelFrames.count == 4, @"the overlap sample should produce four panels");
        // 允许**轻度**重叠：为了保住阅读顺序，宁可轻微压边也不把译文挪到别的句子上面。
        // 但不能大面积互相盖住 —— 那才真的会吞掉一整句。
        for (NSUInteger i = 0; i < panelFrames.count; i++) {
            for (NSUInteger k = i + 1; k < panelFrames.count; k++) {
                CGRect a = panelFrames[i].rectValue;
                CGRect b = panelFrames[k].rectValue;
                CGRect hit = CGRectIntersection(a, b);
                if (CGRectIsNull(hit)) { continue; }
                CGFloat overlapArea = hit.size.width * hit.size.height;
                CGFloat smallerArea = MIN(a.size.width * a.size.height, b.size.width * b.size.height);
                Check(smallerArea > 0 && (overlapArea / smallerArea) < 0.30,
                      @"panels may touch slightly but must not swallow each other (that hides a sentence)");
            }
        }
        [overlapApp clearInlineTranslationPanels];

        // 回归：译文面板必须留在**各自原文附近**，绝不能被避让推到别的句子上面。
        // 之前避让只会“向上找空位”，会把第三行顶到所有面板之上（实测偏移 +257px），
        // 阅读顺序一乱，译文和原文就对不上了。
        AppDelegate *anchorApp = [[AppDelegate alloc] init];
        anchorApp.inlineTranslationPanels = [NSMutableArray array];
        anchorApp.inlineTranslationCache = [NSMutableDictionary dictionary];
        anchorApp.captionFontSizeSlider = [NSSlider sliderWithValue:30 minValue:12 maxValue:48 target:nil action:nil];
        anchorApp.captionOpacitySlider = [NSSlider sliderWithValue:0.58 minValue:0 maxValue:1 target:nil action:nil];
        WindowItem *anchorWindow = [[WindowItem alloc] init];
        anchorWindow.windowID = 666;
        anchorWindow.displayName = @"Fake";
        anchorWindow.bounds = CGRectMake(0, 19, 1710, 979);
        anchorApp.windows = [NSMutableArray arrayWithObject:anchorWindow];
        anchorApp.windowPopup = [[NSPopUpButton alloc] init];
        [anchorApp.windowPopup addItemWithTitle:@"Fake"];
        anchorApp.windowPopup.menu.itemArray.firstObject.representedObject = @(666);

        // 四行紧挨着的弹窗正文（真实实测坐标）
        NSArray<OCRTextItem *> *stackedItems = @[
            Item(@"充満意外不知の昆虫知識がいっぱい！キッズも楽", CGRectMake(0.27, 0.523, 0.48, 0.041)),
            Item(@"も開催予定です。たった一日で、", CGRectMake(0.27, 0.464, 0.45, 0.044)),
            Item(@"世界中の珍しい昆虫をたくさん見られるチャンス！", CGRectMake(0.27, 0.410, 0.47, 0.049)),
            Item(@"ぜひ博物館へ。", CGRectMake(0.27, 0.355, 0.24, 0.051))
        ];
        NSArray<NSString *> *stackedTranslations = @[@"充满意外冷门的昆虫知识！孩子们也开心",
                                                     @"也将举办收尾活动。仅一天，",
                                                     @"能见到世界各地众多珍稀昆虫的机会！",
                                                     @"请借此机会来博物馆。"];
        [anchorApp showInlineTranslations:stackedTranslations forItems:stackedItems];

        NSRect anchorWindowFrame = [anchorApp appKitFrameForWindowItem:anchorWindow];
        Check(anchorApp.inlineTranslationPanels.count == 4, @"sanity: four stacked panels");
        // 旧断言要求“四条贴片的中心偏移基本一致”。那个性质只有在允许贴片**压住下一行原文**
        // 时才成立（同一列的贴片一起往下压，偏移自然一致）。本轮需求明确禁止译文遮挡其它
        // 原文块（见 objc/FYInlineLayout.h 的候选合法性规则），因此改成直接断言两条更强的性质：
        //   ① 每条贴片仍锚定在**自己的**原文上：与原文的垂直偏移有界，绝不漂到别的句子；
        //   ② 任何贴片都不覆盖其它原文框（旧的“一致偏移”靠的正是这种覆盖）。
        for (NSUInteger i = 0; i < anchorApp.inlineTranslationPanels.count && i < stackedItems.count; i++) {
            NSPanel *panel = anchorApp.inlineTranslationPanels[i];
            NSRect sourceFrame = [anchorApp appKitFrameForOCRItem:stackedItems[i] inWindowFrame:anchorWindowFrame];
            CGFloat offset = CGRectGetMidY(panel.frame) - CGRectGetMidY(sourceFrame);
            Check(fabs(offset) <= MAX(NSHeight(sourceFrame), NSHeight(panel.frame)) + 8,
                  @"every panel must stay anchored to its own source line (placement must not jump across sentences)");
            for (NSUInteger j = 0; j < stackedItems.count; j++) {
                if (j == i) { continue; }
                NSRect otherSource = [anchorApp appKitFrameForOCRItem:stackedItems[j] inWindowFrame:anchorWindowFrame];
                Check(!CGRectIntersectsRect(panel.frame, otherSource),
                      @"no patch may cover another source line (the old uniform-offset rule did exactly that)");
            }
        }
        [anchorApp clearInlineTranslationPanels];

        // 回归：覆盖式（长正文）面板必须**中心对齐原文框**，真正盖在原文上。
        // 旧公式 y = 原文框顶部 - 面板高度 + 4 把面板“底部”钉在原文框顶部附近，
        // 面板一高就整体往上飘（实测对白框跑高 0.07，上沿顶到 QuickTime 音量条）。
        AppDelegate *alignApp = [[AppDelegate alloc] init];
        alignApp.captionFontSizeSlider = [NSSlider sliderWithValue:30 minValue:12 maxValue:48 target:nil action:nil];
        alignApp.captionOpacitySlider = [NSSlider sliderWithValue:0.58 minValue:0 maxValue:1 target:nil action:nil];
        NSRect alignWindow = NSMakeRect(0, 38, 1710, 963);
        // 真实对白：日文两行（源框高约 113px），译文只有两行短句。
        // 旧的高度公式 MAX(译文高度, 源框高度 + 8) 会被日文的高度撑大 → 框里大片留白、看着不贴合。
        OCRTextItem *coverItem = Item(@"この教会の人じゃ、\nないんですか？", CGRectMake(0.29, 0.057, 0.20, 0.116));
        NSRect coverSource = [alignApp appKitFrameForOCRItem:coverItem inWindowFrame:alignWindow];
        NSPanel *coverPanel = [alignApp inlinePanelForTranslation:@"可是，\n你不是这个教会的人吗？"
                                                      sourceText:coverItem.text
                                                     sourceFrame:coverSource
                                                     windowFrame:alignWindow];
        // ① 位置：与原文左对齐、夹在画面内（不再用旧的中心覆盖式摆放）。
        Check(fabs(NSMinX(coverPanel.frame) - NSMinX(coverSource)) < 4,
              @"an inline panel must stay left-aligned with its source line instead of drifting sideways");
        Check(CGRectGetMinX(coverPanel.frame) >= -1 && CGRectGetMaxX(coverPanel.frame) <= NSMaxX(alignWindow) + 1 &&
              CGRectGetMinY(coverPanel.frame) >= -1 && CGRectGetMaxY(coverPanel.frame) <= NSMaxY(alignWindow) + 1,
              @"an inline panel must stay inside the capturable window frame");
        // ② 高度贴合译文，而不是被原文框撑大
        Check(NSHeight(coverPanel.frame) < NSHeight(coverSource) * 0.75,
              @"panel height must hug the translation, not inherit the taller source box (that leaves big empty margins)");
        [coverPanel close];

        // 回归：对白框里的**第一句短台词**不能被丢掉。
        // 真实截图（教会那场）里「平気。」只有 0.06 宽，被候选门槛 w>=0.10 直接剔除，
        // 用户看到的就是“第一句没翻译”。
        NSArray<OCRTextItem *> *shortDialogue = @[
            Item(@"？？？", CGRectMake(0.27, 0.320, 0.06, 0.044)),
            Item(@"平気。", CGRectMake(0.29, 0.247, 0.06, 0.049)),
            Item(@"それより、", CGRectMake(0.29, 0.188, 0.10, 0.043)),
            Item(@"もう、遅いから『起那不，", CGRectMake(0.29, 0.121, 0.24, 0.046)),
            Item(@"送ってく。", CGRectMake(0.29, 0.052, 0.11, 0.052))
        ];
        NSArray<OCRTextItem *> *shortBand = SubtitleBandItemsFromBlocks(shortDialogue);
        NSMutableArray<OCRTextItem *> *shortDialogueItems = [NSMutableArray array];
        NSMutableArray<OCRTextItem *> *shortOptionItems = [NSMutableArray array];
        SplitDialogueAndOptionsFromItems(shortBand, shortDialogue, shortDialogueItems, shortOptionItems);
        NSMutableArray<NSString *> *shortTexts = [NSMutableArray array];
        for (OCRTextItem *item in shortDialogueItems) { [shortTexts addObject:item.text]; }
        Check([shortTexts containsObject:@"平気。"],
              @"the first short line of a dialogue box must survive (narrow lines are still dialogue)");
        Check([shortTexts containsObject:@"送ってく。"], @"the last short line must survive too");

        // 回归：我们自己的状态栏文字（会被下一轮 OCR 读回来）必须被剔除
        Check(IsOwnOverlayText(@"译文已更新 · OCR 0.2s 翻译 0.6s 总 0.8s"),
              @"our own caption status line must be recognised as our overlay");
        Check(IsOwnOverlayText(@"本次 3 句"), @"our own sentence counter must be recognised as our overlay");
        Check(!IsOwnOverlayText(@"この教会の人じゃ、"),
              @"real game dialogue must NOT be mistaken for our overlay");

        // 回归：对白框**通篇都是短句**时也必须翻。
        // 真实截图（「思い出した。」那一屏）整框只有 2 条短行，
        // 既过不了 IsDialogueAnchorCandidate（要 w>=0.22 或 len>=10），
        // 又过不了“必须有实质长行”的闸门 → 字幕带为空，一个字都不翻。
        NSArray<OCRTextItem *> *allShortDialogue = @[
            Item(@"？？？（体与", CGRectMake(0.27, 0.193, 0.104, 0.044)),
            Item(@"思い出した。", CGRectMake(0.29, 0.118, 0.131, 0.050))
        ];
        NSArray<OCRTextItem *> *allShortBand = SubtitleBandItemsFromBlocks(allShortDialogue);
        Check(allShortBand.count >= 1,
              @"a dialogue box made only of short sentences must still produce a subtitle band");
        NSMutableArray<NSString *> *allShortTexts = [NSMutableArray array];
        for (OCRTextItem *item in allShortBand) { [allShortTexts addObject:item.text]; }
        Check([allShortTexts containsObject:@"思い出した。"],
              @"the short sentence itself must be included in the band");

        // 反向守护：散落的短招牌**不能**被当成对白。
        // 它们彼此离得远（纵向间隔远超 0.10），不满足“紧挨堆叠”的条件。
        NSArray<OCRTextItem *> *scatteredSigns = @[
            Item(@"立入禁止", CGRectMake(0.10, 0.80, 0.10, 0.040)),
            Item(@"非常口", CGRectMake(0.72, 0.52, 0.09, 0.040)),
            Item(@"売店", CGRectMake(0.20, 0.24, 0.09, 0.040))
        ];
        Check(SubtitleBandItemsFromBlocks(scatteredSigns).count == 0,
              @"scattered short signs must NOT be treated as a dialogue box");

        // 回归：名字框被错读成平假名噪声时，真对白仍然要翻，噪声不能发去翻译。
        // 实测日志：`？？？` 被读成 `ことと` → 被当成“勉强合格的锚点”，
        // 于是短句兜底被跳过，真对白「思い出した。」又丢了；
        // 而噪声本身被发去翻译，模型硬编出「事情与」这种完全不相关的中文。
        NSArray<OCRTextItem *> *misreadFrame = @[
            Item(@"ことと", CGRectMake(0.30, 0.193, 0.09, 0.044)),
            Item(@"思い出した。", CGRectMake(0.29, 0.118, 0.131, 0.050))
        ];
        NSArray<OCRTextItem *> *misreadBand = SubtitleBandItemsFromBlocks(misreadFrame);
        NSMutableArray<NSString *> *misreadBandTexts = [NSMutableArray array];
        for (OCRTextItem *item in misreadBand) { [misreadBandTexts addObject:item.text]; }
        Check([misreadBandTexts containsObject:@"思い出した。"],
              @"a misread character-name line must not stop the real dialogue from reaching the band");

        // 环境无关的守卫：纯平假名短碎片不能发去翻译（界面模式）
        AppDelegate *noiseApp = [[AppDelegate alloc] init];
        NSArray<OCRTextItem *> *noiseItems = @[
            Item(@"ことと", CGRectMake(0.30, 0.193, 0.09, 0.044)),
            Item(@"おはよう", CGRectMake(0.30, 0.150, 0.10, 0.040)),
            Item(@"映画公演スケジュール", CGRectMake(0.10, 0.60, 0.20, 0.040)),
            Item(@"9/1更新", CGRectMake(0.84, 0.81, 0.06, 0.034))
        ];
        NSArray<OCRTextItem *> *noiseKept = [noiseApp filteredInlineTextItems:noiseItems strict:NO];
        NSMutableArray<NSString *> *noiseTexts = [NSMutableArray array];
        for (OCRTextItem *item in noiseKept) { [noiseTexts addObject:item.text]; }
        // 本轮要求（2026-10-06）：只要含有效日文文字，就不能凭“字数少/纯平假名”删掉。
        // 短平假名行（「ことと」「おはよう」「え……」）现在一律保留；宁可偶尔翻出错读，
        // 也不让真台词漏句。完全没有假名/汉字的 ASCII 碎片（iee / ???cJ）仍然过滤。
        Check([noiseTexts containsObject:@"ことと"],
              @"short all-hiragana OCR text must no longer be dropped by character shape");
        Check([noiseTexts containsObject:@"おはよう"],
              @"short all-hiragana fragments must be kept (real dialogue completeness first)");
        Check([noiseTexts containsObject:@"映画公演スケジュール"],
              @"real UI text with kanji must still be translated");
        Check([noiseTexts containsObject:@"9/1更新"], @"update badges must still be translated");

        // 回归：名字框 `？？？` 被 OCR 误读成的各种碎片，都不能发去翻译。
        // 实测同一块区域在不同帧被读成 `ことと` / `iee` / `???cJ` / `事情与`，
        // 发去翻译模型就会编出「事情与」这种完全不相关的中文贴到名字旁边。
        // 这些碎片的共同特征：**短**，且**完全没有日文假名/汉字**。
        // 注意：「ことと」是纯平假名，形状上像正常日文，**不该由形状识别来拒**
        //（否则真实的对白短句会被误杀）。它由下面「界面模式：短且纯平假名」那条守卫负责。
        Check(IsOwnOverlayText(@"iee"), @"short ASCII misread of ？？？ must be rejected");
        Check(IsOwnOverlayText(@"???cJ"), @"short symbol/ASCII misread of ？？？ must be rejected");
        // 「事情与」是我们自己画上去的译文，靠“已渲染文本集合”比对拒掉（不是形状识别）
        NSDictionary *renderedCache = @{@"k": @"事情与"};
        NSSet<NSString *> *renderedSet = RenderedTranslationSet(@"", renderedCache);
        NSArray<OCRTextItem *> *readBack = @[Item(@"事情与", CGRectMake(0.31, 0.120, 0.05, 0.030)),
                                             Item(@"思い出した。", CGRectMake(0.29, 0.118, 0.131, 0.050))];
        NSArray<OCRTextItem *> *readBackKept = OCRItemsExcludingOwnOverlay(readBack, renderedSet);
        Check(readBackKept.count == 1, @"our own rendered translation must be filtered when OCR reads it back");
        Check([readBackKept.firstObject.text isEqualToString:@"思い出した。"],
              @"filtering our own translation must not remove real dialogue");
        // 真实游戏文字绝不能被误杀
        Check(!IsOwnOverlayText(@"思い出した。"), @"real dialogue must not be rejected");
        Check(!IsOwnOverlayText(@"映画公演スケジュール"), @"real menu text must not be rejected");
        Check(!IsOwnOverlayText(@"9/1更新"), @"real update badge must not be rejected");

        // 纯假名 / 纯拉丁字母的碎片由界面模式筛选拦下；
        // 「事情与」含汉字，形状上和正常日文无异，**只能**靠“已渲染译文集合”比对拦住
        // —— 所以这两道防线要分别断言，不能混在一起要求同一个函数全包。
        NSArray<OCRTextItem *> *junkItems = @[
            Item(@"ことと", CGRectMake(0.30, 0.193, 0.09, 0.044)),
            Item(@"iee", CGRectMake(0.30, 0.150, 0.05, 0.030))
        ];
        AppDelegate *junkApp = [[AppDelegate alloc] init];
        NSArray<OCRTextItem *> *junkKept = [junkApp filteredInlineTextItems:junkItems strict:NO];
        Check(junkKept.count == 1 && [junkKept.firstObject.text isEqualToString:@"ことと"],
              @"only the fragment with no kana/kanji is dropped; hiragana text is kept");
        // 对白路径不负责拦这类碎片：它由「字幕带」规则把关
        //（噪声宽度/长度都进不了 band）。这里只确认噪声确实进不了字幕带。
        Check(SubtitleBandItemsFromBlocks(junkItems).count == 0,
              @"short OCR noise must not form a subtitle band");

        // 守卫：Vision 的 minimumTextHeight 必须留在 0.02。
        // 这个参数对小字极敏感：实测同一张截图，0.01/0.015 只读到名字框的错读 `ことと`，
        // **对白正文「思い出した。」完全读不到**（表现为整句对白凭空消失），
        // 而 0.02 能正常读出。它不在运行时数据里，只能靠源码断言守住。
        NSString *sourcePath = [NSString stringWithFormat:@"%s/../objc/LiveCaptionTranslator.m", __FILE__];
        NSString *sourceText = [NSString stringWithContentsOfFile:sourcePath
                                                        encoding:NSUTF8StringEncoding
                                                           error:NULL];
        if (sourceText.length > 0) {
            NSUInteger occurrences = 0;
            NSRange searchRange = NSMakeRange(0, sourceText.length);
            while (YES) {
                NSRange found = [sourceText rangeOfString:@"request.minimumTextHeight" options:0 range:searchRange];
                if (found.location == NSNotFound) { break; }
                occurrences += 1;
                NSUInteger next = NSMaxRange(found);
                searchRange = NSMakeRange(next, sourceText.length - next);
            }
            Check(occurrences >= 2, @"both Vision request paths should set minimumTextHeight explicitly");
            // 自适应：按图像高度换算（目标约 28px），因为固定比例在不同窗口尺寸下会失效。
            // 实测 2727×1536 时 0.02 正好，1710×963 时文字占比 0.054，0.02 会把对白漏掉。
            Check([sourceText rangeOfString:@"targetTextPixels / imageHeight"].location != NSNotFound,
                  @"the primary OCR path must scale minimumTextHeight to the image height");
            // 目标像素必须够大：实测对白高 52px，28px 读不到，48px 才读到。
            Check([sourceText rangeOfString:@"fastOCR ? 32.0 : 48.0"].location != NSNotFound,
                  @"the target text height must be 48px (28px still drops the 52px dialogue)");
            Check([sourceText rangeOfString:@"minimumTextHeight = 0.02;"].location != NSNotFound,
                  @"the enlarged second-pass OCR path must also use minimumTextHeight 0.02");
        }

        // 回归：OCR 会把紧邻对白的小按钮粘进同一行（实测 `思い出した。使用`）。
        // 不切掉的话模型照着输出「想起来了。使用」，按钮文字就混进了字幕。
        Check([DialogueTextWithoutTrailingButton(@"思い出した。使用") isEqualToString:@"思い出した。"],
              @"a trailing UI button glued onto the dialogue by OCR must be stripped before translation");
        Check([DialogueTextWithoutTrailingButton(@"それは、使用") isEqualToString:@"それは、"],
              @"the same stripping must work after a comma");
        // 真实对白绝不能被误切
        Check([DialogueTextWithoutTrailingButton(@"思い出した。") isEqualToString:@"思い出した。"],
              @"plain dialogue must be left untouched");
        Check([DialogueTextWithoutTrailingButton(@"送ってく。") isEqualToString:@"送ってく。"],
              @"kana-ending dialogue must be left untouched");
        Check([DialogueTextWithoutTrailingButton(@"もう、遅いから") isEqualToString:@"もう、遅いから"],
              @"dialogue without trailing punctuation must be left untouched");
        Check([DialogueTextWithoutTrailingButton(@"確認") isEqualToString:@"確認"],
              @"a bare kanji word must NOT be stripped (no kana in the string)");

        // 本轮改动：名字框 `？？？` 的错读（短、窄、全平假名）不再由形状判据删除 ——
        // 「只要含有效日文文字，就不能凭字数少/框窄删」。代价是这类错读可能被翻出来，
        // 换取的保证是真台词（「え……」这种单字台词）绝不再漏。
        AppDelegate *nameApp = [[AppDelegate alloc] init];
        OCRTextItem *nameProbe = Item(@"ここと", CGRectMake(0.27, 0.198, 0.062, 0.034));
        Check(![nameApp shouldIgnoreInlineText:@"ここと"
                                    normalized:NormalizeForComparison(@"ここと")
                                   boundingBox:nameProbe.boundingBox
                                        strict:YES],
              @"short hiragana text must survive strict filtering (no shape-based deletion)");
        // 真实短对白带假名以外的成分，不能被误杀
        OCRTextItem *realLine = Item(@"送ってく。", CGRectMake(0.29, 0.052, 0.11, 0.052));
        Check(![nameApp shouldIgnoreInlineText:@"送ってく。"
                                    normalized:NormalizeForComparison(@"送ってく。")
                                   boundingBox:realLine.boundingBox
                                        strict:YES],
              @"real short dialogue must survive the name-box guard");

        // 回归：状态栏被 OCR 截断后关键词会丢，但计时格式 `0.6s` 还在。
        // 漏掉的话这半截状态行会被当成台词送进字幕。
        Check(IsOwnOverlayText(@"翻译 0.6s 总 0.8s"), @"a truncated caption status fragment must still be recognised");
        Check(IsOwnOverlayText(@"OCR 0.2s"), @"a bare timing fragment must be recognised as our overlay");
        Check(!IsOwnOverlayText(@"思い出した。"), @"dialogue containing no timing must not be mistaken for status");

        // 回归：贴边规则不能把贴在画面下方的对白整句丢掉。
        // `送ってく。`（宽 0.11、y=0.052）本来满足“贴边且短”，于是最后一行对白消失。
        AppDelegate *edgeApp = [[AppDelegate alloc] init];
        OCRTextItem *bottomDialogue = Item(@"送ってく。", CGRectMake(0.29, 0.052, 0.11, 0.052));
        Check(![edgeApp shouldIgnoreInlineText:@"送ってく。"
                                    normalized:NormalizeForComparison(@"送ってく。")
                                   boundingBox:bottomDialogue.boundingBox
                                        strict:YES],
              @"dialogue sitting at the bottom edge must not be dropped (only narrow buttons should be)");
        OCRTextItem *bottomButton = Item(@"戻る", CGRectMake(0.02, 0.02, 0.06, 0.030));
        Check([edgeApp shouldIgnoreInlineText:@"戻る"
                                    normalized:NormalizeForComparison(@"戻る")
                                   boundingBox:bottomButton.boundingBox
                                        strict:YES],
              @"a genuinely narrow corner button must still be dropped");

        // 回归：单行对白（没有名字框、没有第二行）不能被误判成界面。
        // 实测「まあだだよ！」「もういいかい？」「（そうだ・・・」都是单行台词，
        // 之前“短句兜底”要求相邻行堆叠 → 单行被拒 → band=0 → 判成界面贴译。
        NSArray<OCRTextItem *> *singleLines = @[
            Item(@"まあだだよ！", CGRectMake(0.29, 0.11, 0.12, 0.054)),
            Item(@"もういいかい？", CGRectMake(0.29, 0.11, 0.13, 0.054)),
            Item(@"（そうだ・・・", CGRectMake(0.29, 0.11, 0.12, 0.054))
        ];
        for (OCRTextItem *line in singleLines) {
            Check(SubtitleBandItemsFromBlocks(@[line]).count >= 1,
                  @"a single dialogue line ending with punctuation must form a band");
        }

        // 反向守护：以句末标点结尾但明显是招牌的，仍然不能当对白。
        // （这里用“纯数字+句号”验证，结尾是句号但内容不是台词）
        OCRTextItem *sign = Item(@"3F。", CGRectMake(0.10, 0.80, 0.08, 0.035));
        Check(SubtitleBandItemsFromBlocks(@[sign]).count == 0,
              @"a numeric sign ending in 。must NOT be treated as dialogue");

        // 回归：状态栏被 OCR 读花之后，仍必须被认出是我们自己的浮窗。
        // 实测 `译文已要新・OCR 0.25南译0.3550.55）。••` —— 关键词「译文已更新」被打断、
        // `0.2s` 变成 `0.25南`，旧判定要求含「秒/句/s」于是漏过，
        // 这行乱码就混进字幕带被当成台词送去翻译，模型给出一句完全不相干的译文。
        Check(IsOwnOverlayText(@"译文已要新・OCR 0.25南译0.3550.55）。••"),
              @"a garbled caption status line must still be recognised as our own overlay");
        Check(IsOwnOverlayText(@"译文已更新 OCR 0.2s"), @"a clean status line must be recognised");
        Check(IsOwnOverlayText(@"翻译 0.6s 总 0.8s"), @"a truncated status fragment must be recognised");
        // 真实台词不能被误杀
        Check(!IsOwnOverlayText(@"行くぞ。"), @"plain dialogue must not be taken for a status line");
        Check(!IsOwnOverlayText(@"思い出した。"), @"plain dialogue must not be taken for a status line");
        Check(!IsOwnOverlayText(@"智恵、"), @"a name-like line must not be taken for a status line");

        // 回归：很短的台词行（实测「行くぞ。」只有 0.08 宽）也必须能成立为对白。
        // 宽度门槛原来卡在 0.09，于是这行 band=0 → 被误判成界面贴译。
        OCRTextItem *shortLine = Item(@"行くぞ。", CGRectMake(0.29, 0.054, 0.080, 0.049));
        Check(SubtitleBandItemsFromBlocks(@[shortLine]).count >= 1,
              @"a very short dialogue line ending in 。must still form a band (it is only 0.08 wide)");

        // 端到端：这一帧的完整流程里，我方状态栏不得进入字幕带
        NSArray<OCRTextItem *> *mixedFrame = @[
            Item(@"コウ", CGRectMake(0.27, 0.196, 0.039, 0.039)),
            Item(@"译文已要新・OCR 0.25南译0.3550.55）。••", CGRectMake(0.22, 0.129, 0.170, 0.028)),
            Item(@"行くぞ。", CGRectMake(0.29, 0.054, 0.080, 0.049))
        ];
        NSArray<OCRTextItem *> *mixedFresh = OCRItemsExcludingOwnOverlay(mixedFrame, RenderedTranslationSet(@"", @{}));
        NSArray<OCRTextItem *> *mixedBand = SubtitleBandItemsFromBlocks(mixedFresh);
        NSMutableArray<NSString *> *mixedTexts = [NSMutableArray array];
        for (OCRTextItem *item in mixedBand) { [mixedTexts addObject:item.text]; }
        Check([mixedTexts containsObject:@"行くぞ。"], @"the real dialogue must reach the band");
        for (NSString *text in mixedTexts) {
            Check(![text containsString:@"OCR"], @"our own status line must never enter the dialogue band");
        }

        // 回归：只有**纯省略号/纯标点**（没有假名汉字）才没有可译内容，可以丢弃。
        // 含假名或汉字的行一律保留 —— 包括 `ちえつ・・・`：它可能是纯省略号被 OCR 认错，
        // 也可能确实是台词，仅凭文本分不出来；本轮没有额外证据，按“保留”处理（用户明确要求），
        // 也暂不新增连续帧判断机制。
        AppDelegate *dotsApp = [[AppDelegate alloc] init];
        OCRTextItem *dotsLine = Item(@"ちえつ・・・", CGRectMake(0.29, 0.110, 0.116, 0.055));
        Check(![dotsApp shouldIgnoreInlineText:@"ちえつ・・・"
                                    normalized:NormalizeForComparison(@"ちえつ・・・")
                                   boundingBox:dotsLine.boundingBox
                                        strict:YES],
              @"kana + ellipsis must be kept (it may be a misread ellipsis, but it may also be a line)");
        OCRTextItem *pureDots = Item(@"・・・・・・・", CGRectMake(0.29, 0.110, 0.116, 0.055));
        Check([dotsApp shouldIgnoreInlineText:@"・・・・・・・"
                                   normalized:NormalizeForComparison(@"・・・・・・・")
                                  boundingBox:pureDots.boundingBox
                                       strict:YES],
              @"a pure-dots line must not be translated");
        // 关键：**以省略号结尾的真台词不能被当成噪声丢掉**。
        // 实测「退学って・・・・・・」是 4 字 + 6 个点（占比 0.67），只按占比判会被丢掉 →
        // 第一句不翻；而 OCR 每轮读到的点数还不一样，于是它时有时无、送出去的文本一直在变，
        // 表现就是“译文一直在变、两次含义还不一致”。判据必须同时要求“实义部分无汉字/片假名”。
        OCRTextItem *ellipsisDialogue = Item(@"退学って・・・・・・", CGRectMake(0.29, 0.12, 0.20, 0.05));
        Check(![dotsApp shouldIgnoreInlineText:@"退学って・・・・・・"
                                    normalized:NormalizeForComparison(@"退学って・・・・・・")
                                   boundingBox:ellipsisDialogue.boundingBox
                                        strict:YES],
              @"real dialogue ending in ellipses must be translated (has kanji, so it is not noise)");
        OCRTextItem *ellipsisDialogue2 = Item(@"退学って・・・・・•", CGRectMake(0.29, 0.12, 0.20, 0.05));
        Check(![dotsApp shouldIgnoreInlineText:@"退学って・・・・・•"
                                    normalized:NormalizeForComparison(@"退学って・・・・・•")
                                   boundingBox:ellipsisDialogue2.boundingBox
                                        strict:YES],
              @"a different dot count for the same line must also be kept (otherwise the text flickers)");
        OCRTextItem *kanaEllipsis = Item(@"なんて言うか・・・", CGRectMake(0.29, 0.12, 0.20, 0.05));
        Check(![dotsApp shouldIgnoreInlineText:@"なんて言うか・・・"
                                    normalized:NormalizeForComparison(@"なんて言うか・・・")
                                   boundingBox:kanaEllipsis.boundingBox
                                        strict:YES],
              @"a kana line with fewer dots than half must be kept");

        // 2026-10-04 现场回归：真台词 `どれど……` 被 Vision 读成 `どれど......`（6 个点，
        // 占比 0.67）时，旧的“占比 ≥50%”判据把整行丢掉 → 画面上两行对白只翻出一行。
        // 现场噪声行（`ちえつ・・・`）框宽只有 0.116，真台词那行接近 0.22：宽框必须保留。
        for (NSString *variant in @[@"どれど......", @"どれど・・・", @"どれど…"]) {
            OCRTextItem *realLine = Item(variant, CGRectMake(0.27, 0.30, 0.22, 0.05));
            Check(![dotsApp shouldIgnoreInlineText:variant
                                        normalized:NormalizeForComparison(variant)
                                       boundingBox:realLine.boundingBox
                                            strict:YES],
                  @"a wide real dialogue line ending in ellipses must still be translated");
        }

        // 含省略号的台词：只要含假名/汉字就一律保留（不再有“三字+省略号”的取舍）。
        OCRTextItem *realDots = Item(@"（そうだ・・・", CGRectMake(0.29, 0.110, 0.150, 0.055));
        Check(![dotsApp shouldIgnoreInlineText:@"（そうだ・・・"
                                    normalized:NormalizeForComparison(@"（そうだ・・・")
                                   boundingBox:realDots.boundingBox
                                        strict:YES],
              @"a line with an ellipsis but enough content must still be translated");

        // 用户现场案例：`あれは・・・・・・`（框宽 0.115987）曾被窄框判据整行删除。
        // 现在同一句话必须在**不同框宽、不同数量与形式的省略号**下都保留有效文字。
        NSArray<NSString *> *realEllipsisLines = @[
            @"あれは・・・・・・", @"そうだ・・・", @"どれど......", @"え……", @"退学って・・・・・・"
        ];
        NSArray<NSNumber *> *ellipsisWidths = @[@(0.06), @(0.116), @(0.16), @(0.25)];
        for (NSString *line in realEllipsisLines) {
            for (NSNumber *width in ellipsisWidths) {
                OCRTextItem *probe = Item(line, CGRectMake(0.29, 0.11, width.doubleValue, 0.055));
                Check(![dotsApp shouldIgnoreInlineText:line
                                            normalized:NormalizeForComparison(line)
                                           boundingBox:probe.boundingBox
                                                strict:YES],
                      [NSString stringWithFormat:@"<%@> 宽 %.3f 时必须保留", line, width.doubleValue]);
                Check(![dotsApp shouldIgnoreInlineText:line
                                            normalized:NormalizeForComparison(line)
                                           boundingBox:probe.boundingBox
                                                strict:NO],
                      [NSString stringWithFormat:@"<%@> 宽 %.3f 在贴译路径也必须保留", line, width.doubleValue]);
            }
        }
        // 纯省略号仍然过滤（没有假名汉字）
        for (NSString *pure in @[@"・・・・・・・", @"……", @"、、、", @"！！！"]) {
            OCRTextItem *probe = Item(pure, CGRectMake(0.29, 0.11, 0.116, 0.055));
            Check([dotsApp shouldIgnoreInlineText:pure
                                       normalized:NormalizeForComparison(pure)
                                      boundingBox:probe.boundingBox
                                           strict:YES],
                  [NSString stringWithFormat:@"<%@> 纯标点行仍应过滤", pure]);
        }

        // 回归：贴在画面底部的对白不能被当成角落按钮丢掉。
        // 「行くぞ。」在 y=0.053、宽 0.084 —— 只按“纵向贴边+窄”判定会整句丢掉，字幕变空。
        OCRTextItem *bottomLine = Item(@"行くぞ。", CGRectMake(0.29, 0.053, 0.084, 0.050));
        Check(![dotsApp shouldIgnoreInlineText:@"行くぞ。"
                                    normalized:NormalizeForComparison(@"行くぞ。")
                                   boundingBox:bottomLine.boundingBox
                                        strict:YES],
              @"dialogue at the very bottom must not be dropped (it is centred, not in a corner)");
        // 真正的角落按钮仍要丢掉
        OCRTextItem *cornerButton = Item(@"戻る", CGRectMake(0.02, 0.02, 0.06, 0.030));
        Check([dotsApp shouldIgnoreInlineText:@"戻る"
                                   normalized:NormalizeForComparison(@"戻る")
                                  boundingBox:cornerButton.boundingBox
                                       strict:YES],
              @"a genuinely cornered button must still be dropped");

        // 回归：只有“够大且水平居中”的亮矩形才算弹窗。
        // 实测「我的房间」界面里那张房间照片（x=0.15..0.57，中心 0.36）被误判成弹窗，
        // 12 条文字被裁到 4 条，底部那两行说明整段消失。
        Check(ModalRectQualifiesForCropping(CGRectMake(0.20, 0.17, 0.60, 0.29)),
              @"a large horizontally-centred popup must qualify for modal cropping");
        Check(!ModalRectQualifiesForCropping(CGRectMake(0.15, 0.33, 0.41, 0.34)),
              @"an off-centre bright block (e.g. an in-game photo) must NOT be treated as a modal");
        Check(!ModalRectQualifiesForCropping(CGRectMake(0.40, 0.30, 0.20, 0.30)),
              @"a narrow block must not qualify even if centred");
        Check(!ModalRectQualifiesForCropping(CGRectMake(0.30, 0.45, 0.40, 0.10)),
              @"a short block must not qualify even if centred");
        Check(!ModalRectQualifiesForCropping(CGRectMake(0.05, 0.30, 0.45, 0.30)),
              @"a left-aligned block must not qualify");

        // 回归：弹窗裁剪必须处于关闭状态。
        // 它连续 3 次误伤正常界面（我的房间 / 邮件界面底部说明被整段裁掉）。
        // 实测尺寸、居中、亮度差都无法区分真弹窗和普通界面里的大亮块，故默认关闭。
        {
            NSString *srcPath = [NSString stringWithFormat:@"%s/../objc/LiveCaptionTranslator.m", __FILE__];
            NSString *src = [NSString stringWithContentsOfFile:srcPath encoding:NSUTF8StringEncoding error:NULL];
            if (src.length > 0) {
                Check([src rangeOfString:@"static const BOOL kModalScopingEnabled = NO;"].location != NSNotFound,
                      @"modal scoping must stay disabled by default (it repeatedly cropped away real UI text)");
            }
            // 关闭时，弹窗裁剪必须原样返回，一条都不能丢
            AppDelegate *modalApp = [[AppDelegate alloc] init];
            NSArray<OCRTextItem *> *sample = @[
                Item(@"知り合いからのメールやアルバイト情報などを見ることができます。", CGRectMake(0.20, 0.10, 0.55, 0.05)),
                Item(@"こまめに確認してみましょう。", CGRectMake(0.30, 0.05, 0.35, 0.05))
            ];
            NSArray<OCRTextItem *> *out = [modalApp blocksInsideModalIfPresent:sample inImage:NULL normalizedExclusions:@[]];
            Check(out.count == sample.count,
                  @"with modal scoping disabled every block must be passed through untouched");
        }

        NSLog(@"Inline translation tests passed");
    }
    return 0;
}
