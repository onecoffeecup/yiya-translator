#pragma once
#import <Foundation/Foundation.h>
// Immutable container of the original strong local NSString aliases; native UI getter/fallback order stays in its adapter.
@interface FYGrammarServiceConfiguration : NSObject
@property(nonatomic,strong,readonly) NSString *baseURL;
@property(nonatomic,strong,readonly) NSString *model;
@property(nonatomic,strong,readonly) NSString *apiKey;
- (instancetype)initWithBaseURL:(NSString *)baseURL model:(NSString *)model apiKey:(NSString *)apiKey;
@end
