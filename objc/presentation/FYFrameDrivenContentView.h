#pragma once
#import <AppKit/AppKit.h>
@protocol FYFrameDrivenGeometrySource <NSObject>
@property(nonatomic,readonly) NSRect bounds;
@property(nonatomic,strong,readonly) NSView *layoutContent;
@property(nonatomic,strong,readonly) NSLayoutConstraint *layoutWidth;
@property(nonatomic,strong,readonly) NSLayoutConstraint *layoutHeight;
@end
// Native geometry adapter; the original expression/getter order stays intact.
FOUNDATION_EXPORT void FYSyncFrameDrivenContentGeometry(id<FYFrameDrivenGeometrySource> source);
@interface FYFrameDrivenContentView : NSView <FYFrameDrivenGeometrySource>
@property(nonatomic, strong) NSView *layoutContent;
@property(nonatomic, strong) NSLayoutConstraint *layoutWidth;
@property(nonatomic, strong) NSLayoutConstraint *layoutHeight;
@end
