#import "FYFrameDrivenContentView.h"

void FYSyncFrameDrivenContentGeometry(id<FYFrameDrivenGeometrySource> source) {
    source.layoutWidth.constant = NSWidth(source.bounds);
    source.layoutHeight.constant = NSHeight(source.bounds);
    source.layoutContent.frame = source.bounds;
}

@implementation FYFrameDrivenContentView
- (instancetype)initWithFrame:(NSRect)frame {
    if ((self = [super initWithFrame:frame])) {
        self.autoresizesSubviews = NO;
        _layoutContent = [[NSView alloc] initWithFrame:self.bounds];
        _layoutContent.translatesAutoresizingMaskIntoConstraints = NO;
        [self addSubview:_layoutContent];
        _layoutWidth = [_layoutContent.widthAnchor constraintEqualToConstant:NSWidth(self.bounds)];
        _layoutHeight = [_layoutContent.heightAnchor constraintEqualToConstant:NSHeight(self.bounds)];
        [NSLayoutConstraint activateConstraints:@[_layoutWidth, _layoutHeight]];
    }
    return self;
}
- (void)syncLayoutGeometry { FYSyncFrameDrivenContentGeometry(self); }
- (void)setFrameSize:(NSSize)size {
    [super setFrameSize:size];
    [self syncLayoutGeometry];
}
- (void)layout {
    [self syncLayoutGeometry];
    [super layout];
}
@end
