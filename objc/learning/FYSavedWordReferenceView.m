#import "FYAdventureTheme.h"
#import "FYSavedWordReferenceView.h"
@implementation FYSavedWordReferenceView {
    NSArray<NSDictionary *> *_records;
    NSPopUpButton *_entries;
    NSPopUpButton *_senses;
    NSSegmentedControl *_tabs;
    NSStackView *_details;
    NSUInteger _generation;
}
- (instancetype)initWithFrame:(NSRect)frame {
    if((self=[super initWithFrame:frame])){self.orientation=NSUserInterfaceLayoutOrientationVertical;self.alignment=NSLayoutAttributeLeading;self.spacing=12;self.identifier=@"saved-word-reference";}
    return self;
}
- (void)addArrangedSubview:(NSView *)view {
    view.translatesAutoresizingMaskIntoConstraints=NO;[super addArrangedSubview:view];
    [view.widthAnchor constraintEqualToAnchor:self.widthAnchor].active=YES;
}
- (NSTextField *)text:(NSString *)text {
    NSTextField *label=[NSTextField wrappingLabelWithString:text ?: @""];label.font=FYUIFont(14, NSFontWeightRegular);label.textColor=FYAdventureColor(@"ink");return label;
}
- (void)clear:(NSStackView *)stack {
    for(NSView *view in stack.arrangedSubviews.copy){[stack removeArrangedSubview:view];[view removeFromSuperview];}
}
- (void)loadWord:(NSString *)word reading:(NSString *)reading dictionary:(FYReferenceDictionary *)dictionary {
    NSUInteger generation=++_generation;[self clear:self];[self addArrangedSubview:[self text:[NSString stringWithFormat:@"正在查询「%@」的离线词典资料…",word]]];
    [dictionary lookupWord:word reading:reading completion:^(NSArray<NSDictionary *> *records,NSError *error){
        if(generation!=self->_generation){return;}[self clear:self];self->_records=records;
        if(error || !records.count){[self addArrangedSubview:[self text:error.localizedDescription ?: @"没有匹配到这个词及读音的资料。释义与参考等级暂时留空。"]];return;}
        self->_entries=[NSPopUpButton new];self->_entries.target=self;self->_entries.action=@selector(entryChanged:);
        for(NSDictionary *record in records){NSArray *forms=[record[@"spellings"] count]?record[@"spellings"]:record[@"readings"];[self->_entries addItemWithTitle:[NSString stringWithFormat:@"%@ · %@",[forms componentsJoinedByString:@"／"],[record[@"readings"] componentsJoinedByString:@"／"]]];}
        [self entryChanged:nil];
    }];
}
- (void)entryChanged:(id)sender {
    [self clear:self];if(_records.count>1){[self addArrangedSubview:_entries];}
    NSDictionary *record=_records[_entries.indexOfSelectedItem];
    [self addArrangedSubview:[self text:[NSString stringWithFormat:@"词典读音：%@",[record[@"readings"] componentsJoinedByString:@"／"]]]];
    NSString *levels=[record[@"reference_levels"] componentsJoinedByString:@"／"];
    [self addArrangedSubview:[self text:levels.length?[NSString stringWithFormat:@"JLPT 参考 %@ · 社区分级，非官方清单",levels]:@"等级暂无资料 · 未分级不代表考试不会出现"]];
    _tabs=[NSSegmentedControl segmentedControlWithLabels:@[@"释义与用法",@"例句",@"来源"] trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(renderDetails:)];_tabs.selectedSegment=0;[self addArrangedSubview:_tabs];
    _senses=[NSPopUpButton new];_senses.target=self;_senses.action=@selector(renderDetails:);
    NSUInteger index=0;for(NSDictionary *sense in record[@"senses"]){[_senses addItemWithTitle:[NSString stringWithFormat:@"义项 %lu · %@",(unsigned long)++index,[sense[@"glosses"] firstObject] ?: @""]];}
    if([record[@"senses"] count]>1){[self addArrangedSubview:_senses];}
    _details=[NSStackView new];_details.orientation=NSUserInterfaceLayoutOrientationVertical;_details.alignment=NSLayoutAttributeLeading;_details.spacing=10;[self addArrangedSubview:_details];[self renderDetails:nil];
}
- (void)addDetail:(NSView *)view {
    view.translatesAutoresizingMaskIntoConstraints=NO;[_details addArrangedSubview:view];[view.widthAnchor constraintEqualToAnchor:_details.widthAnchor].active=YES;
}
- (void)link:(NSString *)title URL:(NSString *)url {
    if(!url.length){return;}NSButton *button=[NSButton buttonWithTitle:title target:self action:@selector(openLink:)];button.identifier=url;[self addDetail:button];
}
- (void)openLink:(NSButton *)sender {
    NSURL *url=[NSURL URLWithString:sender.identifier];if([url.scheme isEqualToString:@"https"]){[NSWorkspace.sharedWorkspace openURL:url];}
}
- (void)renderDetails:(id)sender {
    [self clear:_details];NSDictionary *record=_records[_entries.indexOfSelectedItem];NSArray *senses=record[@"senses"];
    NSDictionary *sense=(_senses.indexOfSelectedItem>=0 && _senses.indexOfSelectedItem<senses.count)?senses[_senses.indexOfSelectedItem]:@{};
    if(_tabs.selectedSegment==0){
        [self addDetail:[self text:[sense[@"glosses"] componentsJoinedByString:@"；"]]];
        [self addDetail:[self text:@"JMdict 词典原文 · 英文释义"]];
        for(NSArray *field in @[@[@"词典词性",@"pos"],@[@"使用说明",@"notes"],@[@"语体",@"register"],@[@"领域",@"fields"],@[@"方言",@"dialect"],@[@"适用写法",@"only_spellings"],@[@"适用读音",@"only_readings"]]){NSString *value=[sense[field[1]] componentsJoinedByString:@"；"];if(value.length){[self addDetail:[self text:[NSString stringWithFormat:@"%@：%@",field[0],value]]];}}
    }else if(_tabs.selectedSegment==1){
        NSArray *examples=sense[@"examples"];if(!examples.count){[self addDetail:[self text:@"这个义项暂无导入例句，可以切换其他义项查看。"]];}
        for(NSDictionary *example in examples){[self addDetail:[self text:example[@"ja"]]];[self addDetail:[self text:[NSString stringWithFormat:@"关联词形 %@ · 作者 %@ · Tatoeba #%@ · %@",example[@"matched_text"],example[@"author"],example[@"sentence_id"],example[@"license"]]]];[self link:@"查看原始例句 ↗" URL:example[@"url"]];}
        [self addDetail:[self text:@"例句与词典义项关联，尚未独立人工审校。"]];
    }else{
        [self addDetail:[self text:@"词义与读音：JMdict / EDRDG · CC BY-SA 4.0\n日文例句：Tatoeba · CC BY 2.0 FR，逐条保留作者\n参考等级：OpenJLPT / Jonathan Waller · CC BY-SA 4.0\n资料用于词义与用法参考，尚未加入历年真题。"]];
        [self link:@"词典原始条目 ↗" URL:record[@"source_url"]];if([record[@"reference_levels"] count]){[self link:@"等级数据来源 ↗" URL:@"https://github.com/evanclan/OpenJLPT"];}
    }
}
@end
