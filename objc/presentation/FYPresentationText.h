#pragma once
#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT NSString *Trim(NSString * _Nullable value);
FOUNDATION_EXPORT NSString *NormalizeForComparison(NSString * _Nullable value);
FOUNDATION_EXPORT NSString *Shorten(NSString * _Nullable value, NSUInteger limit);
NS_ASSUME_NONNULL_END
