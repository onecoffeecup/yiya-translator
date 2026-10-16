#import "FYGrammarPageBuilder.h"
#import "../learning/FYLearningViews.h"
#import <QuartzCore/QuartzCore.h>
@implementation FYGrammarPageBuilder

+ (NSView *)structureViewForAnalysis:(FYAnalysisResult *)analysis source:(NSString *)source quick:(BOOL)quick receiver:(id<FYGrammarPageSource>)receiver {
    if(analysis.structureParts.count<2){return nil;}
    NSUInteger previousEnd=0;
    for(NSDictionary *part in analysis.structureParts){
        NSUInteger location=[part[@"location"] unsignedIntegerValue],length=[part[@"length"] unsignedIntegerValue];
        if(location<previousEnd || location>source.length || length>source.length-location || ![[source substringWithRange:NSMakeRange(location,length)] isEqualToString:part[@"text"]]){return nil;}
        previousEnd=location+length;
    }
    NSStackView *group=[receiver verticalStack];group.spacing=10;
    [group addArrangedSubview:[receiver quickReadingLabel:analysis.structureTitle.length?analysis.structureTitle:@"整句结构" size:15 weight:NSFontWeightSemibold color:receiver.uiInk]];
    NSStackView *flow=[NSStackView new];flow.orientation=NSUserInterfaceLayoutOrientationHorizontal;flow.spacing=8;flow.alignment=NSLayoutAttributeCenterY;
    NSUInteger index=0;NSMutableArray *structureButtons=[NSMutableArray new];
    for(NSDictionary *part in analysis.structureParts){
        if(index++){NSTextField *arrow=[receiver mutedLabel:@"→"];arrow.font=FYUIFont(15, NSFontWeightRegular);[flow addArrangedSubview:arrow];}
        // 紧凑胶囊节点：不固定 180×90，按内容自适应并允许换行。
        NSButton *node=[NSButton buttonWithTitle:@"" target:receiver.grammarControlTarget action:quick?@selector(selectQuickStructure:):@selector(selectMainStructure:)];
        node.translatesAutoresizingMaskIntoConstraints=NO;node.bordered=NO;node.wantsLayer=YES;
        node.layer.cornerRadius=14;node.layer.borderWidth=1;node.layer.borderColor=receiver.uiBorder.CGColor;
        node.layer.backgroundColor=FYAdventureColor(@"paper").CGColor;node.cell.wraps=YES;node.cell.scrollable=NO;
        NSMutableParagraphStyle *nodeParagraph=[NSMutableParagraphStyle new];
        nodeParagraph.alignment=NSTextAlignmentCenter;nodeParagraph.lineBreakMode=NSLineBreakByCharWrapping;
        node.attributedTitle=[[NSAttributedString alloc] initWithString:part[@"text"] ?: @"" attributes:@{NSFontAttributeName:FYJapaneseFont(13),NSForegroundColorAttributeName:receiver.uiInk,NSParagraphStyleAttributeName:nodeParagraph}];
        node.toolTip=[NSString stringWithFormat:@"%@：%@",part[@"role"],part[@"meaning"]];
        node.tag=-1;NSRange range=NSMakeRange([part[@"location"] unsignedIntegerValue],[part[@"length"] unsignedIntegerValue]);
        for(NSUInteger grammarIndex=0;grammarIndex<analysis.grammar.count;grammarIndex++){if(NSIntersectionRange(range,analysis.grammar[grammarIndex].matchedRange).length){node.tag=grammarIndex;break;}}
        BOOL selected=node.tag>=0 && node.tag==(quick?receiver.quickSelectedGrammarIndex:receiver.selectedGrammarIndex);
        node.layer.backgroundColor=(selected?receiver.uiSelected:FYAdventureColor(@"paper")).CGColor;
        [structureButtons addObject:node];
        [node.widthAnchor constraintGreaterThanOrEqualToConstant:52].active=YES;
        [node.widthAnchor constraintLessThanOrEqualToConstant:220].active=YES;
        [node.heightAnchor constraintGreaterThanOrEqualToConstant:30].active=YES;
        // 角色标签放在节点下方。
        NSTextField *role=[receiver mutedLabel:part[@"role"] ?: @""];
        role.alignment=NSTextAlignmentCenter;role.font=FYUIFont(10, NSFontWeightRegular);
        role.maximumNumberOfLines=1;role.lineBreakMode=NSLineBreakByTruncatingTail;
        NSStackView *wrapper=[receiver verticalStack];wrapper.spacing=3;wrapper.alignment=NSLayoutAttributeCenterX;
        [wrapper addArrangedSubview:node];
        [wrapper addArrangedSubview:role];
        [node.widthAnchor constraintEqualToAnchor:wrapper.widthAnchor].active=YES;
        [wrapper.widthAnchor constraintLessThanOrEqualToConstant:240].active=YES;
        [flow addArrangedSubview:wrapper];
    }
    if(quick){receiver.quickStructureButtons=structureButtons;}else{receiver.mainStructureButtons=structureButtons;}
    NSScrollView *scroll=[NSScrollView new];scroll.drawsBackground=NO;scroll.hasHorizontalScroller=YES;scroll.scrollerStyle=NSScrollerStyleOverlay;
    scroll.documentView=flow;
    if(quick){receiver.quickStructureScrollView=scroll;}else{receiver.mainStructureScrollView=scroll;}
    NSSize size=flow.fittingSize;
    flow.frame=NSMakeRect(0,0,MAX(1,size.width),MAX(46,size.height));
    [scroll.heightAnchor constraintEqualToConstant:MIN(104,MAX(50,size.height+8))].active=YES;
    [group addArrangedSubview:scroll];
    [group addArrangedSubview:[receiver mutedLabel:(analysis.structureParts.count>3?@"AI 结构讲解 · 点击片段查看语法 · 可左右滚动":@"AI 结构讲解 · 点击片段查看对应语法")]];
    return group;
}

+ (NSView *)grammarInfoCellWithLabel:(NSString *)labelText value:(NSString *)valueText receiver:(id<FYGrammarPageSource>)receiver {
    NSStackView *cell = [receiver verticalStack];
    cell.spacing = 4;
    [cell addArrangedSubview:[receiver mutedLabel:labelText]];
    NSTextField *value = [receiver label:valueText.length ? valueText : @"—" font:FYUIFont(13, NSFontWeightRegular) color:receiver.uiInk];
    value.maximumNumberOfLines = 3;
    value.lineBreakMode = NSLineBreakByWordWrapping;
    [cell addArrangedSubview:value];
    NSView *box = [receiver card];
    box.wantsLayer = YES;
    ((FYAdventurePanel *)box).fillColor = FYAdventureColor(@"shell");
    ((FYAdventurePanel *)box).edgeColor = FYAdventureColor(@"rim");
    [box addSubview:cell];
    cell.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [cell.leadingAnchor constraintEqualToAnchor:box.leadingAnchor constant:12],
        [cell.trailingAnchor constraintEqualToAnchor:box.trailingAnchor constant:-12],
        [cell.topAnchor constraintEqualToAnchor:box.topAnchor constant:10],
        [cell.bottomAnchor constraintEqualToAnchor:box.bottomAnchor constant:-10]]];
    return box;
}

+ (NSView *)makeIntegratedGrammarCardWithReceiver:(id<FYGrammarPageSource>)receiver {
    NSStackView *content = [receiver verticalStack]; content.spacing = 16;

    // 标题栏
    // 标题与整句动作同一行；页签、固定状态与结果状态另起一行以适应窄窗口。
    NSStackView *header = [receiver horizontalStack];
    header.spacing = 14;
    [header addArrangedSubview:[receiver cardTitle:@"这一句的语法"]];
    NSStackView *tabRow = [receiver horizontalStack]; tabRow.spacing = 14;
    NSMutableArray *tabButtons = [NSMutableArray array];
    NSMutableArray *tabUnderlines = [NSMutableArray array];
    for (NSString *title in @[@"整句理解", @"语法点", @"例句"]) {
        NSButton *tab = [NSButton buttonWithTitle:title target:receiver.grammarControlTarget action:@selector(selectGrammarTab:)];
        tab.bordered = NO; tab.tag = tabButtons.count;
        tab.font = FYUIFont(13, NSFontWeightRegular);
        tab.contentTintColor = receiver.uiMuted;
        NSView *underline = [[NSView alloc] init];
        underline.wantsLayer = YES;
        underline.layer.cornerRadius = 1;
        underline.layer.backgroundColor = NSColor.clearColor.CGColor;
        [underline.heightAnchor constraintEqualToConstant:2].active = YES;
        NSStackView *wrapper = [receiver verticalStack]; wrapper.spacing = 3;
        [wrapper addArrangedSubview:tab];
        [wrapper addArrangedSubview:underline];
        [underline.widthAnchor constraintEqualToAnchor:wrapper.widthAnchor].active = YES;
        [wrapper setContentHuggingPriority:999 forOrientation:NSLayoutConstraintOrientationHorizontal];
        [tabRow addArrangedSubview:wrapper];
        [tabButtons addObject:tab];
        [tabUnderlines addObject:underline];
    }
    [tabRow setContentHuggingPriority:999 forOrientation:NSLayoutConstraintOrientationHorizontal];
    receiver.grammarTabButtons = tabButtons;
    receiver.grammarTabUnderlines = tabUnderlines;
    receiver.grammarTabRow = tabRow;
    NSStackView *metaHeader = [receiver horizontalStack]; metaHeader.spacing = 12;
    [metaHeader addArrangedSubview:tabRow];
    [metaHeader addArrangedSubview:[receiver spacer]];
    receiver.grammarPinnedLabel = [receiver mutedLabel:@""];
    [metaHeader addArrangedSubview:receiver.grammarPinnedLabel];
    receiver.grammarStatusLabel = [receiver mutedLabel:@"尚未分析"];
    [metaHeader addArrangedSubview:receiver.grammarStatusLabel];
    [header addArrangedSubview:[receiver spacer]];
    receiver.grammarReviewButton = [receiver workspaceButton:@"深度复核" action:@selector(reviewGrammarSentence:) primary:NO];
    receiver.grammarReviewButton.hidden = YES;
    receiver.grammarReviewButton.toolTip = @"补查这一句的遗漏与疑点；已有结果保持可读";
    [header addArrangedSubview:receiver.grammarReviewButton];
    [content addArrangedSubview:header];
    [content addArrangedSubview:metaHeader];

    // 分析前只呈现一份提示和一个动作，不提前展开空列表、详情与追问。
    NSView *empty = [NSView new];
    NSStackView *emptyContent = [NSStackView new];
    emptyContent.orientation = NSUserInterfaceLayoutOrientationVertical;
    emptyContent.alignment = NSLayoutAttributeCenterX;
    emptyContent.spacing = 10;
    emptyContent.translatesAutoresizingMaskIntoConstraints = NO;
    receiver.grammarEmptyTitle = [receiver label:@"" font:FYUIFont(16, NSFontWeightSemibold) color:receiver.uiInk];
    receiver.grammarEmptyHint = [receiver mutedLabel:@""];
    for (NSTextField *label in @[receiver.grammarEmptyTitle, receiver.grammarEmptyHint]) {
        label.alignment = NSTextAlignmentCenter;
        label.maximumNumberOfLines = 0;
        label.lineBreakMode = NSLineBreakByWordWrapping;
        label.translatesAutoresizingMaskIntoConstraints = NO;
        [emptyContent addArrangedSubview:label];
        [label.widthAnchor constraintEqualToAnchor:emptyContent.widthAnchor].active = YES;
    }
    receiver.grammarEmptyAnalyzeButton = [receiver workspaceButton:@"分析此句" action:@selector(analyzeCurrentSentence:) primary:YES];
    [emptyContent addArrangedSubview:receiver.grammarEmptyAnalyzeButton];
    [emptyContent setCustomSpacing:16 afterView:receiver.grammarEmptyHint];
    [empty addSubview:emptyContent];
    [NSLayoutConstraint activateConstraints:@[
        [emptyContent.leadingAnchor constraintEqualToAnchor:empty.leadingAnchor constant:12],
        [emptyContent.trailingAnchor constraintEqualToAnchor:empty.trailingAnchor constant:-12],
        [emptyContent.topAnchor constraintEqualToAnchor:empty.topAnchor constant:12],
        [emptyContent.bottomAnchor constraintEqualToAnchor:empty.bottomAnchor constant:-16]
    ]];
    receiver.grammarEmptyPane = empty;
    [content addArrangedSubview:empty];

    // 隐藏的镜像视图：学习同步仍在使用这些属性，只是不在界面上重复展示原句。
    receiver.grammarSourceLabel = [receiver mutedLabel:@""];
    receiver.grammarSourceTextView = [NSTextView new];
    receiver.grammarSourceTextView.font = FYJapaneseFont(22);
    receiver.grammarBackToSourceButton = [receiver workspaceButton:@"返回原句选词" action:@selector(backToSourcePage:) primary:NO];
    receiver.grammarResultsLabel = [receiver mutedLabel:@""]; receiver.grammarResultsLabel.hidden = YES;
    receiver.grammarSourceLabel.hidden = YES;

    // —— Tab 0：整句理解 ——
    receiver.sentenceInsightStack = [receiver verticalStack]; receiver.sentenceInsightStack.spacing = 8;
    receiver.sentenceStructureStack = [receiver verticalStack]; receiver.sentenceStructureStack.spacing = 8;
    receiver.sentenceInsightLabel = [receiver label:@"" font:FYUIFont(14, NSFontWeightRegular) color:receiver.uiInk];
    receiver.sentenceInsightLabel.maximumNumberOfLines = 6;
    receiver.sentenceInsightLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [receiver.sentenceInsightStack addArrangedSubview:receiver.sentenceInsightLabel];
    [content addArrangedSubview:receiver.sentenceInsightStack];

    // —— 句子结构图（紧凑胶囊节点，独立于左右两栏）——
    NSView *structureCard = [receiver card];
    ((FYAdventurePanel *)structureCard).fillColor = FYAdventureColor(@"paper");
    ((FYAdventurePanel *)structureCard).edgeColor = FYAdventureColor(@"line");
    [structureCard addSubview:receiver.sentenceStructureStack];
    receiver.sentenceStructureStack.translatesAutoresizingMaskIntoConstraints = NO;
    [NSLayoutConstraint activateConstraints:@[
        [receiver.sentenceStructureStack.leadingAnchor constraintEqualToAnchor:structureCard.leadingAnchor constant:14],
        [receiver.sentenceStructureStack.trailingAnchor constraintEqualToAnchor:structureCard.trailingAnchor constant:-14],
        [receiver.sentenceStructureStack.topAnchor constraintEqualToAnchor:structureCard.topAnchor constant:12],
        [receiver.sentenceStructureStack.bottomAnchor constraintEqualToAnchor:structureCard.bottomAnchor constant:-12]]];
    structureCard.hidden = YES;
    receiver.grammarStructureCard = structureCard;
    [content addArrangedSubview:structureCard];

    // —— Tab 1：语法点（左窄栏列表约两成 + 右详情；右侧不再套大边框）——
    NSStackView *columns = [receiver horizontalStack];
    columns.spacing = 20;
    columns.alignment = NSLayoutAttributeTop;
    NSStackView *left = [receiver verticalStack]; left.spacing = 6;
    // 列表上方不再重复标题与说明；grammarOtherEmptyLabel 保留属性但不加入界面。
    receiver.grammarOtherEmptyLabel = [receiver mutedLabel:@""];
    receiver.grammarOtherStack = [receiver verticalStack]; receiver.grammarOtherStack.spacing = 6;
    [left addArrangedSubview:receiver.grammarOtherStack];
    NSLayoutConstraint *listFraction = [left.widthAnchor constraintEqualToAnchor:columns.widthAnchor multiplier:0.2];
    listFraction.priority = 500;
    NSLayoutConstraint *listMinWidth = [left.widthAnchor constraintGreaterThanOrEqualToConstant:110];
    listMinWidth.priority = 500;
    listMinWidth.active = YES;

    NSStackView *detail = [receiver verticalStack]; detail.spacing = 12;
    // 1) 语法名 + 等级
    NSStackView *detailHeader = [receiver horizontalStack];
    receiver.grammarDetailNameLabel = [receiver label:@"尚未分析" font:FYUIFont(17, NSFontWeightSemibold) color:receiver.uiInk];
    receiver.grammarDetailLevelLabel = [receiver mutedLabel:@""];
    [detailHeader addArrangedSubview:receiver.grammarDetailNameLabel];
    [detailHeader addArrangedSubview:[receiver spacer]];
    [detailHeader addArrangedSubview:receiver.grammarDetailLevelLabel];
    [detail addArrangedSubview:detailHeader];
    // 2) 一句解释
    receiver.grammarDetailBodyLabel = [receiver label:@"点击「查看分析」，查看含义、接续和本句用法。" font:FYUIFont(14, NSFontWeightRegular) color:receiver.uiInk];
    receiver.grammarDetailBodyLabel.maximumNumberOfLines = 4;
    receiver.grammarDetailBodyLabel.lineBreakMode = NSLineBreakByWordWrapping;
    [detail addArrangedSubview:receiver.grammarDetailBodyLabel];
    // 3) 横向短字段
    receiver.grammarDetailFields = [receiver horizontalStack];
    receiver.grammarDetailFields.spacing = 18;
    receiver.grammarDetailFields.alignment = NSLayoutAttributeTop;
    [detail addArrangedSubview:receiver.grammarDetailFields];
    // 4) 用法或例句块
    receiver.grammarUsageBlock = [receiver verticalStack]; receiver.grammarUsageBlock.spacing = 6;
    [detail addArrangedSubview:receiver.grammarUsageBlock];
    // 5) 底部操作行：收藏、来源与重新分析（主界面追问统一走右侧 AI 伙伴，这里不再重复入口）
    NSStackView *detailActions = [receiver horizontalStack];
    receiver.grammarDetailBookmarkButton = [receiver workspaceButton:@"收藏此语法" action:@selector(bookmarkSelectedGrammar:) primary:NO];
    receiver.grammarDetailBookmarkButton.hidden = YES;
    receiver.grammarExpandButton = [receiver workspaceButton:@"展开解释" action:@selector(toggleGrammarExplanation:) primary:YES];
    receiver.grammarExpandButton.hidden = YES;
    [detailActions addArrangedSubview:receiver.grammarExpandButton];
    [detailActions addArrangedSubview:receiver.grammarDetailBookmarkButton];
    receiver.grammarSourceLinkButton = [NSButton buttonWithTitle:@"查看等级参考来源 ↗" target:receiver.grammarControlTarget action:@selector(openGrammarSource:)];
    receiver.grammarSourceLinkButton.bordered = NO; receiver.grammarSourceLinkButton.contentTintColor = receiver.uiAccent; receiver.grammarSourceLinkButton.hidden = YES;
    NSStackView *secondaryActions = [receiver horizontalStack];
    [secondaryActions addArrangedSubview:receiver.grammarSourceLinkButton];
    [secondaryActions addArrangedSubview:[receiver spacer]];
    receiver.grammarPageAnalyzeButton = [receiver workspaceButton:@"查看分析" action:@selector(analyzeCurrentSentence:) primary:NO];
    ((FYWorkspaceButton *)receiver.grammarPageAnalyzeButton).accent = YES;
    receiver.grammarPageAnalyzeButton.enabled = NO;
    receiver.analyzeButton = receiver.grammarPageAnalyzeButton;
    [secondaryActions addArrangedSubview:receiver.grammarPageAnalyzeButton];
    [detail addArrangedSubview:detailActions];
    receiver.grammarExpandedLabel = [receiver label:@"" font:FYUIFont(13, NSFontWeightRegular) color:receiver.uiInk];
    receiver.grammarExpandedLabel.maximumNumberOfLines = 0;
    receiver.grammarExpandedLabel.selectable = YES; receiver.grammarExpandedLabel.hidden = YES;
    [detail addArrangedSubview:receiver.grammarExpandedLabel];
    [detail addArrangedSubview:secondaryActions];

    // 主界面不再有「继续追问」入口：追问统一用右侧 AI 伙伴。
    // 这里的控件与逻辑保留（浮动学习卡的「问 AI」共享同一套聊天/隔离逻辑），只是不排进主界面布局。
    NSStackView *followup = [receiver verticalStack]; followup.spacing = 10;
    followup.hidden = YES;
    NSStackView *suggestions = [receiver horizontalStack];
    [suggestions addArrangedSubview:[receiver workspaceButton:@"解释简单一点" action:@selector(simplerExplanationForGrammar:) primary:NO]];
    [suggestions addArrangedSubview:[receiver workspaceButton:@"这句话是什么语气？" action:@selector(askGrammarTone:) primary:NO]];
    [followup addArrangedSubview:suggestions];
    NSStackView *ask = [receiver horizontalStack];
    receiver.grammarQuestionField = [receiver textField:@"还有哪里没看懂？"];
    receiver.grammarQuestionField.bezeled = NO; receiver.grammarQuestionField.wantsLayer = YES;
    receiver.grammarQuestionField.layer.backgroundColor = FYAdventureColor(@"reading").CGColor;
    receiver.grammarQuestionField.layer.cornerRadius = 7; receiver.grammarQuestionField.layer.borderWidth = 1;
    receiver.grammarQuestionField.layer.borderColor = receiver.uiBorder.CGColor;
    receiver.grammarQuestionField.target = receiver.grammarControlTarget; receiver.grammarQuestionField.action = @selector(askGrammarQuestion:);
    [receiver.grammarQuestionField.heightAnchor constraintEqualToConstant:34].active = YES;
    [ask addArrangedSubview:receiver.grammarQuestionField];
    NSButton *question = [receiver workspaceButton:@"提问" action:@selector(askGrammarQuestion:) primary:YES];
    [ask addArrangedSubview:question];
    [followup addArrangedSubview:ask];
    receiver.grammarFollowupResultLabel = [receiver label:@"" font:FYUIFont(13, NSFontWeightRegular) color:receiver.uiInk];
    receiver.grammarFollowupResultLabel.maximumNumberOfLines = 6;
    [followup addArrangedSubview:receiver.grammarFollowupResultLabel];
    receiver.grammarFollowupControls = @[suggestions.arrangedSubviews[0], suggestions.arrangedSubviews[1], question, receiver.grammarQuestionField];
    for (NSControl *control in receiver.grammarFollowupControls) { control.enabled = NO; }
    receiver.grammarFollowupDisclosure = followup;
    // 刻意不 addArrangedSubview：主界面没有入口，避免留下不可达的追问面板。

    [columns addArrangedSubview:left];
    [columns addArrangedSubview:detail];
    listFraction.active = YES;
    [detail setContentHuggingPriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
    receiver.grammarPointsPane = columns;
    [content addArrangedSubview:columns];

    // —— Tab 2：例句 ——
    NSStackView *examples = [receiver verticalStack]; examples.spacing = 10;
    [examples addArrangedSubview:[receiver mutedLabel:@"例句由 AI 按需生成，用于对照当前语法点。"]];
    receiver.grammarExampleLabel = [receiver label:@"还没有例句。" font:FYUIFont(14, NSFontWeightRegular) color:receiver.uiInk];
    receiver.grammarExampleLabel.maximumNumberOfLines = 8;
    receiver.grammarExampleLabel.lineBreakMode = NSLineBreakByWordWrapping;
    NSView *exampleCard = [receiver cardWithStack:({
        NSStackView *inner = [receiver verticalStack]; inner.spacing = 6;
        [inner addArrangedSubview:receiver.grammarExampleLabel];
        inner;
    })];
    ((FYAdventurePanel *)exampleCard).fillColor = FYAdventureColor(@"shell");
    ((FYAdventurePanel *)exampleCard).edgeColor = FYAdventureColor(@"rim");
    [examples addArrangedSubview:exampleCard];
    [examples addArrangedSubview:[receiver workspaceButton:@"生成一个例句" action:@selector(exampleSentenceForGrammar:) primary:NO]];
    receiver.grammarExamplesPane = examples;
    [content addArrangedSubview:examples];

    receiver.selectedGrammarTab = 1;
    receiver.grammarReferenceNote = [receiver mutedLabel:@"语法解释与等级供学习参考；分析与追问按需生成。"];
    [content addArrangedSubview:receiver.grammarReferenceNote];
    [receiver applyGrammarTabSelection];
    NSView *card = [receiver cardWithStack:content]; card.identifier = @"integrated-grammar-card";
    return card;
}
@end
