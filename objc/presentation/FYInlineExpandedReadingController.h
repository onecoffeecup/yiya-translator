#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "../ocr/FYOCRTextModels.h"
#import "../inline/FYInlineTextModels.h"
@class NSPanel, NSEvent, NSTextField, FYInlineLayoutEngine;
// Original expanded state only. The concrete synchronous receiver remains the
// compatibility facade; neither component nor callbacks retain that receiver.
@protocol FYInlineExpandedReadingStateSource <NSObject>
@property(nonatomic,strong) NSPanel *inlineExpandedReadingPanel;
@property(nonatomic,strong) id inlineExpandedReadingKeyMonitor;
@property(nonatomic,copy) NSString *inlineExpandedReadingBlockID;
@property(nonatomic) NSUInteger inlineExpandedMissingFrames;
@property(nonatomic,strong,readonly) FYInlineLayoutResult *lastInlineLayoutResult;
@end
@protocol FYInlineExpandedReadingActions <NSObject>
@property(nonatomic,strong,readonly) FYInlineLayoutEngine *inlineLayoutEngine;
- (BOOL)inlinePlacementRect:(CGRect *)outRect reason:(NSString **)outReason;
- (CGSize)expandedInlineReadingSizeForTranslation:(NSString *)translation viewport:(CGRect)viewport;
- (FYInlinePlacement *)inlinePlacementForLongCardFrame:(CGRect)frame translation:(NSString *)translation expandedReading:(BOOL)expandedReading;
- (NSPanel *)inlineLongPanelForTranslation:(NSString *)translation item:(OCRTextItem *)item frame:(CGRect)frame placement:(FYInlinePlacement *)placement;
- (void)hideOtherInlinePanelsForExpandedReading:(NSPanel *)panel;
- (void)refreshExpandedInlineReadingCardAppearanceInRect:(CGRect)viewport;
- (void)wireInlinePanelDrag:(NSPanel *)panel placement:(FYInlinePlacement *)placement;
- (void)applyInlineLongCardBody:(NSString *)translation toLabel:(NSTextField *)label cardWidth:(CGFloat)width placement:(FYInlinePlacement *)placement;
- (void)closeExpandedInlineReadingCard;
- (void)restoreOtherInlinePanelsAfterExpandedReading;
- (id)installInlineExpandedReadingMonitorWithHandler:(NSEvent *(^)(NSEvent *))handler;
- (void)removeInlineExpandedReadingMonitor:(id)monitor;
@end
@protocol FYInlineExpandedReadingSource <FYInlineExpandedReadingStateSource,FYInlineExpandedReadingActions>
@end
@interface FYInlineExpandedReadingController : NSObject
@property(nonatomic,strong) NSPanel *inlineExpandedReadingPanel;
@property(nonatomic,strong) id inlineExpandedReadingKeyMonitor;
@property(nonatomic,copy) NSString *inlineExpandedReadingBlockID;
@property(nonatomic) NSUInteger inlineExpandedMissingFrames;
- (CGSize)expandedInlineReadingSizeForTranslation:(NSString *)translation viewport:(CGRect)viewport source:(id<FYInlineExpandedReadingSource>)source;
- (void)refreshExpandedInlineReadingCardAppearanceInRect:(CGRect)viewport source:(id<FYInlineExpandedReadingSource>)source;
- (void)openFullInlineReadingCardForItem:(OCRTextItem *)item translation:(NSString *)translation stableBlockID:(NSString *)stableBlockID source:(id<FYInlineExpandedReadingSource>)source;
- (void)repositionExpandedInlineReadingCardInRect:(CGRect)viewport source:(id<FYInlineExpandedReadingSource>)source;
- (void)advanceExpandedReadingStateWithSource:(id<FYInlineExpandedReadingSource>)source;
- (void)closeExpandedInlineReadingCardWithSource:(id<FYInlineExpandedReadingSource>)source;
@end
