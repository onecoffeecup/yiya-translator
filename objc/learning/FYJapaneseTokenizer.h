#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// 系统日语分词：只返回 NSString 的 UTF-16 NSRange，不提供读音/原形/释义。
// NLTokenizer 非线程安全，所有调用在内部串行队列执行。
// 异步请求入队前复制文本；回调范围对应提交时的 UTF-16 文本快照。
@interface FYJapaneseTokenizer : NSObject

- (void)setCompletionQueue:(dispatch_queue_t)queue; // 默认主队列

- (void)rangesInText:(NSString *)text
          completion:(void (^)(NSArray<NSValue *> *ranges))completion;

- (void)rangeForLocation:(NSUInteger)location
                  inText:(NSString *)text
              completion:(void (^)(NSRange range))completion;

@end

NS_ASSUME_NONNULL_END
