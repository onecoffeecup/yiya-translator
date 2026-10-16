#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "../inline/FYInlineTextModels.h"
#import "FYInlineBlockSnapshot.h"
@protocol FYInlineTranslationListStateSource <NSObject>
@property(nonatomic, copy) NSString *inlineTranslationListSignature;
@property(nonatomic, copy) NSArray<FYInlineBlockSnapshot *> *inlineTranslationListSnapshots;
@end
@protocol FYInlineTranslationListInputSource <NSObject>
@property(nonatomic,strong,readonly) FYInlineLayoutResult *lastInlineLayoutResult;
@end
@protocol FYInlineTranslationListNativeActions <NSObject>
- (BOOL)isInlineTranslationListReady;
- (void)setInlineTranslationListHidden:(BOOL)hidden;
- (void)clearInlineTranslationListRows;
- (void)updateInlineTranslationListCountText:(NSString *)text;
- (void)appendInlineTranslationListRowForPlacement:(FYInlinePlacement *)placement currentSnapshots:(NSArray<FYInlineBlockSnapshot *> *)snapshots;
@end
@protocol FYInlineTranslationListLearningActions <NSObject>
- (FYInlineBlockSnapshot *)inlineSnapshotForBlock:(FYInlineTextBlock *)block translation:(NSString *)translation stableBlockID:(NSString *)stableBlockID;
- (void)openInlineLearningWithSnapshot:(FYInlineBlockSnapshot *)snapshot;
@end
@protocol FYInlineTranslationListSource <FYInlineTranslationListStateSource,FYInlineTranslationListInputSource,FYInlineTranslationListNativeActions,FYInlineTranslationListLearningActions>
@end
// Sole owner of the two original copy fields. No native views or idle receiver.
@interface FYInlineTranslationListCoordinator : NSObject
@property(nonatomic, copy) NSString *inlineTranslationListSignature;
@property(nonatomic, copy) NSArray<FYInlineBlockSnapshot *> *inlineTranslationListSnapshots;
- (void)refreshWithReceiver:(id<FYInlineTranslationListSource>)receiver;
- (void)openRowAtIndex:(NSInteger)index receiver:(id<FYInlineTranslationListSource>)receiver;
@end
