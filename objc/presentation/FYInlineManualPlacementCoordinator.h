#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "../inline/FYInlineTextModels.h"
@class NSPanel;
NS_ASSUME_NONNULL_BEGIN
@protocol FYInlineManualPlacementStateSource <NSObject>
@property(nonatomic,strong,nullable) NSMutableDictionary<NSString *,NSValue *> *inlineManualOffsets;
@property(nonatomic,strong,nullable) NSMutableDictionary<NSString *,NSNumber *> *inlineManualOffsetAge;
- (NSString *)inlineManualOffsetKeyForText:(NSString *)text normalizedBox:(CGRect)box;
@end
@protocol FYInlineManualPlacementNativeActions <NSObject>
- (void)clearInlineDraggingPanel;
- (nullable NSString *)identifierForManualInlinePanel:(NSPanel *)panel;
- (CGRect)frameForManualInlinePanel:(NSPanel *)panel;
- (void)setManualInlinePanel:(NSPanel *)panel frame:(CGRect)frame display:(BOOL)display;
- (nullable FYInlineLayoutResult *)currentLayoutForManualPlacement;
- (BOOL)inlinePlacementRect:(CGRect *)rect reason:(NSString * _Nullable * _Nullable)reason;
- (void)recordInlineManualDiagnosticText:(NSString *)text offset:(CGSize)offset;
@end
@interface FYInlineManualPlacementCoordinator : NSObject <FYInlineManualPlacementStateSource>
@property(nonatomic,strong,nullable) NSMutableDictionary<NSString *,NSValue *> *inlineManualOffsets;
@property(nonatomic,strong,nullable) NSMutableDictionary<NSString *,NSNumber *> *inlineManualOffsetAge;
- (NSString *)inlineManualOffsetKeyForText:(NSString *)text normalizedBox:(CGRect)box;
- (nullable NSValue *)inlineManualOffsetForText:(NSString *)text normalizedBox:(CGRect)box stateSource:(id<FYInlineManualPlacementStateSource>)source;
- (void)recordInlineManualOffsetForPanel:(nullable NSPanel *)panel stateSource:(id<FYInlineManualPlacementStateSource>)source nativeActions:(id<FYInlineManualPlacementNativeActions>)actions;
- (void)maintainOffsetsForPlacements:(NSArray<FYInlinePlacement *> *)placements stateSource:(id<FYInlineManualPlacementStateSource>)source;
@end
NS_ASSUME_NONNULL_END
