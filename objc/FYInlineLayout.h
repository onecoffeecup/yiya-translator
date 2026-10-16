#pragma once
//  界面贴译的自适应分组与布局组件。
//
//  设计边界（本文件只做这两件事，不碰其它系统）：
//    · FYInlineGrouper  —— 把 OCR 行按几何与阅读连续性并成文本块；
//    · FYInlineLayoutEngine —— 对同一帧的全部块统一安排译文位置。
//
//  坐标约定：
//    · 分组（FYInlineTextLine / FYInlineTextBlock）使用**归一化页面坐标**：
//      原点左下、0..1，与 Vision 的 boundingBox 一致；判定只用相对量（局部行高、
//      行距、横向重叠），因此与图像尺寸、缩放无关。
//    · 布局（FYInlineLayoutRequest.sourceFrame / viewport / 结果 frame）使用**显示区域
//      坐标**（AppKit 屏幕坐标，y 向上）。调用方必须先把 OCR 框换算到同一个显示区域，
//      映射不可用属于上游状态，不由布局器猜测。
//
//  刻意不做的事：不认页面类型、不认示例文案、不写死屏幕坐标、不按字符数当几何证据。

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import "inline/FYInlineTextModels.h"
#import "inline/FYInlineGrouping.h"
#import "inline/FYInlineTextUtilities.h"
#import <AppKit/AppKit.h>
#import "inline/FYInlineTextMeasurer.h"
#import "inline/FYInlineLayoutCalculator.h"

#import "inline/FYInlineOverlayViews.h"

NS_ASSUME_NONNULL_BEGIN

#pragma mark - 布局引擎

@interface FYInlineLayoutEngine : FYInlineLayoutCalculator <FYInlineTextMeasurementState>
@property(nonatomic, strong, readonly) FYInlineTextMeasurer *textMeasurer;
+ (instancetype)defaultEngine;
/// Original theme factory; its copied block is stored only by the measurer.
@property(nonatomic, copy, nullable) NSFont * (^fontProvider)(CGFloat size, NSFontWeight weight);
@end

NS_ASSUME_NONNULL_END
