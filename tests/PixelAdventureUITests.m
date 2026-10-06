#import "LearningAppTestSupport.h"

static void Snapshot(NSView *view, NSString *path) {
    [view layoutSubtreeIfNeeded];[view displayIfNeeded];
    NSBitmapImageRep *bitmap=[view bitmapImageRepForCachingDisplayInRect:view.bounds];
    [view cacheDisplayInRect:view.bounds toBitmapImageRep:bitmap];
    Require([[bitmap representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES],@"snapshot failed");
}
// 长卡剖析：正文视口 / 文档 / 正文标签，用于断言"可读"而不是"存在"。
static NSScrollView *LongCardScroll(NSPanel *panel){for(NSView *v in panel.contentView.subviews){if([v isKindOfClass:NSScrollView.class]){return (NSScrollView *)v;}}return nil;}
static NSTextField *LongCardBody(NSPanel *panel){NSScrollView *s=LongCardScroll(panel);return [s.documentView isKindOfClass:NSTextField.class]?(NSTextField *)s.documentView:nil;}
static CGFloat LongCardLineHeight(NSTextField *body){NSFont *f=body.font;return ceil(f.ascender-f.descender+f.leading)+8;}
// 正文文档是否装得下整段译文（用同一字体/段落样式独立重算一遍，不是复述实现）。
static CGFloat TranslationHeightForBody(NSTextField *body){
    NSParagraphStyle *style=[body.attributedStringValue attribute:NSParagraphStyleAttributeName atIndex:0 effectiveRange:NULL];
    NSRect r=[body.stringValue boundingRectWithSize:NSMakeSize(NSWidth(body.frame),CGFLOAT_MAX)
        options:NSStringDrawingUsesLineFragmentOrigin|NSStringDrawingUsesFontLeading
        attributes:@{NSFontAttributeName:body.font?:[NSFont systemFontOfSize:19],
                     NSParagraphStyleAttributeName:style?:[NSParagraphStyle defaultParagraphStyle]}];
    return ceil(NSHeight(r));
}

static BOOL ContainsButtonTitled(NSView *view, NSString *title) {
    if ([view isKindOfClass:NSButton.class] && [[(NSButton *)view title] isEqualToString:title]) { return YES; }
    for (NSView *child in view.subviews) { if (ContainsButtonTitled(child, title)) { return YES; } }
    return NO;
}
static BOOL HasBadge(NSView *view) {
    for (NSView *child in view.subviews) {
        if ([child isKindOfClass:NSTextField.class] && [((NSTextField *)child).stringValue isEqualToString:@"已选中"]) { return YES; }
        if (HasBadge(child)) { return YES; }
    }
    return NO;
}
static OCRTextItem *Item2(NSString *text, CGRect box) {
    OCRTextItem *item=[OCRTextItem new];
    item.text=text;item.boundingBox=box;item.lineBoxes=@[[NSValue valueWithRect:box]];item.lineCount=1;
    return item;
}
// 把原文日文按 OCR 框画进示例画面，这样截图里能真正核对「贴片在原文下方、左对齐」。
static NSImage *DrawSources(NSImage *base, NSArray<OCRTextItem *> *items) {
    NSSize size = base.size;
    NSImage *scene = [[NSImage alloc] initWithSize:size];
    [scene lockFocus];
    [base drawInRect:NSMakeRect(0, 0, size.width, size.height) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
    for (OCRTextItem *item in items) {
        CGRect box = item.boundingBox;
        NSRect rect = NSMakeRect(box.origin.x * size.width, box.origin.y * size.height, box.size.width * size.width, box.size.height * size.height);
        NSMutableParagraphStyle *style = [NSMutableParagraphStyle new];
        style.lineBreakMode = NSLineBreakByCharWrapping;
        CGFloat pointSize = MAX((CGFloat)10, rect.size.height * (item.lineCount > 1 ? 0.34 : 0.62));
        NSFont *font = [NSFont fontWithName:@"HiraMaruProN-W4" size:pointSize] ?: [NSFont systemFontOfSize:pointSize];
        [item.text drawInRect:rect withAttributes:@{NSFontAttributeName: font,
                                                    NSForegroundColorAttributeName: [NSColor colorWithSRGBRed:0.13 green:0.11 blue:0.10 alpha:1],
                                                    NSParagraphStyleAttributeName: style}];
    }
    [scene unlockFocus];
    return scene;
}
// 把真实贴译面板的内容渲染叠在示例画面上：这是生产视图的实际位图，不是概念图。
static void DrawInlineLayer(AppDelegate *app, NSImage *backdrop, NSArray<NSString *> *translations, NSArray<OCRTextItem *> *items, NSString *path) {
    NSRect placement = NSMakeRect(0, 0, backdrop.size.width, backdrop.size.height);
    [app clearInlineTranslationPanels];
    [app showInlineTranslations:translations forItems:items placementRect:placement];
    Tick();
    NSImage *canvas = [[NSImage alloc] initWithSize:backdrop.size];
    [canvas lockFocus];
    [backdrop drawInRect:NSMakeRect(0, 0, backdrop.size.width, backdrop.size.height) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
    for (NSPanel *panel in [app.inlineTranslationPanels arrayByAddingObjectsFromArray:app.inlineLongCardPanels]) {
        NSView *content = panel.contentView;
        [content displayIfNeeded];
        NSBitmapImageRep *rep = [content bitmapImageRepForCachingDisplayInRect:content.bounds];
        [content cacheDisplayInRect:content.bounds toBitmapImageRep:rep];
        NSImage *shot = [[NSImage alloc] initWithSize:content.bounds.size];
        [shot addRepresentation:rep];
        NSRect frame = panel.frame;
        [shot drawInRect:NSMakeRect(NSMinX(frame) - NSMinX(placement), NSMinY(frame) - NSMinY(placement), NSWidth(frame), NSHeight(frame))
                fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:1];
    }
    [canvas unlockFocus];
    NSBitmapImageRep *out = [NSBitmapImageRep imageRepWithData:[canvas TIFFRepresentation]];
    Require([[out representationUsingType:NSBitmapImageFileTypePNG properties:@{}] writeToFile:path atomically:YES], @"inline layer snapshot failed");
}
int main(int argc,const char *argv[]) {
    @autoreleasepool {
        [NSApplication sharedApplication];[NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
        NSString *output=[NSString stringWithUTF8String:argv[1]];
        NSString *temp=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
        FYLearningStore *store=Store(temp);
        FYGrammarCatalog *catalog=[[FYGrammarCatalog alloc] initWithURL:[NSURL fileURLWithPath:@"resources/learning/grammar-catalog.json"]];
        Require([catalog loadWithError:NULL],@"catalog");
        AppDelegate *app=App(store,Analyzer(catalog),catalog);
        [app refreshLearningStatus];
        Require(!app.grammarEmptyPane.hidden && app.grammarTabRow.hidden && app.grammarPointsPane.hidden && !app.grammarEmptyAnalyzeButton.enabled,@"no source must show a compact waiting state without result controls");
        Require(!app.pinSentenceButton.enabled,@"the pin action must be disabled when there is no usable sentence");
        Require(!ContainsButtonTitled(app.mainWindow.contentView,@"翻译当前界面"),@"the live toolbar must not offer 翻译当前界面");
        NSString *source=@"絵が得意でも、毎日練習しないと上達しない。";
        FYRequestIdentity *identity=[app.learningCoordinator recordText:source kind:FYSentenceKindDialogue];
        [app.learningCoordinator setTranslation:@"即使擅长画画，不每天练习也不会进步。" forIdentity:identity];
        [app.learningCoordinator pinCurrent];[app refreshLearningSource];
        [app refreshLearningStatus];
        [app.mainWindow setContentSize:NSMakeSize(1440,1000)];Tick();
        NSView *grammarCard=app.grammarEmptyPane.superview.superview;
        Require(app.grammarEmptyAnalyzeButton.enabled && !app.grammarEmptyPane.hidden,@"an available sentence must expose the real analysis action");
        Require(NSHeight(grammarCard.frame)<240,@"empty grammar must not retain the tall split-detail layout");
        Snapshot(grammarCard,[output stringByAppendingPathComponent:@"yiya-grammar-empty.png"]);
        [app toggleMainStudyChat:nil];[app.mainWindow setContentSize:NSMakeSize(980,660)];Tick();
        Require(NSMaxX(app.grammarEmptyAnalyzeButton.frame)<=NSWidth(app.grammarEmptyAnalyzeButton.superview.bounds)+1,@"compact empty-state action must fit its container");
        Snapshot(grammarCard,[output stringByAppendingPathComponent:@"yiya-grammar-empty-compact.png"]);
        [app toggleMainStudyChat:nil];[app.mainWindow setContentSize:NSMakeSize(1440,1000)];Tick();
        __block void (^analysisDone)(NSData *,NSURLResponse *,NSError *);
        app.learningAnalyzer.transport=^(NSURLRequest *request,void (^done)(NSData *,NSURLResponse *,NSError *)){analysisDone=[done copy];};
        [app.grammarEmptyAnalyzeButton performClick:nil];
        Pump(^BOOL{return analysisDone!=nil;});
        Require(app.learningAnalysisBusy && !app.grammarEmptyAnalyzeButton.enabled && app.grammarPointsPane.hidden,@"empty-state action must invoke analysis and prevent duplicate clicks while waiting");
        analysisDone(nil,nil,[NSError errorWithDomain:@"UITest" code:1 userInfo:@{NSLocalizedDescriptionKey:@"测试连接失败"}]);
        Pump(^BOOL{return !app.learningAnalysisBusy;});
        Require([app.grammarEmptyHint.stringValue containsString:@"测试连接失败"] && app.grammarEmptyAnalyzeButton.enabled,@"analysis failure must remain readable with a retry action");
        [app clearAnalysisDisplay];
        FYGrammarItem *grammar=[FYGrammarItem new];grammar.name=@"〜ないと";grammar.matchedText=@"しないと";
        grammar.matchedRange=[source rangeOfString:grammar.matchedText];grammar.meaning=@"如果不……就……";
        grammar.connection=@"动词ない形＋と";grammar.explanation=@"说明不练习就无法进步。";
        FYAnalysisResult *analysis=[FYAnalysisResult new];analysis.status=FYAnalysisStatusSuccess;
        analysis.sentenceID=identity.sentenceID;analysis.version=identity.version;analysis.grammar=@[grammar];
        app.currentAnalysis=analysis;[app refreshGrammarResults];
        Require(app.grammarEmptyPane.hidden && !app.grammarTabRow.hidden && !app.grammarPointsPane.hidden,@"successful analysis must restore the grammar list and details");

        // —— 「这一句的语法」分析结果态：真实数据驱动的多语法 + 紧凑胶囊结构图 ——
        // 语法条目数、等级、拆句与例句全部来自分析结果，视图不硬编码。
        NSMutableArray *parts=[NSMutableArray array];
        void (^addPart)(NSString*,NSString*,NSString*)=^(NSString *text,NSString *meaning,NSString *role){
            NSRange range=[source rangeOfString:text];
            Require(range.location!=NSNotFound,@"structure part must exist in the real source");
            [parts addObject:@{@"text":text,@"location":@(range.location),@"length":@(range.length),@"meaning":meaning,@"role":role}];
        };
        addPart(@"絵が得意でも",@"即使擅长画画",@"让步");
        addPart(@"毎日練習しないと",@"如果不每天练习",@"条件");
        addPart(@"上達しない",@"不会进步",@"结论");
        FYGrammarItem *g1=[FYGrammarItem new];g1.name=@"〜ても";g1.matchedText=@"得意でも";g1.matchedRange=[source rangeOfString:g1.matchedText];
        g1.referenceLevel=@"N4";g1.levelVerified=YES;g1.connection=@"イ形／名詞＋でも";g1.meaning=@"即使……也……";g1.explanation=@"让步说明即使擅长画画，也仍需每天练习。";
        FYGrammarItem *g2=[FYGrammarItem new];g2.name=@"〜ないと";g2.matchedText=@"しないと";g2.matchedRange=[source rangeOfString:g2.matchedText];
        g2.referenceLevel=@"N4";g2.levelVerified=NO;g2.connection=@"动词ない形＋と";g2.meaning=@"如果不……就……";g2.explanation=@"说明不练习就无法进步。";
        FYAnalysisResult *rich=[FYAnalysisResult new];rich.status=FYAnalysisStatusSuccess;
        rich.sentenceID=identity.sentenceID;rich.version=identity.version;
        rich.grammar=@[g1,g2];rich.sentenceNote=@"即使擅长画画，如果不每天练习，也不会进步。";
        rich.structureTitle=@"整句结构";rich.structureParts=parts;
        app.currentAnalysis=rich;[app refreshGrammarResults];Tick();
        Require(app.grammarOtherStack.arrangedSubviews.count==rich.grammar.count,@"the left list must render exactly the analysed grammar count");
        NSView *structureHost=app.sentenceStructureStack.arrangedSubviews.firstObject;
        Require([structureHost isKindOfClass:NSStackView.class],@"sentence structure must render as a compact node flow");
        Require(app.grammarDetailBookmarkButton.enabled && !app.grammarDetailBookmarkButton.hidden,@"grammar bookmark must stay reachable in the result state");
        Require(app.grammarQuestionField.enabled,@"grammar follow-up must stay reachable in the result state");
        [app.mainWindow setContentSize:NSMakeSize(1440,1000)];Tick();
        // 主界面语法区不再有重复的追问入口（追问统一走右侧 AI 伙伴）。
        for(NSString *duplicate in @[@"追问",@"继续追问",@"收起追问"]){
            Require(!ContainsButtonTitled(grammarCard,duplicate),
                    ([NSString stringWithFormat:@"the main grammar area must not offer a duplicate follow-up entry (%@)",duplicate]));
        }
        Require(app.mainStudyChatView!=nil && !app.mainStudyChatView.hidden && app.mainStudyChatView.superview!=nil,
                @"the right-side AI companion must stay available as the single follow-up entry");
        // 组件几何验收：同一窗口宽度下左栏约两成、结构节点为紧凑胶囊（不再是固定 180×90）。
        NSView *leftList=app.grammarOtherStack.superview;
        Require(app.grammarPointsPane.frame.size.width>0 && leftList.frame.size.width>0,@"grammar columns must lay out");
        CGFloat listRatio=leftList.frame.size.width/app.grammarPointsPane.frame.size.width;
        NSStackView *structureFlow=nil;
        for(NSView *child in ((NSStackView *)structureHost).arrangedSubviews){if([child isKindOfClass:NSScrollView.class]){structureFlow=(NSStackView *)((NSScrollView *)child).documentView;}}
        Require(structureFlow!=nil && structureFlow.arrangedSubviews.count==rich.structureParts.count*2-1,@"structure flow must show one node per real part plus arrows");
        NSView *nodeWrapper=structureFlow.arrangedSubviews.firstObject;
        [nodeWrapper layoutSubtreeIfNeeded];
        NSView *firstNode=[(NSStackView *)nodeWrapper arrangedSubviews].firstObject;
        NSLog(@"GRAMMAR GEOMETRY card=%.0f columns=%.0f left=%.0f ratio=%.2f nodeHeight=%.0f",
              NSWidth(grammarCard.frame),NSWidth(app.grammarPointsPane.frame),NSWidth(leftList.frame),listRatio,NSHeight(firstNode.frame));
        Require(fabs(listRatio-0.2)<0.08,@"left grammar list must take about 20% of the columns");
        Require(NSHeight(firstNode.frame)>0 && NSHeight(firstNode.frame)<70,@"structure nodes must be compact capsules rather than fixed 180x90");
        Snapshot(grammarCard,[output stringByAppendingPathComponent:@"yiya-grammar-result.png"]);

        // —— 结构图：点击节点只更新高亮与解释，不能把横向滚动位置打回最左 ——
        {
            // 用一句更长的真实句子拆成多段，保证结构图比视口宽、真的需要横向滚动。
            NSString *wideSource=@"絵が得意でも、毎日練習しないと上達しないので、明日も図書館で一緒に勉強しましょう。";
            [app followLatestSentence:nil];Tick();   // 确保这一句真的成为当前显示句（否则结构校验会失败）
            FYRequestIdentity *wideIdentity=[app.learningCoordinator recordText:wideSource kind:FYSentenceKindDialogue];
            [app.learningCoordinator setTranslation:@"即使擅长画画，如果不每天练习就不会进步，所以明天也一起去图书馆学习吧。" forIdentity:wideIdentity];
            [app refreshLearningSource];[app refreshLearningStatus];Tick();
            Require([app.learningCoordinator.currentSourceText isEqualToString:wideSource],@"the wide fixture must become the displayed sentence");
            NSMutableArray *wide=[NSMutableArray array];
            NSUInteger cursor=0;
            for (NSString *piece in @[@"絵が",@"得意でも",@"、",@"毎日",@"練習しないと",@"上達しない",@"ので",@"、",@"明日も",@"図書館で",@"一緒に",@"勉強しましょう",@"。"]) {
                NSRange search=NSMakeRange(cursor,wideSource.length-cursor);
                NSRange r=[wideSource rangeOfString:piece options:0 range:search];
                Require(r.location!=NSNotFound,@"wide structure fixture must be a real in-order substring");
                cursor=r.location+r.length;
                [wide addObject:@{@"text":piece,@"location":@(r.location),@"length":@(r.length),@"meaning":piece,@"role":@"段"}];
            }
            // 四个语法分别落在前段/中段/末段：滚到任何位置都能点到"看得见"的节点。
            NSMutableArray<NSString *> *wideNames=[NSMutableArray array];
            NSMutableArray<FYGrammarItem *> *wideGrammar=[NSMutableArray array];
            for (NSArray<NSString *> *spec in @[@[@"〜ても",@"得意でも"],@[@"〜ないと",@"練習しないと"],@[@"〜と一緒に",@"一緒に"],@[@"〜ましょう",@"勉強しましょう"]]) {
                FYGrammarItem *item=[FYGrammarItem new];
                item.name=spec[0];item.matchedText=spec[1];
                item.matchedRange=[wideSource rangeOfString:spec[1]];
                item.meaning=spec[0];
                [wideNames addObject:spec[0]];
                [wideGrammar addObject:item];
            }
            FYAnalysisResult *wideResult=[FYAnalysisResult new];wideResult.status=FYAnalysisStatusSuccess;
            wideResult.sentenceID=wideIdentity.sentenceID;wideResult.version=wideIdentity.version;
            wideResult.grammar=wideGrammar;wideResult.sentenceNote=rich.sentenceNote;
            wideResult.structureTitle=@"整句结构";wideResult.structureParts=wide;
            app.currentAnalysis=wideResult;[app refreshGrammarResults];Tick();
            NSScrollView *flow=app.mainStructureScrollView;
            Require(flow!=nil && flow.documentView.frame.size.width>flow.contentView.bounds.size.width+20,
                    @"the fixture must produce a horizontally scrollable structure flow");
            NSButton *(^nodeWithTag)(NSInteger)=^NSButton *(NSInteger tag){
                for(NSButton *b in app.mainStructureButtons){if(b.tag==tag){return b;}}
                return nil;
            };
            NSButton *nodeG0=nodeWithTag(0);
            Require(nodeG0!=nil,@"the structure must expose nodes for its grammar items");
            // 用户只会点"看得见"的节点：每次都在当前视野里挑一个来点。
            // documentView.visibleRect 在离屏布局里是空的，用 clip 的 bounds 换算可见区域。
            NSButton *(^visibleNode)(BOOL)=^NSButton *(BOOL preferTagged){
                [flow.documentView layoutSubtreeIfNeeded];
                NSRect visible=[flow.documentView convertRect:flow.contentView.bounds fromView:flow.contentView];
                NSButton *fallback=nil;
                for(NSButton *b in app.mainStructureButtons){
                    NSRect inDoc=[b convertRect:b.bounds toView:flow.documentView];
                    if(!NSIntersectsRect(inDoc,visible)){continue;}
                    if(b.tag>=0){return b;}
                    if(!fallback){fallback=b;}
                }
                return preferTagged?nil:fallback;
            };
            NSScrollView *page=(NSScrollView *)app.pages[0];
            // 收窄窗口，让结构图真的需要滚动（宽窗口下几乎整条都可见，测不出"跳回"）。
            [app.mainWindow setContentSize:NSMakeSize(980,900)];Tick();
            flow=app.mainStructureScrollView;
            Require(flow!=nil && flow.documentView.frame.size.width>flow.contentView.bounds.size.width+20,
                    @"the narrow window must make the structure flow scrollable");
            CGFloat maxX=flow.documentView.frame.size.width-flow.contentView.bounds.size.width;
            // ① 滚到中段 → 点当前视野里的节点
            [nodeG0 performClick:nil];Tick();
            Require(app.selectedGrammarIndex==0,@"the fixture starts on the first grammar item");
            [flow.contentView scrollToPoint:NSMakePoint(maxX*0.5,0)],[flow reflectScrolledClipView:flow.contentView];
            CGFloat midOffset=flow.contentView.bounds.origin.x;
            CGFloat pageYBefore=page.contentView.bounds.origin.y;
            Require(midOffset>1,@"the fixture must actually scroll to the middle");
            NSButton *midNode=visibleNode(YES);
            Require(midNode!=nil && midNode.tag>0,
                    @"the middle viewport must expose a tagged node other than the first, else the update proves nothing");
            [midNode performClick:nil];Tick();
            Require(app.selectedGrammarIndex==midNode.tag &&
                    [app.grammarDetailNameLabel.stringValue isEqualToString:wideNames[midNode.tag]],
                    @"clicking a visible structure node must update the explanation");
            Require(app.mainStructureScrollView==flow,
                    @"clicking a node must not rebuild the structure view (that is exactly what resets the offset)");
            Require(fabs(flow.contentView.bounds.origin.x-midOffset)<1.5,
                    @"clicking a node must not reset the structure's horizontal scroll (middle)");
            Require(fabs(page.contentView.bounds.origin.y-pageYBefore)<1.5,
                    @"clicking a node must not move the page vertically");
            NSRect nodeInDoc=[midNode convertRect:midNode.bounds toView:flow.documentView];
            NSRect midVisible=[flow.documentView convertRect:flow.contentView.bounds fromView:flow.contentView];
            Require(NSIntersectsRect(nodeInDoc,midVisible),
                    @"the clicked node must stay inside the visible area (no extra auto-centering)");
            // ② 滚到最右 → 点另一个节点
            [flow.contentView scrollToPoint:NSMakePoint(maxX,0)],[flow reflectScrolledClipView:flow.contentView];
            CGFloat rightOffset=flow.contentView.bounds.origin.x;
            Require(rightOffset>midOffset,@"the fixture must be able to scroll further right");
            NSButton *rightNode=visibleNode(YES) ?: visibleNode(NO);
            Require(rightNode!=nil,@"the far-right viewport must expose at least one node");
            [rightNode performClick:nil];Tick();
            if(rightNode.tag>=0){
                Require(app.selectedGrammarIndex==rightNode.tag &&
                        [app.grammarDetailNameLabel.stringValue isEqualToString:wideNames[rightNode.tag]],
                        @"clicking a node at the far right must update the explanation");
            }
            Require(fabs(flow.contentView.bounds.origin.x-rightOffset)<1.5,
                    @"clicking a node must not reset the structure's horizontal scroll (far right)");
            // ③ 独立学习卡复用同一组件，同样不能跳
            [app openInlineLearningForBlockText:wideSource translation:@"即使擅长画画，如果不每天练习就不会进步，所以明天也一起去图书馆学习吧。"];
            Pump(^BOOL{return !app.quickSentenceAnalyzing;});
            app.quickSentenceSource=wideSource;   // 显式设定：渲染时 quickSentenceSource 必须已等于分析来源
            app.quickSentenceAnalysisError=nil;   // 分析请求在隔离环境里会失败，直接放结果
            app.quickSentenceAnalysis=wideResult;app.quickSentenceAnalysisSource=wideSource;
            app.quickSentenceAnalysisTranslation=app.quickSentenceTranslation;
            [app renderQuickSentence];[app.quickSentencePanel setContentSize:NSMakeSize(440,500)];Tick();
            NSScrollView *quickFlow=app.quickStructureScrollView;
            Require(quickFlow!=nil && quickFlow.documentView.frame.size.width>quickFlow.contentView.bounds.size.width+20,
                    @"the standalone learning card must reuse the same scrollable structure component");
            CGFloat quickMax=quickFlow.documentView.frame.size.width-quickFlow.contentView.bounds.size.width;
            [quickFlow.contentView scrollToPoint:NSMakePoint(quickMax,0)],[quickFlow reflectScrolledClipView:quickFlow.contentView];
            CGFloat quickBefore=quickFlow.contentView.bounds.origin.x;
            NSButton *quickNode=nil;
            [quickFlow.documentView layoutSubtreeIfNeeded];
            NSRect quickVisible=[quickFlow.documentView convertRect:quickFlow.contentView.bounds fromView:quickFlow.contentView];
            for(NSButton *b in app.quickStructureButtons){
                NSRect inDoc=[b convertRect:b.bounds toView:quickFlow.documentView];
                if(NSIntersectsRect(inDoc,quickVisible) && b.tag>=0){quickNode=b;break;}
            }
            if(!quickNode){for(NSButton *b in app.quickStructureButtons){NSRect inDoc=[b convertRect:b.bounds toView:quickFlow.documentView];if(NSIntersectsRect(inDoc,quickVisible)){quickNode=b;break;}}}
            Require(quickNode!=nil && quickBefore>1,@"the quick structure must be scrolled and expose a visible node");
            [quickNode performClick:nil];Tick();
            if(quickNode.tag>=0){Require(app.quickSelectedGrammarIndex==quickNode.tag,@"clicking a node in the standalone card must update its explanation");}
            Require(fabs(quickFlow.contentView.bounds.origin.x-quickBefore)<1.5,
                    @"the standalone learning card must keep its structure scroll position too");
            [app closeStudyOverlay:nil];
            [app.mainWindow setContentSize:NSMakeSize(1440,1000)];Tick();
            app.currentAnalysis=rich;[app refreshGrammarResults];
            [app.learningCoordinator recordText:source kind:FYSentenceKindDialogue];
            [app refreshLearningSource];[app refreshLearningStatus];Tick();
        }
        [app.mainStudyChatView setContextText:source label:@"当前句"];
        [app.mainStudyChatView setMessages:@[@{@"role":@"user",@"content":@"「得意」为什么用「が」？"},@{@"role":@"assistant",@"content":@"「〜が得意」表示擅长什么。\n絵が得意 → 擅长画画。"}]];
        // Only the isolated fixture uses this labelled demonstration illustration.
        NSImage *atlas=[[NSImage alloc] initWithContentsOfFile:@"resources/ui/yiya/art/ui-reference-atlas.png"];
        Require(atlas!=nil,@"Yiya artwork must be available");atlas.size=NSMakeSize(1600,1040);
        NSImage *fixture=[[NSImage alloc] initWithSize:NSMakeSize(744,189)];
        [fixture lockFocus];[atlas drawInRect:NSMakeRect(0,0,744,189) fromRect:NSMakeRect(315,678,744,189) operation:NSCompositingOperationSourceOver fraction:1];[fixture unlockFocus];
        app.framePreview.image=fixture;app.previewPlaceholder.stringValue=@"示例画面 · UI 验收";app.previewPlaceholder.hidden=NO;
        [app.mainWindow setContentSize:NSMakeSize(1440,1000)];[app.mainWindow.contentView layoutSubtreeIfNeeded];Tick();[app refreshLearningSource];Tick();
        Require(app.framePreview.image==fixture,@"the theme must not replace incoming preview content");
        Require(app.learningSourceTextView.selectable && !app.learningSourceTextView.editable,@"native selection remains available");
        for(NSButton *button in app.pageButtons){[button performClick:nil];Require(app.selectedPage==button.tag,@"new icon button must preserve navigation action");}
        [app selectPageAtIndex:0];Tick();
        Snapshot(app.mainWindow.contentView,[output stringByAppendingPathComponent:@"yiya-native-main.png"]);

        // —— 实时翻译页操作入口 ——
        // 1) 主工具栏不再有「翻译当前界面」（只移除入口，方法仍保留）。
        Require(!ContainsButtonTitled(app.mainWindow.contentView,@"翻译当前界面"),@"the live toolbar must no longer offer 翻译当前界面");
        // 2) 固定/跟随按钮必须真的在可见布局里，而不是只创建了对象。
        Require(app.pinSentenceButton.superview!=nil && [app.pinSentenceButton isDescendantOf:app.pages[0]],
                @"the pin/follow action must live in the visible live page");

        NSString *sentenceA=@"これは固定した台詞です。";
        // 前面的语法用例固定过句子：先显式恢复跟随，作为本段的初始状态。
        [app followLatestSentence:nil];[app refreshLearningSource];[app refreshLearningStatus];Tick();
        Require(!app.learningCoordinator.isPinned,@"the fixture starts in following state");
        FYRequestIdentity *a=[app.learningCoordinator recordText:sentenceA kind:FYSentenceKindDialogue];
        [app.learningCoordinator setTranslation:@"这是被固定的台词。" forIdentity:a];
        [app refreshLearningSource];[app refreshLearningStatus];Tick();
        Require(!app.learningCoordinator.isPinned && [app.pinSentenceButton.title isEqualToString:@"固定此句"] && app.pinSentenceButton.enabled,
                @"following state offers an enabled 固定此句 action");
        Snapshot(app.pages[0],[output stringByAppendingPathComponent:@"yiya-live-following.png"]);

        // 固定 A
        [app.pinSentenceButton performClick:nil];Tick();
        Require(app.learningCoordinator.isPinned && [app.pinSentenceButton.title isEqualToString:@"跟随最新"],
                @"clicking the action pins the sentence and switches the label to 跟随最新");

        // 新台词 B 到达：固定只影响学习区查看的内容，不停止后台识别/翻译/字幕。
        NSUInteger generationBeforePin=app.translationGeneration;
        app.running=YES;
        FYRequestIdentity *b=[app.learningCoordinator recordText:@"新しい台詞 B です。" kind:FYSentenceKindDialogue];
        [app.learningCoordinator setTranslation:@"B 的译文。" forIdentity:b];
        [app refreshLearningSource];[app refreshLearningStatus];Tick();
        Require(app.running && app.translationGeneration==generationBeforePin,
                @"pinning must not stop the background translation pipeline");
        Require([app.learningCoordinator.latestSentenceID isEqualToString:b.sentenceID] && app.learningCoordinator.hasNewerSentence,
                @"background OCR/recording still advances to B while A is pinned");
        Require([app.learningSourceTextView.string isEqualToString:sentenceA] && [app.displayedSentenceID isEqualToString:a.sentenceID],
                @"the pinned learning area keeps showing A while B arrives");
        Require([app.learningPinnedLabel.stringValue containsString:@"有新台词"],
                @"a pinned sentence with newer dialogue keeps the 有新台词 hint");
        Snapshot(app.pages[0],[output stringByAppendingPathComponent:@"yiya-live-pinned-newer.png"]);

        // 点击「跟随最新」→ 学习区切到 B，并继续跟随后续 C。
        [app.pinSentenceButton performClick:nil];Tick();
        Require(!app.learningCoordinator.isPinned && [app.learningSourceTextView.string containsString:@"B"],
                @"clicking 跟随最新 resumes following and shows B");
        Require([app.pinSentenceButton.title isEqualToString:@"固定此句"],@"after resuming the action reads 固定此句 again");
        FYRequestIdentity *c=[app.learningCoordinator recordText:@"さらに新しい台詞 C です。" kind:FYSentenceKindDialogue];
        [app.learningCoordinator setTranslation:@"更新的台词 C。" forIdentity:c];
        [app refreshLearningSource];[app refreshLearningStatus];Tick();
        Require([app.learningSourceTextView.string containsString:@"C"],@"following keeps updating on later dialogue C");
        Snapshot(app.pages[0],[output stringByAppendingPathComponent:@"yiya-live-resumed.png"]);

        // 3) 选词导致的固定也能用同一按钮恢复跟随。
        [app freezeLearningSentenceForSelection];Tick();
        Require(app.learningCoordinator.isPinned && [app.pinSentenceButton.title isEqualToString:@"跟随最新"] && app.pinSentenceButton.enabled,
                @"word selection pins the sentence and leaves the resume action enabled");
        [app.pinSentenceButton performClick:nil];Tick();
        Require(!app.learningCoordinator.isPinned,@"the same action resumes following after a selection-driven pin");

        // —— AI 伙伴侧栏：主内容区唯一显隐开关，收起只隐藏不重建 ——
        NSButton *chatToggle=app.mainChatToggle;
        Require(chatToggle.superview!=nil && [chatToggle isDescendantOf:app.mainWindow.contentView],
                @"the AI toggle must live in the main content header");
        Require(![chatToggle isDescendantOf:app.mainStudyChatView],
                @"the AI toggle must not live inside the collapsible sidebar");
        NSButton *innerClose=[app.mainStudyChatView valueForKey:@"closeButton"];
        Require(innerClose!=nil && innerClose.hidden,@"the sidebar must no longer show its own 收起 button");
        Require([chatToggle.title isEqualToString:@"收起 AI 伙伴"],@"expanded state offers 收起 AI 伙伴");
        Snapshot(app.mainWindow.contentView,[output stringByAppendingPathComponent:@"yiya-ai-expanded.png"]);

        // 草稿 + 聊天记录 + 滚动位置
        NSMutableArray *chatMessages=[NSMutableArray array];
        for(NSUInteger i=0;i<12;i++){[chatMessages addObject:@{@"role":(i%2?@"assistant":@"user"),@"content":[NSString stringWithFormat:@"聊天消息 %lu —— 用于验证收起期间不丢内容。",(unsigned long)i]}];}
        [app.mainStudyChatView setMessages:chatMessages];
        [app.mainStudyChatView setDraftText:@"未发送的草稿"];
        [app.mainWindow.contentView layoutSubtreeIfNeeded];Tick();
        NSTextView *chatInput=[app.mainStudyChatView valueForKey:@"input"];
        NSScrollView *chatScroll=[app.mainStudyChatView valueForKey:@"messagesScroll"];
        [chatScroll.documentView layoutSubtreeIfNeeded];
        [chatScroll.contentView scrollToPoint:NSMakePoint(0,60)];[chatScroll reflectScrolledClipView:chatScroll.contentView];
        CGFloat scrollBefore=chatScroll.contentView.bounds.origin.y;
        Require(scrollBefore>0,@"the chat fixture must actually scroll");
        NSUInteger rowsBefore=((NSStackView *)[app.mainStudyChatView valueForKey:@"messagesStack"]).arrangedSubviews.count;

        // 连续三次 收起 → 展开：按钮始终可见且有效
        for(NSInteger cycle=0;cycle<3;cycle++){
            [app toggleMainStudyChat:nil];Tick();
            Require(app.mainStudyChatView.hidden && [chatToggle.title isEqualToString:@"展开 AI 伙伴"],
                    @"collapsing hides the sidebar and the same button offers 展开 AI 伙伴");
            Require(chatToggle.superview!=nil && !chatToggle.hidden,
                    @"the toggle stays visible after the sidebar is hidden");
            [app toggleMainStudyChat:nil];Tick();
            Require(!app.mainStudyChatView.hidden && [chatToggle.title isEqualToString:@"收起 AI 伙伴"],
                    @"expanding restores the sidebar and the button title");
        }
        // 同一窗口宽度（1440）下的收起截图，便于与展开图并排比对。
        [app toggleMainStudyChat:nil];Tick();
        Require(app.mainStudyChatView.hidden && [chatToggle.title isEqualToString:@"展开 AI 伙伴"],
                @"collapsed screenshot is taken with the sidebar hidden");
        Snapshot(app.mainWindow.contentView,[output stringByAppendingPathComponent:@"yiya-ai-collapsed.png"]);
        [app toggleMainStudyChat:nil];Tick();
        Require(!app.mainStudyChatView.hidden,@"the sidebar expands again after the collapsed screenshot");

        Require([[chatInput string] isEqualToString:@"未发送的草稿"],@"the unsent draft survives three collapse/expand cycles");
        Require(((NSStackView *)[app.mainStudyChatView valueForKey:@"messagesStack"]).arrangedSubviews.count==rowsBefore,
                @"the chat history survives collapse/expand without being rebuilt");
        Require(fabs(chatScroll.contentView.bounds.origin.y-scrollBefore)<1,
                @"the chat scroll position survives collapse/expand");

        // AI 生成回复期间收起/展开：请求继续，不重复发送
        __block NSUInteger answerCalls=0;
        __block void (^pendingAnswer)(NSData *,NSURLResponse *,NSError *);
        [app ensureStudyChatSession];
        [app.studyChatSession referenceSource:@"収起中でも質問できます。" translation:@"收起期间也能提问。"];
        app.studyChatSession.analyzer=Analyzer(catalog);
        app.studyChatSession.analyzer.transport=^(NSURLRequest *request,void (^done)(NSData *,NSURLResponse *,NSError *)){answerCalls+=1;pendingAnswer=[done copy];};
        NSUInteger chatCountBefore=app.studyChatSession.messages.count;
        [app.studyChatSession send:@"生成期间收起可以吗？"];
        Require(app.studyChatSession.sending && pendingAnswer!=nil,@"in-flight chat fixture");
        [app toggleMainStudyChat:nil];Tick();
        Require(app.studyChatSession.sending,@"collapsing must not cancel the in-flight AI request");
        [app toggleMainStudyChat:nil];Tick();
        Require(app.studyChatSession.sending && answerCalls==1,@"expanding must not cancel or resend the in-flight request");
        pendingAnswer(Envelope(@"完整的 AI 回复"),Response(),nil);Tick();
        Require(!app.studyChatSession.sending && app.studyChatSession.messages.count==chatCountBefore+2,
                @"the pending reply still arrives complete with no duplicate send");

        // 窄窗口下同样可见、可展开
        [app.mainWindow setContentSize:NSMakeSize(980,660)];Tick();
        [app toggleMainStudyChat:nil];Tick();
        NSRect toggleFrame=[chatToggle convertRect:chatToggle.bounds toView:app.mainWindow.contentView];
        Require(chatToggle.superview!=nil && !chatToggle.hidden && NSWidth(toggleFrame)>10 &&
                NSMaxX(toggleFrame)<=NSWidth(app.mainWindow.contentView.bounds)+1,
                @"the toggle stays inside the visible header in a narrow window");
        [app toggleMainStudyChat:nil];Tick();
        Require(!app.mainStudyChatView.hidden,@"the narrow window can expand the sidebar again");
        [app.mainWindow setContentSize:NSMakeSize(1440,1000)];Tick();

        // —— 贴译视觉：短贴片必须是奶油棕，不能是旧字幕的灰黑框 ——
        // 用 1440×900 的示例画面作为落位区域（744×189 的素材裁片放不下多块正文）。
        NSImage *scene=[[NSImage alloc] initWithSize:NSMakeSize(1440,900)];
        [scene lockFocus];
        [[NSColor colorWithSRGBRed:0.17 green:0.15 blue:0.13 alpha:1] setFill];
        NSRectFill(NSMakeRect(0,0,1440,900));
        [fixture drawInRect:NSMakeRect(0,900-366,1440,366) fromRect:NSZeroRect operation:NSCompositingOperationSourceOver fraction:0.92];
        [scene unlockFocus];
        [app clearInlineTranslationPanels];
        NSArray<OCRTextItem *> *menuItems = @[
            Item2(@"公演日程", CGRectMake(.08,.76,.15,.028)),
            Item2(@"イベント情報", CGRectMake(.08,.69,.16,.028)),
            Item2(@"アルバイト", CGRectMake(.08,.62,.14,.028)),
            Item2(@"詳細", CGRectMake(.86,.70,.07,.024)),
            Item2(@"戻る", CGRectMake(.06,.55,.06,.024)),
            Item2(@"更新", CGRectMake(.62,.76,.06,.024))
        ];
        NSArray<NSString *> *menuTranslations = @[@"公演日程", @"活动信息", @"兼职", @"详情", @"返回", @"更新"];
        DrawInlineLayer(app, DrawSources(scene, menuItems), menuTranslations, menuItems, [output stringByAppendingPathComponent:@"yiya-inline-menu.png"]);
        Require(app.inlineLongCardPanels.count == 0 && app.inlineTranslationPanels.count == menuItems.count,
                @"a menu of short entries must render as passthrough patches only");
        for (NSPanel *panel in app.inlineTranslationPanels) {
            Require(panel.ignoresMouseEvents, @"short patches must stay click-through");
        }
        app.captionThemeControl = [NSSegmentedControl segmentedControlWithLabels:@[@"黑底白字",@"白底黑字",@"粉底深字",@"译芽花境"] trackingMode:NSSegmentSwitchTrackingSelectOne target:nil action:nil];
        app.captionThemeControl.selectedSegment = 0;
        [app clearInlineTranslationPanels];
        [app showInlineTranslations:menuTranslations forItems:menuItems placementRect:NSMakeRect(0,0,scene.size.width,scene.size.height)];
        Tick();
        NSColor *patchFill = app.inlineTranslationPanels.count ? [NSColor colorWithCGColor:app.inlineTranslationPanels.firstObject.contentView.layer.backgroundColor] : nil;
        NSColor *creamToken = FYAdventureColor(@"cream");
        // 贴译底色跟随「背景透明度」设置（该 app 用默认 0.58）；切字幕主题不得改变贴译配色。
        CGFloat expectedInlineAlpha = app.captionOpacitySlider ? app.captionOpacitySlider.doubleValue : 0.58;
        Require(patchFill != nil && fabs(patchFill.redComponent-creamToken.redComponent)<0.03 &&
                fabs(patchFill.alphaComponent-expectedInlineAlpha)<0.03,
                @"switching the caption theme to black must not repaint the inline patches");

        // —— 长卡可读性（回归）：不准出现空细条或"只剩标题"的卡 ——
        {
            [app clearInlineTranslationPanels];
            // 真实新闻页形态：两段正文都靠画面下部，原文下方/上方余量都很紧。
            OCRTextItem *lowA=[OCRTextItem new];
            lowA.text=@"新しい季節のイベントが始まります。\n期間中は限定の衣装も登場します。\nぜひお見逃しなく。";
            lowA.boundingBox=CGRectMake(.08,.10,.42,.10);
            lowA.lineBoxes=@[[NSValue valueWithRect:CGRectMake(.08,.10,.42,.032)],[NSValue valueWithRect:CGRectMake(.08,.135,.42,.032)],[NSValue valueWithRect:CGRectMake(.08,.17,.42,.032)]];
            lowA.lineCount=3;lowA.blockKind=InlineBlockKindLong;
            OCRTextItem *lowB=[OCRTextItem new];
            lowB.text=@"さらに、期間限定の特別なストーリーも公開予定です。\n詳細は公式サイトをご確認ください。\nお楽しみに。";
            lowB.boundingBox=CGRectMake(.56,.13,.40,.09);
            lowB.lineBoxes=@[[NSValue valueWithRect:CGRectMake(.56,.13,.40,.03)],[NSValue valueWithRect:CGRectMake(.56,.165,.40,.03)],[NSValue valueWithRect:CGRectMake(.56,.20,.40,.03)]];
            lowB.lineCount=3;lowB.blockKind=InlineBlockKindLong;
            NSString *para=@"新的季节活动即将开始，活动期间还会推出限定服装，请千万不要错过。为了让这段译文超过卡片的可视高度、必须滚动才能读到结尾，这里再补充一些说明文字：活动期间每天登录还可以领取一份小礼物，累计登录七天可获得特别的纪念道具，详情请查看官方网站。";
            NSArray<OCRTextItem *> *lowItems=@[lowA,lowB];
            DrawInlineLayer(app, DrawSources(scene, lowItems), @[para,para], lowItems, [output stringByAppendingPathComponent:@"yiya-inline-cramped.png"]);
            Require(app.inlineLongCardPanels.count==2,@"the cramped fixture must still render two reading cards");
            CGFloat minCard=[app inlineLongCardMinimumHeight];
            for(NSUInteger i=0;i<2;i++){
                NSPanel *card=app.inlineLongCardPanels[i];
                NSScrollView *scroll=LongCardScroll(card);
                NSTextField *body=LongCardBody(card);
                Require(scroll!=nil && body!=nil && body.stringValue.length>0,
                        ([NSString stringWithFormat:@"card %lu must contain real translation text",(unsigned long)i+1]));
                CGFloat viewport=NSHeight(scroll.contentView.bounds);
                CGFloat lineHeight=LongCardLineHeight(body);
                Require(NSHeight(card.frame)>=minCard-1,
                        ([NSString stringWithFormat:@"card %lu must keep the readable minimum height (got %.0f, want %.0f)",(unsigned long)i+1,NSHeight(card.frame),minCard]));
                Require(viewport>=lineHeight*3-1,
                        ([NSString stringWithFormat:@"card %lu must show at least three body lines (viewport %.0f, line %.0f)",(unsigned long)i+1,viewport,lineHeight]));
                // 卡片按完整译文长高：正文在一屏内就完整可见、超出上限才内部滚动。
                // 这里断言真正要保证的性质 —— 文档装得下整段译文（不是被截断的片段）；
                // 真正的“滚动到末尾”由下面单独的 overflow 用例验证。
                Require(NSHeight(body.frame)>=TranslationHeightForBody(body)-2,
                        ([NSString stringWithFormat:@"card %lu must carry the whole translation (doc %.0f, measured %.0f)",(unsigned long)i+1,NSHeight(body.frame),TranslationHeightForBody(body)]));
                if(NSHeight(body.frame)>viewport+1){
                    CGFloat maxY=NSHeight(body.frame)-viewport;
                    [scroll.contentView scrollToPoint:NSMakePoint(0,maxY)];
                    [scroll reflectScrolledClipView:scroll.contentView];
                    Require(scroll.contentView.bounds.origin.y>=maxY-1.5,
                            ([NSString stringWithFormat:@"card %lu must be able to scroll to the end of the text",(unsigned long)i+1]));
                }
            }
            // 点击各自卡片 → 打开对应块的原文与语法
            FYInlineLongCardView *cardB=(FYInlineLongCardView *)app.inlineLongCardPanels[1].contentView;
            Require(cardB.onClick!=nil && !cardB.compactEntry,@"a readable long card must not be a compact placeholder");
            cardB.onClick();
            Require(app.inlineBlockSnapshot!=nil && [app.inlineBlockSnapshot.sourceText containsString:@"限定の特別"],
                    @"clicking the second card must open that article's own source snapshot");
            [app closeStudyOverlay:nil];
            // 溢出用例：换一段足够长的译文，卡片必须出现真正的滚动范围并能滚到末尾。
            {
                NSString *overflow=[para stringByAppendingString:para];
                overflow=[overflow stringByAppendingString:para];
                [app clearInlineTranslationPanels];
                DrawInlineLayer(app, DrawSources(scene, lowItems), @[overflow,overflow], lowItems, [output stringByAppendingPathComponent:@"yiya-inline-overflow.png"]);
                Require(app.inlineLongCardPanels.count==2,@"the overflow fixture must still render two cards");
                for(NSUInteger i=0;i<2;i++){
                    NSPanel *card=app.inlineLongCardPanels[i];
                    NSScrollView *scroll=LongCardScroll(card);
                    NSTextField *body=LongCardBody(card);
                    CGFloat viewport=NSHeight(scroll.contentView.bounds);
                    Require(scroll!=nil && body!=nil && NSHeight(body.frame)>viewport+1,
                            ([NSString stringWithFormat:@"overflow card %lu must scroll internally (doc %.0f, viewport %.0f)",(unsigned long)i+1,NSHeight(body.frame),viewport]));
                    CGFloat maxY=NSHeight(body.frame)-viewport;
                    [scroll.contentView scrollToPoint:NSMakePoint(0,maxY)];
                    [scroll reflectScrolledClipView:scroll.contentView];
                    Require(scroll.contentView.bounds.origin.y>=maxY-1.5,
                            ([NSString stringWithFormat:@"overflow card %lu must scroll to the end of its translation",(unsigned long)i+1]));
                }
                [app clearInlineTranslationPanels];
            }
            // 缩小窗口后仍要可读（不允许靠压扁解决）
            [app.mainWindow setContentSize:NSMakeSize(980,700)];Tick();
            NSRect smaller=NSMakeRect(0,0,scene.size.width*0.7,scene.size.height*0.7);
            [app clearInlineTranslationPanels];
            [app showInlineTranslations:@[para,para] forItems:lowItems placementRect:smaller];Tick();
            for(NSUInteger i=0;i<app.inlineLongCardPanels.count;i++){
                NSPanel *card=app.inlineLongCardPanels[i];
                NSScrollView *scroll=LongCardScroll(card);
                NSTextField *body=LongCardBody(card);
                Require(scroll!=nil && body!=nil,@"resized cards must keep their body");
                if(card.contentView && [(FYInlineLongCardView *)card.contentView compactEntry]){continue;}
                Require(NSHeight(scroll.contentView.bounds)>=LongCardLineHeight(body)*3-1,
                        @"after resizing, cards must still show at least three body lines");
            }
            [app.mainWindow setContentSize:NSMakeSize(1440,1000)];Tick();
            [app clearInlineTranslationPanels];
        }

        // —— 排版验收：每块译文绑定对应原文；不跨栏、不压相邻标题、不挤进菜单 ——
        {
            [app clearInlineTranslationPanels];
            NSRect placement = NSMakeRect(0, 0, scene.size.width, scene.size.height);
            OCRTextItem *menu1=Item2(@"公演日程", CGRectMake(.05,.80,.13,.026));
            OCRTextItem *menu2=Item2(@"イベント情報", CGRectMake(.05,.72,.15,.026));
            OCRTextItem *menu3=Item2(@"アルバイト", CGRectMake(.05,.64,.12,.026));
            OCRTextItem *titleA=Item2(@"お知らせ", CGRectMake(.30,.78,.12,.028));
            OCRTextItem *titleB=Item2(@"新商品のご案内", CGRectMake(.66,.78,.16,.028));
            OCRTextItem *bodyA=[OCRTextItem new];bodyA.text=@"新しい季節のイベントが始まります。\n期間中は限定の衣装も登場します。\nぜひお見逃しなく。";
            bodyA.boundingBox=CGRectMake(.30,.42,.30,.14);bodyA.lineBoxes=@[[NSValue valueWithRect:CGRectMake(.30,.42,.30,.045)],[NSValue valueWithRect:CGRectMake(.30,.475,.30,.045)],[NSValue valueWithRect:CGRectMake(.30,.53,.30,.045)]];bodyA.lineCount=3;bodyA.blockKind=InlineBlockKindLong;
            OCRTextItem *bodyB=[OCRTextItem new];bodyB.text=@"さらに、期間限定の特別なストーリーも公開予定です。\n詳細は公式サイトをご確認ください。";
            bodyB.boundingBox=CGRectMake(.66,.42,.28,.12);bodyB.lineBoxes=@[[NSValue valueWithRect:CGRectMake(.66,.42,.28,.05)],[NSValue valueWithRect:CGRectMake(.66,.48,.28,.05)]];bodyB.lineCount=2;bodyB.blockKind=InlineBlockKindLong;
            NSArray<OCRTextItem *> *pageItems=@[menu1,menu2,menu3,titleA,titleB,bodyA,bodyB];
            NSString *para=@"新的季节活动即将开始，活动期间还会推出限定服装。";
            NSArray<NSString *> *pageTranslations=@[@"公演日程",@"活动信息",@"兼职",@"通知",@"新商品介绍",para,para];
            DrawInlineLayer(app, DrawSources(scene, pageItems), pageTranslations, pageItems, [output stringByAppendingPathComponent:@"yiya-inline-news-layout.png"]);
            Require(app.inlineLongCardPanels.count==2 && app.inlineTranslationPanels.count==5,@"the news fixture must render two article cards and five short patches");
            NSMutableArray<NSValue *> *sources=[NSMutableArray array];
            for(OCRTextItem *item in pageItems){[sources addObject:[NSValue valueWithRect:[app appKitFrameForOCRItem:item inWindowFrame:placement]]];}
            // ① 左侧菜单三项：锚定一致（与原文左对齐、正下方、间距一致），且不压到下一项
            for(NSUInteger i=0;i<3;i++){
                NSPanel *patch=app.inlineTranslationPanels[i];
                NSRect source=sources[i].rectValue;
                Require(fabs(NSMinX(patch.frame)-NSMinX(source))<2,
                        @"menu patches must stay left-aligned with their own item");
                Require(NSMaxY(patch.frame)<=NSMaxY(source)+1 && NSMinY(source)-NSMaxY(patch.frame)<16,
                        @"menu patches must sit directly under their own item");
                for(NSUInteger j=0;j<3;j++){
                    if(j==i){continue;}
                    Require(!CGRectIntersectsRect(patch.frame,sources[j].rectValue),
                            @"a menu patch must never land on another menu item");
                }
            }
            // ② 两张正文卡：与各自正文横向绑定，且不覆盖任何**其它**原文块（标题/菜单/另一篇）
            NSRect cardA=app.inlineLongCardPanels[0].frame, cardB=app.inlineLongCardPanels[1].frame;
            Require(CGRectGetMinX(cardA)<NSMaxX(sources[5].rectValue) && CGRectGetMaxX(cardA)>NSMinX(sources[5].rectValue),
                    @"article A card must stay horizontally bound to article A");
            Require(CGRectGetMinX(cardB)<NSMaxX(sources[6].rectValue) && CGRectGetMaxX(cardB)>NSMinX(sources[6].rectValue),
                    @"article B card must stay horizontally bound to article B");
            for(NSUInteger i=0;i<5;i++){
                Require(!CGRectIntersectsRect(cardA,sources[i].rectValue),@"article A card must not cover the menu or the titles");
                Require(!CGRectIntersectsRect(cardB,sources[i].rectValue),@"article B card must not cover the menu or the titles");
            }
            Require(!CGRectIntersectsRect(cardA,sources[6].rectValue) && !CGRectIntersectsRect(cardB,sources[5].rectValue),
                    @"each article card must stay out of the other article's region");
            Require(!CGRectIntersectsRect(cardA,cardB),@"the two article cards must not overlap each other");
            // ③ 卡片宽度跟着正文走，不是统一的窄卡；也不越出画面
            Require(NSWidth(cardA)>=300 && NSWidth(cardB)>=300,@"article cards must be wide enough to avoid shredded lines");
            Require(NSMinX(cardA)>=NSMinX(placement)-1 && NSMaxX(cardA)<=NSMaxX(placement)+1 &&
                    NSMinY(cardA)>=NSMinY(placement)-1 && NSMaxY(cardA)<=NSMaxY(placement)+1,
                    @"article A card must stay inside the capturable frame");
            Require(NSMinX(cardB)>=NSMinX(placement)-1 && NSMaxX(cardB)<=NSMaxX(placement)+1 &&
                    NSMinY(cardB)>=NSMinY(placement)-1 && NSMaxY(cardB)<=NSMaxY(placement)+1,
                    @"article B card must stay inside the capturable frame");
            // ④ 缩放画面后仍保持对应关系：同一篇正文 → 同一栏，卡片不出画面、互不重叠
            NSRect scaled = NSMakeRect(0, 0, scene.size.width * 0.72, scene.size.height * 0.72);
            [app clearInlineTranslationPanels];
            [app showInlineTranslations:pageTranslations forItems:pageItems placementRect:scaled];
            Tick();
            Require(app.inlineLongCardPanels.count==2, @"a resized frame must still render both article cards");
            NSMutableArray<NSValue *> *scaledSources=[NSMutableArray array];
            for(OCRTextItem *item in pageItems){[scaledSources addObject:[NSValue valueWithRect:[app appKitFrameForOCRItem:item inWindowFrame:scaled]]];}
            NSRect scaledA=app.inlineLongCardPanels[0].frame, scaledB=app.inlineLongCardPanels[1].frame;
            Require(CGRectGetMinX(scaledA)<NSMaxX(scaledSources[5].rectValue) && CGRectGetMaxX(scaledA)>NSMinX(scaledSources[5].rectValue) &&
                    CGRectGetMinX(scaledB)<NSMaxX(scaledSources[6].rectValue) && CGRectGetMaxX(scaledB)>NSMinX(scaledSources[6].rectValue),
                    @"after resizing, each card must stay bound to its own article column");
            Require(!CGRectIntersectsRect(scaledA,scaledB) && !CGRectIntersectsRect(scaledA,scaledSources[6].rectValue) &&
                    !CGRectIntersectsRect(scaledB,scaledSources[5].rectValue),
                    @"after resizing, cards must not overlap each other or the other article");
            Require(NSMinX(scaledA)>=NSMinX(scaled)-1 && NSMaxX(scaledB)<=NSMaxX(scaled)+1 &&
                    NSMinY(scaledA)>=NSMinY(scaled)-1 && NSMaxY(scaledB)<=NSMaxY(scaled)+1,
                    @"after resizing, cards must stay inside the capturable frame");
            [app clearInlineTranslationPanels];
        }

        // —— 长阅读卡：多个正文块互不重叠 + 短段收紧 + 超长滚动与点击 ——
        OCRTextItem *newsA=[OCRTextItem new];newsA.text=@"新しい季節のイベントが始まります。\n期間中は限定の衣装も登場します。\nぜひお見逃しなく。";
        newsA.boundingBox=CGRectMake(.08,.42,.42,.10);newsA.lineBoxes=@[[NSValue valueWithRect:CGRectMake(.08,.42,.42,.032)],[NSValue valueWithRect:CGRectMake(.08,.455,.42,.032)],[NSValue valueWithRect:CGRectMake(.08,.49,.42,.032)]];newsA.lineCount=3;newsA.blockKind=InlineBlockKindLong;
        OCRTextItem *newsB=[OCRTextItem new];newsB.text=@"さらに、期間限定の特別なストーリーも公開予定です。\n詳細は公式サイトをご確認ください。";
        newsB.boundingBox=CGRectMake(.56,.34,.40,.07);newsB.lineBoxes=@[[NSValue valueWithRect:CGRectMake(.56,.34,.40,.032)],[NSValue valueWithRect:CGRectMake(.56,.375,.40,.032)]];newsB.lineCount=2;newsB.blockKind=InlineBlockKindLong;
        OCRTextItem *shortPara=[OCRTextItem new];shortPara.text=@"お知らせです。";
        shortPara.boundingBox=CGRectMake(.08,.20,.24,.032);shortPara.lineBoxes=@[[NSValue valueWithRect:CGRectMake(.08,.20,.24,.032)]];shortPara.lineCount=1;shortPara.blockKind=InlineBlockKindLong;
        NSString *newsLongTranslation=@"新的季节活动即将开始。活动期间还会推出限定服装，请千万不要错过。此外，还计划公开期间限定的特别剧情，详情请查看官方网站。为了让这段译文超过卡片的最大高度，从而出现真正的滚动范围，这里再补充一些说明文字：活动期间每天登录还可以领取一份小礼物，累计登录七天可获得特别的纪念道具。";
        DrawInlineLayer(app, DrawSources(scene, @[newsA, newsB, shortPara]), @[newsLongTranslation, newsLongTranslation, @"这是一条短通知。"], @[newsA, newsB, shortPara], [output stringByAppendingPathComponent:@"yiya-inline-news.png"]);
        Require(app.inlineLongCardPanels.count == 3, @"three long-form blocks must render three reading cards");
        NSMutableArray<NSValue *> *frames=[NSMutableArray array];
        for(NSPanel *panel in app.inlineLongCardPanels){[frames addObject:[NSValue valueWithRect:panel.frame]];}
        for(NSUInteger i=0;i<frames.count;i++){for(NSUInteger j=i+1;j<frames.count;j++){
            Require(!CGRectIntersectsRect(frames[i].rectValue,frames[j].rectValue),@"long reading cards must not overlap each other");}}
        NSPanel *shortCard=nil;NSPanel *tallCard=nil;
        for(NSPanel *panel in app.inlineLongCardPanels){
            CGFloat h=NSHeight(panel.frame);
            if(!shortCard || h<NSHeight(shortCard.frame)){shortCard=panel;}
            if(!tallCard || h>NSHeight(tallCard.frame)){tallCard=panel;}
        }
        Require(NSHeight(shortCard.frame) < NSHeight(tallCard.frame), @"a short paragraph must produce a tighter card than a long one");
        NSScrollView *longScroll=nil;
        for(NSView *child in tallCard.contentView.subviews){if([child isKindOfClass:NSScrollView.class]){longScroll=(NSScrollView *)child;}}
        // 卡片按完整译文长高：文档必须装得下整段译文；真正的“溢出一屏并滚到末尾”由
        // 上方 cramped 段的 overflow 用例验证（那里用更长的译文）。
        NSTextField *longBody=(NSTextField *)longScroll.documentView;
        Require(longScroll!=nil && longBody!=nil &&
                NSHeight(longBody.frame)>=TranslationHeightForBody(longBody)-2,
                @"the long card must carry the whole translation instead of a truncated fragment");
        Snapshot(tallCard.contentView,[output stringByAppendingPathComponent:@"yiya-inline-longcard.png"]);
        // 「已选中」只在真正选中时出现：把当前学习快照设成这一块，卡片才显示标识。
        Require(!HasBadge(tallCard.contentView),@"an unselected long card must not show the 已选中 badge");
        FYInlineBlockSnapshot *beforeSel=app.inlineBlockSnapshot;
        FYInlineBlockSnapshot *sel=[FYInlineBlockSnapshot new];
        sel.sourceText=newsB.text;sel.translation=newsLongTranslation;sel.lineBoxes=newsB.lineBoxes;
        sel.blockID=[app inlineBlockIdentityForItem:newsB];   // 选中判定按块身份（原文+行框），不是纯文本
        app.inlineBlockSnapshot=sel;
        NSPanel *selectedCard=[app inlineLongPanelForTranslation:newsLongTranslation item:newsB frame:NSMakeRect(160,160,340,240)];
        Require(HasBadge(selectedCard.contentView),@"a selected long card must show the 已选中 badge");
        Snapshot(selectedCard.contentView,[output stringByAppendingPathComponent:@"yiya-inline-longcard-selected.png"]);
        [selectedCard close];
        app.inlineBlockSnapshot=beforeSel;
        FYInlineLongCardView *longCardView=(FYInlineLongCardView *)app.inlineLongCardPanels[1].contentView;
        Require(longCardView.onClick!=nil,@"the long card must own its click handler and not pass it through");
        longCardView.onClick();
        Require(app.inlineBlockSnapshot!=nil && [app.inlineBlockSnapshot.sourceText containsString:@"限定の特別"],
                @"clicking a long card must open that block's own source snapshot, not the latest dialogue");
        [app closeStudyOverlay:nil];
        [app clearInlineTranslationPanels];
        app.captionThemeControl.selectedSegment = 3;

        [app toggleMainStudyChat:nil];[app.mainWindow setContentSize:NSMakeSize(980,660)];Tick();
        Require(app.mainStudyChatView.hidden,@"AI collapse must remain available");
        Require([app.mainChatToggle.title isEqualToString:@"展开 AI 伙伴"] && app.mainChatToggle.superview!=nil,
                @"the collapsed state still offers a visible 展开 AI 伙伴 toggle");
        Snapshot(app.mainWindow.contentView,[output stringByAppendingPathComponent:@"yiya-ai-collapsed-narrow.png"]);
        Require(fabs(NSWidth(app.mainWindow.contentView.bounds)-980)<2,@"compact window remains resizable");
        Snapshot(app.mainWindow.contentView,[output stringByAppendingPathComponent:@"yiya-native-compact.png"]);
        [app createCaptionWindow];Require(app.captionThemeControl.selectedSegment==3,@"fresh installations default to Yiya caption");
        for(NSInteger i=0;i<3;i++){
            app.captionThemeControl.selectedSegment=i;[app updateCaptionAppearance];
            Require([app captionThemeIndex]==i,@"legacy theme choices must not be remapped");
        }
        app.captionThemeControl.selectedSegment=3;app.captionOpacitySlider.doubleValue=.92;
        app.captionTextLabel.stringValue=@"即使擅长画画，不每天练习也不会进步。";[app updateCaptionAppearance];
        Snapshot(app.captionPanel.contentView,[output stringByAppendingPathComponent:@"yiya-native-caption.png"]);
        Require(app.captionTextLabel.selectable,@"caption text remains copyable");
        Require([[app captionTextColor] isEqual:FYAdventureColor(@"ink")],@"cream caption must use readable brown text");
        // 固定期间字幕仍可更新：固定不是「停止翻译」。
        [app.pinSentenceButton performClick:nil];Tick();
        Require(app.learningCoordinator.isPinned,@"caption check starts from a pinned sentence");
        [app updateCaptionWindowWithText:@"固定期间的后台字幕。" status:@"正在翻译"];
        Require([app.captionTextLabel.stringValue containsString:@"固定期间的后台字幕"],
                @"the caption/subtitle path still updates while a sentence is pinned");
        [app.pinSentenceButton performClick:nil];Tick();
        Require(!app.learningCoordinator.isPinned,@"caption check restores following");
        if([NSFont fontWithName:@"STYuanti-SC-Regular" size:20])Require([app.captionTextLabel.font.fontName containsString:@"Yuanti"],@"caption uses the approved rounded Chinese font");
        if([NSFont fontWithName:@"HiraMaruProN-W4" size:20])Require([app.learningSourceTextView.font.fontName containsString:@"HiraMaru"],@"Japanese source uses the approved rounded Japanese font");
        app.quickSentenceSource=source;app.quickSentenceTranslation=@"即使擅长画画，不每天练习也不会进步。";
        app.quickSentenceAnalysis=analysis;app.quickSentenceAnalysisSource=source;
        [app renderQuickSentence];Tick();
        Snapshot(app.quickSentencePanel.contentView,[output stringByAppendingPathComponent:@"yiya-native-dialogue.png"]);
        [app.quickSentencePanel orderOut:nil];
        [app.mainWindow orderOut:nil];[app.captionPanel orderOut:nil];
        __block BOOL closed=NO;[store closeWithCompletion:^(NSError *error){Require(!error,@"close");closed=YES;}];Pump(^BOOL{return closed;});
        for(NSString *suffix in @[@"",@"-wal",@"-shm"])[NSFileManager.defaultManager removeItemAtPath:[temp stringByAppendingString:suffix] error:NULL];
        NSLog(@"PASS: Yiya native navigation, selection, resizing, artwork, caption styles and snapshots; isolated sample data only.");
    }return 0;
}
