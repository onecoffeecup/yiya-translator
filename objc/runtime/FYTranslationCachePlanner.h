#pragma once
#import <Foundation/Foundation.h>
@class OCRTextItem;

// Canonical cache owners and the unchanged production planning functions.
@interface FYInlineTranslationCache : NSObject
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *entries;
- (void)storeValue:(NSString *)value forKey:(NSString *)key;
- (void)clear;
@end
@interface FYTranslationCache : NSObject
@property(nonatomic, copy, readonly) NSString *key;
@property(nonatomic, copy, readonly) NSString *value;
- (NSString *)valueForKey:(NSString *)key;
- (void)storeValue:(NSString *)value forKey:(NSString *)key;
- (void)clear;
@end
FOUNDATION_EXPORT void FYStoreInlineTranslation(NSMutableDictionary<NSString *, NSString *> *cache, NSString *value, NSString *key);
FOUNDATION_EXPORT void FYPlanInlineTranslations(NSUInteger count, NSDictionary<NSString *, NSString *> *cache,
    NSString *(^keyAtIndex)(NSUInteger), void (^observeHit)(NSUInteger, BOOL),
    NSMutableArray<NSString *> *translations, NSMutableArray<NSNumber *> *pendingIndexes, NSMutableArray<NSString *> *pendingKeys);
FOUNDATION_EXPORT void FYPartitionInlineBatch(NSArray *items, NSArray<NSNumber *> *indexes, NSArray<NSString *> *keys,
    BOOL (^isLongAtIndex)(NSUInteger), NSMutableArray *shortItems, NSMutableArray<NSNumber *> *shortIndexes,
    NSMutableArray<NSString *> *shortKeys, NSMutableArray *longItems, NSMutableArray<NSNumber *> *longIndexes,
    NSMutableArray<NSString *> *longKeys);
FOUNDATION_EXPORT NSError *FYApplyInlineBatchResults(NSArray<NSString *> *parsed, NSUInteger count,
    NSArray<NSNumber *> *indexes, NSArray<NSString *> *keys, NSMutableArray<NSString *> *translations,
    void (^cacheValue)(NSString *, NSString *));
FOUNDATION_EXPORT void FYRunInlineBatches(BOOL hasShort, BOOL hasLong, NSArray<NSString *> *translations,
    void (^launch)(BOOL longText, void (^done)(NSError *)), void (^completion)(NSArray<NSString *> *, NSError *));
FOUNDATION_EXPORT NSString *FYTranslationCacheKey(NSInteger generation, NSInteger serviceGeneration,
    NSString *sentenceID, NSInteger version, NSString *text, NSString *prompt);
FOUNDATION_EXPORT BOOL FYTranslationCacheCanStore(NSInteger requestGeneration, NSInteger currentGeneration,
    NSInteger requestServiceGeneration, NSInteger currentServiceGeneration, NSString *translated);

typedef void (^FYInlineLongBatchCompletion)(NSArray<NSString *> *, NSError *);
@interface FYInlinePendingLongBatch : NSObject
@property(nonatomic, copy) NSArray<NSString *> *keys;
@property(nonatomic, strong) NSURLSessionDataTask *task;
@property(nonatomic, strong) NSMutableArray<FYInlineLongBatchCompletion> *completions;
@end

// Arrays copy the plan container, preserving original OCR observation identities.
@interface FYInlineTranslationBatch : NSObject
- (instancetype)initWithItems:(NSArray<OCRTextItem *> *)items indexes:(NSArray<NSNumber *> *)indexes
    keys:(NSArray<NSString *> *)keys longText:(BOOL)longText;
@property(nonatomic, copy, readonly) NSArray<OCRTextItem *> *items;
@property(nonatomic, copy, readonly) NSArray<NSNumber *> *indexes;
@property(nonatomic, copy, readonly) NSArray<NSString *> *keys;
@property(nonatomic, readonly) BOOL longText;
@end
@interface FYInlineTranslationPlan : NSObject
@property(nonatomic, copy, readonly) NSArray<NSString *> *cachedValues;
@property(nonatomic, strong, readonly) FYInlineTranslationBatch *shortBatch;
@property(nonatomic, strong, readonly) FYInlineTranslationBatch *longBatch;
@property(nonatomic, readonly) NSUInteger pendingCount;
+ (instancetype)planForItems:(NSArray<OCRTextItem *> *)items cache:(NSDictionary<NSString *, NSString *> *)cache
    key:(NSString *(^)(OCRTextItem *))key isLong:(BOOL (^)(OCRTextItem *))isLong
    observer:(void (^)(NSUInteger, BOOL))observer;
@end
