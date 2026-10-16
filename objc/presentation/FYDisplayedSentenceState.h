#pragma once
#import <Foundation/Foundation.h>

@interface FYDisplayedSentenceState : NSObject
@property(nonatomic, copy) NSString *displayedSentenceID;
@property(nonatomic, copy) NSString *displayedSourceText;
@property(nonatomic, copy, nullable) NSString *displayedTranslation;
@property(nonatomic) NSInteger displayedVersion;
@end
