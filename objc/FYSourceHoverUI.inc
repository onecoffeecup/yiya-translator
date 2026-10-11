// Glyph ranges drive the themed hover card without changing native text selection.
- (void)setSourceHoverTip:(NSString *)tip range:(NSRange)range source:(NSString *)source views:(NSArray *)views {
    for(NSTextView *view in views){
        if(![view isKindOfClass:NSTextView.class] || view.editable || ![view.string isEqualToString:source]){continue;}
        if(range.location!=NSNotFound && range.length && NSMaxRange(range)<=view.string.length){
            [view.textStorage addAttribute:FYSourceHoverAttributeName value:tip range:range];
        }
    }
}
- (void)applyAnalysisHoverTips:(FYAnalysisResult *)analysis source:(NSString *)source views:(NSArray *)views {
    for(FYVocabularyEntry *word in analysis.vocabulary){
        if(!word.surface.length){continue;}
        NSString *tip=[NSString stringWithFormat:@"%@%@\n%@\nAI 解析 · 按语境核对",word.surface,word.reading.length?[NSString stringWithFormat:@"（%@）",word.reading]:@"",word.meaning ?: @"释义待补充"];
        NSRange remaining=NSMakeRange(0,source.length);
        while(remaining.length){NSRange range=[source rangeOfString:word.surface options:0 range:remaining];if(range.location==NSNotFound){break;}[self setSourceHoverTip:tip range:range source:source views:views];remaining=NSMakeRange(NSMaxRange(range),source.length-NSMaxRange(range));}
    }
    // Verified grammar ranges take priority over an overlapping token tooltip.
    for(FYGrammarItem *item in analysis.grammar){
        NSRange range=item.matchedRange;
        if(range.location==NSNotFound || !range.length || NSMaxRange(range)>source.length || ![[source substringWithRange:range] isEqualToString:item.matchedText]){continue;}
        NSMutableArray *lines=[NSMutableArray arrayWithObject:item.name ?: item.matchedText];
        if(item.meaning.length){[lines addObject:item.meaning];}
        if(item.connection.length){[lines addObject:[@"接续：" stringByAppendingString:item.connection]];}
        if(item.explanation.length){[lines addObject:[@"本句：" stringByAppendingString:item.explanation]];}
        [lines addObject:@"AI 解析 · 点击语法标签查看详情"];
        [self setSourceHoverTip:[lines componentsJoinedByString:@"\n"] range:range source:source views:views];
    }
}
- (void)populateSourceHoverTips:(NSString *)source views:(NSArray *)views analysis:(FYAnalysisResult *)analysis fallback:(NSString *)fallback isCurrent:(BOOL (^)(void))isCurrent {
    for(NSTextView *view in views){
        if([view isKindOfClass:NSTextView.class]){if([view isKindOfClass:FYSelectableSourceTextView.class]){[(FYSelectableSourceTextView *)view dismissSourceHover];}[view.textStorage removeAttribute:FYSourceHoverAttributeName range:NSMakeRange(0,view.string.length)];}
    }
    if(!source.length || !isCurrent()){return;}
    [self applyAnalysisHoverTips:analysis source:source views:views];
    if(!self.sourceHoverCache){self.sourceHoverCache=[NSCache new];self.sourceHoverCache.countLimit=300;}
    if(!self.referenceDictionary){self.referenceDictionary=[[FYReferenceDictionary alloc] initWithURL:[self referenceResourceURL:@"reference.sqlite"]];}
    if(!self.japaneseTokenizer){self.japaneseTokenizer=[FYJapaneseTokenizer new];}
    [self.japaneseTokenizer rangesInText:source completion:^(NSArray<NSValue *> *ranges){
        if(!isCurrent()){return;}
        NSMutableDictionary<NSString *,NSMutableArray<NSValue *> *> *words=[NSMutableDictionary new];
        for(NSValue *value in ranges){NSRange range=value.rangeValue;if(!range.length || NSMaxRange(range)>source.length){continue;}NSString *surface=[source substringWithRange:range];
            if(!words[surface]){words[surface]=[NSMutableArray new];} [words[surface] addObject:value];
            [self setSourceHoverTip:[NSString stringWithFormat:@"%@\n%@",surface,fallback] range:range source:source views:views];
        }
        [self applyAnalysisHoverTips:analysis source:source views:views];
        for(NSString *surface in words){
            NSString *cached=[self.sourceHoverCache objectForKey:surface];
            if(cached){for(NSValue *value in words[surface]){[self setSourceHoverTip:cached range:value.rangeValue source:source views:views];}[self applyAnalysisHoverTips:analysis source:source views:views];continue;}
            [self.referenceDictionary lookupWord:surface reading:@"" completion:^(NSArray<NSDictionary *> *records,NSError *error){
                if(error || !records.count){return;}
                NSDictionary *record=records.firstObject;NSDictionary *sense=[record[@"senses"] firstObject];
                NSString *tip=[NSString stringWithFormat:@"%@（%@）\n%@\nJMdict · 英文释义%@",surface,[record[@"readings"] componentsJoinedByString:@"／"],[sense[@"glosses"] componentsJoinedByString:@"；"] ?: @"暂无释义",records.count>1?@" · 多个词条，请结合语境核对":@""];
                [self.sourceHoverCache setObject:tip forKey:surface];
                if(!isCurrent()){return;}
                for(NSValue *value in words[surface]){[self setSourceHoverTip:tip range:value.rangeValue source:source views:views];}
                [self applyAnalysisHoverTips:analysis source:source views:views];
            }];
        }
    }];
}
- (void)refreshSourceHoverTips {
    NSUInteger generation=++self.sourceHoverGeneration;
    self.sourceHoverSuspended=NO;
    // Keep callback comparisons tied to this request, not mutable text storage.
    NSString *source=[self.learningSourceTextView.string copy] ?: @"";
    NSArray *views=@[self.learningSourceTextView ?: (id)NSNull.null,self.grammarSourceTextView ?: (id)NSNull.null];
    FYAnalysisResult *analysis=[self analysisMatchesCurrentSentence]?self.currentAnalysis:nil;
    __weak typeof(self) weakSelf=self;
    [self populateSourceHoverTips:source views:views analysis:analysis fallback:@"点击或拖选可收藏；用法可向 AI 提问。" isCurrent:^BOOL{
        typeof(self) owner=weakSelf;
        return owner && generation==owner.sourceHoverGeneration && !owner.learningSourceTextView.editable && [source isEqualToString:owner.learningSourceTextView.string];
    }];
}
- (void)refreshQuickSentenceHoverTips {
    NSUInteger generation=++self.quickSourceHoverGeneration;
    FYSelectableSourceTextView *view=self.quickSourceTextView;
    if(!view){return;}
    NSString *source=[view.string copy] ?: @"";
    NSString *sentenceID=[self.quickSentenceID copy] ?: @"";
    NSInteger version=self.quickSentenceVersion;
    FYAnalysisResult *analysis=[source isEqualToString:self.quickSentenceAnalysisSource]?self.quickSentenceAnalysis:nil;
    __weak typeof(self) weakSelf=self;
    [self populateSourceHoverTips:source views:@[view] analysis:analysis fallback:@"本机词典暂无释义 · 可选词复制或向 AI 提问" isCurrent:^BOOL{
        typeof(self) owner=weakSelf;
        return owner && owner.quickSentenceRequested && generation==owner.quickSourceHoverGeneration &&
            owner.quickSourceTextView==view && !view.editable && [source isEqualToString:view.string] &&
            [source isEqualToString:owner.quickSentenceSource] && [sentenceID isEqualToString:owner.quickSentenceID ?: @""] && version==owner.quickSentenceVersion;
    }];
}
