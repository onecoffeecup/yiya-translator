#pragma once
#import "FYTranslationCachePlanner.h"
#import "FYContentTranslationState.h"

// An operation-scoped transport lease. The adapter preserves native overrides
// and retains the original receiver only while a batch is outstanding.
@protocol FYInlineBatchTransport <NSObject>
- (FYContentTranslationSnapshot *)contentSnapshot;
- (void)submitBatch:(FYInlineTranslationBatch *)batch translations:(NSMutableArray<NSString *> *)translations
    completion:(void (^)(NSError *))completion;
- (void)submitRetainedLongBatch:(FYInlineTranslationBatch *)batch translations:(NSMutableArray<NSString *> *)translations
    completion:(void (^)(NSError *))completion;
- (NSURLSessionDataTask *)activeTask;
@end
@interface FYInlineBatchTransportLease : NSObject <FYInlineBatchTransport>
- (instancetype)initWithSnapshot:(FYContentTranslationSnapshot *(^)(void))snapshot
    submit:(void (^)(FYInlineTranslationBatch *, NSMutableArray<NSString *> *, void (^)(NSError *)))submit
    submitLong:(void (^)(FYInlineTranslationBatch *, NSMutableArray<NSString *> *, void (^)(NSError *)))submitLong
    activeTask:(NSURLSessionDataTask *(^)(void))activeTask;
@end

// Main-thread cache/plan state, independent of UI, OCR/HTTP busy slots and services.
@interface FYInlineTranslationCoordinator : NSObject
@property(nonatomic, strong) FYInlineTranslationCache *cache;
@property(nonatomic, strong) FYTranslationCache *dialogueCache;
@property(nonatomic) NSUInteger serial;
@property(nonatomic, strong) FYInlinePendingLongBatch *pendingLongBatch;
- (BOOL)retainsLongBatchForContent:(FYContentTranslationSnapshot *)content
    newKeys:(NSArray<NSString *> *(^)(void))newKeys existingKeys:(NSArray<NSString *> *(^)(void))existingKeys;
- (void)discardPendingLongBatch;
- (void)advanceSerial;
- (void)clearPendingLongCompletions;
- (void)translateItems:(NSArray<OCRTextItem *> *)items key:(NSString *(^)(OCRTextItem *))key
    isLong:(BOOL (^)(OCRTextItem *))isLong observer:(void (^)(NSUInteger, BOOL))observer
    transport:(id<FYInlineBatchTransport>)transport completion:(void (^)(NSArray<NSString *> *, NSError *))completion;
- (void)translateRetainedLongBatch:(FYInlineTranslationBatch *)batch translations:(NSMutableArray<NSString *> *)translations
    transport:(id<FYInlineBatchTransport>)transport completion:(void (^)(NSError *))completion;
- (void)applyText:(NSString *)text error:(NSError *)error batch:(FYInlineTranslationBatch *)batch
    translations:(NSMutableArray<NSString *> *)translations submittedSerial:(NSUInteger)serial
    parse:(NSArray<NSString *> *(^)(NSString *, NSUInteger))parse cache:(void (^)(NSString *, NSString *))cache
    completion:(void (^)(NSError *))completion;
@end
