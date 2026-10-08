#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Text-only, opt-in diagnostics. Does not import AppKit, capture pixels, inspect
// settings/credentials or make requests. Only timer-selected-window call sites
// may create a cycle; async work retains that cycle's immutable context.
@interface FYTranslationTrace : NSObject
+ (instancetype)shared;
+ (NSString *)defaultDirectory;
- (instancetype)initWithDirectory:(NSString *)directory
                             clock:(NSTimeInterval (^)(void))clock
                          maxBytes:(NSUInteger)maxBytes;
- (nullable NSDictionary *)beginCycleForWindow:(uint32_t)windowID generation:(NSInteger)generation;
// 采集输入会话关联：inputEpoch 是采集会话代次，inputSource 是识别输入源
// （0 = 窗口截图，1 = 采集卡）。两者会写进本轮所有记录的上下文，
// 因此 OCR、请求、字幕应用/丢弃都能对上是哪一次采集会话的画面。
- (nullable NSDictionary *)beginCycleForWindow:(uint32_t)windowID
                                    generation:(NSInteger)generation
                                    inputEpoch:(NSUInteger)inputEpoch
                                   inputSource:(NSInteger)inputSource;
- (nullable NSDictionary *)requestContextForCycle:(nullable NSDictionary *)cycle;
// Attach the captured frame to the immutable cycle before scheduling OCR.
// Window capture has no device counter (index 0); frame_id remains unique.
- (nullable NSDictionary *)frameContextForCycle:(nullable NSDictionary *)cycle index:(uint64_t)index;
- (void)recordEvent:(NSString *)event context:(nullable NSDictionary *)context fields:(NSDictionary *)fields;
@end

// Scoped, synchronous propagation through existing translation entry points.
// Async callbacks capture the returned immutable context explicitly. No app-wide
// mutable current-request field, and no context leaks into unrelated actions.
FOUNDATION_EXPORT NSDictionary * _Nullable FYCurrentTrace(void);
FOUNDATION_EXPORT void FYTracePerform(NSDictionary * _Nullable context, void (^work)(void));

// Avoid assembling OCR arrays/text dictionaries when tracing was not enabled
// at cycle start. recordEvent also checks the live switch on EVERY write.
#define FYTrace(traceContext, eventName, ...) do { \
    if ((traceContext) != nil) { \
        [[FYTranslationTrace shared] recordEvent:(eventName) context:(traceContext) fields:(__VA_ARGS__)]; \
    } \
} while (0)

NS_ASSUME_NONNULL_END
