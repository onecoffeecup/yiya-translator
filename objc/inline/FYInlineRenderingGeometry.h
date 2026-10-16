#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
NS_ASSUME_NONNULL_BEGIN
FOUNDATION_EXPORT CGFloat FYInlineLongCardLineHeight(CGFloat ascender, CGFloat descender, CGFloat leading);
FOUNDATION_EXPORT CGFloat FYInlineLongCardMinimumHeight(CGFloat lineHeight);
FOUNDATION_EXPORT CGFloat FYInlineLongCardBodyViewport(CGFloat cardHeight);
FOUNDATION_EXPORT NSSize FYInlineLongCardSize(NSSize proposed, BOOL compact);
FOUNDATION_EXPORT NSRect FYInlineLongCardBodyFrame(CGFloat width, CGFloat height, CGFloat padding, CGFloat titleBandHeight);
NS_ASSUME_NONNULL_END
