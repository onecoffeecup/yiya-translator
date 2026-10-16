#import "FYInlineDragController.h"
#import "../inline/FYInlineOverlayViews.h"

@implementation FYInlineDragController
- (void)wireInlinePanelDrag:(NSPanel *)panel placement:(FYInlinePlacement *)placement stateSource:(id<FYInlineDragStateSource>)source {
    __weak id<FYInlineDragStateSource> weakSelf = source;
    __weak NSPanel *weakPanel = panel;
    if ([panel.contentView isKindOfClass:FYInlineLongCardView.class]) {
        FYInlineLongCardView *card = (FYInlineLongCardView *)panel.contentView;
        // 紧凑入口点哪儿都是“点击展开”，所以不给它标题栏拖动区。
        card.titleBarHeight = placement.compactEntry ? 0 : (placement.panelPadding + placement.titleBandHeight);
        card.onDragBegan = ^{ weakSelf.inlineDraggingPanel = weakPanel; };
        card.onDragEnded = ^{ [weakSelf recordInlineManualOffsetForPanel:weakPanel]; };
    } else if ([panel.contentView isKindOfClass:FYInlinePatchView.class]) {
        FYInlinePatchView *patch = (FYInlinePatchView *)panel.contentView;
        patch.dragEnabled = weakSelf.inlineOptionDragArmed;
        patch.showsDragHint = weakSelf.inlineOptionDragArmed;
        patch.onDragBegan = ^{ weakSelf.inlineDraggingPanel = weakPanel; };
        patch.onDragEnded = ^{ [weakSelf recordInlineManualOffsetForPanel:weakPanel]; };
    }
}

- (void)startInlineModifierMonitorWithSource:(id<FYInlineDragStateSource>)source timerActions:(id<FYInlineDragTimerActions>)actions {
    if (source.inlineModifierTimer) { return; }
    source.inlineModifierTimer = [actions scheduledInlineModifierTimer];
}

- (void)stopInlineModifierMonitorWithSource:(id<FYInlineDragStateSource>)source {
    [source.inlineModifierTimer invalidate];
    source.inlineModifierTimer = nil;
    if (source.inlineOptionDragArmed) { [source applyInlineDragMode:NO]; }
}

- (void)applyInlineDragMode:(BOOL)armed stateSource:(id<FYInlineDragStateSource>)source {
    source.inlineOptionDragArmed = armed;
    for (NSPanel *panel in source.inlineTranslationPanels) {
        if (panel == source.inlineDraggingPanel) { continue; }
        panel.ignoresMouseEvents = !armed;
        NSView *content = panel.contentView;
        if ([content isKindOfClass:FYInlinePatchView.class]) {
            FYInlinePatchView *patch = (FYInlinePatchView *)content;
            patch.dragEnabled = armed;
            patch.showsDragHint = armed;
        }
    }
}
@end
