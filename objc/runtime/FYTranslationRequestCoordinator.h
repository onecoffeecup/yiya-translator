#pragma once
#import <Foundation/Foundation.h>
#import "../settings/FYSettingsStore.h"

// Each cancellation scope has its own task collection. No transport/UI ownership.
@interface FYTranslationTaskOwner : NSObject
@property(nonatomic, strong) NSURLSessionDataTask *activeTask;
- (void)finishTask:(NSURLSessionDataTask *)task;
- (void)cancelActiveTask;
- (void)cancelTasksExceptTask:(NSURLSessionDataTask *)retainedTask;
@end

typedef NS_ENUM(NSInteger, FYTranslationRequestScope) {
    FYTranslationRequestRealtime, FYTranslationRequestServiceTest
};
typedef NS_ENUM(NSInteger, FYTranslationRequestDrop) {
    FYTranslationRequestContentChanged, FYTranslationRequestGenerationChanged
};

// Ephemeral immutable result. It contains authentication only in the request,
// never in diagnostics, preferences, files or a second credential store.
@interface FYPreparedTranslationRequest : NSObject
@property(nonatomic, copy, readonly) NSURLRequest *request;
@property(nonatomic, strong, readonly) NSError *error;
@property(nonatomic, copy, readonly) NSString *failureReason;
+ (instancetype)prepareText:(NSString *)text configuration:(FYTranslationConfiguration *)configuration
    systemPrompt:(NSString *)prompt defaultPrompt:(NSString *(^)(void))defaultPrompt maxTokens:(NSInteger)maxTokens
    modelOverride:(NSString *)modelOverride longText:(BOOL)longText;
@end

@interface FYTranslationRequestIdentity : NSObject
- (instancetype)initWithScope:(FYTranslationRequestScope)scope generation:(NSInteger)generation revision:(NSUInteger)revision;
@property(nonatomic, readonly) FYTranslationRequestScope scope;
@property(nonatomic, readonly) NSInteger generation;
@property(nonatomic, readonly) NSUInteger revision;
@end

// The two primitive readers retain the original receiver for this operation
// only. The coordinator stores no application context or idle source delegate.
@interface FYTranslationRequestLease : NSObject
- (instancetype)initWithIdentity:(FYTranslationRequestIdentity *)identity
    generation:(NSInteger (^)(void))generation revision:(NSUInteger (^)(void))revision;
@property(nonatomic, strong, readonly) FYTranslationRequestIdentity *identity;
- (NSInteger)currentGeneration;
- (NSUInteger)currentRevision;
@end
@protocol FYTranslationRequestTransport <NSObject>
- (NSURLSessionDataTask *)taskWithRequest:(NSURLRequest *)request
    observer:(void (^)(NSURLResponse *, NSError *))observer completion:(void (^)(NSString *, NSError *))completion;
@end
@interface FYSystemTranslationRequestTransport : NSObject <FYTranslationRequestTransport>
@end

@interface FYTranslationRequestCoordinator : NSObject
- (instancetype)initWithTransport:(id<FYTranslationRequestTransport>)transport;
@property(nonatomic, strong) FYTranslationTaskOwner *realtimeTaskOwner;
- (void)submit:(FYPreparedTranslationRequest *)prepared owner:(FYTranslationTaskOwner *)owner lease:(FYTranslationRequestLease *)lease
    observer:(void (^)(NSURLResponse *, NSError *))observer received:(void (^)(NSString *, NSError *))received
    willResume:(void (^)(void))willResume completion:(void (^)(NSString *, NSError *))completion
    dropped:(void (^)(FYTranslationRequestDrop))dropped;
@end
