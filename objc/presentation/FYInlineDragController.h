#pragma once
#import <Foundation/Foundation.h>
#import "../inline/FYInlineTextModels.h"
@class NSPanel;
NS_ASSUME_NONNULL_BEGIN
@protocol FYInlineDragStateSource <NSObject>
@property(nonatomic,weak,nullable) NSPanel *inlineDraggingPanel;
@property(nonatomic,strong,nullable) NSTimer *inlineModifierTimer;
@property(nonatomic) BOOL inlineOptionDragArmed;
@property(nonatomic,strong,readonly,nullable) NSMutableArray<NSPanel *> *inlineTranslationPanels;
- (void)recordInlineManualOffsetForPanel:(nullable NSPanel *)panel;
- (void)applyInlineDragMode:(BOOL)armed;
@end
@protocol FYInlineDragTimerActions <NSObject>
- (NSTimer *)scheduledInlineModifierTimer;
@end
@interface FYInlineDragController : NSObject
@property(nonatomic,weak,nullable) NSPanel *inlineDraggingPanel;
@property(nonatomic,strong,nullable) NSTimer *inlineModifierTimer;
@property(nonatomic) BOOL inlineOptionDragArmed;
- (void)wireInlinePanelDrag:(NSPanel *)panel placement:(FYInlinePlacement *)placement stateSource:(id<FYInlineDragStateSource>)source;
- (void)startInlineModifierMonitorWithSource:(id<FYInlineDragStateSource>)source timerActions:(id<FYInlineDragTimerActions>)actions;
- (void)stopInlineModifierMonitorWithSource:(id<FYInlineDragStateSource>)source;
- (void)applyInlineDragMode:(BOOL)armed stateSource:(id<FYInlineDragStateSource>)source;
@end
NS_ASSUME_NONNULL_END
