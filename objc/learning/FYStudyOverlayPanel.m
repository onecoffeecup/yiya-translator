#import "FYStudyOverlayPanel.h"
@implementation FYStudyOverlayPanel
- (BOOL)canBecomeKeyWindow {return YES;}
- (BOOL)canBecomeMainWindow {return NO;}
- (void)cancelOperation:(id)sender {if(self.onEscape){self.onEscape();}else{[self orderOut:nil];}}
@end

@implementation FYOverlayDragHeader
- (NSView *)hitTest:(NSPoint)point {
    NSView *hit = [super hitTest:point];
    if (!hit) { return nil; }
    for (NSView *view = hit; view && view != self; view = view.superview) {
        if ([view isKindOfClass:NSButton.class]) { return hit; }
    }
    // Labels must not consume the drag as a text selection. Reading text lives
    // outside this header and retains native selection and copying.
    return self;
}
- (BOOL)acceptsFirstMouse:(NSEvent *)event { return YES; }
- (BOOL)mouseDownCanMoveWindow { return NO; }
- (void)mouseDown:(NSEvent *)event { [self.window performWindowDragWithEvent:event]; }
@end
