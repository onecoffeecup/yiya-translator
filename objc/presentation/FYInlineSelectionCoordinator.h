#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "FYInlineBlockSnapshot.h"
#import "../ocr/FYOCRTextModels.h"
#import "../inline/FYInlineGrouping.h"
// Original state remains with Study/current display owners. Synchronous source
// interfaces carry values only and are never stored by this stateless policy.
@protocol FYInlineSnapshotInputSource <NSObject>
- (BOOL)captureCardInputEnabled;
- (NSUInteger)inlineSnapshotInputEpoch;
- (NSString *)inlineBlockIdentityForItem:(OCRTextItem *)item;
@end
@protocol FYInlineSelectionStateSource <NSObject>
@property(nonatomic,strong,readonly) FYInlineBlockSnapshot *inlineBlockSnapshot;
@property(nonatomic,strong,readonly) NSMutableDictionary<NSString *,NSString *> *inlineStableBlockIDs;
- (NSString *)inlineBlockIdentityForItem:(OCRTextItem *)item;
- (BOOL)inlineHostBlockID:(NSString *)stableBlockID isSelectedForItem:(OCRTextItem *)item;
@end
@interface FYInlineSelectionCoordinator : NSObject
- (NSString *)inlineBlockIdentityForItem:(OCRTextItem *)item;
- (BOOL)inlineBlockID:(NSString *)stableBlockID isSelectedForItem:(OCRTextItem *)item stateSource:(id<FYInlineSelectionStateSource>)source;
- (BOOL)inlineBlockIsSelectedForItem:(OCRTextItem *)item stateSource:(id<FYInlineSelectionStateSource>)source;
- (FYInlineBlockSnapshot *)inlineSnapshotForItem:(OCRTextItem *)item translation:(NSString *)translation stableBlockID:(NSString *)stableBlockID source:(id<FYInlineSnapshotInputSource>)source;
- (FYInlineBlockSnapshot *)inlineSnapshotForBlock:(FYInlineTextBlock *)block translation:(NSString *)translation stableBlockID:(NSString *)stableBlockID source:(id<FYInlineSnapshotInputSource>)source;
@end
