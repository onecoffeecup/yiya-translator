// Included inside AppDelegate. Offline references remain separate from AI explanations.
- (NSURL *)referenceResourceURL:(NSString *)file {
    return [[NSBundle mainBundle] URLForResource:file.stringByDeletingPathExtension withExtension:file.pathExtension subdirectory:@"learning/reference"];
}

- (NSView *)makeIntegratedReferenceCard {
    NSStackView *content=[self verticalStack]; content.spacing=20;
    FYLearningColumnsView *header=[FYLearningColumnsView new]; header.leftFraction=0.58; header.spacing=20; header.compactWidth=750;
    NSStackView *titles=[self verticalStack]; titles.spacing=4;
    [titles addArrangedSubview:[self cardTitle:@"词语用法"]];
    [titles addArrangedSubview:[self mutedLabel:@"选中原句中的词，查看词典释义与 JLPT 参考等级"]];
    [header addArrangedSubview:titles];
    NSStackView *search=[self horizontalStack];
    self.referenceSearchField=[self textField:@"输入词语原形，例如：得意"];
    self.referenceSearchField.bezeled=NO; self.referenceSearchField.wantsLayer=YES;
    self.referenceSearchField.layer.backgroundColor=self.uiSurface.CGColor;
    self.referenceSearchField.layer.cornerRadius=7;
    self.referenceSearchField.layer.borderColor=self.uiBorder.CGColor;
    self.referenceSearchField.layer.borderWidth=1;
    self.referenceSearchField.target=self; self.referenceSearchField.action=@selector(searchReferenceWord:);
    [self.referenceSearchField.heightAnchor constraintEqualToConstant:34].active=YES;
    [self.referenceSearchField setAccessibilityLabel:@"查询词语原形"];
    [search addArrangedSubview:self.referenceSearchField];
    [search addArrangedSubview:[self workspaceButton:@"查词" action:@selector(searchReferenceWord:) primary:YES]];
    [header addArrangedSubview:search]; [content addArrangedSubview:header];
    self.referenceStack=[self verticalStack]; self.referenceStack.spacing=16;
    [self.referenceStack addArrangedSubview:[self mutedLabel:@"词典资料可离线查看。选词或输入原形后，内容会在这里展开。"]];
    [content addArrangedSubview:self.referenceStack];
    self.referenceCard=[self cardWithStack:content]; self.referenceCard.identifier=@"integrated-reference-card";
    return self.referenceCard;
}

- (NSButton *)referenceLink:(NSString *)title URL:(NSString *)url {
    NSButton *button=[self workspaceButton:title action:@selector(openReferenceLink:) primary:NO];
    button.identifier=url; return button;
}
- (void)openReferenceLink:(NSButton *)sender {
    NSURL *url=[NSURL URLWithString:sender.identifier ?: @""];
    if ([url.scheme isEqualToString:@"https"]) { [NSWorkspace.sharedWorkspace openURL:url]; }
}
- (void)revealReferenceCard {
    [self selectPageAtIndex:0];
    [self.mainWindow makeKeyAndOrderFront:nil];
    [self.mainWindow.contentView layoutSubtreeIfNeeded];
    NSScrollView *scroll=(NSScrollView *)self.pages[0];
    NSRect rect=[self.referenceCard convertRect:self.referenceCard.bounds toView:scroll.documentView];
    // Align the card's title, rather than jumping to the bottom of a long article.
    CGFloat y=MAX(0,MIN(rect.origin.y-18,NSHeight(scroll.documentView.bounds)-NSHeight(scroll.contentView.bounds)));
    [scroll.contentView scrollToPoint:NSMakePoint(0,y)]; [scroll reflectScrolledClipView:scroll.contentView];
}
- (void)searchReferenceWord:(id)sender {
    NSString *word=Trim(self.referenceSearchField.stringValue);
    if(word.length){[self lookupReferenceWord:word reading:@""];}
}
- (void)lookupReferenceWord:(NSString *)word reading:(NSString *)reading {
    if(!self.referenceStack){return;}
    self.referenceSearchField.stringValue=word;
    [self clearArrangedSubviews:self.referenceStack];
    [self.referenceStack addArrangedSubview:[self mutedLabel:[NSString stringWithFormat:@"正在查询「%@」的本机资料…",word]]];
    NSInteger generation=++self.referenceRequestGeneration;
    self.referenceRecords=@[]; self.referenceActiveWord=word;
    if(!self.referenceDictionary){self.referenceDictionary=[[FYReferenceDictionary alloc] initWithURL:[self referenceResourceURL:@"reference.sqlite"]];}
    [self.referenceDictionary lookupWord:word reading:reading completion:^(NSArray<NSDictionary *> *records,NSError *error){
        if(generation!=self.referenceRequestGeneration){return;}
        self.referenceRecords=records;
        [self clearArrangedSubviews:self.referenceStack];
        if(error || !records.count){
            [self.referenceStack addArrangedSubview:[self label:[NSString stringWithFormat:@"%@ · 暂无资料",word] font:FYUIFont(20, NSFontWeightSemibold) color:self.uiInk]];
            [self.referenceStack addArrangedSubview:[self mutedLabel:error ? error.localizedDescription : @"试试输入辞书形，或缩小选词范围。未匹配的释义与等级会留空。"]]; return;
        }
        self.referenceEntryPopup=[NSPopUpButton new]; self.referenceEntryPopup.target=self;
        self.referenceEntryPopup.action=@selector(referenceEntryChanged:);
        for(NSDictionary *record in records){
            NSArray *forms=[record[@"spellings"] count] ? record[@"spellings"] : record[@"readings"];
            [self.referenceEntryPopup addItemWithTitle:[NSString stringWithFormat:@"%@ · %@",[forms componentsJoinedByString:@"／"],[record[@"readings"] componentsJoinedByString:@"／"]]];
        }
        [self referenceEntryChanged:nil];
    }];
}
- (void)showSelectedWordReference:(id)sender {
    NSString *surface=[self selectedLearningText]; if(!surface.length){return;}
    NSString *lemma=Trim(self.lemmaField.stringValue);
    [self lookupReferenceWord:lemma.length ? lemma : surface reading:Trim(self.readingField.stringValue)];
    [self revealReferenceCard];
}
- (void)showSavedWordReference:(NSButton *)sender {
    FYVocabularyEntry *entry=[self wordForCardButton:sender];if(!entry){return;}
    NSStackView *detail=(NSStackView *)sender.superview.superview;
    FYSavedWordReferenceView *reference=(FYSavedWordReferenceView *)detail.arrangedSubviews.lastObject;
    if(![reference isKindOfClass:FYSavedWordReferenceView.class]){return;}
    BOOL opening=reference.hidden;reference.hidden=!opening;
    sender.title=opening?@"收起用法与等级参考":@"用法与等级参考";
    if(opening){
        if(!self.referenceDictionary){self.referenceDictionary=[[FYReferenceDictionary alloc] initWithURL:[self referenceResourceURL:@"reference.sqlite"]];}
        [reference loadWord:entry.lemma.length?entry.lemma:entry.surface reading:entry.reading ?: @"" dictionary:self.referenceDictionary];
    }
}
- (void)referenceEntryChanged:(id)sender {
    NSInteger index=self.referenceEntryPopup.indexOfSelectedItem;
    if(index<0 || index>=self.referenceRecords.count){return;}
    NSDictionary *record=self.referenceRecords[index];
    [self clearArrangedSubviews:self.referenceStack];
    if(self.referenceRecords.count>1){
        [self.referenceStack addArrangedSubview:[self mutedLabel:@"同形词 · 请按读音选择"]];
        [self.referenceStack addArrangedSubview:self.referenceEntryPopup];
    }
    FYLearningColumnsView *columns=[FYLearningColumnsView new]; columns.leftFraction=0.30; columns.spacing=24; columns.compactWidth=720;
    NSStackView *summary=[self verticalStack]; summary.spacing=12;
    [summary addArrangedSubview:[self label:self.referenceActiveWord font:FYUIFont(28, NSFontWeightSemibold) color:self.uiInk]];
    [summary addArrangedSubview:[self label:[record[@"readings"] componentsJoinedByString:@"／"] font:FYUIFont(16, NSFontWeightRegular) color:self.uiMuted]];
    NSString *levels=[record[@"reference_levels"] componentsJoinedByString:@"／"];
    NSStackView *badge=[self verticalStack]; badge.spacing=4;
    [badge addArrangedSubview:[self label:levels.length ? [NSString stringWithFormat:@"JLPT 参考 %@",levels] : @"等级暂无资料" font:FYUIFont(14, NSFontWeightSemibold) color:self.uiAccent]];
    [badge addArrangedSubview:[self mutedLabel:levels.length ? @"社区分级 · 非官方清单" : @"未分级不代表考试不会出现"]];
    [summary addArrangedSubview:[self workspaceSection:badge]];
    NSArray *forms=[record[@"spellings"] count] ? record[@"spellings"] : record[@"readings"];
    NSString *formText=[forms componentsJoinedByString:@"／"];
    if(![formText isEqualToString:self.referenceActiveWord]){[summary addArrangedSubview:[self mutedLabel:[NSString stringWithFormat:@"词典写法\n%@",formText]]];}
    [summary addArrangedSubview:[self mutedLabel:@"JMdict 词典原文\n英文释义 · 日文例句"]];
    [columns addArrangedSubview:summary];
    NSStackView *details=[self verticalStack]; details.spacing=16;
    self.referenceTabs=[self segmentedWithLabels:@[@"释义与用法",@"例句",@"来源"] action:@selector(referenceTabChanged:)];
    [self.referenceTabs.heightAnchor constraintEqualToConstant:32].active=YES;
    [details addArrangedSubview:self.referenceTabs];
    self.referenceSensePopup=[NSPopUpButton new]; self.referenceSensePopup.target=self; self.referenceSensePopup.action=@selector(referenceTabChanged:);
    for(NSDictionary *sense in record[@"senses"]){
        NSString *gloss=[sense[@"glosses"] firstObject] ?: @"";
        [self.referenceSensePopup addItemWithTitle:[NSString stringWithFormat:@"义项 %@ · %@",sense[@"number"],gloss]];
    }
    [self.referenceSensePopup setContentCompressionResistancePriority:250 forOrientation:NSLayoutConstraintOrientationHorizontal];
    if([record[@"senses"] count]>1){[details addArrangedSubview:self.referenceSensePopup];}
    self.referenceDetailStack=[self verticalStack]; self.referenceDetailStack.spacing=12;
    [details addArrangedSubview:self.referenceDetailStack];
    [columns addArrangedSubview:details]; [self.referenceStack addArrangedSubview:columns];
    [self referenceTabChanged:nil];
}
- (void)referenceTabChanged:(id)sender {
    NSInteger index=self.referenceEntryPopup.indexOfSelectedItem;
    if(index<0 || index>=self.referenceRecords.count){return;}
    NSDictionary *record=self.referenceRecords[index]; NSArray *senses=record[@"senses"];
    NSInteger senseIndex=self.referenceSensePopup.indexOfSelectedItem;
    if(senseIndex<0 || senseIndex>=senses.count){return;}
    NSDictionary *sense=senses[senseIndex];
    [self clearArrangedSubviews:self.referenceDetailStack];
    self.referenceMoreExamples=nil;
    NSInteger tab=self.referenceTabs.selectedSegment;
    self.referenceSensePopup.hidden=tab==2;
    if(tab==0){
        [self.referenceDetailStack addArrangedSubview:[self label:[sense[@"glosses"] componentsJoinedByString:@"; "] font:FYUIFont(18, NSFontWeightMedium) color:self.uiInk]];
        NSDictionary *tags=@{@"noun (common) (futsuumeishi)":@"名词", @"adjectival nouns or quasi-adjectives (keiyodoshi)":@"な形容词", @"nouns which may take the genitive case particle 'no'":@"可接「の」", @"adverb (fukushi)":@"副词", @"expressions (phrases, clauses, etc.)":@"惯用表达", @"Ichidan verb":@"一段动词", @"transitive verb":@"他动词", @"intransitive verb":@"自动词", @"adjective (keiyoushi)":@"い形容词", @"noun or participle which takes the aux. verb suru":@"サ变名词"};
        NSMutableArray *shortTags=[NSMutableArray array];
        for(NSString *pos in sense[@"pos"]){if(tags[pos]){[shortTags addObject:tags[pos]];}}
        if(shortTags.count){[self.referenceDetailStack addArrangedSubview:[self label:[shortTags componentsJoinedByString:@"  ·  "] font:FYUIFont(13, NSFontWeightMedium) color:self.uiAccent]];}
        if([sense[@"pos"] count]){
            self.referenceMoreExamples=[self verticalStack];
            [self.referenceMoreExamples addArrangedSubview:[self mutedLabel:[sense[@"pos"] componentsJoinedByString:@"; "]]];
            [self addReferenceDisclosure:@"词典原始词性标签" content:self.referenceMoreExamples];
        }
        NSStackView *notes=[self verticalStack]; notes.spacing=8;
        for(NSArray *field in @[@[@"使用说明",@"notes"],@[@"语体",@"register"],@[@"领域",@"fields"],@[@"方言",@"dialect"],@[@"适用写法",@"only_spellings"],@[@"适用读音",@"only_readings"]]){
            NSString *value=[sense[field[1]] componentsJoinedByString:@"; "];
            if(value.length){[notes addArrangedSubview:[self mutedLabel:[NSString stringWithFormat:@"%@\n%@",field[0],value]]];}
        }
        if(notes.arrangedSubviews.count){[self.referenceDetailStack addArrangedSubview:[self workspaceSection:notes]];}
        [self.referenceDetailStack addArrangedSubview:[self mutedLabel:@"释义按词典义项展示。选择其他义项，或切换到「例句」查看具体用法。"]];
    }else if(tab==1){
        NSArray *examples=sense[@"examples"];
        if(!examples.count){[self.referenceDetailStack addArrangedSubview:[self mutedLabel:@"这个义项暂无符合导入条件的例句。可以切换其他义项查看。"]];}
        NSInteger n=0;
        NSStackView *more=[self verticalStack]; more.spacing=12;
        for(NSDictionary *example in examples){
            NSStackView *item=[self verticalStack]; item.spacing=8;
            [item addArrangedSubview:[self label:example[@"ja"] font:FYUIFont(17, NSFontWeightMedium) color:self.uiInk]];
            [item addArrangedSubview:[self mutedLabel:[NSString stringWithFormat:@"关联词形 %@ · 作者 %@\nTatoeba #%@ · %@",example[@"matched_text"],example[@"author"],example[@"sentence_id"],example[@"license"]]]];
            [item addArrangedSubview:[self referenceLink:@"查看原始例句 ↗" URL:example[@"url"]]];
            NSView *card=[self workspaceSection:item];
            if(n++<2){[self.referenceDetailStack addArrangedSubview:card];}else{[more addArrangedSubview:card];}
        }
        if(more.arrangedSubviews.count){self.referenceMoreExamples=more; [self addReferenceDisclosure:[NSString stringWithFormat:@"更多例句（%lu）",(unsigned long)more.arrangedSubviews.count] content:more];}
        [self.referenceDetailStack addArrangedSubview:[self mutedLabel:@"例句与词典义项关联，尚未独立人工审校。"]];
    }else{
        [self.referenceDetailStack addArrangedSubview:[self cardTitle:@"资料可追溯"]];
        [self.referenceDetailStack addArrangedSubview:[self mutedLabel:@"词义与读音 · JMdict / EDRDG\nCC BY-SA 4.0\n\n日文例句 · Tatoeba\nCC BY 2.0 FR，逐条保留作者\n\n参考等级 · OpenJLPT / Jonathan Waller\nCC BY-SA 4.0，社区整理"]];
        [self.referenceDetailStack addArrangedSubview:[self referenceLink:@"词典原始条目 ↗" URL:record[@"source_url"]]];
        if([record[@"reference_levels"] count]){[self.referenceDetailStack addArrangedSubview:[self referenceLink:@"等级数据来源 ↗" URL:@"https://github.com/evanclan/OpenJLPT"]];}
        [self.referenceDetailStack addArrangedSubview:[self workspaceButton:@"在 Finder 查看完整许可文件 ↗" action:@selector(showReferenceLicenses:) primary:NO]];
        [self.referenceDetailStack addArrangedSubview:[self mutedLabel:@"资料用于词义与用法参考；没有加入历年真题或未经核对的考试讲解。"]];
    }
}
- (void)addReferenceDisclosure:(NSString *)title content:(NSView *)content {
    NSButton *button=[self workspaceButton:title action:@selector(toggleReferenceExtra:) primary:NO];
    [button setButtonType:NSButtonTypePushOnPushOff]; content.hidden=YES;
    [self.referenceDetailStack addArrangedSubview:button];
    [self.referenceDetailStack addArrangedSubview:content];
}
- (void)toggleReferenceExtra:(NSButton *)sender {
    self.referenceMoreExamples.hidden=sender.state!=NSControlStateValueOn;
}
- (void)showReferenceLicenses:(id)sender {
    NSURL *manifest=[self referenceResourceURL:@"reference-manifest.json"];
    NSURL *directory=[[manifest URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"licenses" isDirectory:YES];
    BOOL isDirectory=NO;
    if(directory && [NSFileManager.defaultManager fileExistsAtPath:directory.path isDirectory:&isDirectory] && isDirectory &&
       [self openReferenceLicensesDirectory:directory]){return;}
    NSAlert *alert=[NSAlert new];
    alert.messageText=@"无法打开完整许可文件";
    alert.informativeText=@"请在「资料来源与许可」中阅读说明。若应用缺少随包的许可文件，请重新安装完整应用。";
    if(self.mainWindow.isVisible){[alert beginSheetModalForWindow:self.mainWindow completionHandler:nil];}
    else{[alert runModal];}
}
- (BOOL)openReferenceLicensesDirectory:(NSURL *)directory {
    return [NSWorkspace.sharedWorkspace openURL:directory];
}
