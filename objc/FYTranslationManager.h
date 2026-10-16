#import <Foundation/Foundation.h>

// Translation protocol/policies and isolated owners; no UI or delegate dependency.
FOUNDATION_EXPORT NSString *FYDisplayableTranslation(NSString *translated, NSString *sourceText,
    NSString *(^trim)(NSString *), NSString *(^normalize)(NSString *),
    BOOL (^equivalent)(NSString *, NSString *), BOOL (^looksLikeSource)(NSString *));
#import "runtime/FYTranslationCachePlanner.h"
#import "runtime/FYTranslationRequestCoordinator.h"

@interface FYTranslationRunState : NSObject
@property(nonatomic, copy) NSString *lastTranslatedText;
@property(nonatomic, copy) NSString *lastSubmittedText;
@property(nonatomic, strong) NSDate *lastAttemptDate;
- (void)reset;
- (BOOL)shouldThrottleText:(NSString *)text geometryChanged:(BOOL)geometryChanged interval:(NSTimeInterval)interval
    equivalent:(BOOL (^)(NSString *current, NSString *previous))equivalent now:(NSDate *(^)(void))now;
@end
#import "runtime/FYRuntimeDeliveryChecks.h"



FOUNDATION_EXPORT NSErrorDomain const FYTranslationURLValidationErrorDomain;
typedef NS_ENUM(NSInteger, FYTranslationURLValidationError) {
    FYTranslationURLMissing = 1,
    FYTranslationURLInvalidScheme,
    FYTranslationURLMissingHost,
    FYTranslationURLUnsupportedComponents,
    FYTranslationURLMalformed,
    FYTranslationURLInsecureRemoteHTTP,
};
// Invalid input returns nil and a localized error; diagnostics never include credentials/input URL.
FOUNDATION_EXPORT NSURL *FYChatCompletionsURLWithError(NSString *baseURL, NSError **error);
// Compatibility wrapper, identical acceptance rules.
FOUNDATION_EXPORT NSURL *FYChatCompletionsURL(NSString *baseURL);
// Official Claude host or an explicitly supplied /messages endpoint uses Messages.
// Other service URLs retain OpenAI-compatible requests; no UI protocol choice.
FOUNDATION_EXPORT NSURL *FYTranslationServiceURLWithError(NSString *baseURL, NSError **error);
FOUNDATION_EXPORT BOOL FYUsesAnthropicMessagesAPI(NSURL *url);
FOUNDATION_EXPORT BOOL FYIsDeepSeekService(NSString *baseURL, NSString *model);
FOUNDATION_EXPORT NSString *FYNumberedTranslationSource(NSUInteger count, NSString *(^textAtIndex)(NSUInteger));
FOUNDATION_EXPORT NSString *FYInlineBatchPrompt(NSString *sourceLanguage, BOOL longText);
FOUNDATION_EXPORT NSInteger FYInlineBatchMaxTokens(NSUInteger itemCount, BOOL longText);
FOUNDATION_EXPORT NSArray<NSString *> *FYParseNumberedTranslations(NSString *text, NSUInteger count);

// Launch callbacks and their completions must run on the same serial queue.




@interface FYTranslationManager : NSObject
+ (NSMutableURLRequest *)requestWithURL:(NSURL *)url apiKey:(NSString *)key model:(NSString *)model
                              messages:(NSArray<NSDictionary *> *)messages maxTokens:(NSInteger)maxTokens
                      disableReasoning:(BOOL)disableReasoning requiresJSON:(BOOL)requiresJSON
                               timeout:(NSTimeInterval)timeout error:(NSError **)error;
// Returns suspended task. Observer runs before decoding; completion stays on session queue.
+ (NSURLSessionDataTask *)taskWithRequest:(NSURLRequest *)request session:(NSURLSession *)session
                              observer:(void (^)(NSURLResponse *, NSError *))observer
                            completion:(void (^)(NSString *, NSError *))completion;
+ (NSMutableURLRequest *)requestWithURL:(NSURL *)url apiKey:(NSString *)key model:(NSString *)model
                           sourceText:(NSString *)text systemPrompt:(NSString *)prompt
                            maxTokens:(NSInteger)maxTokens disableReasoning:(BOOL)disableReasoning
                                error:(NSError **)error;
// Only long-text batches may extend the 15-second request timeout.
+ (NSMutableURLRequest *)requestWithURL:(NSURL *)url apiKey:(NSString *)key model:(NSString *)model
                           sourceText:(NSString *)text systemPrompt:(NSString *)prompt
                            maxTokens:(NSInteger)maxTokens disableReasoning:(BOOL)disableReasoning
                             longText:(BOOL)longText error:(NSError **)error;
+ (NSString *)translationFromData:(NSData *)data statusCode:(NSInteger)statusCode error:(NSError **)error;
@end
