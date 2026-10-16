#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "../ocr/FYOCRTextModels.h"
#import "../inline/FYInlineLayoutCalculator.h"
@class NSPanel;
NS_ASSUME_NONNULL_BEGIN
// Immutable carrier of the original synchronous locals. Strong references
// retain their original mutable aliases; no extra early copy or native source.
@interface FYInlineDisplayFrame : NSObject
@property(nonatomic,strong,readonly) FYInlineLayoutResult *result;
@property(nonatomic,strong,readonly,nullable) FYInlineLayoutResult *previous;
@property(nonatomic,readonly) NSRect viewport;
@property(nonatomic,strong,readonly) NSArray<OCRTextItem *> *items;
@property(nonatomic,strong,readonly) NSDictionary<NSString *,OCRTextItem *> *itemsByBlockID;
@property(nonatomic,strong,readonly) NSString *identity;
@property(nonatomic,strong,readonly) NSString *contentKey;
@property(nonatomic,strong,readonly) NSString *geometryKey;
@property(nonatomic,strong,readonly) NSString *reason;
- (instancetype)initWithResult:(FYInlineLayoutResult *)result previous:(nullable FYInlineLayoutResult *)previous viewport:(NSRect)viewport items:(NSArray<OCRTextItem *> *)items itemsByBlockID:(NSDictionary<NSString *,OCRTextItem *> *)itemsByBlockID identity:(NSString *)identity contentKey:(NSString *)contentKey geometryKey:(NSString *)geometryKey reason:(NSString *)reason;
@end

@interface FYInlineDisplayCoordinator : NSObject
@property(nonatomic, strong, nullable) NSMutableArray<NSPanel *> *inlineLongCardPanels;
@property(nonatomic, strong, nullable) NSMutableDictionary<NSString *, NSPanel *> *inlinePanelsByBlockID;
@property(nonatomic, strong, nullable) NSMutableDictionary<NSString *, NSString *> *inlineStableBlockIDs;
@property(nonatomic, strong, nullable) NSMutableArray<NSPanel *> *inlineTranslationPanels;
@property(nonatomic) NSUInteger lastInlineCompactEntryCount;
@property(nonatomic, copy, nullable) NSArray<NSValue *> *lastInlineLayoutBoxes;
@property(nonatomic, copy, nullable) NSString *lastInlineLayoutContentKey;
@property(nonatomic, copy, nullable) NSDictionary *lastInlineLayoutDebugContext;
@property(nonatomic) NSRect lastInlineLayoutDebugViewport;
@property(nonatomic, copy, nullable) NSString *lastInlineLayoutGeometryKey;
@property(nonatomic, strong, nullable) FYInlineLayoutResult *lastInlineLayoutResult;
@property(nonatomic, copy, nullable) NSString *lastInlineRenderGeometryToken;
@property(nonatomic, copy, nullable) NSArray<OCRTextItem *> *lastInlineRenderedItems;
@property(nonatomic, copy, nullable) NSArray<NSString *> *lastInlineRenderedTranslations;
@property(nonatomic, copy, nullable) NSString *lastInlineTranslationKey;
@property(nonatomic) NSUInteger lastInlineUnplaceableCount;
- (NSString *)inlineTranslationIdentityForTranslations:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items;
- (void)showInlineTranslations:(NSArray<NSString *> *)translations forItems:(NSArray<OCRTextItem *> *)items placementRect:(NSRect)windowFrame;
- (void)applyInlineDisplayFrame:(FYInlineDisplayFrame *)frame;
- (BOOL)hasMinorOCRJitterForItems:(NSArray<OCRTextItem *> *)items contentKey:(NSString *)contentKey geometryKey:(NSString *)geometryKey;
@end
NS_ASSUME_NONNULL_END
