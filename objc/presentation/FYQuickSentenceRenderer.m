#import "FYQuickSentenceRenderer.h"
#import "../learning/FYStudyChatView.h"
#import "../learning/FYStudyChatSession.h"
#import "../learning/FYStudyOverlayPanel.h"
#import "../learning/FYLearningViews.h"
#import "FYFlippedDocumentView.h"
#import "FYPresentationText.h"
#import <QuartzCore/QuartzCore.h>

@implementation FYQuickSentenceRenderer
+ (void)selectQuickStructure:(NSButton *)sender receiver:(id<FYQuickSentenceRenderSource>)receiver {
    if(sender.tag>=0){[receiver selectQuickGrammar:receiver.quickGrammarChoices[sender.tag]];}
    else{receiver.quickGrammarBookmarkStatus.stringValue=@"该片段的含义见结构图，未对应独立的语法条目。";}
}

+ (void)updateQuickGrammarBookmarkWithReceiver:(id<FYQuickSentenceRenderSource>)receiver {
    receiver.quickGrammarBookmarkButton.title=[receiver quickGrammarBookmark]?@"已收藏 · 取消收藏":@"＋ 收藏语法";
    receiver.quickGrammarBookmarkButton.enabled=!receiver.quickGrammarBookmarkPending && receiver.quickSentenceID.length>0;
}

+ (NSView *)quickGrammarDetailForItem:(FYGrammarItem *)item receiver:(id<FYQuickSentenceRenderSource>)receiver {
            NSStackView *point=[receiver verticalStack];point.spacing=8;
            BOOL shortMeaning=item.meaning.length>0 && item.meaning.length<=16;
            NSString *heading=shortMeaning?[NSString stringWithFormat:@"%@ · %@",item.name,item.meaning]:item.name;
            [point addArrangedSubview:[receiver quickReadingLabel:heading size:15 weight:NSFontWeightSemibold color:receiver.uiAccent]];
            if(item.matchedText.length){[point addArrangedSubview:[receiver quickReadingLabel:[@"原句 · " stringByAppendingString:item.matchedText] size:12 weight:NSFontWeightRegular color:receiver.uiMuted]];}
            if(item.meaning.length && !shortMeaning){[point addArrangedSubview:[receiver quickReadingLabel:item.meaning size:13 weight:NSFontWeightMedium color:receiver.uiInk]];}
            if(item.explanation.length){[point addArrangedSubview:[receiver quickReadingLabel:item.explanation size:12 weight:NSFontWeightRegular color:receiver.uiMuted]];}
            if(item.connection.length || item.registerNote.length){
                NSMutableArray *notes=[NSMutableArray new];
                if(item.connection.length){[notes addObject:[@"接续 · " stringByAppendingString:item.connection]];}
                if(item.registerNote.length){[notes addObject:item.registerNote];}
                [point addArrangedSubview:[receiver quickReadingLabel:[notes componentsJoinedByString:@"\n"] size:11 weight:NSFontWeightRegular color:receiver.uiMuted]];
            }
    receiver.quickGrammarBookmarkButton=[receiver workspaceButton:@"＋ 收藏语法" action:@selector(bookmarkQuickGrammar:) primary:NO];
    NSStackView *actions = [receiver horizontalStack]; actions.spacing = 8;
    receiver.quickGrammarExpandButton = [receiver workspaceButton:@"展开解释" action:@selector(toggleGrammarExplanation:) primary:YES];
    receiver.quickGrammarExpandButton.tag = 1;
    [actions addArrangedSubview:receiver.quickGrammarExpandButton];
    [actions addArrangedSubview:receiver.quickGrammarBookmarkButton];
    [point addArrangedSubview:actions];
    FYGrammarActionState *state = [receiver grammarActionsForQuick:YES];
    if (state.expandedItem == item) {
        NSString *explanation = [state.explanations objectForKey:item] ?: [state.errors objectForKey:item] ?: @"正在补充接续、用法与例句…";
        [point addArrangedSubview:[receiver quickReadingLabel:explanation size:13 weight:NSFontWeightRegular color:receiver.uiInk]];
    }
    [receiver updateGrammarActionControlsForQuick:YES];
    receiver.quickGrammarBookmarkStatus=[receiver mutedLabel:@""];[point addArrangedSubview:receiver.quickGrammarBookmarkStatus];
    [receiver updateQuickGrammarBookmark];
    return [receiver quickReadingCard:point tinted:NO];
}

+ (void)selectQuickGrammar:(NSButton *)sender receiver:(id<FYQuickSentenceRenderSource>)receiver {
    if(sender.tag<0 || sender.tag>=(NSInteger)receiver.quickSentenceAnalysis.grammar.count || !receiver.quickGrammarStack){return;}
    NSScrollView *scroll=receiver.quickGrammarStack.enclosingScrollView;
    NSPoint position=scroll.contentView.bounds.origin;
    receiver.quickSelectedGrammarIndex=sender.tag;
    receiver.quickGrammarActions.expandedItem=nil;
    for(NSButton *button in receiver.quickStructureButtons){button.layer.backgroundColor=(button.tag==sender.tag?receiver.uiSelected:FYAdventureColor(@"paper")).CGColor;}
    for(NSButton *button in receiver.quickGrammarChoices){button.state=button.tag==sender.tag?NSControlStateValueOn:NSControlStateValueOff;}
    receiver.quickSelectedGrammarButton=sender;
    [receiver.quickGrammarStack removeArrangedSubview:receiver.quickGrammarDetailCard];[receiver.quickGrammarDetailCard removeFromSuperview];
    receiver.quickGrammarDetailCard=[receiver quickGrammarDetailForItem:receiver.quickSentenceAnalysis.grammar[sender.tag]];
    [receiver.quickGrammarStack addArrangedSubview:receiver.quickGrammarDetailCard];
    [receiver.quickSentencePanel.contentView layoutSubtreeIfNeeded];
    [scroll.documentView layoutSubtreeIfNeeded];
    [receiver.quickSentencePanel makeFirstResponder:sender];
    // Preserve the reading position, clamping only if the new detail is shorter.
    position.y=MIN(position.y,MAX(0,NSHeight(scroll.documentView.frame)-NSHeight(scroll.contentView.bounds)));
    [scroll.contentView scrollToPoint:position];[scroll reflectScrolledClipView:scroll.contentView];
}

+ (NSTextField *)quickReadingLabel:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color receiver:(id<FYQuickSentenceRenderSource>)receiver {
    NSTextField *label=[NSTextField wrappingLabelWithString:text ?: @""];
    label.translatesAutoresizingMaskIntoConstraints=NO;label.maximumNumberOfLines=0;
    label.font=FYFontForText(text, size, weight);label.selectable=YES;label.textColor=color;
    NSMutableParagraphStyle *paragraph=[NSMutableParagraphStyle new];paragraph.lineSpacing=size>=18?6:4;
    label.attributedStringValue=[[NSAttributedString alloc] initWithString:text ?: @"" attributes:@{
        NSFontAttributeName:label.font,NSForegroundColorAttributeName:color,NSParagraphStyleAttributeName:paragraph}];
    [label setContentCompressionResistancePriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}

+ (NSView *)quickReadingCard:(NSStackView *)stack tinted:(BOOL)tinted receiver:(id<FYQuickSentenceRenderSource>)receiver {
    NSView *card=[receiver card];
    ((FYAdventurePanel *)card).fillColor=FYAdventureColor(tinted?@"reading":@"paper");
    ((FYAdventurePanel *)card).edgeColor=FYAdventureColor(tinted?@"reading":@"rim");
    stack.translatesAutoresizingMaskIntoConstraints=NO;[card addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:14],
        [stack.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-14],
        [stack.topAnchor constraintEqualToAnchor:card.topAnchor constant:12],
        [stack.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-12]]];
    return card;
}

+ (void)renderQuickSentenceWithReceiver:(id<FYQuickSentenceRenderSource>)receiver {
    [receiver.quickSourceTextView dismissSourceHover];
    receiver.quickSourceHoverGeneration++;receiver.quickSourceTextView=nil;
    // 结构图整体重建前先记下横向偏移，构建完立刻恢复（避免跳回最左、也不用延时跳回）。
    CGFloat keptStructureOffset=[receiver structureScrollOffsetForQuick:YES];
    receiver.quickGrammarStack=nil;receiver.quickGrammarDetailCard=nil;receiver.quickGrammarChoices=@[];
    NSColor *paper=FYAdventureColor(@"paper");
    if(!receiver.quickSentencePanel){
        CGFloat height=MIN(640,NSHeight((receiver.captionPanel.screen ?: NSScreen.mainScreen).visibleFrame)-48);
        receiver.quickSentencePanel=[[FYStudyOverlayPanel alloc] initWithContentRect:NSMakeRect(0,0,440,height) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        [receiver configureStudyOverlay:receiver.quickSentencePanel];
        receiver.quickSentencePanel.opaque=NO;receiver.quickSentencePanel.backgroundColor=NSColor.clearColor;
        receiver.quickSentencePanel.minSize=NSMakeSize(440,MIN(500,height));receiver.quickSentencePanel.maxSize=NSMakeSize(4096,4096);
        __weak id<FYQuickSentenceRenderSource> weakSelf=receiver;receiver.quickSentencePanel.onEscape=^{[weakSelf closeStudyOverlay:nil];};
    }
    // A frame-driven host keeps the window independent of long document content.
    NSView *host=[[NSView alloc] initWithFrame:NSMakeRect(0,0,NSWidth(receiver.quickSentencePanel.contentView.bounds),NSHeight(receiver.quickSentencePanel.contentView.bounds))];
    host.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;host.wantsLayer=YES;
    host.layer.backgroundColor=paper.CGColor;host.layer.cornerRadius=13;host.layer.masksToBounds=YES;
    host.layer.borderWidth=1;host.layer.borderColor=receiver.uiBorder.CGColor;
    NSStackView *titles=[receiver verticalStack];titles.spacing=4;
    BOOL inlineBlock=receiver.quickSentenceIsInlineBlock;
    [titles addArrangedSubview:[receiver quickReadingLabel:inlineBlock?@"原文 · 译文 · 这段话的语法":@"快捷查询 · 当前句" size:10 weight:NSFontWeightMedium color:receiver.uiAccent]];
    // 标题行只放文本标签：拖动区里不能混入容器视图。
    NSTextField *cardTitle=[receiver quickReadingLabel:inlineBlock?@"选中内容 · 已固定":@"读懂这一句" size:22 weight:NSFontWeightSemibold color:receiver.uiInk];
    // 标题始终完整一行：被压缩时也不要断成「选中内容 ·」，更不要被挤出右边距。
    cardTitle.maximumNumberOfLines=1;
    cardTitle.lineBreakMode=NSLineBreakByTruncatingTail;
    [cardTitle setContentCompressionResistancePriority:751 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [cardTitle setContentCompressionResistancePriority:751 forOrientation:NSLayoutConstraintOrientationVertical];
    [titles addArrangedSubview:cardTitle];
    NSButton *close=[NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"收起句子查询"] target:[receiver studyActionTarget] action:@selector(closeStudyOverlay:)];
    close.bordered=NO;close.contentTintColor=receiver.uiMuted;close.toolTip=@"收起 · Esc";
    close.translatesAutoresizingMaskIntoConstraints=NO;[close.widthAnchor constraintEqualToConstant:30].active=YES;[close.heightAnchor constraintEqualToConstant:30].active=YES;
    FYOverlayDragHeader *header=[FYOverlayDragHeader new];header.translatesAutoresizingMaskIntoConstraints=NO;
    header.orientation=NSUserInterfaceLayoutOrientationHorizontal;header.alignment=NSLayoutAttributeCenterY;header.spacing=10;
    // AppKit 的 NSStackView 默认是 GravityAreas：子视图不会按优先级撑开，
    // 标题被压成两个字、关闭按钮停在卡片中间。改成 Fill，标题吃掉剩余宽度、关闭按钮贴右端。
    header.distribution=NSStackViewDistributionFill;
    header.toolTip=@"拖动这里移动窗口";
    for(NSView *view in titles.arrangedSubviews){if([view isKindOfClass:NSTextField.class]){[(NSTextField *)view setSelectable:NO];}}
    [titles setContentHuggingPriority:1 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [header addArrangedSubview:titles];[header addArrangedSubview:close];[host addSubview:header];
    NSView *topLine=[receiver separator];topLine.translatesAutoresizingMaskIntoConstraints=NO;[host addSubview:topLine];
    NSStackView *content=[receiver verticalStack];content.spacing=18;
    NSStackView *source=[receiver verticalStack];source.spacing=8;
    [source addArrangedSubview:[receiver quickReadingLabel:inlineBlock?@"原文":@"日文原句" size:10 weight:NSFontWeightRegular color:receiver.uiMuted]];
    if(receiver.quickSentenceSource.length){
        FYSourceReadingView *reading=[[FYSourceReadingView alloc] initWithFrame:NSMakeRect(0,0,400,26)];
        NSMutableParagraphStyle *paragraph=[NSMutableParagraphStyle new];paragraph.lineSpacing=6;
        reading.textView.font=FYFontForText(receiver.quickSentenceSource,19,NSFontWeightRegular);
        reading.textView.textColor=receiver.uiInk;
        reading.textView.defaultParagraphStyle=paragraph;
        [reading.textView.textStorage setAttributedString:[[NSAttributedString alloc] initWithString:receiver.quickSentenceSource attributes:@{
            NSFontAttributeName:FYFontForText(receiver.quickSentenceSource,19,NSFontWeightRegular),NSForegroundColorAttributeName:receiver.uiInk,NSParagraphStyleAttributeName:paragraph}]];
        [source addArrangedSubview:reading];receiver.quickSourceTextView=reading.textView;
        [source addArrangedSubview:[receiver quickReadingLabel:@"悬停查看词义 · 按住拖拽可选择原文" size:11 weight:NSFontWeightRegular color:receiver.uiMuted]];
    }else{
        [source addArrangedSubview:[receiver quickReadingLabel:inlineBlock?@"尚未选中内容":@"尚未识别到对白" size:19 weight:NSFontWeightRegular color:receiver.uiInk]];
    }
    [content addArrangedSubview:source];
    NSStackView *translation=[receiver verticalStack];translation.spacing=5;
    [translation addArrangedSubview:[receiver quickReadingLabel:receiver.quickSentenceTranslation.length?receiver.quickSentenceTranslation:@"暂无译文" size:14 weight:NSFontWeightRegular color:receiver.uiInk]];
    [content addArrangedSubview:[receiver quickReadingCard:translation tinted:YES]];
    FYAnalysisResult *analysis=[receiver.quickSentenceSource isEqualToString:receiver.quickSentenceAnalysisSource]?receiver.quickSentenceAnalysis:nil;
    NSStackView *grammar=[receiver verticalStack];grammar.spacing=12;
    NSStackView *grammarHeader=[receiver horizontalStack]; grammarHeader.spacing=8;
    [grammarHeader addArrangedSubview:[receiver quickReadingLabel:@"这一句的语法" size:15 weight:NSFontWeightSemibold color:receiver.uiInk]];
    [grammarHeader addArrangedSubview:[receiver spacer]];
    receiver.quickGrammarReviewButton=[receiver workspaceButton:@"深度复核" action:@selector(reviewGrammarSentence:) primary:NO];
    receiver.quickGrammarReviewButton.tag=1;
    receiver.quickGrammarReviewButton.toolTip=@"补查这一句的遗漏与疑点；已有结果保持可读";
    [grammarHeader addArrangedSubview:receiver.quickGrammarReviewButton];
    [grammar addArrangedSubview:grammarHeader];
    receiver.quickGrammarReviewStatus=[receiver quickReadingLabel:@"" size:12 weight:NSFontWeightRegular color:receiver.uiMuted];
    [grammar addArrangedSubview:receiver.quickGrammarReviewStatus];
    if(receiver.quickSentenceAnalyzing){
        NSStackView *loading=[receiver verticalStack];loading.spacing=6;
        [loading addArrangedSubview:[receiver quickReadingLabel:@"正在分析这句对白…" size:14 weight:NSFontWeightMedium color:receiver.uiAccent]];
        [loading addArrangedSubview:[receiver quickReadingLabel:@"先读原句和译文，解析完成后会显示在这里。" size:12 weight:NSFontWeightRegular color:receiver.uiMuted]];
        [grammar addArrangedSubview:[receiver quickReadingCard:loading tinted:YES]];
    }else if(receiver.quickSentenceAnalysisError.length){
        NSStackView *failure=[receiver verticalStack];failure.spacing=10;
        [failure addArrangedSubview:[receiver quickReadingLabel:[@"分析失败：" stringByAppendingString:receiver.quickSentenceAnalysisError] size:12 weight:NSFontWeightRegular color:NSColor.systemRedColor]];
        [failure addArrangedSubview:[receiver workspaceButton:@"重试分析" action:@selector(analyzeQuickSentence:) primary:NO]];
        [grammar addArrangedSubview:[receiver quickReadingCard:failure tinted:NO]];
    }else if(analysis){
        NSView *structure=[receiver structureViewForAnalysis:analysis source:receiver.quickSentenceSource quick:YES];
        if(structure){[grammar addArrangedSubview:structure];}
        else{[grammar addArrangedSubview:[receiver mutedLabel:@"本次解析未返回整句结构，可在主界面重新分析。"]];}
        if(analysis.sentenceNote.length){[grammar addArrangedSubview:[receiver quickReadingLabel:analysis.sentenceNote size:13 weight:NSFontWeightRegular color:receiver.uiMuted]];}
        if(analysis.grammar.count){
            if(receiver.quickSelectedGrammarIndex<0 || receiver.quickSelectedGrammarIndex>=(NSInteger)analysis.grammar.count){receiver.quickSelectedGrammarIndex=0;}
            [grammar addArrangedSubview:[receiver quickReadingLabel:@"选择一个语法，查看它在这句里的用法" size:11 weight:NSFontWeightRegular color:receiver.uiMuted]];
            NSMutableArray<NSButton *> *buttons=[NSMutableArray new];
            NSMutableArray<NSArray<NSView *> *> *rows=[NSMutableArray new];
            NSMutableArray<NSView *> *row=[NSMutableArray new];
            for(NSUInteger index=0;index<analysis.grammar.count;index++){
                FYGrammarItem *item=analysis.grammar[index];
                NSButton *button=[receiver workspaceButton:item.name action:@selector(selectQuickGrammar:) primary:NO];
                button.tag=index;button.state=index==receiver.quickSelectedGrammarIndex?NSControlStateValueOn:NSControlStateValueOff;
                button.toolTip=item.matchedText;button.accessibilityLabel=[NSString stringWithFormat:@"查看语法：%@",item.name];
                if(index==receiver.quickSelectedGrammarIndex){receiver.quickSelectedGrammarButton=button;}
                [buttons addObject:button];[row addObject:button];
                if(row.count==2){[rows addObject:row];row=[NSMutableArray new];}
            }
            if(row.count){[row addObject:[NSView new]];[rows addObject:row];}
            NSGridView *choices=[NSGridView gridViewWithViews:rows];choices.columnSpacing=8;choices.rowSpacing=8;
            choices.xPlacement=NSGridCellPlacementFill;choices.yPlacement=NSGridCellPlacementFill;
            for(NSArray<NSView *> *pair in rows){for(NSView *choice in pair){[choice.widthAnchor constraintEqualToAnchor:choices.widthAnchor multiplier:0.5 constant:-4].active=YES;}}
            receiver.quickGrammarChoices=buttons;
            [grammar addArrangedSubview:choices];
            FYGrammarItem *item=analysis.grammar[receiver.quickSelectedGrammarIndex];
            receiver.quickGrammarStack=grammar;
            receiver.quickGrammarDetailCard=[receiver quickGrammarDetailForItem:item];
            [grammar addArrangedSubview:receiver.quickGrammarDetailCard];
        }
        if(!analysis.grammar.count){[grammar addArrangedSubview:[receiver quickReadingLabel:@"这句没有识别到可核实的语法条目，可以继续向 AI 提问。" size:12 weight:NSFontWeightRegular color:receiver.uiMuted]];}
    }else{[grammar addArrangedSubview:[receiver quickReadingLabel:@"识别到对白后，打开这里会自动分析。" size:12 weight:NSFontWeightRegular color:receiver.uiMuted]];}
    [receiver updateGrammarActionControlsForQuick:YES];
    [content addArrangedSubview:grammar];
    NSScrollView *scroll=[NSScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;
    scroll.hasVerticalScroller=YES;scroll.scrollerStyle=NSScrollerStyleOverlay;scroll.drawsBackground=NO;
    NSView *document=[FlippedDocumentView new];document.translatesAutoresizingMaskIntoConstraints=NO;
    scroll.documentView=document;content.translatesAutoresizingMaskIntoConstraints=NO;[document addSubview:content];[host addSubview:scroll];
    NSStackView *footer=[receiver verticalStack];footer.translatesAutoresizingMaskIntoConstraints=NO;footer.spacing=10;
    NSStackView *actions=[receiver horizontalStack];actions.spacing=8;
    [actions addArrangedSubview:[receiver workspaceButton:inlineBlock?@"问 AI":@"这句我还想问 AI" action:@selector(askQuickSentence:) primary:YES]];
    receiver.quickSentenceBookmarkButton=[receiver workspaceButton:[receiver quickSentenceIsBookmarked]?@"已收藏 · 取消":(inlineBlock?@"收藏这段":@"收藏这一句") action:@selector(bookmarkQuickSentence:) primary:NO];
    receiver.quickSentenceBookmarkButton.enabled=!receiver.sentenceBookmarkPending && receiver.quickSentenceID.length>0;
    [actions addArrangedSubview:receiver.quickSentenceBookmarkButton];
    [actions addArrangedSubview:[receiver workspaceButton:@"完整学习界面 ↗" action:@selector(openStudyWorkspace:) primary:NO]];
    [footer addArrangedSubview:actions];[footer addArrangedSubview:[receiver quickReadingLabel:inlineBlock?@"Esc 收起回到画面 · 选中的内容保持不变":@"Esc 收起回到画面 · 本次查看的原句保持不变" size:10 weight:NSFontWeightRegular color:receiver.uiMuted]];
    [host addSubview:footer];NSView *bottomLine=[receiver separator];bottomLine.translatesAutoresizingMaskIntoConstraints=NO;[host addSubview:bottomLine];
    [NSLayoutConstraint activateConstraints:@[
        [header.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:20],
        [header.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-18],
        [header.topAnchor constraintEqualToAnchor:host.topAnchor constant:17],
        [header.heightAnchor constraintEqualToConstant:48],
        [topLine.topAnchor constraintEqualToAnchor:header.bottomAnchor constant:14],
        [topLine.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [topLine.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [topLine.heightAnchor constraintEqualToConstant:1],
        [scroll.topAnchor constraintEqualToAnchor:topLine.bottomAnchor],
        [scroll.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [scroll.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [scroll.bottomAnchor constraintEqualToAnchor:bottomLine.topAnchor],
        [document.widthAnchor constraintEqualToAnchor:scroll.contentView.widthAnchor],
        [content.leadingAnchor constraintEqualToAnchor:document.leadingAnchor constant:20],
        [content.trailingAnchor constraintEqualToAnchor:document.trailingAnchor constant:-20],
        [content.topAnchor constraintEqualToAnchor:document.topAnchor constant:18],
        [content.bottomAnchor constraintEqualToAnchor:document.bottomAnchor constant:-20],
        [bottomLine.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
        [bottomLine.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
        [bottomLine.bottomAnchor constraintEqualToAnchor:footer.topAnchor constant:-14],
        [bottomLine.heightAnchor constraintEqualToConstant:1],
        [footer.leadingAnchor constraintEqualToAnchor:host.leadingAnchor constant:20],
        [footer.trailingAnchor constraintEqualToAnchor:host.trailingAnchor constant:-20],
        [footer.bottomAnchor constraintEqualToAnchor:host.bottomAnchor constant:-16]]];
    receiver.quickSentencePanel.contentView=host;
    [receiver refreshQuickSentenceHoverTips];
    [receiver refreshOverlayVisibility:nil];
    [receiver restoreStructureScrollOffset:keptStructureOffset quick:YES];
}
@end
