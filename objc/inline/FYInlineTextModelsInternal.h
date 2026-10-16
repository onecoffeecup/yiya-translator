#pragma once
#import "FYInlineTextModels.h"
// Original variant fields; only the model implementation synthesizes storage.
@interface FYInlinePlacement ()
@property (nonatomic, copy) NSArray *bodyFontSettings;
@property (nonatomic) CGFloat stableBodyFontSize;
@property (nonatomic) NSUInteger availableVariantCount;
@end

