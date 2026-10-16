#import "FYInlineTranslationCoordinator.h"

@implementation FYInlineBatchTransportLease {
    FYContentTranslationSnapshot *(^_snapshot)(void);
    void (^_submit)(FYInlineTranslationBatch *, NSMutableArray<NSString *> *, void (^)(NSError *));
    void (^_submitLong)(FYInlineTranslationBatch *, NSMutableArray<NSString *> *, void (^)(NSError *));
    NSURLSessionDataTask *(^_activeTask)(void);
}
- (instancetype)initWithSnapshot:(FYContentTranslationSnapshot *(^)(void))snapshot
    submit:(void (^)(FYInlineTranslationBatch *, NSMutableArray<NSString *> *, void (^)(NSError *)))submit
    submitLong:(void (^)(FYInlineTranslationBatch *, NSMutableArray<NSString *> *, void (^)(NSError *)))submitLong
    activeTask:(NSURLSessionDataTask *(^)(void))activeTask {
    if ((self = [super init])) { _snapshot = [snapshot copy]; _submit = [submit copy]; _submitLong = [submitLong copy]; _activeTask = [activeTask copy]; }
    return self;
}
- (FYContentTranslationSnapshot *)contentSnapshot { return _snapshot(); }
- (void)submitBatch:(FYInlineTranslationBatch *)batch translations:(NSMutableArray<NSString *> *)translations completion:(void (^)(NSError *))completion { _submit(batch, translations, completion); }
- (void)submitRetainedLongBatch:(FYInlineTranslationBatch *)batch translations:(NSMutableArray<NSString *> *)translations completion:(void (^)(NSError *))completion { _submitLong(batch, translations, completion); }
- (NSURLSessionDataTask *)activeTask { return _activeTask(); }
@end

@implementation FYInlineTranslationCoordinator
- (instancetype)init { if ((self = [super init])) { _cache = [FYInlineTranslationCache new]; } return self; }
- (BOOL)retainsLongBatchForContent:(FYContentTranslationSnapshot *)content
    newKeys:(NSArray<NSString *> *(^)(void))newKeys existingKeys:(NSArray<NSString *> *(^)(void))existingKeys {
    return self.pendingLongBatch.task && content.operations && content.mode == FYContentModeUI && [newKeys() isEqual:existingKeys()];
}
- (void)advanceSerial { self.serial += 1; }
- (void)clearPendingLongCompletions { [self.pendingLongBatch.completions removeAllObjects]; }
- (void)discardPendingLongBatch {
    [self.pendingLongBatch.completions removeAllObjects];
    self.pendingLongBatch.task = nil;
    self.pendingLongBatch = nil;
}
- (void)translateItems:(NSArray<OCRTextItem *> *)items key:(NSString *(^)(OCRTextItem *))key
    isLong:(BOOL (^)(OCRTextItem *))isLong observer:(void (^)(NSUInteger, BOOL))observer
    transport:(id<FYInlineBatchTransport>)transport completion:(void (^)(NSArray<NSString *> *, NSError *))completion {
    FYInlineTranslationPlan *plan = [FYInlineTranslationPlan planForItems:items cache:self.cache.entries key:key isLong:isLong observer:observer];
    NSMutableArray<NSString *> *translations = [plan.cachedValues mutableCopy];
    if (plan.pendingCount == 0) { completion(translations, nil); return; }
    FYRunInlineBatches(plan.shortBatch.items.count > 0, plan.longBatch.items.count > 0, translations,
        ^(BOOL longText, void (^done)(NSError *)) {
            FYInlineTranslationBatch *batch = longText ? plan.longBatch : plan.shortBatch;
            FYContentTranslationSnapshot *content = longText ? [transport contentSnapshot] : nil;
            if (longText && content.operations && content.mode == FYContentModeUI && content.items) {
                [transport submitRetainedLongBatch:batch translations:translations completion:done];
            } else { [transport submitBatch:batch translations:translations completion:done]; }
        }, completion);
}
- (void)translateRetainedLongBatch:(FYInlineTranslationBatch *)plan translations:(NSMutableArray<NSString *> *)translations
    transport:(id<FYInlineBatchTransport>)transport completion:(void (^)(NSError *))completion {
    FYInlinePendingLongBatch *batch = self.pendingLongBatch;
    BOOL reuse = batch && [[batch.keys sortedArrayUsingSelector:@selector(compare:)] isEqual:[plan.keys sortedArrayUsingSelector:@selector(compare:)]];
    if (!reuse) {
        batch = [FYInlinePendingLongBatch new]; batch.keys = plan.keys;
        batch.completions = [NSMutableArray new]; self.pendingLongBatch = batch;
    }
    NSArray<NSString *> *batchKeys = batch.keys;
    [batch.completions addObject:^(NSArray<NSString *> *values, NSError *error) {
        if (!error) {
            NSMutableIndexSet *usedIndexes = [NSMutableIndexSet new];
            for (NSUInteger i = 0; i < plan.keys.count; i++) {
                NSUInteger oldIndex = [batchKeys indexOfObjectPassingTest:^BOOL(NSString *key, NSUInteger index, __attribute__((unused)) BOOL *stop) {
                    return ![usedIndexes containsIndex:index] && [key isEqualToString:plan.keys[i]];
                }];
                [usedIndexes addIndex:oldIndex];
                translations[plan.indexes[i].unsignedIntegerValue] = values[oldIndex];
            }
        }
        completion(error);
    }];
    if (reuse) { return; }
    NSMutableArray<NSString *> *values = [NSMutableArray new];
    NSMutableArray<NSNumber *> *indexes = [NSMutableArray new];
    for (NSUInteger i = 0; i < plan.keys.count; i++) { [values addObject:@""]; [indexes addObject:@(i)]; }
    FYInlineTranslationBatch *request = [[FYInlineTranslationBatch alloc] initWithItems:plan.items indexes:indexes keys:plan.keys longText:YES];
    [transport submitBatch:request translations:values completion:^(NSError *error) {
        // The bounded transport lease preserves the original receiver's strong
        // lifetime until this reply is consumed, including native test overrides.
        [self finishLongBatch:batch values:values error:error keepingTransport:transport];
    }];
    if (self.pendingLongBatch == batch) { batch.task = transport.activeTask; }
}
- (void)finishLongBatch:(FYInlinePendingLongBatch *)batch values:(NSArray<NSString *> *)values error:(NSError *)error
    keepingTransport:(__attribute__((unused)) id<FYInlineBatchTransport>)transport {
    if (self.pendingLongBatch != batch) { return; }
    self.pendingLongBatch = nil; batch.task = nil;
    NSArray<FYInlineLongBatchCompletion> *callbacks = [batch.completions copy];
    [batch.completions removeAllObjects];
    for (FYInlineLongBatchCompletion callback in callbacks) { callback(values, error); }
}
- (void)applyText:(NSString *)text error:(NSError *)error batch:(FYInlineTranslationBatch *)batch
    translations:(NSMutableArray<NSString *> *)translations submittedSerial:(NSUInteger)serial
    parse:(NSArray<NSString *> *(^)(NSString *, NSUInteger))parse cache:(void (^)(NSString *, NSString *))cache
    completion:(void (^)(NSError *))completion {
    if (!batch.longText && serial != self.serial) {
        completion([NSError errorWithDomain:NSURLErrorDomain code:NSURLErrorCancelled userInfo:nil]); return;
    }
    if (error) { completion(error); return; }
    NSArray<NSString *> *parsed = parse(text, batch.items.count);
    completion(FYApplyInlineBatchResults(parsed, batch.items.count, batch.indexes, batch.keys, translations, cache));
}
@end
