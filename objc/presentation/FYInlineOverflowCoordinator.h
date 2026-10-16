#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "../ocr/FYOCRTextModels.h"
#import "../inline/FYInlineTextModels.h"
@class NSPanel;
@protocol FYInlineOverflowPolicyState <NSObject>
@property(nonatomic,strong) NSArray<NSDictionary *> *inlineOverflowEntries;
@property(nonatomic) NSUInteger inlineOverflowCount;
@property(nonatomic) NSUInteger inlineOverflowPanelCount;
@property(nonatomic) NSUInteger inlineOverflowCandidateCount;
@property(nonatomic) NSUInteger inlineOverflowCandidateFrames;
@property(nonatomic) NSTimeInterval inlineOverflowEmptySince;
@end
@protocol FYInlineOverflowResources <NSObject>
@property(nonatomic,strong) NSPanel *inlineOverflowPanel;
@property(nonatomic,strong) NSPanel *inlineOverflowChoicePanel;
@property(nonatomic,strong) id inlineOverflowChoiceKeyMonitor;
@property(nonatomic,strong,readonly) NSPanel *inlineExpandedReadingPanel;
@end
@protocol FYInlineOverflowEntryActions <NSObject>
- (NSString *)inlineOverflowTitleForBlockText:(NSString *)text;
- (NSString *)inlineOverflowFallbackTitle;
- (NSTimeInterval)inlineOverflowTime;
- (void)inlineHostExpireInlineOverflowEntryIfNeeded;
- (void)hideInlineOverflowEntryForExpandedReading;
- (void)buildInlineOverflowEntryForViewport:(CGRect)viewport;
- (void)resizeInlineOverflowEntryWithTitle:(NSString *)title viewport:(CGRect)viewport;
- (void)positionInlineOverflowEntryInViewport:(CGRect)viewport;
- (BOOL)inlineOverflowEntryIsVisible;
- (void)orderInlineOverflowEntryFront;
- (void)setInlineOverflowEntryIgnoresMouseEvents:(BOOL)value;
- (void)closeInlineOverflowEntryPanel;
@end
@protocol FYInlineOverflowChoiceActions <NSObject>
- (void)showInlineOverflowList;
- (void)closeInlineOverflowChoice;
- (void)openFullInlineReadingCardForItem:(OCRTextItem *)item translation:(NSString *)translation stableBlockID:(NSString *)stableBlockID;
@end
@protocol FYInlineOverflowSource <FYInlineOverflowPolicyState,FYInlineOverflowResources,FYInlineOverflowEntryActions,FYInlineOverflowChoiceActions>
@end
@interface FYInlineOverflowCoordinator : NSObject <FYInlineOverflowPolicyState>
@property(nonatomic,strong) NSArray<NSDictionary *> *inlineOverflowEntries;
@property(nonatomic) NSUInteger inlineOverflowCount;
@property(nonatomic) NSUInteger inlineOverflowPanelCount;
@property(nonatomic) NSUInteger inlineOverflowCandidateCount;
@property(nonatomic) NSUInteger inlineOverflowCandidateFrames;
@property(nonatomic) NSTimeInterval inlineOverflowEmptySince;
- (void)updateInlineOverflowEntryWithPlacements:(NSArray<FYInlinePlacement *> *)placements items:(NSDictionary<NSString *,OCRTextItem *> *)itemsByBlockID viewport:(CGRect)viewport unplaceable:(NSUInteger)unplaceable source:(id<FYInlineOverflowSource>)source;
- (void)expireInlineOverflowEntryIfNeededWithSource:(id<FYInlineOverflowSource>)source;
- (void)showInlineOverflowChooserWithSource:(id<FYInlineOverflowSource>)source;
- (NSString *)overflowRowTitleForEntry:(NSDictionary *)entry;
- (void)openInlineOverflowRowAtIndex:(NSInteger)index source:(id<FYInlineOverflowSource>)source;
@end
