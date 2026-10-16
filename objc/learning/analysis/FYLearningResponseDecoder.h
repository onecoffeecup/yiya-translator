#import <Foundation/Foundation.h>
@interface FYLearningResponseDecoder : NSObject
// Called synchronously by the analyzer on its delivery queue, after task ownership checks.
+ (void)decodeData:(NSData *)data response:(NSURLResponse *)response error:(NSError *)error
    requestURL:(NSURL *)requestURL completion:(void (^)(NSString *, NSError *))completion;
@end
