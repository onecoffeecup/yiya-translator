#import "FYSourceHoverCoordinator.h"

@implementation FYSourceHoverCoordinator
- (void)applyAnalysis:(FYAnalysisResult *)analysis source:(NSString *)source views:(NSArray *)views receiver:(id<FYSourceHoverSource>)receiver {
    for(FYVocabularyEntry *word in analysis.vocabulary){
        if(!word.surface.length){continue;}
        NSString *tip=[NSString stringWithFormat:@"%@%@\n%@\nAI 解析 · 按语境核对",word.surface,word.reading.length?[NSString stringWithFormat:@"（%@）",word.reading]:@"",word.meaning ?: @"释义待补充"];
        NSRange remaining=NSMakeRange(0,source.length);
        while(remaining.length){NSRange range=[source rangeOfString:word.surface options:0 range:remaining];if(range.location==NSNotFound){break;}[receiver setSourceHoverTip:tip range:range source:source views:views];remaining=NSMakeRange(NSMaxRange(range),source.length-NSMaxRange(range));}
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
        [receiver setSourceHoverTip:[lines componentsJoinedByString:@"\n"] range:range source:source views:views];
    }
}

- (void)populateSource:(NSString *)source views:(NSArray *)views analysis:(FYAnalysisResult *)analysis fallback:(NSString *)fallback isCurrent:(BOOL(^)(void))isCurrent receiver:(id<FYSourceHoverSource>)receiver {
    [receiver clearSourceHoverAttributes:views];
    if(!source.length || !isCurrent()){return;}
    [receiver applyAnalysisHoverTips:analysis source:source views:views];
    if(!receiver.sourceHoverCache){receiver.sourceHoverCache=[NSCache new];receiver.sourceHoverCache.countLimit=300;}
    if(!receiver.referenceDictionary){receiver.referenceDictionary=[receiver makeReferenceDictionary];}
    if(!receiver.japaneseTokenizer){receiver.japaneseTokenizer=[FYJapaneseTokenizer new];}
    [receiver.japaneseTokenizer rangesInText:source completion:^(NSArray<NSValue *> *ranges){
        if(!isCurrent()){return;}
        NSMutableDictionary<NSString *,NSMutableArray<NSValue *> *> *words=[NSMutableDictionary new];
        for(NSValue *value in ranges){NSRange range=value.rangeValue;if(!range.length || NSMaxRange(range)>source.length){continue;}NSString *surface=[source substringWithRange:range];
            if(!words[surface]){words[surface]=[NSMutableArray new];} [words[surface] addObject:value];
            [receiver setSourceHoverTip:[NSString stringWithFormat:@"%@\n%@",surface,fallback] range:range source:source views:views];
        }
        [receiver applyAnalysisHoverTips:analysis source:source views:views];
        for(NSString *surface in words){
            NSString *cached=[receiver.sourceHoverCache objectForKey:surface];
            if(cached){for(NSValue *value in words[surface]){[receiver setSourceHoverTip:cached range:value.rangeValue source:source views:views];}[receiver applyAnalysisHoverTips:analysis source:source views:views];continue;}
            [receiver.referenceDictionary lookupWord:surface reading:@"" completion:^(NSArray<NSDictionary *> *records,NSError *error){
                if(error || !records.count){return;}
                NSDictionary *record=records.firstObject;NSDictionary *sense=[record[@"senses"] firstObject];
                NSString *tip=[NSString stringWithFormat:@"%@（%@）\n%@\nJMdict · 英文释义%@",surface,[record[@"readings"] componentsJoinedByString:@"／"],[sense[@"glosses"] componentsJoinedByString:@"；"] ?: @"暂无释义",records.count>1?@" · 多个词条，请结合语境核对":@""];
                [receiver.sourceHoverCache setObject:tip forKey:surface];
                if(!isCurrent()){return;}
                for(NSValue *value in words[surface]){[receiver setSourceHoverTip:tip range:value.rangeValue source:source views:views];}
                [receiver applyAnalysisHoverTips:analysis source:source views:views];
            }];
        }
    }];
}

- (void)refreshMainWithReceiver:(id<FYSourceHoverSource>)receiver {
    NSUInteger generation=++receiver.sourceHoverGeneration;
    receiver.sourceHoverSuspended=NO;
    // Keep callback comparisons tied to this request, not mutable text storage.
    NSString *source=[[receiver mainHoverText] copy] ?: @"";
    NSArray *views=[receiver mainHoverViews];
    FYAnalysisResult *analysis=[receiver analysisMatchesCurrentSentence]?receiver.currentAnalysis:nil;
    __weak typeof(receiver) weakSelf=receiver;
    [receiver populateSourceHoverTips:source views:views analysis:analysis fallback:@"点击或拖选可收藏；用法可向 AI 提问。" isCurrent:^BOOL{
        id<FYSourceHoverSource> owner=weakSelf;
        return owner && generation==owner.sourceHoverGeneration && ![owner mainHoverEditable] && [source isEqualToString:[owner mainHoverText]];
    }];
}

- (void)refreshQuickWithReceiver:(id<FYSourceHoverSource>)receiver {
    NSUInteger generation=++receiver.quickSourceHoverGeneration;
    id<NSObject> view=[receiver quickHoverView];
    if(!view){return;}
    NSString *source=[[receiver hoverTextForView:view] copy] ?: @"";
    NSString *sentenceID=[receiver.quickSentenceID copy] ?: @"";
    NSInteger version=receiver.quickSentenceVersion;
    FYAnalysisResult *analysis=[source isEqualToString:receiver.quickSentenceAnalysisSource]?receiver.quickSentenceAnalysis:nil;
    __weak typeof(receiver) weakSelf=receiver;
    [receiver populateSourceHoverTips:source views:@[view] analysis:analysis fallback:@"本机词典暂无释义 · 可选词复制或向 AI 提问" isCurrent:^BOOL{
        id<FYSourceHoverSource> owner=weakSelf;
        return owner && owner.quickSentenceRequested && generation==owner.quickSourceHoverGeneration &&
            [owner quickHoverView]==view && ![owner hoverEditableForView:view] && [source isEqualToString:[owner hoverTextForView:view]] &&
            [source isEqualToString:owner.quickSentenceSource] && [sentenceID isEqualToString:owner.quickSentenceID ?: @""] && version==owner.quickSentenceVersion;
    }];
}

@end
