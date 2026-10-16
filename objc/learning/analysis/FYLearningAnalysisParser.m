#import "FYLearningAnalysisParser.h"
#import "FYLearningAnalysisSupport.h"
@interface FYLearningParsedAnalysis ()
@property(nonatomic, strong, readwrite) FYAnalysisResult *result;
@property(nonatomic, strong, readwrite) NSMutableArray<FYGrammarItem *> *verifiedGrammar;
@property(nonatomic, strong, readwrite) NSMutableArray<NSDictionary *> *rejectedItems;
@end
@implementation FYLearningParsedAnalysis
@end
@interface FYLearningAnalysisParser ()
@property(nonatomic, strong) FYLearningGrammarMatcher *matcher;
@end
@implementation FYLearningAnalysisParser
- (instancetype)initWithMatcher:(FYLearningGrammarMatcher *)matcher {
    self = [super init];
    if (self) { _matcher = matcher; }
    return self;
}

- (nullable NSData *)extractJSONDataFromContent:(NSString *)content {
    NSString *trimmed = FYTrim(content);
    NSString *lower = trimmed.lowercaseString;
    if ([lower hasPrefix:@"```"]) {
        NSRange firstNewline = [trimmed rangeOfString:@"\n"];
        if (firstNewline.location == NSNotFound) { return nil; }
        NSUInteger contentStart = NSMaxRange(firstNewline);
        NSRange endFence = [trimmed rangeOfString:@"```" options:0 range:NSMakeRange(contentStart, trimmed.length - contentStart)];
        if (endFence.location == NSNotFound) { return nil; }
        // 结束 fence 之后只能有空白，否则视为混杂输出（例如 JSON 后又附解释正文）。
        NSString *after = [trimmed substringFromIndex:NSMaxRange(endFence)];
        if (FYTrim(after).length > 0) { return nil; }
        trimmed = FYTrim([trimmed substringWithRange:NSMakeRange(contentStart, endFence.location - contentStart)]);
    }
    if (trimmed.length == 0 || trimmed.length > 100000) { return nil; }
    if (![trimmed hasPrefix:@"{"]) { return nil; }
    return [trimmed dataUsingEncoding:NSUTF8StringEncoding];
}

- (BOOL)optionalStringsIn:(NSDictionary *)dictionary keys:(NSArray<NSString *> *)keys {
    for (NSString *key in keys) {
        id value = dictionary[key];
        if (value && value != NSNull.null && (![value isKindOfClass:NSString.class] || [value length] > 10000)) { return NO; }
    }
    return YES;
}

- (FYLearningParsedAnalysis *)parseContent:(NSString *)content source:(NSString *)sourceText
    catalogProvider:(id<FYLearningCatalogProviding>)catalogProvider error:(NSError **)outError {
    NSData *jsonData = [self extractJSONDataFromContent:content];
    NSError *parseError = nil;
    NSDictionary *root = jsonData ? [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&parseError] : nil;
    if (![root isKindOfClass:NSDictionary.class]) {
        if (outError) { *outError = parseError ?: [NSError errorWithDomain:@"FYLearningAnalyzer" code:210
                                                      userInfo:@{NSLocalizedDescriptionKey: @"分析结果不是合法 JSON。"}]; } return nil;
    }
    if (![root[@"schema_version"] isKindOfClass:NSNumber.class] || CFGetTypeID((__bridge CFTypeRef)root[@"schema_version"]) == CFBooleanGetTypeID() || [root[@"schema_version"] doubleValue] != 1) {
        if (outError) { *outError = [NSError errorWithDomain:@"FYLearningAnalyzer" code:211
                                        userInfo:@{NSLocalizedDescriptionKey: @"分析结果的 schema_version 无效或不受支持。"}]; } return nil;
    }
    NSInteger schemaVersion = [root[@"schema_version"] integerValue];
    NSArray *grammarRaw = root[@"grammar"];
    NSArray *vocabRaw = root[@"vocabulary"];
    if (![grammarRaw isKindOfClass:NSArray.class] || ![vocabRaw isKindOfClass:NSArray.class] || grammarRaw.count > 100 || vocabRaw.count > 200) {
        if (outError) { *outError = [NSError errorWithDomain:@"FYLearningAnalyzer" code:212
                                        userInfo:@{NSLocalizedDescriptionKey: @"分析结果字段类型错误。"}]; } return nil;
    }

    // Reject a malformed element as a failed response, never as an empty result.
    BOOL valid = [self optionalStringsIn:root keys:@[@"sentence_note_zh"]];
    for (id raw in grammarRaw) {
        if (![raw isKindOfClass:NSDictionary.class]) { valid = NO; break; }
        NSDictionary *g = raw;
        if (![g[@"name"] isKindOfClass:NSString.class] || FYTrim(g[@"name"]).length == 0 ||
            ![g[@"matched_text"] isKindOfClass:NSString.class] || [g[@"matched_text"] length] == 0 ||
            ![self optionalStringsIn:g keys:@[@"catalog_id", @"connection", @"meaning_zh", @"explanation_zh", @"register_note"]]) { valid = NO; break; }
        id occurrence = g[@"occurrence"];
        // JSON null 等价于「未提供」：模型常用 null 表示不确定，不能当作字段类型错误。
        if (occurrence == NSNull.null) { occurrence = nil; }
        if (occurrence && (![occurrence isKindOfClass:NSNumber.class] ||
            CFGetTypeID((__bridge CFTypeRef)occurrence) == CFBooleanGetTypeID() ||
            [occurrence doubleValue] < 0 || [occurrence doubleValue] > sourceText.length ||
            [occurrence doubleValue] != [occurrence integerValue])) { valid = NO; break; }
    }
    // 词表只判结构与类型：模型常把活用形写成辞书形（原文「高くて」→ surface「高い」），
    // 这是形式不一致，不是伪造，交给下面的构建循环按「surface 必须取自原文」逐条丢弃即可。
    // 若在这里判整条失败，一个词形差异就会连带丢掉本来完全可用的语法结果（历史上表现为
    // 反复「分析失败：分析结果的条目或字段无效」且永远没有结果落库）。
    for (id raw in vocabRaw) {
        if (![raw isKindOfClass:NSDictionary.class]) { valid = NO; break; }
        NSDictionary *v = raw;
        if (![v[@"surface"] isKindOfClass:NSString.class] || [v[@"surface"] length] == 0 ||
            ![self optionalStringsIn:v keys:@[@"lemma", @"reading", @"meaning_zh"]]) { valid = NO; break; }
    }
    if (!valid) {
        if (outError) { *outError = [NSError errorWithDomain:@"FYLearningAnalyzer" code:214 userInfo:@{NSLocalizedDescriptionKey: @"分析结果的条目或字段无效，请重新分析。"}]; } return nil;
    }

    FYAnalysisResult *result = [[FYAnalysisResult alloc] init];
    result.schemaVersion = schemaVersion;
    result.sentenceNote = FYOptionalString(root[@"sentence_note_zh"]);

    NSMutableArray<FYGrammarItem *> *grammar = [NSMutableArray array];
    NSMutableArray<NSDictionary *> *rejectedItems = [NSMutableArray array];
    for (id raw in grammarRaw) {
        if (![raw isKindOfClass:NSDictionary.class]) { continue; }
        NSDictionary *g = raw;
        FYGrammarItem *item = [[FYGrammarItem alloc] init];
        item.name = FYTrim(FYStringOrEmpty(g[@"name"]));
        item.matchedText = FYStringOrEmpty(g[@"matched_text"]);
        item.connection = FYOptionalString(g[@"connection"]);
        item.meaning = FYOptionalString(g[@"meaning_zh"]);
        item.explanation = FYOptionalString(g[@"explanation_zh"]);
        item.registerNote = FYOptionalString(g[@"register_note"]);
        item.catalogID = FYOptionalString(g[@"catalog_id"]);
        if (item.name.length == 0 || item.matchedText.length == 0) { continue; }

        NSInteger occurrence = [g[@"occurrence"] isKindOfClass:NSNumber.class] ? [g[@"occurrence"] integerValue] : 0;
        item.matchedRange = [self.matcher verifiedRangeForText:item.matchedText occurrence:occurrence inText:sourceText];
        if (item.matchedRange.location == NSNotFound) { [rejectedItems addObject:g]; continue; }
        // Keep the actual source span, including OCR line breaks, for highlighting/cache.
        item.matchedText = [sourceText substringWithRange:item.matchedRange];

        if ([self.matcher hasLexicalConflict:item source:sourceText]) { continue; }
        FYGrammarCatalogEntry *entry = [self.matcher resolveCatalogEntryForItem:item provider:catalogProvider];
        if (entry) {
            item.referenceLevel = entry.referenceLevel.length > 0 ? entry.referenceLevel : nil;
            item.levelSourceTitle = entry.sourceTitle;
            item.levelSourceURL = entry.sourceURL;
            item.levelVerified = [entry.levelReviewStatus isEqualToString:@"verified"];
        } else {
            item.referenceLevel = nil;
            item.levelVerified = NO;
        }
        BOOL duplicate = NO;
        for (FYGrammarItem *known in grammar) {
            BOOL sameName = [known.name isEqualToString:item.name];
            FYGrammarCatalogEntry *knownEntry = [self.matcher resolveCatalogEntryForItem:known provider:catalogProvider];
            BOOL sameCatalog = entry && knownEntry && [entry.catalogID isEqualToString:knownEntry.catalogID];
            if ((sameName || sameCatalog) && NSEqualRanges(known.matchedRange,item.matchedRange)) { duplicate=YES; break; }
        }
        if (!duplicate) { [grammar addObject:item]; }
    }
    result.grammar = grammar;
    NSMutableArray *parts=[NSMutableArray new];NSUInteger previousEnd=0;
    NSArray *rawParts=[root[@"structure_parts"] isKindOfClass:NSArray.class]?root[@"structure_parts"]:@[];
    BOOL structureValid=rawParts.count>=2 && rawParts.count<=8;
    for(id raw in rawParts){
        if(![raw isKindOfClass:NSDictionary.class] || ![raw[@"text"] isKindOfClass:NSString.class] || ![raw[@"meaning_zh"] isKindOfClass:NSString.class] || ![raw[@"role_zh"] isKindOfClass:NSString.class] || ![raw[@"meaning_zh"] length]){structureValid=NO;break;}
        NSInteger occurrence=[raw[@"occurrence"] isKindOfClass:NSNumber.class]?[raw[@"occurrence"] integerValue]:0;
        NSRange range=[self.matcher verifiedRangeForText:raw[@"text"] occurrence:occurrence inText:sourceText];
        if(range.location==NSNotFound || range.location<previousEnd){structureValid=NO;break;}
        [parts addObject:@{@"text":[sourceText substringWithRange:range],@"meaning":raw[@"meaning_zh"],@"role":raw[@"role_zh"],@"location":@(range.location),@"length":@(range.length)}];previousEnd=NSMaxRange(range);
    }
    result.structureParts=structureValid?parts:@[];
    result.structureTitle=structureValid?FYOptionalString(root[@"structure_title_zh"]):nil;


    NSMutableArray<FYVocabularyEntry *> *vocabulary = [NSMutableArray array];
    for (id raw in vocabRaw) {
        if (![raw isKindOfClass:NSDictionary.class]) { continue; }
        NSDictionary *v = raw;
        FYVocabularyEntry *entry = [[FYVocabularyEntry alloc] init];
        entry.kind = FYVocabularyKindWord;
        entry.surface = FYStringOrEmpty(v[@"surface"]);
        entry.lemma = FYOptionalString(v[@"lemma"]);
        entry.reading = FYOptionalString(v[@"reading"]);
        entry.meaning = FYOptionalString(v[@"meaning_zh"]);
        entry.completionSource = FYCompletionSourceAI;
        if (entry.surface.length == 0) { continue; }
        if (![sourceText containsString:entry.surface]) { continue; }  // surface 必须取自原文
        [vocabulary addObject:entry];
    }
    result.vocabulary = vocabulary;

    FYLearningParsedAnalysis *parsed = [FYLearningParsedAnalysis new];
    parsed.result = result; parsed.verifiedGrammar = grammar; parsed.rejectedItems = rejectedItems;
    return parsed;
}

- (FYVocabularyEntry *)parseVocabularyContent:(NSString *)content surface:(NSString *)surface error:(NSError **)outError {
    NSData *jsonData = [self extractJSONDataFromContent:content];
    NSDictionary *root = jsonData ? [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:NULL] : nil;
    if (![root isKindOfClass:NSDictionary.class]) {
        if (outError) { *outError = [NSError errorWithDomain:@"FYLearningAnalyzer" code:213
                                        userInfo:@{NSLocalizedDescriptionKey: @"词条补全结果不是合法 JSON。"}]; } return nil;
    }
    if (!root[@"lemma"] || !root[@"reading"] || !root[@"meaning_zh"] ||
        ![self optionalStringsIn:root keys:@[@"lemma", @"reading", @"meaning_zh"]]) {
        if (outError) { *outError = [NSError errorWithDomain:@"FYLearningAnalyzer" code:215 userInfo:@{NSLocalizedDescriptionKey: @"词条补全字段缺失或类型错误。"}]; } return nil;
    }
    FYVocabularyEntry *entry = [[FYVocabularyEntry alloc] init];
    entry.kind = FYVocabularyKindWord;
    entry.surface = FYTrim(surface ?: @"");
    entry.lemma = FYOptionalString(root[@"lemma"]);
    entry.reading = FYOptionalString(root[@"reading"]);
    entry.meaning = FYOptionalString(root[@"meaning_zh"]);
    entry.completionSource = FYCompletionSourceAI;
    return entry;
}
@end
