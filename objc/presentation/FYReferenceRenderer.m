#import "FYReferenceRenderer.h"
#import "../learning/FYLearningViews.h"
#import "../learning/FYSavedWordReferenceView.h"
#import "../learning/FYReferenceDictionary.h"
#import <QuartzCore/QuartzCore.h>

@implementation FYReferenceRenderer
+ (NSView *)makeReferenceCardWithReceiver:(id<FYReferenceRenderSource>)receiver {
    NSStackView *content=[receiver verticalStack]; content.spacing=20;
    FYLearningColumnsView *header=[FYLearningColumnsView new]; header.leftFraction=0.58; header.spacing=20; header.compactWidth=750;
    NSStackView *titles=[receiver verticalStack]; titles.spacing=4;
    [titles addArrangedSubview:[receiver cardTitle:@"词语用法"]];
    [titles addArrangedSubview:[receiver mutedLabel:@"选中原句中的词，查看词典释义与 JLPT 参考等级"]];
    [header addArrangedSubview:titles];
    NSStackView *search=[receiver horizontalStack];
    receiver.referenceSearchField=[receiver textField:@"输入词语原形，例如：得意"];
    receiver.referenceSearchField.bezeled=NO; receiver.referenceSearchField.wantsLayer=YES;
    receiver.referenceSearchField.layer.backgroundColor=receiver.uiSurface.CGColor;
    receiver.referenceSearchField.layer.cornerRadius=7;
    receiver.referenceSearchField.layer.borderColor=receiver.uiBorder.CGColor;
    receiver.referenceSearchField.layer.borderWidth=1;
    receiver.referenceSearchField.target=[receiver referenceActionTarget]; receiver.referenceSearchField.action=@selector(searchReferenceWord:);
    [receiver.referenceSearchField.heightAnchor constraintEqualToConstant:34].active=YES;
    [receiver.referenceSearchField setAccessibilityLabel:@"查询词语原形"];
    [search addArrangedSubview:receiver.referenceSearchField];
    [search addArrangedSubview:[receiver workspaceButton:@"查词" action:@selector(searchReferenceWord:) primary:YES]];
    [header addArrangedSubview:search]; [content addArrangedSubview:header];
    receiver.referenceStack=[receiver verticalStack]; receiver.referenceStack.spacing=16;
    [receiver.referenceStack addArrangedSubview:[receiver mutedLabel:@"词典资料可离线查看。选词或输入原形后，内容会在这里展开。"]];
    [content addArrangedSubview:receiver.referenceStack];
    receiver.referenceCard=[receiver cardWithStack:content]; receiver.referenceCard.identifier=@"integrated-reference-card";
    return receiver.referenceCard;
}

+ (NSButton *)referenceLink:(NSString *)title URL:(NSString *)url receiver:(id<FYReferenceRenderSource>)receiver {
    NSButton *button=[receiver workspaceButton:title action:@selector(openReferenceLink:) primary:NO];
    button.identifier=url; return button;
}

+ (void)revealReferenceCardWithReceiver:(id<FYReferenceRenderSource>)receiver {
    [receiver selectPageAtIndex:0];
    [receiver.mainWindow makeKeyAndOrderFront:nil];
    [receiver.mainWindow.contentView layoutSubtreeIfNeeded];
    NSScrollView *scroll=(NSScrollView *)receiver.pages[0];
    NSRect rect=[receiver.referenceCard convertRect:receiver.referenceCard.bounds toView:scroll.documentView];
    // Align the card's title, rather than jumping to the bottom of a long article.
    CGFloat y=MAX(0,MIN(rect.origin.y-18,NSHeight(scroll.documentView.bounds)-NSHeight(scroll.contentView.bounds)));
    [scroll.contentView scrollToPoint:NSMakePoint(0,y)]; [scroll reflectScrolledClipView:scroll.contentView];
}

+ (void)showSavedWordReference:(NSButton *)sender receiver:(id<FYReferenceRenderSource>)receiver {
    FYVocabularyEntry *entry=[receiver wordForCardButton:sender];if(!entry){return;}
    NSStackView *detail=(NSStackView *)sender.superview.superview;
    FYSavedWordReferenceView *reference=(FYSavedWordReferenceView *)detail.arrangedSubviews.lastObject;
    if(![reference isKindOfClass:FYSavedWordReferenceView.class]){return;}
    BOOL opening=reference.hidden;reference.hidden=!opening;
    sender.title=opening?@"收起用法与等级参考":@"用法与等级参考";
    if(opening){
        if(!receiver.referenceDictionary){receiver.referenceDictionary=[receiver makeReferenceDictionary];}
        [reference loadWord:entry.lemma.length?entry.lemma:entry.surface reading:entry.reading ?: @"" dictionary:receiver.referenceDictionary];
    }
}

+ (void)referenceEntryChangedWithReceiver:(id<FYReferenceRenderSource>)receiver {
    NSInteger index=receiver.referenceEntryPopup.indexOfSelectedItem;
    if(index<0 || index>=receiver.referenceRecords.count){return;}
    NSDictionary *record=receiver.referenceRecords[index];
    [receiver clearArrangedSubviews:receiver.referenceStack];
    if(receiver.referenceRecords.count>1){
        [receiver.referenceStack addArrangedSubview:[receiver mutedLabel:@"同形词 · 请按读音选择"]];
        [receiver.referenceStack addArrangedSubview:receiver.referenceEntryPopup];
    }
    FYLearningColumnsView *columns=[FYLearningColumnsView new]; columns.leftFraction=0.30; columns.spacing=24; columns.compactWidth=720;
    NSStackView *summary=[receiver verticalStack]; summary.spacing=12;
    [summary addArrangedSubview:[receiver label:receiver.referenceActiveWord font:FYUIFont(28, NSFontWeightSemibold) color:receiver.uiInk]];
    [summary addArrangedSubview:[receiver label:[record[@"readings"] componentsJoinedByString:@"／"] font:FYUIFont(16, NSFontWeightRegular) color:receiver.uiMuted]];
    NSString *levels=[record[@"reference_levels"] componentsJoinedByString:@"／"];
    NSStackView *badge=[receiver verticalStack]; badge.spacing=4;
    [badge addArrangedSubview:[receiver label:levels.length ? [NSString stringWithFormat:@"JLPT 参考 %@",levels] : @"等级暂无资料" font:FYUIFont(14, NSFontWeightSemibold) color:receiver.uiAccent]];
    [badge addArrangedSubview:[receiver mutedLabel:levels.length ? @"社区分级 · 非官方清单" : @"未分级不代表考试不会出现"]];
    [summary addArrangedSubview:[receiver workspaceSection:badge]];
    NSArray *forms=[record[@"spellings"] count] ? record[@"spellings"] : record[@"readings"];
    NSString *formText=[forms componentsJoinedByString:@"／"];
    if(![formText isEqualToString:receiver.referenceActiveWord]){[summary addArrangedSubview:[receiver mutedLabel:[NSString stringWithFormat:@"词典写法\n%@",formText]]];}
    [summary addArrangedSubview:[receiver mutedLabel:@"JMdict 词典原文\n英文释义 · 日文例句"]];
    [columns addArrangedSubview:summary];
    NSStackView *details=[receiver verticalStack]; details.spacing=16;
    receiver.referenceTabs=[receiver segmentedWithLabels:@[@"释义与用法",@"例句",@"来源"] action:@selector(referenceTabChanged:)];
    [receiver.referenceTabs.heightAnchor constraintEqualToConstant:32].active=YES;
    [details addArrangedSubview:receiver.referenceTabs];
    receiver.referenceSensePopup=[NSPopUpButton new]; receiver.referenceSensePopup.target=[receiver referenceActionTarget]; receiver.referenceSensePopup.action=@selector(referenceTabChanged:);
    for(NSDictionary *sense in record[@"senses"]){
        NSString *gloss=[sense[@"glosses"] firstObject] ?: @"";
        [receiver.referenceSensePopup addItemWithTitle:[NSString stringWithFormat:@"义项 %@ · %@",sense[@"number"],gloss]];
    }
    [receiver.referenceSensePopup setContentCompressionResistancePriority:250 forOrientation:NSLayoutConstraintOrientationHorizontal];
    if([record[@"senses"] count]>1){[details addArrangedSubview:receiver.referenceSensePopup];}
    receiver.referenceDetailStack=[receiver verticalStack]; receiver.referenceDetailStack.spacing=12;
    [details addArrangedSubview:receiver.referenceDetailStack];
    [columns addArrangedSubview:details]; [receiver.referenceStack addArrangedSubview:columns];
    [receiver referenceTabChanged:nil];
}

+ (void)referenceTabChangedWithReceiver:(id<FYReferenceRenderSource>)receiver {
    NSInteger index=receiver.referenceEntryPopup.indexOfSelectedItem;
    if(index<0 || index>=receiver.referenceRecords.count){return;}
    NSDictionary *record=receiver.referenceRecords[index]; NSArray *senses=record[@"senses"];
    NSInteger senseIndex=receiver.referenceSensePopup.indexOfSelectedItem;
    if(senseIndex<0 || senseIndex>=senses.count){return;}
    NSDictionary *sense=senses[senseIndex];
    [receiver clearArrangedSubviews:receiver.referenceDetailStack];
    receiver.referenceMoreExamples=nil;
    NSInteger tab=receiver.referenceTabs.selectedSegment;
    receiver.referenceSensePopup.hidden=tab==2;
    if(tab==0){
        [receiver.referenceDetailStack addArrangedSubview:[receiver label:[sense[@"glosses"] componentsJoinedByString:@"; "] font:FYUIFont(18, NSFontWeightMedium) color:receiver.uiInk]];
        NSDictionary *tags=@{@"noun (common) (futsuumeishi)":@"名词", @"adjectival nouns or quasi-adjectives (keiyodoshi)":@"な形容词", @"nouns which may take the genitive case particle 'no'":@"可接「の」", @"adverb (fukushi)":@"副词", @"expressions (phrases, clauses, etc.)":@"惯用表达", @"Ichidan verb":@"一段动词", @"transitive verb":@"他动词", @"intransitive verb":@"自动词", @"adjective (keiyoushi)":@"い形容词", @"noun or participle which takes the aux. verb suru":@"サ变名词"};
        NSMutableArray *shortTags=[NSMutableArray array];
        for(NSString *pos in sense[@"pos"]){if(tags[pos]){[shortTags addObject:tags[pos]];}}
        if(shortTags.count){[receiver.referenceDetailStack addArrangedSubview:[receiver label:[shortTags componentsJoinedByString:@"  ·  "] font:FYUIFont(13, NSFontWeightMedium) color:receiver.uiAccent]];}
        if([sense[@"pos"] count]){
            receiver.referenceMoreExamples=[receiver verticalStack];
            [receiver.referenceMoreExamples addArrangedSubview:[receiver mutedLabel:[sense[@"pos"] componentsJoinedByString:@"; "]]];
            [receiver addReferenceDisclosure:@"词典原始词性标签" content:receiver.referenceMoreExamples];
        }
        NSStackView *notes=[receiver verticalStack]; notes.spacing=8;
        for(NSArray *field in @[@[@"使用说明",@"notes"],@[@"语体",@"register"],@[@"领域",@"fields"],@[@"方言",@"dialect"],@[@"适用写法",@"only_spellings"],@[@"适用读音",@"only_readings"]]){
            NSString *value=[sense[field[1]] componentsJoinedByString:@"; "];
            if(value.length){[notes addArrangedSubview:[receiver mutedLabel:[NSString stringWithFormat:@"%@\n%@",field[0],value]]];}
        }
        if(notes.arrangedSubviews.count){[receiver.referenceDetailStack addArrangedSubview:[receiver workspaceSection:notes]];}
        [receiver.referenceDetailStack addArrangedSubview:[receiver mutedLabel:@"释义按词典义项展示。选择其他义项，或切换到「例句」查看具体用法。"]];
    }else if(tab==1){
        NSArray *examples=sense[@"examples"];
        if(!examples.count){[receiver.referenceDetailStack addArrangedSubview:[receiver mutedLabel:@"这个义项暂无符合导入条件的例句。可以切换其他义项查看。"]];}
        NSInteger n=0;
        NSStackView *more=[receiver verticalStack]; more.spacing=12;
        for(NSDictionary *example in examples){
            NSStackView *item=[receiver verticalStack]; item.spacing=8;
            [item addArrangedSubview:[receiver label:example[@"ja"] font:FYUIFont(17, NSFontWeightMedium) color:receiver.uiInk]];
            [item addArrangedSubview:[receiver mutedLabel:[NSString stringWithFormat:@"关联词形 %@ · 作者 %@\nTatoeba #%@ · %@",example[@"matched_text"],example[@"author"],example[@"sentence_id"],example[@"license"]]]];
            [item addArrangedSubview:[receiver referenceLink:@"查看原始例句 ↗" URL:example[@"url"]]];
            NSView *card=[receiver workspaceSection:item];
            if(n++<2){[receiver.referenceDetailStack addArrangedSubview:card];}else{[more addArrangedSubview:card];}
        }
        if(more.arrangedSubviews.count){receiver.referenceMoreExamples=more; [receiver addReferenceDisclosure:[NSString stringWithFormat:@"更多例句（%lu）",(unsigned long)more.arrangedSubviews.count] content:more];}
        [receiver.referenceDetailStack addArrangedSubview:[receiver mutedLabel:@"例句与词典义项关联，尚未独立人工审校。"]];
    }else{
        [receiver.referenceDetailStack addArrangedSubview:[receiver cardTitle:@"资料可追溯"]];
        [receiver.referenceDetailStack addArrangedSubview:[receiver mutedLabel:@"词义与读音 · JMdict / EDRDG\nCC BY-SA 4.0\n\n日文例句 · Tatoeba\nCC BY 2.0 FR，逐条保留作者\n\n参考等级 · OpenJLPT / Jonathan Waller\nCC BY-SA 4.0，社区整理"]];
        [receiver.referenceDetailStack addArrangedSubview:[receiver referenceLink:@"词典原始条目 ↗" URL:record[@"source_url"]]];
        if([record[@"reference_levels"] count]){[receiver.referenceDetailStack addArrangedSubview:[receiver referenceLink:@"等级数据来源 ↗" URL:@"https://github.com/evanclan/OpenJLPT"]];}
        [receiver.referenceDetailStack addArrangedSubview:[receiver workspaceButton:@"在 Finder 查看完整许可文件 ↗" action:@selector(showReferenceLicenses:) primary:NO]];
        [receiver.referenceDetailStack addArrangedSubview:[receiver mutedLabel:@"资料用于词义与用法参考；没有加入历年真题或未经核对的考试讲解。"]];
    }
}

+ (void)addDisclosure:(NSString *)title content:(NSView *)content receiver:(id<FYReferenceRenderSource>)receiver {
    NSButton *button=[receiver workspaceButton:title action:@selector(toggleReferenceExtra:) primary:NO];
    [button setButtonType:NSButtonTypePushOnPushOff]; content.hidden=YES;
    [receiver.referenceDetailStack addArrangedSubview:button];
    [receiver.referenceDetailStack addArrangedSubview:content];
}

+ (void)toggleExtra:(NSButton *)sender receiver:(id<FYReferenceRenderSource>)receiver {
    receiver.referenceMoreExamples.hidden=sender.state!=NSControlStateValueOn;
}

+ (void)setHoverTip:(NSString *)tip range:(NSRange)range source:(NSString *)source views:(NSArray *)views receiver:(id<FYReferenceRenderSource>)receiver {
    for(NSTextView *view in views){
        if(![view isKindOfClass:NSTextView.class] || view.editable || ![view.string isEqualToString:source]){continue;}
        if(range.location!=NSNotFound && range.length && NSMaxRange(range)<=view.string.length){
            [view.textStorage addAttribute:FYSourceHoverAttributeName value:tip range:range];
        }
    }
}

+ (void)clearHoverAttributes:(NSArray *)views {
    for(NSTextView *view in views){
        if([view isKindOfClass:NSTextView.class]){if([view isKindOfClass:FYSelectableSourceTextView.class]){[(FYSelectableSourceTextView *)view dismissSourceHover];}[view.textStorage removeAttribute:FYSourceHoverAttributeName range:NSMakeRange(0,view.string.length)];}
    }
}

+ (void)showEmptyWord:(NSString *)word error:(NSError *)error receiver:(id<FYReferenceRenderSource>)receiver {
            [receiver.referenceStack addArrangedSubview:[receiver label:[NSString stringWithFormat:@"%@ · 暂无资料",word] font:FYUIFont(20, NSFontWeightSemibold) color:receiver.uiInk]];
            [receiver.referenceStack addArrangedSubview:[receiver mutedLabel:error ? error.localizedDescription : @"试试输入辞书形，或缩小选词范围。未匹配的释义与等级会留空。"]];
}

+ (void)renderRecords:(NSArray<NSDictionary *> *)records receiver:(id<FYReferenceRenderSource>)receiver {
        receiver.referenceEntryPopup=[NSPopUpButton new]; receiver.referenceEntryPopup.target=[receiver referenceActionTarget];
        receiver.referenceEntryPopup.action=@selector(referenceEntryChanged:);
        for(NSDictionary *record in records){
            NSArray *forms=[record[@"spellings"] count] ? record[@"spellings"] : record[@"readings"];
            [receiver.referenceEntryPopup addItemWithTitle:[NSString stringWithFormat:@"%@ · %@",[forms componentsJoinedByString:@"／"],[record[@"readings"] componentsJoinedByString:@"／"]]];
        }
        [receiver referenceEntryChanged:nil];
}

@end
