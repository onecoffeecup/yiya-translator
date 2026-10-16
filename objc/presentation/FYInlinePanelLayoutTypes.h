#pragma once
#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
@class NSFont;
typedef struct {
    NSRect frame;
    NSRect labelFrame;
    NSFont *font;
    CGFloat cornerRadius;
} InlinePanelLayout;
