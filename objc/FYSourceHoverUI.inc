// Glyph ranges drive the themed hover card without changing native text selection.
- (void)setSourceHoverTip:(NSString *)tip range:(NSRange)range source:(NSString *)source {
    for(NSTextView *view in @[self.learningSourceTextView ?: (id)NSNull.null,self.grammarSourceTextView ?: (id)NSNull.null]){
        if(![view isKindOfClass:NSTextView.class] || view.editable || ![view.string isEqualToString:source]){continue;}
        if(range.location!=NSNotFound && range.length && NSMaxRange(range)<=view.string.length){
            [view.textStorage addAttribute:FYSourceHoverAttributeName value:tip range:range];
        }
    }
}
- (void)applyAnalysisHoverTipsToSource:(NSString *)source {
    if(![self analysisMatchesCurrentSentence]){return;}
    for(FYVocabularyEntry *word in self.currentAnalysis.vocabulary){
        if(!word.surface.length){continue;}
        NSString *tip=[NSString stringWithFormat:@"%@%@\n%@\nAI 解析 · 按语境核对",word.surface,word.reading.length?[NSString stringWithFormat:@"（%@）",word.reading]:@"",word.meaning ?: @"释义待补充"];
        NSRange remaining=NSMakeRange(0,source.length);
        while(remaining.length){NSRange range=[source rangeOfString:word.surface options:0 range:remaining];if(range.location==NSNotFound){break;}[self setSourceHoverTip:tip range:range source:source];remaining=NSMakeRange(NSMaxRange(range),source.length-NSMaxRange(range));}
    }
    // Verified grammar ranges take priority over an overlapping token tooltip.
    for(FYGrammarItem *item in self.currentAnalysis.grammar){
        NSRange range=item.matchedRange;
        if(range.location==NSNotFound || !range.length || NSMaxRange(range)>source.length || ![[source substringWithRange:range] isEqualToString:item.matchedText]){continue;}
        NSMutableArray *lines=[NSMutableArray arrayWithObject:item.name ?: item.matchedText];
        if(item.meaning.length){[lines addObject:item.meaning];}
        if(item.connection.length){[lines addObject:[@"接续：" stringByAppendingString:item.connection]];}
        if(item.explanation.length){[lines addObject:[@"本句：" stringByAppendingString:item.explanation]];}
        [lines addObject:@"AI 解析 · 点击语法标签查看详情"];
        [self setSourceHoverTip:[lines componentsJoinedByString:@"\n"] range:range source:source];
    }
}
- (void)refreshSourceHoverTips {
    NSUInteger generation=++self.sourceHoverGeneration;
    self.sourceHoverSuspended=NO;
    for(NSTextView *view in @[self.learningSourceTextView ?: (id)NSNull.null,self.grammarSourceTextView ?: (id)NSNull.null]){
        if([view isKindOfClass:NSTextView.class]){if([view isKindOfClass:FYSelectableSourceTextView.class]){[(FYSelectableSourceTextView *)view dismissSourceHover];}[view.textStorage removeAttribute:FYSourceHoverAttributeName range:NSMakeRange(0,view.string.length)];}
    }
    // Keep callback comparisons tied to this request, not the live text storage.
    NSString *source=[self.learningSourceTextView.string copy] ?: @"";
    if(!source.length || self.learningSourceTextView.editable){return;}
    [self applyAnalysisHoverTipsToSource:source];
    if(!self.sourceHoverCache){self.sourceHoverCache=[NSCache new];self.sourceHoverCache.countLimit=300;}
    if(!self.referenceDictionary){self.referenceDictionary=[[FYReferenceDictionary alloc] initWithURL:[self referenceResourceURL:@"reference.sqlite"]];}
    [self.japaneseTokenizer rangesInText:source completion:^(NSArray<NSValue *> *ranges){
        if(generation!=self.sourceHoverGeneration || self.learningSourceTextView.editable || ![source isEqualToString:self.learningSourceTextView.string]){return;}
        NSMutableDictionary<NSString *,NSMutableArray<NSValue *> *> *words=[NSMutableDictionary new];
        for(NSValue *value in ranges){NSRange range=value.rangeValue;if(!range.length || NSMaxRange(range)>source.length){continue;}NSString *surface=[source substringWithRange:range];
            if(!words[surface]){words[surface]=[NSMutableArray new];} [words[surface] addObject:value];
            [self setSourceHoverTip:[NSString stringWithFormat:@"%@\n点击或拖选可收藏；用法可向 AI 提问。",surface] range:range source:source];
        }
        [self applyAnalysisHoverTipsToSource:source];
        for(NSString *surface in words){
            NSString *cached=[self.sourceHoverCache objectForKey:surface];
            if(cached){for(NSValue *value in words[surface]){[self setSourceHoverTip:cached range:value.rangeValue source:source];}[self applyAnalysisHoverTipsToSource:source];continue;}
            [self.referenceDictionary lookupWord:surface reading:@"" completion:^(NSArray<NSDictionary *> *records,NSError *error){
                if(error || !records.count){return;}
                NSDictionary *record=records.firstObject;NSDictionary *sense=[record[@"senses"] firstObject];
                NSString *tip=[NSString stringWithFormat:@"%@（%@）\n%@\nJMdict · 英文释义%@",surface,[record[@"readings"] componentsJoinedByString:@"／"],[sense[@"glosses"] componentsJoinedByString:@"；"] ?: @"暂无释义",records.count>1?@" · 多个词条，请结合语境核对":@""];
                [self.sourceHoverCache setObject:tip forKey:surface];
                if(generation!=self.sourceHoverGeneration || self.learningSourceTextView.editable || ![source isEqualToString:self.learningSourceTextView.string]){return;}
                for(NSValue *value in words[surface]){[self setSourceHoverTip:tip range:value.rangeValue source:source];}
                [self applyAnalysisHoverTipsToSource:source];
            }];
        }
    }];
}
