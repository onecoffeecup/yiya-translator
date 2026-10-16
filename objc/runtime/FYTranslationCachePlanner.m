#import "FYTranslationCachePlanner.h"


@implementation FYInlineTranslationCache
- (void)storeValue:(NSString *)value forKey:(NSString *)key { FYStoreInlineTranslation(self.entries,value,key); }
- (void)clear { [self.entries removeAllObjects]; }
@end

void FYPartitionInlineBatch(NSArray *items, NSArray<NSNumber *> *indexes, NSArray<NSString *> *keys,
    BOOL (^isLongAtIndex)(NSUInteger), NSMutableArray *shortItems, NSMutableArray<NSNumber *> *shortIndexes,
    NSMutableArray<NSString *> *shortKeys, NSMutableArray *longItems, NSMutableArray<NSNumber *> *longIndexes,
    NSMutableArray<NSString *> *longKeys) {
    for (NSUInteger index=0; index<items.count; index++) {
        BOOL longText=isLongAtIndex(index);
        [(longText ? longItems : shortItems) addObject:items[index]];
        [(longText ? longIndexes : shortIndexes) addObject:indexes[index]];
        [(longText ? longKeys : shortKeys) addObject:keys[index]];
    }
}

void FYPlanInlineTranslations(NSUInteger count, NSDictionary<NSString *, NSString *> *cache,
    NSString *(^keyAtIndex)(NSUInteger), void (^observeHit)(NSUInteger, BOOL),
    NSMutableArray<NSString *> *translations, NSMutableArray<NSNumber *> *pendingIndexes, NSMutableArray<NSString *> *pendingKeys) {
    for (NSUInteger index=0; index<count; index++) {
        NSString *key=keyAtIndex(index), *cached=cache[key];
        if (observeHit) observeHit(index, cached.length > 0);
        if (cached.length > 0) [translations addObject:cached];
        else { [translations addObject:@""]; [pendingIndexes addObject:@(index)]; [pendingKeys addObject:key]; }
    }
}

void FYStoreInlineTranslation(NSMutableDictionary<NSString *, NSString *> *cache, NSString *value, NSString *key) {
    if (value.length == 0 || key.length == 0) return;
    if (cache.count >= 4000 && cache[key] == nil) [cache removeAllObjects];
    cache[key] = value;
}

void FYRunInlineBatches(BOOL hasShort, BOOL hasLong, NSArray<NSString *> *translations,
    void (^launch)(BOOL longText, void (^done)(NSError *)),
    void (^completion)(NSArray<NSString *> *, NSError *)) {
    __block BOOL shortDone=!hasShort, longDone=!hasLong;
    __block NSError *shortError=nil, *longError=nil;
    void (^maybeFinish)(void)=^{
        if (!shortDone || !longDone) return;
        NSError *error=shortError ?: longError;
        completion(error ? nil : translations, error);
    };
    if (hasShort) launch(NO, ^(NSError *error){ shortError=error; shortDone=YES; maybeFinish(); });
    if (hasLong) launch(YES, ^(NSError *error){ longError=error; longDone=YES; maybeFinish(); });
    if (!hasShort && !hasLong) maybeFinish();
}

NSError *FYApplyInlineBatchResults(NSArray<NSString *> *parsed, NSUInteger count,
    NSArray<NSNumber *> *indexes, NSArray<NSString *> *keys, NSMutableArray<NSString *> *translations,
    void (^cacheValue)(NSString *, NSString *)) {
        if (parsed.count != count) {
            NSMutableArray<NSString *> *seenValues = [NSMutableArray array];
            BOOL allBlank = YES;
            for (NSUInteger index = 0; index < count; index++) {
                NSString *value = index < parsed.count ? [parsed[index] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
                NSNumber *targetIndex = indexes[index];
                translations[targetIndex.unsignedIntegerValue] = value;
                if (value.length == 0) { continue; }
                allBlank = NO;
                if (![seenValues containsObject:value]) { [seenValues addObject:value]; }
            }

            if (allBlank) {
                NSError *parseError = [NSError errorWithDomain:@"LiveCaptionTranslator"
                                                          code:205
                                                      userInfo:@{NSLocalizedDescriptionKey: @"贴译结果没有按编号返回，已跳过这一轮；请重试或改用更稳定的模型（如 DeepSeek Flash）。"}];
                return parseError;
            }

            BOOL looksLikeDuplicatedParagraph = seenValues.count == 1 && count >= 3 && [seenValues[0] length] > 24;
            if (looksLikeDuplicatedParagraph) {
                NSError *parseError = [NSError errorWithDomain:@"LiveCaptionTranslator"
                                                          code:205
                                                      userInfo:@{NSLocalizedDescriptionKey: @"贴译结果像是一整段文字被重复返回，已跳过这一轮以避免整屏贴同一句。"}];
                return parseError;
            }

            for (NSUInteger index = 0; index < count; index++) {
                NSString *value = translations[indexes[index].unsignedIntegerValue];
                if (value.length == 0) { continue; }
                cacheValue(value, keys[index]);
            }
            return nil;
        }

        for (NSUInteger index = 0; index < count; index++) {
            NSString *value = index < parsed.count ? [parsed[index] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
            NSNumber *targetIndex = indexes[index];
            translations[targetIndex.unsignedIntegerValue] = value;
            if (value.length == 0) { continue; }
            cacheValue(value, keys[index]);
        }
        return nil;
}

NSString *FYTranslationCacheKey(NSInteger generation, NSInteger serviceGeneration, NSString *sentenceID,
                                NSInteger version, NSString *text, NSString *prompt) {
    return sentenceID.length ? [NSString stringWithFormat:@"%ld|%ld|%@|%ld|%@|%@", (long)generation,
        (long)serviceGeneration, sentenceID, (long)version, text, prompt] : nil;
}

BOOL FYTranslationCacheCanStore(NSInteger requestGeneration, NSInteger currentGeneration,
    NSInteger requestServiceGeneration, NSInteger currentServiceGeneration, NSString *translated) {
    return requestGeneration == currentGeneration && requestServiceGeneration == currentServiceGeneration &&
        [translated stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet].length > 0;
}

@interface FYTranslationCache ()
@property(nonatomic, copy, readwrite) NSString *key;
@property(nonatomic, copy, readwrite) NSString *value;
@end
@implementation FYTranslationCache
- (NSString *)valueForKey:(NSString *)key { return key && [key isEqualToString:self.key] && self.value.length ? self.value : nil; }
- (void)storeValue:(NSString *)value forKey:(NSString *)key { self.key=key; self.value=value; }
- (void)clear { self.key=nil; self.value=nil; }
@end

@implementation FYInlinePendingLongBatch
@end

@implementation FYInlineTranslationBatch
- (instancetype)initWithItems:(NSArray<OCRTextItem *> *)items indexes:(NSArray<NSNumber *> *)indexes keys:(NSArray<NSString *> *)keys longText:(BOOL)longText {
    if ((self = [super init])) { _items = [items copy]; _indexes = [indexes copy]; _keys = [keys copy]; _longText = longText; }
    return self;
}
@end
@implementation FYInlineTranslationPlan
+ (instancetype)planForItems:(NSArray<OCRTextItem *> *)items cache:(NSDictionary<NSString *, NSString *> *)cache
    key:(NSString *(^)(OCRTextItem *))key isLong:(BOOL (^)(OCRTextItem *))isLong observer:(void (^)(NSUInteger, BOOL))observer {
    NSMutableArray<NSString *> *translations = [NSMutableArray new];
    NSMutableArray<OCRTextItem *> *pendingItems = [NSMutableArray new];
    NSMutableArray<NSNumber *> *indexes = [NSMutableArray new];
    NSMutableArray<NSString *> *keys = [NSMutableArray new];
    FYPlanInlineTranslations(items.count, cache, ^NSString *(NSUInteger i) { return key(items[i]); }, observer, translations, indexes, keys);
    for (NSNumber *index in indexes) { [pendingItems addObject:items[index.unsignedIntegerValue]]; }
    NSMutableArray *shortItems = [NSMutableArray new], *longItems = [NSMutableArray new];
    NSMutableArray *shortIndexes = [NSMutableArray new], *longIndexes = [NSMutableArray new];
    NSMutableArray *shortKeys = [NSMutableArray new], *longKeys = [NSMutableArray new];
    FYPartitionInlineBatch(pendingItems, indexes, keys, ^BOOL(NSUInteger i) { return isLong(pendingItems[i]); },
        shortItems, shortIndexes, shortKeys, longItems, longIndexes, longKeys);
    FYInlineTranslationPlan *plan = [self new];
    plan->_cachedValues = [translations copy]; plan->_pendingCount = pendingItems.count;
    plan->_shortBatch = [[FYInlineTranslationBatch alloc] initWithItems:shortItems indexes:shortIndexes keys:shortKeys longText:NO];
    plan->_longBatch = [[FYInlineTranslationBatch alloc] initWithItems:longItems indexes:longIndexes keys:longKeys longText:YES];
    return plan;
}
@end
