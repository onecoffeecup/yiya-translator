#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "FYInlineSelectionCoordinator.h"
@class NSPanel;
@protocol FYInlineCardActionSource <NSObject>
@property(nonatomic,copy,readonly) NSString *inlineExpandedReadingBlockID;
@property(nonatomic,strong,readonly) NSPanel *inlineExpandedReadingPanel;
- (FYInlineBlockSnapshot *)inlineSnapshotForItem:(OCRTextItem *)item translation:(NSString *)translation stableBlockID:(NSString *)stableBlockID;
- (void)closeExpandedInlineReadingCard;
- (void)openFullInlineReadingCardForItem:(OCRTextItem *)item translation:(NSString *)translation stableBlockID:(NSString *)stableBlockID;
- (void)openInlineLearningWithSnapshot:(FYInlineBlockSnapshot *)snapshot;
@end
@interface FYInlineCardActionBinder : NSObject
- (void)wireInlineLongCardPanel:(NSPanel *)panel item:(OCRTextItem *)item translation:(NSString *)translation frame:(CGRect)frame stableBlockID:(NSString *)stableBlockID source:(id<FYInlineCardActionSource>)source;
@end
