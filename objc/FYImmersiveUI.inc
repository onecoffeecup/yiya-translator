// Workspace and game windows share one session; capture remains independent.
- (void)ensureStudyChatSession {
    if(self.studyChatSession){return;}
    self.studyChatSession=[FYStudyChatSession new];
    __weak typeof(self) weakSelf=self;
    self.studyChatSession.onChange=^{[weakSelf refreshStudyChatViews];};
}
- (FYStudyChatView *)makeStudyChatViewForOverlay:(BOOL)overlay {
    [self ensureStudyChatSession];FYStudyChatView *view=[FYStudyChatView new];view.translatesAutoresizingMaskIntoConstraints=NO;
    __weak typeof(self) weakSelf=self;
    view.onSend=^(NSString *text){[weakSelf sendStudyChat:text];};
    view.onLatest=^{[weakSelf referenceLatestStudySentence:nil];};
    // 从贴译学习卡进入 AI 时，返回动作走聊天组件自己的导航行回调。
    view.onReturn=^{[weakSelf returnFromStudyChatToInlineLearning:nil];};
    if(overlay){
        view.onClose=^{[weakSelf closeStudyOverlay:nil];};
    }else{
        // 主内容区右上角有唯一的显隐开关：侧栏内部不再放「收起」，避免两个入口状态不同步。
        [view setCloseVisible:NO];
    }
    return view;
}
- (void)referenceLatestStudySentence:(id)sender {
    [self ensureStudyChatSession];
    NSInteger generation=++self.chatContextGeneration;
    self.chatResolvingSource=YES;
    [self.studyChatSession startNewConversationWithSource:@"" translation:@""];
    // 引用最新句是显式重新识别，作废旧返回关系，避免返回入口指向旧块。
    self.inlineReturnSnapshot=nil;[self updateInlineReturnButtonVisibility];
    [self resolveLatestStudySentence:^(NSString *source,NSString *translation){
        if(generation!=self.chatContextGeneration){return;}
        self.chatResolvingSource=NO;
        [self.studyChatSession referenceSource:source translation:translation];
    }];
}
- (void)resolveLatestStudyIdentity:(void (^)(FYRequestIdentity *))completion {
    NSString *latest=self.learningCoordinator.latestSentenceID;
    if(latest.length && ![latest isEqualToString:self.learningCoordinator.currentSentenceID]){
        [self.learningStore fetchSentence:latest completion:^(FYSentenceRecord *record,NSError *error){
            completion(record?[FYRequestIdentity identityWithSentenceID:record.sentenceID version:record.latestVersion requestID:NSUUID.UUID.UUIDString sourceText:record.latestText translation:record.latestTranslation]:nil);
        }];
    }else if(self.learningCoordinator.currentSentenceID.length){
        completion([FYRequestIdentity identityWithSentenceID:self.learningCoordinator.currentSentenceID version:self.learningCoordinator.currentVersion requestID:NSUUID.UUID.UUIDString sourceText:self.learningCoordinator.currentSourceText translation:self.learningCoordinator.currentTranslation]);
    }else{completion(nil);}
}
- (void)resolveLatestStudySentence:(void (^)(NSString *,NSString *))completion {
    // The preview can already show the next line while the regular OCR cycle
    // is waiting for stability or translating the previous line. Capture at
    // the user's click, independently of that cycle and the pinned reader.
    if(self.running && [self selectedWindowID]){
        [self captureLatestStudySentenceWithCompletion:^(NSString *source,NSError *error){
            if(error){[self showError:error.localizedDescription];completion(@"",@"");return;}
            [self resolveLatestStudyIdentity:^(FYRequestIdentity *identity){
                BOOL sameSource=identity.sourceText.length && [FYDialogueComparisonKey(source) isEqualToString:FYDialogueComparisonKey(identity.sourceText)];
                BOOL anchoredFragment=[self effectiveModeSegment]==ContentModeDialogue && self.languageControl.selectedSegment==0 &&
                    identity.sourceText.length && FYDialogueIsSpeakerAnchoredFragment(source,identity.sourceText);
                NSString *resolvedSource=anchoredFragment?identity.sourceText:source;
                NSString *translation=(sameSource || anchoredFragment)?identity.translation:@"";
                completion(resolvedSource,translation ?: @"");
            }];
        }];
        return;
    }
    [self resolveLatestStudyIdentity:^(FYRequestIdentity *identity){
        completion(identity.sourceText ?: self.learningSourceTextView.string ?: @"",identity?identity.translation ?: @"":self.learningTranslationLabel.stringValue ?: @"");
    }];
}
- (void)captureLatestStudySentenceWithCompletion:(void (^)(NSString *,NSError *))completion {
    uint32_t windowID=[self selectedWindowID];
    NSInteger generation=self.translationGeneration;
    NSInteger language=self.languageControl.selectedSegment;
    BOOL dialogueMode=[self effectiveModeSegment]==ContentModeDialogue;
    BOOL captureCard=[self captureCardInputEnabled];
    NSUInteger inputEpoch=self.captureCardInput.sessionEpoch;
    NSSet<NSString *> *rendered=RenderedTranslationSet(self.captionTextLabel.stringValue,self.inlineTranslationCache);
    // 「引用最新句」的语义是"重新识别当前画面"，不是绑定已显示字幕
    //（「看原句」「问 AI」走 resolveLatestStudyIdentity，仍绑定当前句，行为不变）。
    // 因此它必须和实时循环用同一个识别输入源：采集卡模式取采集卡最新帧，
    // 窗口截图模式才截窗 —— 否则采集卡模式下这个动作又会把录制条拍进去。
    CGImageRef image=captureCard?[self.captureCardInput copyLatestFrame]:[self copyFullCapturedImageForWindow:windowID];
    if(!image){
        NSString *message=captureCard?@"采集卡暂无画面，请等画面恢复后重新引用。"
                                     :@"无法截取当前画面，请检查游戏窗口后重新引用。";
        completion(@"",[NSError errorWithDomain:@"FYStudyReference" code:1 userInfo:@{NSLocalizedDescriptionKey:message}]);
        return;
    }
    dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED,0),^{
        NSError *error=nil;
        // Nominal-resolution game captures can have dialogue below Vision's
        // accurate-recognition pixel threshold. Upscale this one-off snapshot
        // before recognition; continuous translation keeps its own fast path.
        size_t width=CGImageGetWidth(image),height=CGImageGetHeight(image);
        CGFloat scale=MIN(2.0,4096.0/MAX(width,height));
        CGImageRef enlarged=NULL;
        if(scale>1){
            CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
            CGContextRef context=CGBitmapContextCreate(NULL,(size_t)(width*scale),(size_t)(height*scale),8,0,space,kCGImageAlphaPremultipliedLast);
            CGColorSpaceRelease(space);
            if(context){
                CGContextSetInterpolationQuality(context,kCGInterpolationHigh);
                CGContextDrawImage(context,CGRectMake(0,0,width*scale,height*scale),image);
                enlarged=CGBitmapContextCreateImage(context);CGContextRelease(context);
            }
        }
        NSArray<OCRTextItem *> *blocks=[self recognizeTextItemsInImage:enlarged ?: image fastOCR:NO languageSegment:language error:&error];
        if(enlarged){CGImageRelease(enlarged);}
        CGImageRelease(image);
        blocks=OCRItemsExcludingOwnOverlay(blocks,rendered);
        dispatch_async(dispatch_get_main_queue(),^{
            NSError *referenceError=error;
            if(generation!=self.translationGeneration || windowID!=[self selectedWindowID] ||
               (captureCard && inputEpoch!=self.captureCardInput.sessionEpoch)){
                NSString *message=(captureCard && inputEpoch!=self.captureCardInput.sessionEpoch)
                    ? @"识别期间采集卡输入已切换，请重新引用。"
                    : @"识别期间目标窗口已切换，请重新引用。";
                completion(@"",[NSError errorWithDomain:@"FYStudyReference" code:2 userInfo:@{NSLocalizedDescriptionKey:message}]);return;
            }
            NSString *source=@"";
            if(!error && dialogueMode){
                NSMutableArray<OCRTextItem *> *dialogue=[NSMutableArray array],*options=[NSMutableArray array];
                SplitDialogueAndOptionsFromItems(SubtitleBandItemsFromBlocks(blocks),blocks,dialogue,options);
                BOOL speakerOnly=NO;
                source=[self dialogueTextFromItems:dialogue.count?dialogue:blocks speakerLabelOnly:&speakerOnly];
                if(speakerOnly){source=@"";}
            }else if(!error){source=[[blocks valueForKey:@"text"] componentsJoinedByString:@"\n"];}
            if(!referenceError && NormalizeForComparison(source).length<2){
                referenceError=[NSError errorWithDomain:@"FYStudyReference" code:3 userInfo:@{NSLocalizedDescriptionKey:@"当前画面没有识别到对白，请等文字显示完整后重新引用。"}];
            }
            completion(referenceError?@"":source,referenceError);
        });
    });
}
- (void)askQuickSentence:(id)sender {
    ++self.chatContextGeneration;
    self.chatResolvingSource=NO;
    // 进入 AI 前保存语法卡滚动位置，返回时恢复。
    [self captureQuickSentenceScrollPosition];
    NSString *source=self.quickSentenceSource ?: @"";
    NSString *translation=self.quickSentenceTranslation ?: @"";
    // 同一快照往返只切换显示：不重新引用、不取消正在生成的回答。
    BOOL sameSource=[source isEqualToString:self.studyChatSession.source ?: @""] &&
                    [translation isEqualToString:self.studyChatSession.translation ?: @""];
    if(!sameSource){[self.studyChatSession referenceSource:source translation:translation];}
    [self showStudyChatOverlay:sender];
}
- (void)refreshStudyChatViews {
    for(FYStudyChatView *view in @[self.mainStudyChatView ?: (id)NSNull.null,self.overlayStudyChatView ?: (id)NSNull.null]){
        if(![view isKindOfClass:FYStudyChatView.class]){continue;}
        [view setContextText:self.studyChatSession.source label:self.chatResolvingSource?@"正在识别当前画面的对白…":@"当前讨论句 · 点击引用最新句可更新"];
        [view setMessages:self.studyChatSession.messages];[view setSending:self.studyChatSession.sending || self.chatResolvingSource];
    }
}
- (void)sendStudyChat:(NSString *)text {
    [self ensureStudyChatSession];
    if(self.chatResolvingSource || self.studyChatSession.sending){return;}
    FYLearningAnalyzer *analyzer=self.studyChatSession.analyzer;
    analyzer.baseURL=self.baseURLField.stringValue ?: @"";analyzer.apiKey=self.apiKeyField.stringValue ?: @"";
    NSString *model=Trim(self.learningModelField.stringValue);analyzer.model=model.length?model:self.modelField.stringValue;
    if(self.studyChatSession.source.length){[self.studyChatSession send:text];return;}
    self.chatResolvingSource=YES;[self refreshStudyChatViews];
    NSInteger generation=self.chatContextGeneration;
    [self resolveLatestStudySentence:^(NSString *source,NSString *translation){
        if(generation!=self.chatContextGeneration){
            [self refreshStudyChatViews];
            [self.mainStudyChatView restoreDraftText:text];[self.overlayStudyChatView restoreDraftText:text];return;
        }
        self.chatResolvingSource=NO;
        [self.studyChatSession referenceSource:source translation:translation];
        [self.studyChatSession send:text];[self refreshStudyChatViews];
    }];
}
- (void)toggleMainStudyChat:(id)sender {
    // 单一显隐状态：隐藏侧栏不销毁会话，聊天记录和草稿保持原样。
    if (NSWidth(self.mainWindow.contentView.bounds) < 960) { return; }
    self.mainChatWantsVisible = self.mainStudyChatView.hidden;
    [self updateMainChatForWindowWidth];
    [self.mainWindow.contentView layoutSubtreeIfNeeded];
}
- (void)updateMainChatForWindowWidth {
    if (!self.mainWindow || !self.mainStudyChatView || !self.workspaceWidth) { return; }
    BOOL roomy = NSWidth(self.mainWindow.contentView.bounds) >= 960;
    BOOL showChat = roomy && self.mainChatWantsVisible;
    if (self.mainStudyChatView.hidden != !showChat) {
        self.mainStudyChatView.hidden = !showChat;
    }
    self.mainChatWidth.active = showChat;
    self.workspaceWidth.constant = showChat ? -510 : -190;
    [self updateMainChatToggle];
}
// 按钮标题始终跟随同一份状态；侧栏内已无第二个入口。
- (void)updateMainChatToggle {
    if (!self.mainChatToggle) { return; }
    self.mainChatToggle.title = self.mainStudyChatView.hidden ? @"展开 AI 伙伴" : @"收起 AI 伙伴";
    BOOL roomy = NSWidth(self.mainWindow.contentView.bounds) >= 960;
    self.mainChatToggle.enabled = roomy;
    self.mainChatToggle.toolTip = roomy ? nil : @"放大窗口后可展开 AI 伙伴";
}
- (void)configureStudyOverlay:(NSPanel *)panel {
    panel.hidesOnDeactivate=NO;panel.releasedWhenClosed=NO;panel.level=NSFloatingWindowLevel;
    panel.collectionBehavior=NSWindowCollectionBehaviorCanJoinAllSpaces|NSWindowCollectionBehaviorFullScreenAuxiliary;
    panel.backgroundColor=self.uiSurface;panel.movableByWindowBackground=YES;
}
- (void)showStudyChatOverlay:(id)sender {
    if(![self translationTargetIsForeground]){return;}
    [self ensureStudyChatSession];if(!self.studyChatSession.source.length){[self referenceLatestStudySentence:nil];}
    if(!self.studyChatPanel){
        self.studyChatPanel=[[FYStudyOverlayPanel alloc] initWithContentRect:NSMakeRect(0,0,340,660) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        [self configureStudyOverlay:self.studyChatPanel];self.overlayStudyChatView=[self makeStudyChatViewForOverlay:YES];
        NSView *host=[[NSView alloc] initWithFrame:NSMakeRect(0,0,340,660)];
        host.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
        [host addSubview:self.overlayStudyChatView];
        [NSLayoutConstraint activateConstraints:@[
            [self.overlayStudyChatView.leadingAnchor constraintEqualToAnchor:host.leadingAnchor],
            [self.overlayStudyChatView.trailingAnchor constraintEqualToAnchor:host.trailingAnchor],
            [self.overlayStudyChatView.topAnchor constraintEqualToAnchor:host.topAnchor],
            [self.overlayStudyChatView.bottomAnchor constraintEqualToAnchor:host.bottomAnchor]
        ]];
        self.studyChatPanel.contentView=host;
        self.studyChatPanel.minSize=NSMakeSize(340,500);
        self.studyChatPanel.maxSize=NSMakeSize(4096,4096);
        NSScreen *screen=self.captionPanel.screen ?: NSScreen.mainScreen;NSRect frame=screen.visibleFrame;
        [self.studyChatPanel setFrame:NSMakeRect(NSMaxX(frame)-360,NSMinY(frame)+24,340,MIN(720,NSHeight(frame)-48)) display:YES];
        __weak typeof(self) weakSelf=self;self.studyChatPanel.onEscape=^{[weakSelf closeStudyOverlay:nil];};
    }
    [self updateInlineReturnButtonVisibility];
    self.studyChatOverlayRequested=YES;self.quickSentenceRequested=NO;self.quickSentenceGeneration++;[self cancelQuickSentenceAnalysis];[self.quickSentencePanel orderOut:nil];
    [self refreshStudyChatViews];[self.studyChatPanel orderFrontRegardless];[self.studyChatPanel makeKeyWindow];[self.overlayStudyChatView focusInput];
}
- (void)closeStudyOverlay:(id)sender {
    self.studyChatOverlayRequested=NO;self.quickSentenceRequested=NO;self.quickSentenceGeneration++;[self cancelQuickSentenceAnalysis];
    [self.studyChatPanel orderOut:nil];[self.quickSentencePanel orderOut:nil];
    // 关闭/Esc 回到游戏，清除「返回语法」关系，避免残留指向旧块的返回入口。
    self.inlineReturnSnapshot=nil;[self updateInlineReturnButtonVisibility];
    [self refreshOverlayVisibility:nil];
}
// Dedicated request ownership keeps quick reading independent of main analysis and AI chat.
- (void)cancelQuickSentenceAnalysis {
    self.quickAnalysisGeneration++;
    self.quickSentenceAnalyzing=NO;
    [self.quickSentenceAnalyzer cancelAll];
}
- (void)analyzeQuickSentence:(id)sender {
    if(!self.quickSentenceRequested || !self.quickSentenceSource.length || self.quickSentenceAnalyzing){return;}
    [self cancelQuickSentenceAnalysis];
    self.quickSentenceAnalysis=nil;self.quickSentenceAnalysisError=nil;self.quickSelectedGrammarIndex=0;
    self.quickSentenceAnalysisSource=self.quickSentenceSource;
    self.quickSentenceAnalysisTranslation=self.quickSentenceTranslation ?: @"";
    if(!self.quickSentenceAnalyzer){self.quickSentenceAnalyzer=[FYLearningAnalyzer new];}
    FYLearningAnalyzer *analyzer=self.quickSentenceAnalyzer;
    analyzer.baseURL=self.baseURLField.stringValue ?: @"";analyzer.apiKey=self.apiKeyField.stringValue ?: @"";
    NSString *model=Trim(self.learningModelField.stringValue);
    analyzer.model=model.length?model:self.modelField.stringValue;analyzer.catalog=self.grammarCatalog;
    NSString *source=self.quickSentenceSource;NSString *translation=self.quickSentenceTranslation;
    NSInteger generation=self.quickAnalysisGeneration;
    self.quickSentenceAnalyzing=YES;[self renderQuickSentence];
    [analyzer analyzeSentence:source translation:translation completion:^(FYAnalysisResult *result,NSError *error){
        if(generation!=self.quickAnalysisGeneration || !self.quickSentenceRequested ||
           ![source isEqualToString:self.quickSentenceSource]){return;}
        self.quickSentenceAnalyzing=NO;
        self.quickSentenceAnalysis=error?nil:result;
        self.quickSentenceAnalysisError=error.localizedDescription;
        [self renderQuickSentence];
    }];
}
- (void)showQuickSentence:(id)sender {
    if(![self translationTargetIsForeground]){return;}
    // 对白查句走旧语义（标题/操作），清除贴译块标记。
    self.quickSentenceIsInlineBlock=NO;
    self.quickSentenceRequested=YES;NSInteger generation=++self.quickSentenceGeneration;
    [self resolveLatestStudyIdentity:^(FYRequestIdentity *identity){
        NSString *source=identity.sourceText ?: @"";NSString *translation=identity.translation ?: @"";
        if(!self.quickSentenceRequested || generation!=self.quickSentenceGeneration){return;}
        BOOL same=[source isEqualToString:self.quickSentenceAnalysisSource] &&
            [(translation ?: @"") isEqualToString:self.quickSentenceAnalysisTranslation];
        if(!same){[self cancelQuickSentenceAnalysis];self.quickSentenceAnalysis=nil;self.quickSentenceAnalysisError=nil;self.quickSelectedGrammarIndex=0;}
        self.quickSentenceSource=source;self.quickSentenceTranslation=translation;
        self.quickSentenceID=identity.sentenceID;self.quickSentenceVersion=identity.version;
        if(!self.quickSentenceAnalysis && !self.quickSentenceAnalyzing && [self analysisMatchesCurrentSentence] &&
           [source isEqualToString:self.learningCoordinator.currentSourceText] &&
           [(translation ?: @"") isEqualToString:(self.learningCoordinator.currentTranslation ?: @"")]){
            self.quickSentenceAnalysis=self.currentAnalysis;
            self.quickSentenceAnalysisSource=source;self.quickSentenceAnalysisTranslation=translation ?: @"";
        }
        self.studyChatOverlayRequested=NO;[self.studyChatPanel orderOut:nil];
        BOOL firstPresentation=self.quickSentencePanel==nil;
        [self renderQuickSentence];[self refreshSavedSentences];if(firstPresentation){[self.quickSentencePanel center];}
        if(!self.selectingCaptureRegion && [self translationTargetIsForeground]){[self.quickSentencePanel makeKeyWindow];}
        if(!self.quickSentenceAnalysis && !self.quickSentenceAnalyzing){[self analyzeQuickSentence:nil];}
    }];
}
- (NSView *)structureViewForAnalysis:(FYAnalysisResult *)analysis source:(NSString *)source quick:(BOOL)quick {
    if(analysis.structureParts.count<2){return nil;}
    NSUInteger previousEnd=0;
    for(NSDictionary *part in analysis.structureParts){
        NSUInteger location=[part[@"location"] unsignedIntegerValue],length=[part[@"length"] unsignedIntegerValue];
        if(location<previousEnd || location>source.length || length>source.length-location || ![[source substringWithRange:NSMakeRange(location,length)] isEqualToString:part[@"text"]]){return nil;}
        previousEnd=location+length;
    }
    NSStackView *group=[self verticalStack];group.spacing=10;
    [group addArrangedSubview:[self quickReadingLabel:analysis.structureTitle.length?analysis.structureTitle:@"整句结构" size:15 weight:NSFontWeightSemibold color:self.uiInk]];
    NSStackView *flow=[NSStackView new];flow.orientation=NSUserInterfaceLayoutOrientationHorizontal;flow.spacing=8;flow.alignment=NSLayoutAttributeCenterY;
    NSUInteger index=0;NSMutableArray *structureButtons=[NSMutableArray new];
    for(NSDictionary *part in analysis.structureParts){
        if(index++){NSTextField *arrow=[self mutedLabel:@"→"];arrow.font=FYUIFont(15, NSFontWeightRegular);[flow addArrangedSubview:arrow];}
        // 紧凑胶囊节点：不固定 180×90，按内容自适应并允许换行。
        NSButton *node=[NSButton buttonWithTitle:@"" target:self action:quick?@selector(selectQuickStructure:):@selector(selectMainStructure:)];
        node.translatesAutoresizingMaskIntoConstraints=NO;node.bordered=NO;node.wantsLayer=YES;
        node.layer.cornerRadius=14;node.layer.borderWidth=1;node.layer.borderColor=self.uiBorder.CGColor;
        node.layer.backgroundColor=FYAdventureColor(@"paper").CGColor;node.cell.wraps=YES;node.cell.scrollable=NO;
        NSMutableParagraphStyle *nodeParagraph=[NSMutableParagraphStyle new];
        nodeParagraph.alignment=NSTextAlignmentCenter;nodeParagraph.lineBreakMode=NSLineBreakByCharWrapping;
        node.attributedTitle=[[NSAttributedString alloc] initWithString:part[@"text"] ?: @"" attributes:@{NSFontAttributeName:FYJapaneseFont(13),NSForegroundColorAttributeName:self.uiInk,NSParagraphStyleAttributeName:nodeParagraph}];
        node.toolTip=[NSString stringWithFormat:@"%@：%@",part[@"role"],part[@"meaning"]];
        node.tag=-1;NSRange range=NSMakeRange([part[@"location"] unsignedIntegerValue],[part[@"length"] unsignedIntegerValue]);
        for(NSUInteger grammarIndex=0;grammarIndex<analysis.grammar.count;grammarIndex++){if(NSIntersectionRange(range,analysis.grammar[grammarIndex].matchedRange).length){node.tag=grammarIndex;break;}}
        BOOL selected=node.tag>=0 && node.tag==(quick?self.quickSelectedGrammarIndex:self.selectedGrammarIndex);
        node.layer.backgroundColor=(selected?self.uiSelected:FYAdventureColor(@"paper")).CGColor;
        [structureButtons addObject:node];
        [node.widthAnchor constraintGreaterThanOrEqualToConstant:52].active=YES;
        [node.widthAnchor constraintLessThanOrEqualToConstant:220].active=YES;
        [node.heightAnchor constraintGreaterThanOrEqualToConstant:30].active=YES;
        // 角色标签放在节点下方。
        NSTextField *role=[self mutedLabel:part[@"role"] ?: @""];
        role.alignment=NSTextAlignmentCenter;role.font=FYUIFont(10, NSFontWeightRegular);
        role.maximumNumberOfLines=1;role.lineBreakMode=NSLineBreakByTruncatingTail;
        NSStackView *wrapper=[self verticalStack];wrapper.spacing=3;wrapper.alignment=NSLayoutAttributeCenterX;
        [wrapper addArrangedSubview:node];
        [wrapper addArrangedSubview:role];
        [node.widthAnchor constraintEqualToAnchor:wrapper.widthAnchor].active=YES;
        [wrapper.widthAnchor constraintLessThanOrEqualToConstant:240].active=YES;
        [flow addArrangedSubview:wrapper];
    }
    if(quick){self.quickStructureButtons=structureButtons;}else{self.mainStructureButtons=structureButtons;}
    NSScrollView *scroll=[NSScrollView new];scroll.drawsBackground=NO;scroll.hasHorizontalScroller=YES;scroll.scrollerStyle=NSScrollerStyleOverlay;
    scroll.documentView=flow;
    if(quick){self.quickStructureScrollView=scroll;}else{self.mainStructureScrollView=scroll;}
    NSSize size=flow.fittingSize;
    flow.frame=NSMakeRect(0,0,MAX(1,size.width),MAX(46,size.height));
    [scroll.heightAnchor constraintEqualToConstant:MIN(104,MAX(50,size.height+8))].active=YES;
    [group addArrangedSubview:scroll];
    [group addArrangedSubview:[self mutedLabel:(analysis.structureParts.count>3?@"AI 结构讲解 · 点击片段查看语法 · 可左右滚动":@"AI 结构讲解 · 点击片段查看对应语法")]];
    return group;
}
- (void)selectMainStructure:(NSButton *)sender {
    if(sender.tag>=0){[self selectGrammarItem:sender];}
    else{self.grammarStatusLabel.stringValue=@"该片段的含义见结构图，未对应独立的语法条目。";}
}
- (void)selectQuickStructure:(NSButton *)sender {
    if(sender.tag>=0){[self selectQuickGrammar:self.quickGrammarChoices[sender.tag]];}
    else{self.quickGrammarBookmarkStatus.stringValue=@"该片段的含义见结构图，未对应独立的语法条目。";}
}
- (BOOL)quickSentenceIsBookmarked {
    for(FYRequestIdentity *identity in self.savedSentences){if([identity.sentenceID isEqualToString:self.quickSentenceID] && identity.version==self.quickSentenceVersion){return YES;}}return NO;
}
- (void)refreshSavedSentences {
    [self.learningStore fetchSentenceBookmarks:^(NSArray<FYRequestIdentity *> *identities,NSError *error){
        if(error){return;}
        self.savedSentences=identities;[self updateLearningCollectionSummary];[self clearArrangedSubviews:self.savedSentenceStack];
        if(!identities.count){[self.savedSentenceStack addArrangedSubview:[self mutedLabel:@"在查句弹窗中收藏想复习的句子。"]];}
        for(NSUInteger index=0;index<identities.count;index++){
            FYRequestIdentity *identity=identities[index];NSStackView *card=[self verticalStack];
            [card addArrangedSubview:[self label:identity.sourceText font:FYUIFont(14, NSFontWeightRegular) color:self.uiInk]];
            [card addArrangedSubview:[self mutedLabel:identity.translation ?: @""]];NSStackView *row=[self horizontalStack];
            for(NSString *title in @[@"查看句子结构",@"取消收藏"]){NSButton *button=[self workspaceButton:title action:[title isEqualToString:@"取消收藏"]?@selector(removeSavedSentence:):@selector(openSavedSentence:) primary:NO];button.tag=index;button.identifier=[NSString stringWithFormat:@"%@:%ld",identity.sentenceID,(long)identity.version];[row addArrangedSubview:button];}
            [card addArrangedSubview:row];[self.savedSentenceStack addArrangedSubview:[self cardWithStack:card]];
        }
        self.quickSentenceBookmarkButton.title=[self quickSentenceIsBookmarked]?@"已收藏 · 取消":@"收藏这一句";
        self.quickSentenceBookmarkButton.enabled=!self.sentenceBookmarkPending && self.quickSentenceID.length>0;
    }];
}
- (FYRequestIdentity *)savedSentenceForButton:(NSButton *)sender {
    for(FYRequestIdentity *identity in self.savedSentences){if([sender.identifier isEqualToString:[NSString stringWithFormat:@"%@:%ld",identity.sentenceID,(long)identity.version]]){return identity;}}return nil;
}
- (void)openSavedSentence:(NSButton *)sender {
    FYRequestIdentity *identity=[self savedSentenceForButton:sender];if(!identity){return;}
    [self.learningCoordinator selectSentenceID:identity.sentenceID version:identity.version sourceText:identity.sourceText translation:identity.translation];
    [self refreshLearningSource];[self refreshLearningStatus];[self selectPageAtIndex:0];[self analyzeCurrentSentence:nil];
}
- (void)removeSavedSentence:(NSButton *)sender {
    FYRequestIdentity *identity=[self savedSentenceForButton:sender];if(!identity || self.sentenceBookmarkPending){return;}
    self.sentenceBookmarkPending=YES;sender.enabled=NO;
    [self.learningStore toggleSentenceBookmark:identity completion:^(BOOL saved,NSError *error){self.sentenceBookmarkPending=NO;if(error){self.vocabularyStatusLabel.stringValue=error.localizedDescription;}[self refreshSavedSentences];}];
}
- (void)bookmarkQuickSentence:(id)sender {
    if(self.sentenceBookmarkPending || !self.quickSentenceID.length){return;}
    FYRequestIdentity *identity=[FYRequestIdentity identityWithSentenceID:self.quickSentenceID version:self.quickSentenceVersion requestID:NSUUID.UUID.UUIDString sourceText:self.quickSentenceSource translation:self.quickSentenceTranslation];
    self.sentenceBookmarkPending=YES;self.quickSentenceBookmarkButton.enabled=NO;
    [self.learningStore toggleSentenceBookmark:identity completion:^(BOOL saved,NSError *error){
        self.sentenceBookmarkPending=NO;if(error){self.quickGrammarBookmarkStatus.stringValue=[@"句子收藏失败：" stringByAppendingString:error.localizedDescription];}
        [self refreshSavedSentences];
    }];
}
- (FYGrammarBookmark *)quickGrammarBookmark {
    if(self.quickSelectedGrammarIndex>=(NSInteger)self.quickSentenceAnalysis.grammar.count){return nil;}
    FYGrammarItem *item=self.quickSentenceAnalysis.grammar[self.quickSelectedGrammarIndex];
    for(FYGrammarBookmark *bookmark in self.grammarBookmarks){if([bookmark.sentenceID isEqualToString:self.quickSentenceID] && bookmark.version==self.quickSentenceVersion && [bookmark.name isEqualToString:item.name]){return bookmark;}}
    return nil;
}
- (void)updateQuickGrammarBookmark {
    self.quickGrammarBookmarkButton.title=[self quickGrammarBookmark]?@"已收藏 · 取消收藏":@"＋ 收藏语法";
    self.quickGrammarBookmarkButton.enabled=!self.quickGrammarBookmarkPending && self.quickSentenceID.length>0;
}
- (void)bookmarkQuickGrammar:(id)sender {
    if(self.quickGrammarBookmarkPending || !self.quickSentenceID.length || self.quickSelectedGrammarIndex>=(NSInteger)self.quickSentenceAnalysis.grammar.count){return;}
    FYGrammarItem *item=self.quickSentenceAnalysis.grammar[self.quickSelectedGrammarIndex];
    NSString *sentenceID=self.quickSentenceID;NSInteger version=self.quickSentenceVersion;
    NSString *source=self.quickSentenceSource,*translation=self.quickSentenceTranslation;
    self.quickGrammarBookmarkPending=YES;[self updateQuickGrammarBookmark];
    void (^finish)(NSError *)=^(NSError *error){
        self.quickGrammarBookmarkPending=NO;
        if([sentenceID isEqualToString:self.quickSentenceID] && version==self.quickSentenceVersion){self.quickGrammarBookmarkStatus.stringValue=error?[@"收藏失败：" stringByAppendingString:error.localizedDescription]:@"收藏已更新，可在单词学习的语法收藏中查看。";}
        [self refreshGrammarBookmarks:nil];[self updateQuickGrammarBookmark];
    };
    [self.learningStore fetchGrammarBookmarksWithCompletion:^(NSArray<FYGrammarBookmark *> *bookmarks,NSError *error){
        if(error){finish(error);return;}
        FYGrammarBookmark *existing=nil;
        for(FYGrammarBookmark *bookmark in bookmarks){if([bookmark.sentenceID isEqualToString:sentenceID] && bookmark.version==version && [bookmark.name isEqualToString:item.name]){existing=bookmark;break;}}
        if(existing){[self.learningStore deleteGrammarBookmark:existing.bookmarkID completion:finish];}
        else{FYGrammarBookmark *bookmark=[FYGrammarBookmark new];bookmark.name=item.name;bookmark.catalogID=item.catalogID;bookmark.sentenceID=sentenceID;bookmark.version=version;bookmark.sourceTextSnapshot=source;bookmark.translationSnapshot=translation;[self.learningStore addGrammarBookmark:bookmark completion:finish];}
    }];
}
- (NSView *)quickGrammarDetailForItem:(FYGrammarItem *)item {
            NSStackView *point=[self verticalStack];point.spacing=8;
            BOOL shortMeaning=item.meaning.length>0 && item.meaning.length<=16;
            NSString *heading=shortMeaning?[NSString stringWithFormat:@"%@ · %@",item.name,item.meaning]:item.name;
            [point addArrangedSubview:[self quickReadingLabel:heading size:15 weight:NSFontWeightSemibold color:self.uiAccent]];
            if(item.matchedText.length){[point addArrangedSubview:[self quickReadingLabel:[@"原句 · " stringByAppendingString:item.matchedText] size:12 weight:NSFontWeightRegular color:self.uiMuted]];}
            if(item.meaning.length && !shortMeaning){[point addArrangedSubview:[self quickReadingLabel:item.meaning size:13 weight:NSFontWeightMedium color:self.uiInk]];}
            if(item.explanation.length){[point addArrangedSubview:[self quickReadingLabel:item.explanation size:12 weight:NSFontWeightRegular color:self.uiMuted]];}
            if(item.connection.length || item.registerNote.length){
                NSMutableArray *notes=[NSMutableArray new];
                if(item.connection.length){[notes addObject:[@"接续 · " stringByAppendingString:item.connection]];}
                if(item.registerNote.length){[notes addObject:item.registerNote];}
                [point addArrangedSubview:[self quickReadingLabel:[notes componentsJoinedByString:@"\n"] size:11 weight:NSFontWeightRegular color:self.uiMuted]];
            }
    self.quickGrammarBookmarkButton=[self workspaceButton:@"＋ 收藏语法" action:@selector(bookmarkQuickGrammar:) primary:NO];
    [point addArrangedSubview:self.quickGrammarBookmarkButton];
    self.quickGrammarBookmarkStatus=[self mutedLabel:@""];[point addArrangedSubview:self.quickGrammarBookmarkStatus];
    [self updateQuickGrammarBookmark];
    return [self quickReadingCard:point tinted:NO];
}
- (void)selectQuickGrammar:(NSButton *)sender {
    if(sender.tag<0 || sender.tag>=(NSInteger)self.quickSentenceAnalysis.grammar.count || !self.quickGrammarStack){return;}
    NSScrollView *scroll=self.quickGrammarStack.enclosingScrollView;
    NSPoint position=scroll.contentView.bounds.origin;
    self.quickSelectedGrammarIndex=sender.tag;
    for(NSButton *button in self.quickStructureButtons){button.layer.backgroundColor=(button.tag==sender.tag?self.uiSelected:FYAdventureColor(@"paper")).CGColor;}
    for(NSButton *button in self.quickGrammarChoices){button.state=button.tag==sender.tag?NSControlStateValueOn:NSControlStateValueOff;}
    self.quickSelectedGrammarButton=sender;
    [self.quickGrammarStack removeArrangedSubview:self.quickGrammarDetailCard];[self.quickGrammarDetailCard removeFromSuperview];
    self.quickGrammarDetailCard=[self quickGrammarDetailForItem:self.quickSentenceAnalysis.grammar[sender.tag]];
    [self.quickGrammarStack addArrangedSubview:self.quickGrammarDetailCard];
    [self.quickSentencePanel.contentView layoutSubtreeIfNeeded];
    [scroll.documentView layoutSubtreeIfNeeded];
    [self.quickSentencePanel makeFirstResponder:sender];
    // Preserve the reading position, clamping only if the new detail is shorter.
    position.y=MIN(position.y,MAX(0,NSHeight(scroll.documentView.frame)-NSHeight(scroll.contentView.bounds)));
    [scroll.contentView scrollToPoint:position];[scroll reflectScrolledClipView:scroll.contentView];
}
- (NSTextField *)quickReadingLabel:(NSString *)text size:(CGFloat)size weight:(NSFontWeight)weight color:(NSColor *)color {
    NSTextField *label=[NSTextField wrappingLabelWithString:text ?: @""];
    label.translatesAutoresizingMaskIntoConstraints=NO;label.maximumNumberOfLines=0;
    label.font=FYFontForText(text, size, weight);label.selectable=YES;label.textColor=color;
    NSMutableParagraphStyle *paragraph=[NSMutableParagraphStyle new];paragraph.lineSpacing=size>=18?6:4;
    label.attributedStringValue=[[NSAttributedString alloc] initWithString:text ?: @"" attributes:@{
        NSFontAttributeName:label.font,NSForegroundColorAttributeName:color,NSParagraphStyleAttributeName:paragraph}];
    [label setContentCompressionResistancePriority:249 forOrientation:NSLayoutConstraintOrientationHorizontal];
    return label;
}
- (NSView *)quickReadingCard:(NSStackView *)stack tinted:(BOOL)tinted {
    NSView *card=[self card];
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
- (void)renderQuickSentence {
    // 结构图整体重建前先记下横向偏移，构建完立刻恢复（避免跳回最左、也不用延时跳回）。
    CGFloat keptStructureOffset=[self structureScrollOffsetForQuick:YES];
    self.quickGrammarStack=nil;self.quickGrammarDetailCard=nil;self.quickGrammarChoices=@[];
    NSColor *paper=FYAdventureColor(@"paper");
    if(!self.quickSentencePanel){
        CGFloat height=MIN(640,NSHeight((self.captionPanel.screen ?: NSScreen.mainScreen).visibleFrame)-48);
        self.quickSentencePanel=[[FYStudyOverlayPanel alloc] initWithContentRect:NSMakeRect(0,0,440,height) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel|NSWindowStyleMaskResizable backing:NSBackingStoreBuffered defer:NO];
        [self configureStudyOverlay:self.quickSentencePanel];
        self.quickSentencePanel.opaque=NO;self.quickSentencePanel.backgroundColor=NSColor.clearColor;
        self.quickSentencePanel.minSize=NSMakeSize(440,MIN(500,height));self.quickSentencePanel.maxSize=NSMakeSize(4096,4096);
        __weak typeof(self) weakSelf=self;self.quickSentencePanel.onEscape=^{[weakSelf closeStudyOverlay:nil];};
    }
    // A frame-driven host keeps the window independent of long document content.
    NSView *host=[[NSView alloc] initWithFrame:NSMakeRect(0,0,NSWidth(self.quickSentencePanel.contentView.bounds),NSHeight(self.quickSentencePanel.contentView.bounds))];
    host.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;host.wantsLayer=YES;
    host.layer.backgroundColor=paper.CGColor;host.layer.cornerRadius=13;host.layer.masksToBounds=YES;
    host.layer.borderWidth=1;host.layer.borderColor=self.uiBorder.CGColor;
    NSStackView *titles=[self verticalStack];titles.spacing=4;
    BOOL inlineBlock=self.quickSentenceIsInlineBlock;
    [titles addArrangedSubview:[self quickReadingLabel:inlineBlock?@"原文 · 译文 · 这段话的语法":@"快捷查询 · 当前句" size:10 weight:NSFontWeightMedium color:self.uiAccent]];
    // 标题行只放文本标签：拖动区里不能混入容器视图。
    NSTextField *cardTitle=[self quickReadingLabel:inlineBlock?@"选中内容 · 已固定":@"读懂这一句" size:22 weight:NSFontWeightSemibold color:self.uiInk];
    // 标题始终完整一行：被压缩时也不要断成「选中内容 ·」，更不要被挤出右边距。
    cardTitle.maximumNumberOfLines=1;
    cardTitle.lineBreakMode=NSLineBreakByTruncatingTail;
    [cardTitle setContentCompressionResistancePriority:751 forOrientation:NSLayoutConstraintOrientationHorizontal];
    [cardTitle setContentCompressionResistancePriority:751 forOrientation:NSLayoutConstraintOrientationVertical];
    [titles addArrangedSubview:cardTitle];
    NSButton *close=[NSButton buttonWithImage:[NSImage imageWithSystemSymbolName:@"xmark" accessibilityDescription:@"收起句子查询"] target:self action:@selector(closeStudyOverlay:)];
    close.bordered=NO;close.contentTintColor=self.uiMuted;close.toolTip=@"收起 · Esc";
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
    NSView *topLine=[self separator];topLine.translatesAutoresizingMaskIntoConstraints=NO;[host addSubview:topLine];
    NSStackView *content=[self verticalStack];content.spacing=18;
    NSStackView *source=[self verticalStack];source.spacing=8;
    [source addArrangedSubview:[self quickReadingLabel:inlineBlock?@"原文":@"日文原句" size:10 weight:NSFontWeightRegular color:self.uiMuted]];
    [source addArrangedSubview:[self quickReadingLabel:self.quickSentenceSource.length?self.quickSentenceSource:(inlineBlock?@"尚未选中内容":@"尚未识别到对白") size:19 weight:NSFontWeightRegular color:self.uiInk]];
    [content addArrangedSubview:source];
    NSStackView *translation=[self verticalStack];translation.spacing=5;
    [translation addArrangedSubview:[self quickReadingLabel:self.quickSentenceTranslation.length?self.quickSentenceTranslation:@"暂无译文" size:14 weight:NSFontWeightRegular color:self.uiInk]];
    [content addArrangedSubview:[self quickReadingCard:translation tinted:YES]];
    FYAnalysisResult *analysis=[self.quickSentenceSource isEqualToString:self.quickSentenceAnalysisSource]?self.quickSentenceAnalysis:nil;
    NSStackView *grammar=[self verticalStack];grammar.spacing=12;
    [grammar addArrangedSubview:[self quickReadingLabel:@"这一句的语法" size:15 weight:NSFontWeightSemibold color:self.uiInk]];
    if(self.quickSentenceAnalyzing){
        NSStackView *loading=[self verticalStack];loading.spacing=6;
        [loading addArrangedSubview:[self quickReadingLabel:@"正在分析这句对白…" size:14 weight:NSFontWeightMedium color:self.uiAccent]];
        [loading addArrangedSubview:[self quickReadingLabel:@"先读原句和译文，解析完成后会显示在这里。" size:12 weight:NSFontWeightRegular color:self.uiMuted]];
        [grammar addArrangedSubview:[self quickReadingCard:loading tinted:YES]];
    }else if(self.quickSentenceAnalysisError.length){
        NSStackView *failure=[self verticalStack];failure.spacing=10;
        [failure addArrangedSubview:[self quickReadingLabel:[@"分析失败：" stringByAppendingString:self.quickSentenceAnalysisError] size:12 weight:NSFontWeightRegular color:NSColor.systemRedColor]];
        [failure addArrangedSubview:[self workspaceButton:@"重试分析" action:@selector(analyzeQuickSentence:) primary:NO]];
        [grammar addArrangedSubview:[self quickReadingCard:failure tinted:NO]];
    }else if(analysis){
        NSView *structure=[self structureViewForAnalysis:analysis source:self.quickSentenceSource quick:YES];
        if(structure){[grammar addArrangedSubview:structure];}
        else{[grammar addArrangedSubview:[self mutedLabel:@"本次解析未返回整句结构，可在主界面重新分析。"]];}
        if(analysis.sentenceNote.length){[grammar addArrangedSubview:[self quickReadingLabel:analysis.sentenceNote size:13 weight:NSFontWeightRegular color:self.uiMuted]];}
        if(analysis.grammar.count){
            if(self.quickSelectedGrammarIndex<0 || self.quickSelectedGrammarIndex>=(NSInteger)analysis.grammar.count){self.quickSelectedGrammarIndex=0;}
            [grammar addArrangedSubview:[self quickReadingLabel:@"选择一个语法，查看它在这句里的用法" size:11 weight:NSFontWeightRegular color:self.uiMuted]];
            NSMutableArray<NSButton *> *buttons=[NSMutableArray new];
            NSMutableArray<NSArray<NSView *> *> *rows=[NSMutableArray new];
            NSMutableArray<NSView *> *row=[NSMutableArray new];
            for(NSUInteger index=0;index<analysis.grammar.count;index++){
                FYGrammarItem *item=analysis.grammar[index];
                NSButton *button=[self workspaceButton:item.name action:@selector(selectQuickGrammar:) primary:NO];
                button.tag=index;button.state=index==self.quickSelectedGrammarIndex?NSControlStateValueOn:NSControlStateValueOff;
                button.toolTip=item.matchedText;button.accessibilityLabel=[NSString stringWithFormat:@"查看语法：%@",item.name];
                if(index==self.quickSelectedGrammarIndex){self.quickSelectedGrammarButton=button;}
                [buttons addObject:button];[row addObject:button];
                if(row.count==2){[rows addObject:row];row=[NSMutableArray new];}
            }
            if(row.count){[row addObject:[NSView new]];[rows addObject:row];}
            NSGridView *choices=[NSGridView gridViewWithViews:rows];choices.columnSpacing=8;choices.rowSpacing=8;
            choices.xPlacement=NSGridCellPlacementFill;choices.yPlacement=NSGridCellPlacementFill;
            for(NSArray<NSView *> *pair in rows){for(NSView *choice in pair){[choice.widthAnchor constraintEqualToAnchor:choices.widthAnchor multiplier:0.5 constant:-4].active=YES;}}
            self.quickGrammarChoices=buttons;
            [grammar addArrangedSubview:choices];
            FYGrammarItem *item=analysis.grammar[self.quickSelectedGrammarIndex];
            self.quickGrammarStack=grammar;
            self.quickGrammarDetailCard=[self quickGrammarDetailForItem:item];
            [grammar addArrangedSubview:self.quickGrammarDetailCard];
        }
        if(!analysis.grammar.count){[grammar addArrangedSubview:[self quickReadingLabel:@"这句没有识别到可核实的语法条目，可以继续向 AI 提问。" size:12 weight:NSFontWeightRegular color:self.uiMuted]];}
    }else{[grammar addArrangedSubview:[self quickReadingLabel:@"识别到对白后，打开这里会自动分析。" size:12 weight:NSFontWeightRegular color:self.uiMuted]];}
    [content addArrangedSubview:grammar];
    NSScrollView *scroll=[NSScrollView new];scroll.translatesAutoresizingMaskIntoConstraints=NO;
    scroll.hasVerticalScroller=YES;scroll.scrollerStyle=NSScrollerStyleOverlay;scroll.drawsBackground=NO;
    NSView *document=[FlippedDocumentView new];document.translatesAutoresizingMaskIntoConstraints=NO;
    scroll.documentView=document;content.translatesAutoresizingMaskIntoConstraints=NO;[document addSubview:content];[host addSubview:scroll];
    NSStackView *footer=[self verticalStack];footer.translatesAutoresizingMaskIntoConstraints=NO;footer.spacing=10;
    NSStackView *actions=[self horizontalStack];actions.spacing=8;
    [actions addArrangedSubview:[self workspaceButton:inlineBlock?@"问 AI":@"这句我还想问 AI" action:@selector(askQuickSentence:) primary:YES]];
    self.quickSentenceBookmarkButton=[self workspaceButton:[self quickSentenceIsBookmarked]?@"已收藏 · 取消":(inlineBlock?@"收藏这段":@"收藏这一句") action:@selector(bookmarkQuickSentence:) primary:NO];
    self.quickSentenceBookmarkButton.enabled=!self.sentenceBookmarkPending && self.quickSentenceID.length>0;
    [actions addArrangedSubview:self.quickSentenceBookmarkButton];
    [actions addArrangedSubview:[self workspaceButton:@"完整学习界面 ↗" action:@selector(openStudyWorkspace:) primary:NO]];
    [footer addArrangedSubview:actions];[footer addArrangedSubview:[self quickReadingLabel:inlineBlock?@"Esc 收起回到画面 · 选中的内容保持不变":@"Esc 收起回到画面 · 本次查看的原句保持不变" size:10 weight:NSFontWeightRegular color:self.uiMuted]];
    [host addSubview:footer];NSView *bottomLine=[self separator];bottomLine.translatesAutoresizingMaskIntoConstraints=NO;[host addSubview:bottomLine];
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
    self.quickSentencePanel.contentView=host;
    [self refreshOverlayVisibility:nil];
    [self restoreStructureScrollOffset:keptStructureOffset quick:YES];
}
- (void)openStudyWorkspace:(id)sender {
    [self selectPageAtIndex:0];[self.mainWindow makeKeyAndOrderFront:nil];[NSApp activateIgnoringOtherApps:YES];
    // Carry the exact displayed version, rather than whichever sentence OCR sees now.
    NSString *sentenceID=self.quickSentenceID;NSInteger version=self.quickSentenceVersion;
    NSString *source=self.quickSentenceSource;NSString *translation=self.quickSentenceTranslation;
    FYAnalysisResult *quickResult=[source isEqualToString:self.quickSentenceAnalysisSource]?self.quickSentenceAnalysis:nil;
    [self closeStudyOverlay:nil];
    if(!sentenceID.length || !source.length){return;}
    self.analysisRequestGeneration++;
    [self.learningCoordinator selectSentenceID:sentenceID version:version sourceText:source translation:translation];
    [self clearAnalysisDisplay];[self refreshLearningSource];[self refreshLearningStatus];
    if(quickResult){
        FYAnalysisResult *result=[FYAnalysisResult new];result.schemaVersion=quickResult.schemaVersion;
        result.grammar=quickResult.grammar;result.vocabulary=quickResult.vocabulary;result.sentenceNote=quickResult.sentenceNote;result.structureParts=quickResult.structureParts;result.structureTitle=quickResult.structureTitle;
        result.sentenceID=sentenceID;result.version=version;result.status=FYAnalysisStatusSuccess;
        self.currentAnalysis=result;self.selectedGrammarIndex=self.quickSelectedGrammarIndex;[self setAnalyzeBusy:NO];[self refreshGrammarResults];
    }else{[self analyzeCurrentSentence:nil];}
}
- (void)toggleCaptionCollapsed:(id)sender {self.captionPanelShownByUser?[self hideCaptionPanel:sender]:[self showCaptionPanel:sender];}
- (void)createCaptionDock {
    self.captionDockPanel=[[FYStudyOverlayPanel alloc] initWithContentRect:NSMakeRect(0,0,260,46) styleMask:NSWindowStyleMaskBorderless|NSWindowStyleMaskNonactivatingPanel backing:NSBackingStoreBuffered defer:NO];
    [self configureStudyOverlay:self.captionDockPanel];
    NSStackView *row=[self horizontalStack];row.spacing=8;row.translatesAutoresizingMaskIntoConstraints=NO;
    [row addArrangedSubview:[self workspaceButton:@"⌃ 译芽" action:@selector(showCaptionPanel:) primary:NO]];
    [row addArrangedSubview:[self workspaceButton:@"查句" action:@selector(showQuickSentence:) primary:NO]];
    [row addArrangedSubview:[self workspaceButton:@"问 AI" action:@selector(showStudyChatOverlay:) primary:NO]];
    NSView *card=[self card];[card addSubview:row];
    [NSLayoutConstraint activateConstraints:@[[row.leadingAnchor constraintEqualToAnchor:card.leadingAnchor constant:10],[row.trailingAnchor constraintEqualToAnchor:card.trailingAnchor constant:-10],[row.topAnchor constraintEqualToAnchor:card.topAnchor constant:6],[row.bottomAnchor constraintEqualToAnchor:card.bottomAnchor constant:-6]]];
    card.translatesAutoresizingMaskIntoConstraints=YES;
    card.autoresizingMask=NSViewWidthSizable|NSViewHeightSizable;
    card.frame=NSMakeRect(0,0,260,46);
    self.captionDockPanel.contentView=card;
}
