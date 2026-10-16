#import <Foundation/Foundation.h>

static inline NSString *FYTrim(NSString *value) {
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

static inline NSString *FYStringOrEmpty(id value) {
    if ([value isKindOfClass:NSString.class]) { return value; }
    return @"";
}

static inline NSString *FYOptionalString(id value) {
    if ([value isKindOfClass:NSString.class]) { return value; }
    return nil;
}

static inline NSError *FYCanceledError(void) {
    return [NSError errorWithDomain:@"FYLearningAnalyzer" code:499
                           userInfo:@{NSLocalizedDescriptionKey: @"学习请求已取消。"}];
}

