#import <Foundation/Foundation.h>

// Translation protocol/policies and isolated owners; no UI or delegate dependency.
FOUNDATION_EXPORT NSString *FYDisplayableTranslation(NSString *translated, NSString *sourceText,
    NSString *(^trim)(NSString *), NSString *(^normalize)(NSString *),
    BOOL (^equivalent)(NSString *, NSString *), BOOL (^looksLikeSource)(NSString *));
@interface FYInlineTranslationCache : NSObject
// Preserve mutable container aliases used by rendered OCR snapshots and compatibility fixtures.
@property(nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *entries;
- (void)storeValue:(NSString *)value forKey:(NSString *)key;
- (void)clear;
@end

@interface FYTranslationRunState : NSObject
@property(nonatomic, copy) NSString *lastTranslatedText;
@property(nonatomic, copy) NSString *lastSubmittedText;
@property(nonatomic, strong) NSDate *lastAttemptDate;
- (void)reset;
- (BOOL)shouldThrottleText:(NSString *)text geometryChanged:(BOOL)geometryChanged interval:(NSTimeInterval)interval
    equivalent:(BOOL (^)(NSString *current, NSString *previous))equivalent now:(NSDate *(^)(void))now;
@end
FOUNDATION_EXPORT NSString *FYInlineDeliveryDropReason(NSInteger generation, NSInteger currentGeneration,
    NSUInteger inputEpoch, NSUInteger currentInputEpoch, BOOL running, NSInteger mode, NSInteger currentMode);
FOUNDATION_EXPORT void FYStoreInlineTranslation(NSMutableDictionary<NSString *, NSString *> *cache, NSString *value, NSString *key);
FOUNDATION_EXPORT void FYPlanInlineTranslations(NSUInteger count, NSDictionary<NSString *, NSString *> *cache,
    NSString *(^keyAtIndex)(NSUInteger), void (^observeHit)(NSUInteger, BOOL),
    NSMutableArray<NSString *> *translations, NSMutableArray<NSNumber *> *pendingIndexes, NSMutableArray<NSString *> *pendingKeys);
FOUNDATION_EXPORT void FYPartitionInlineBatch(NSArray *items, NSArray<NSNumber *> *indexes, NSArray<NSString *> *keys,
    BOOL (^isLongAtIndex)(NSUInteger), NSMutableArray *shortItems, NSMutableArray<NSNumber *> *shortIndexes,
    NSMutableArray<NSString *> *shortKeys, NSMutableArray *longItems, NSMutableArray<NSNumber *> *longIndexes,
    NSMutableArray<NSString *> *longKeys);
FOUNDATION_EXPORT NSErrorDomain const FYTranslationURLValidationErrorDomain;
typedef NS_ENUM(NSInteger, FYTranslationURLValidationError) {
    FYTranslationURLMissing = 1,
    FYTranslationURLInvalidScheme,
    FYTranslationURLMissingHost,
    FYTranslationURLUnsupportedComponents,
    FYTranslationURLMalformed,
};
// Invalid input returns nil and a localized error; diagnostics never include credentials/input URL.
FOUNDATION_EXPORT NSURL *FYChatCompletionsURLWithError(NSString *baseURL, NSError **error);
// Compatibility wrapper, identical acceptance rules.
FOUNDATION_EXPORT NSURL *FYChatCompletionsURL(NSString *baseURL);
FOUNDATION_EXPORT BOOL FYIsDeepSeekService(NSString *baseURL, NSString *model);
FOUNDATION_EXPORT NSString *FYNumberedTranslationSource(NSUInteger count, NSString *(^textAtIndex)(NSUInteger));
FOUNDATION_EXPORT NSString *FYInlineBatchPrompt(NSString *sourceLanguage, BOOL longText);
FOUNDATION_EXPORT NSInteger FYInlineBatchMaxTokens(NSUInteger itemCount, BOOL longText);
FOUNDATION_EXPORT NSArray<NSString *> *FYParseNumberedTranslations(NSString *text, NSUInteger count);
FOUNDATION_EXPORT NSError *FYApplyInlineBatchResults(NSArray<NSString *> *parsed, NSUInteger count,
    NSArray<NSNumber *> *indexes, NSArray<NSString *> *keys, NSMutableArray<NSString *> *translations,
    void (^cacheValue)(NSString *, NSString *));
// Launch callbacks and their completions must run on the same serial queue.
FOUNDATION_EXPORT void FYRunInlineBatches(BOOL hasShort, BOOL hasLong, NSArray<NSString *> *translations,
    void (^launch)(BOOL longText, void (^done)(NSError *)),
    void (^completion)(NSArray<NSString *> *, NSError *));
FOUNDATION_EXPORT NSString *FYTranslationCacheKey(NSInteger generation, NSInteger serviceGeneration,
    NSString *sentenceID, NSInteger version, NSString *text, NSString *prompt);
FOUNDATION_EXPORT BOOL FYTranslationCacheCanStore(NSInteger requestGeneration, NSInteger currentGeneration,
    NSInteger requestServiceGeneration, NSInteger currentServiceGeneration, NSString *translated);
FOUNDATION_EXPORT void FYDeliverTranslationOnMain(NSInteger requestGeneration, NSInteger (^currentGeneration)(void),
    NSString *translated, NSError *error, void (^completion)(NSString *, NSError *), void (^dropped)(void));
// Main-thread owner; assigning a replacement intentionally does not cancel the old task.
@interface FYTranslationTaskOwner : NSObject
@property(nonatomic, strong) NSURLSessionDataTask *activeTask;
- (void)cancelActiveTask;
@end

@interface FYTranslationCache : NSObject
@property(nonatomic, copy, readonly) NSString *key;
@property(nonatomic, copy, readonly) NSString *value;
- (NSString *)valueForKey:(NSString *)key;
- (void)storeValue:(NSString *)value forKey:(NSString *)key;
- (void)clear;
@end

@interface FYTranslationManager : NSObject
// Returns suspended task. Observer runs before decoding; completion stays on session queue.
+ (NSURLSessionDataTask *)taskWithRequest:(NSURLRequest *)request session:(NSURLSession *)session
                              observer:(void (^)(NSURLResponse *, NSError *))observer
                            completion:(void (^)(NSString *, NSError *))completion;
+ (NSMutableURLRequest *)requestWithURL:(NSURL *)url apiKey:(NSString *)key model:(NSString *)model
                           sourceText:(NSString *)text systemPrompt:(NSString *)prompt
                            maxTokens:(NSInteger)maxTokens disableReasoning:(BOOL)disableReasoning
                                error:(NSError **)error;
+ (NSString *)translationFromData:(NSData *)data statusCode:(NSInteger)statusCode error:(NSError **)error;
@end
