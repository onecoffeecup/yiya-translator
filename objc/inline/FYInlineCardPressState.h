#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
NS_ASSUME_NONNULL_BEGIN
// Only the four original gesture values. A native receiver may override their
// compatibility accessors; synchronous operations do not save that receiver.
@protocol FYInlineCardPressStateSource <NSObject>
@property(nonatomic) NSPoint pressPoint;
@property(nonatomic) BOOL pressMovedBeyondThreshold;
@property(nonatomic) BOOL collapsePressed;
@property(nonatomic) CGFloat titleBarHeight;
@end
@protocol FYInlineCardPressNativeActions <NSObject>
- (BOOL)pointIsInCollapseControl:(NSPoint)point;
- (BOOL)pointIsInTitleBar:(NSPoint)point;
- (void)setCollapseControlHighlighted:(BOOL)highlighted;
- (void)performCollapseAfterPressRelease;
- (void)performClickAfterPressRelease;
@end
@interface FYInlineCardPressState : NSObject <FYInlineCardPressStateSource>
@property(nonatomic) NSPoint pressPoint;
@property(nonatomic) BOOL pressMovedBeyondThreshold;
@property(nonatomic) BOOL collapsePressed;
@property(nonatomic) CGFloat titleBarHeight;
- (void)beginPressAtPoint:(NSPoint)point stateSource:(id<FYInlineCardPressStateSource>)source;
- (void)dragPressToPoint:(NSPoint)point stateSource:(id<FYInlineCardPressStateSource>)source nativeActions:(id<FYInlineCardPressNativeActions>)actions;
- (void)releasePressAtPoint:(NSPoint)point stateSource:(id<FYInlineCardPressStateSource>)source nativeActions:(id<FYInlineCardPressNativeActions>)actions;
- (BOOL)pointIsInTitleBar:(NSPoint)point stateSource:(id<FYInlineCardPressStateSource>)source;
@end
NS_ASSUME_NONNULL_END
