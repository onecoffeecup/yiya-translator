#import "FYOCRPixelAnalysis.h"
#import "FYContentPolicy.h"
#import <math.h>

// Modal detector thresholds: RGB mean on 0..255 pixels, dimensionless fractions.
// Keep these together for tuning; values intentionally preserve the established detector.
static const double kFYModalBrightThreshold = 150.0;
static const double kFYModalDimThreshold = 140.0;
static const double kFYModalMinColumnFraction = 0.45;
static const double kFYModalMinRowBrightFraction = 0.55;
static const double kFYModalMinRunFraction = 0.15;
static const size_t kFYModalMinRunPixels = 8;
static const double kFYModalDimColumnFraction = 0.62;

static void FYFreeExcludedMask(unsigned char **buffer) {
    free(*buffer);
    *buffer = NULL;
}

// 找出画面里那块“大白矩形”（详情弹窗 / 模态窗），返回它在**归一化底左坐标**下的范围。
// 依据：模态窗一定是一块又大又亮、轮廓连续的矩形；
// 而被压暗的底层页面虽然也有亮像素，但成不了这种又大又连片的区域。
// 找不到就返回 NO（当帧不裁剪）。
BOOL FYDetectBrightOCRContentRegion(const unsigned char *pixels,
                                      size_t width,
                                      size_t height,
                                      size_t bytesPerRow,
                                      CGRect *outNormalizedRect,
                                      BOOL *outDimmedColumns,
                                      const CGRect *exclusions,
                                      size_t exclusionCount) {
    if (!pixels || width < 8 || height < 8) { return NO; }

    // 把自己浮窗覆盖的像素预先标进一张位图。
    // 之前是对每个像素遍历一遍所有面板（13 万像素 × 20 个面板 ≈ 260 万次循环），
    // 跑在主线程上直接让界面卡住十几秒。
    __attribute__((cleanup(FYFreeExcludedMask))) unsigned char *excludedMask = NULL;
    if (exclusionCount > 0) {
        excludedMask = (unsigned char *)calloc(width * height, 1);
        if (!excludedMask) { return NO; }
        for (size_t i = 0; i < exclusionCount; i++) {
            CGRect r = exclusions[i];
            size_t x0 = (size_t)MAX(0, r.origin.x * width);
            size_t x1 = (size_t)MIN((CGFloat)width, CGRectGetMaxX(r) * width);
            size_t y0 = (size_t)MAX(0, (1.0 - CGRectGetMaxY(r)) * height);
            size_t y1 = (size_t)MIN((CGFloat)height, (1.0 - r.origin.y) * height);
            for (size_t y = y0; y < y1; y++) {
                for (size_t x = x0; x < x1; x++) { excludedMask[y * width + x] = 1; }
            }
        }
    }
    #define FUYI_EXCLUDED(px, py) (excludedMask != NULL && excludedMask[(py) * width + (px)] != 0)

    const size_t minRunColumns = MAX(kFYModalMinRunPixels, (size_t)(width * kFYModalMinRunFraction));
    const size_t minRunRows = MAX(kFYModalMinRunPixels, (size_t)(height * kFYModalMinRunFraction));

    size_t bestX0 = 0, bestXLen = 0, run = 0;
    for (size_t x = 0; x <= width; x++) {
        BOOL ok = NO;
        if (x < width) {
            size_t bright = 0, considered = 0;
            for (size_t y = 0; y < height; y++) {
                if (FUYI_EXCLUDED(x, y)) { continue; }
                const unsigned char *pixel = pixels + y * bytesPerRow + x * 4;
                considered += 1;
                if ((pixel[0] + pixel[1] + pixel[2]) / 3.0 >= kFYModalBrightThreshold) { bright += 1; }
            }
            ok = (considered >= height / 4) && (((double)bright / (double)considered) >= kFYModalMinColumnFraction);
        }
        if (ok) {
            if (run == 0) { run = 1; } else { run += 1; }
        } else {
            if (run > bestXLen) { bestXLen = run; bestX0 = x - run; }
            run = 0;
        }
    }
    if (bestXLen < minRunColumns) { return NO; }

    // 纵向：仍然只在**已确定的列范围**里找最长连续亮段 —— 必须用“亮”而不是“没被压暗”。
    // 曾经为了不切掉橙色页眉，把判据改成“有没有被压暗”，结果上半屏（被压得较浅的页面）
    // 也满足条件，弹窗范围变成 y 0.09..0.83（几乎整屏），左边栏目的译文就又冒出来了。
    // 宁可靠外层把范围向下外扩一点来容纳页眉页脚。
    size_t bestY0 = 0, bestYLen = 0;
    run = 0;
    for (size_t y = 0; y <= height; y++) {
        BOOL brightRow = NO;
        if (y < height) {
            const unsigned char *row = pixels + y * bytesPerRow;
            size_t bright = 0;
            size_t considered = 0;
            for (size_t x = bestX0; x < bestX0 + bestXLen; x++) {
                if (FUYI_EXCLUDED(x, y)) { continue; }
                const unsigned char *pixel = row + x * 4;
                if ((pixel[0] + pixel[1] + pixel[2]) / 3.0 >= kFYModalBrightThreshold) { bright += 1; }
                considered += 1;
            }
            brightRow = (considered >= bestXLen / 4) &&
                        (((double)bright / (double)considered) >= kFYModalMinRowBrightFraction);
        }
        if (brightRow) {
            if (run == 0) { run = 1; } else { run += 1; }
        } else {
            if (run > bestYLen) { bestYLen = run; bestY0 = y - run; }
            run = 0;
        }
    }
    if (bestYLen < minRunRows) { return NO; }

    // 压暗掩码：落在被压暗的列上、且位于弹窗之外的地方，属于“上一级残留文字”
    if (outDimmedColumns) {
        for (size_t x = 0; x < width; x++) { outDimmedColumns[x] = NO; }
        for (size_t x = 0; x < width; x++) {
            size_t dim = 0;
            for (size_t y = 0; y < height; y++) {
                if (FUYI_EXCLUDED(x, y)) { continue; }
                const unsigned char *pixel = pixels + y * bytesPerRow + x * 4;
                if ((pixel[0] + pixel[1] + pixel[2]) / 3.0 < kFYModalDimThreshold) { dim += 1; }
            }
            outDimmedColumns[x] = ((double)dim / (double)height) > kFYModalDimColumnFraction;
        }
    }

    // 位图 y 是从上往下，转回 Vision 的底左原点
    CGFloat nx0 = (CGFloat)bestX0 / (CGFloat)width;
    CGFloat nx1 = (CGFloat)(bestX0 + bestXLen) / (CGFloat)width;
    CGFloat nyTop = (CGFloat)bestY0 / (CGFloat)height;
    CGFloat nyBottom = (CGFloat)(bestY0 + bestYLen) / (CGFloat)height;

    *outNormalizedRect = CGRectMake(nx0, 1.0 - nyBottom, nx1 - nx0, nyBottom - nyTop);
    return YES;
}
#undef FUYI_EXCLUDED

// 判断某个文字块是不是压在半透明遮罩上（= 上一级页面残留的文字）。
// OCR 只给文字和坐标，读不出明暗，所以这里真的去采样像素：
//   弹窗正文是「深色字 + 亮底」，而被压暗的底层页面是「字和底都偏暗」。
// 用「文字外圈一点的平均亮度」近似底色：够亮才算当前这一层的内容。
BOOL FYOCRBlockSitsOnBrightBackdrop(OCRTextItem *block,
                                      const unsigned char *gray,
                                      size_t width,
                                      size_t height,
                                      size_t bytesPerRow) {
    if (!gray || width < 4 || height < 4) { return YES; }

    CGFloat minX = CGRectGetMinX(block.boundingBox) * (CGFloat)width;
    CGFloat maxX = CGRectGetMaxX(block.boundingBox) * (CGFloat)width;
    // Vision 的 y 是底左原点，位图是从上往下存，所以这里要把 y 翻过来
    CGFloat minY = (1.0 - CGRectGetMaxY(block.boundingBox)) * (CGFloat)height;
    CGFloat maxY = (1.0 - CGRectGetMinY(block.boundingBox)) * (CGFloat)height;

    // 往上/下各扩一点作为“底色”采样带（避开文字本身的笔画）
    CGFloat bandTop = MAX(0, minY - 3.0);
    CGFloat bandBottom = MIN((CGFloat)height - 1, maxY + 3.0);
    size_t x0 = (size_t)MAX(0, MIN(minX, (CGFloat)width - 1));
    size_t x1 = (size_t)MAX(0, MIN(maxX, (CGFloat)width - 1));
    if (x1 <= x0) { return YES; }

    double sum = 0;
    size_t count = 0;
    for (size_t y = (size_t)bandTop; y <= (size_t)bandBottom; y += 2) {
        // 只取文字行上下那两条窄带，不统计文字笔画本身
        if (y > (size_t)minY + 1 && y + 1 < (size_t)maxY) { continue; }
        const unsigned char *row = gray + y * bytesPerRow;
        for (size_t x = x0; x <= x1; x += 2) {
            const unsigned char *pixel = row + x * 4;
            sum += (pixel[0] + pixel[1] + pixel[2]) / 3.0;
            count += 1;
        }
    }
    if (count == 0) { return YES; }
    double mean = sum / (double)count;
    return mean >= 150.0;
}

FYOCRPixelBuffer FYCreateOCRPixelBuffer(CGImageRef image) {
    FYOCRPixelBuffer buffer = {NULL, 0, 0, 0, NULL};
    size_t imageWidth = CGImageGetWidth(image);
    size_t imageHeight = CGImageGetHeight(image);
    if (imageWidth < 2 || imageHeight < 2) { return buffer; }

    size_t width = MIN(imageWidth, (size_t)480);
    size_t height = MAX((size_t)2, (size_t)((double)imageHeight * ((double)width / (double)imageWidth)));

    // 用 RGBA 而不是纯灰度：CGBitmapContext 不支持 kCGImageAlphaNone 的灰度格式，
    // 之前传它导致 context 创建失败、缓冲变成 0x0，后面所有判断都退化成“亮底”。
    size_t stride = width * 4;
    unsigned char *pixels = (unsigned char *)calloc(height, stride);
    if (!pixels) { return buffer; }
    // 必须给颜色空间：第三个参数（colorspace）传 NULL 时 CGBitmapContextCreate 会直接失败，
    // 之前就是这样导致缓冲一直是 0x0、所有判断退化成“亮底”。
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(pixels, width, height, 8, stride, space,
                                                 kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) {
        free(pixels);
        return buffer;
    }
    CGContextSetInterpolationQuality(context, kCGInterpolationLow);
    CGContextDrawImage(context, CGRectMake(0, 0, width, height), image);

    buffer.pixels = pixels;
    buffer.width = width;
    buffer.height = height;
    buffer.bytesPerRow = CGBitmapContextGetBytesPerRow(context);
    buffer.context = context;
    return buffer;
}

void FYReleaseOCRPixelBuffer(FYOCRPixelBuffer *buffer) {
    if (buffer->context) { CGContextRelease(buffer->context); }
    if (buffer->pixels) { free(buffer->pixels); }
    buffer->context = NULL;
    buffer->pixels = NULL;
}

BOOL FYOCRModalSurroundingsAreDimmer(unsigned char *pixels, size_t width, size_t height,
                                       size_t bytesPerRow, CGRect rect) {
    if (!pixels || width == 0 || height == 0) { return NO; }
    CGRect inner = CGRectIntersection(rect, CGRectMake(0, 0, 1, 1));
    if (CGRectIsNull(inner)) { return NO; }
    CGRect outer = CGRectInset(inner, -0.08, -0.08);
    outer = CGRectIntersection(outer, CGRectMake(0, 0, 1, 1));

    double innerSum = 0, outerSum = 0, innerCount = 0, outerCount = 0;
    size_t stepX = MAX((size_t)1, width / 160);
    size_t stepY = MAX((size_t)1, height / 160);
    for (size_t y = 0; y < height; y += stepY) {
        double normalizedY = 1.0 - (double)y / (double)height;
        if (normalizedY < outer.origin.y || normalizedY > CGRectGetMaxY(outer)) { continue; }
        const unsigned char *row = pixels + y * bytesPerRow;
        for (size_t x = 0; x < width; x += stepX) {
            double normalizedX = (double)x / (double)width;
            if (normalizedX < outer.origin.x || normalizedX > CGRectGetMaxX(outer)) { continue; }
            const unsigned char *pixel = row + x * 4;
            double brightness = (pixel[0] + pixel[1] + pixel[2]) / 3.0;
            BOOL insideInner = (normalizedX >= inner.origin.x && normalizedX <= CGRectGetMaxX(inner)
                                && normalizedY >= inner.origin.y && normalizedY <= CGRectGetMaxY(inner));
            if (insideInner) { innerSum += brightness; innerCount += 1; }
            else { outerSum += brightness; outerCount += 1; }
        }
    }
    if (innerCount < 20 || outerCount < 20) { return NO; }
    double innerMean = innerSum / innerCount;
    double outerMean = outerSum / outerCount;
    return (innerMean - outerMean) > 30.0;
}

BOOL FYOCRModalRectQualifiesForCropping(CGRect rect) {
    if (rect.size.width < 0.35 || rect.size.height < 0.16) { return NO; }
    CGFloat centerX = CGRectGetMidX(rect);
    return centerX > 0.40 && centerX < 0.60;
}









static BOOL FYPlateColorNear(const unsigned char *a, const unsigned char *b) {
    return abs(a[0]-b[0])<=22 && abs(a[1]-b[1])<=22 && abs(a[2]-b[2])<=22;
}
static const unsigned char *FYPlatePixel(FYOCRPixelBuffer *buffer, CGFloat x, CGFloat y) {
    if (!isfinite(x) || !isfinite(y) || x<0 || x>=1 || y<0 || y>=1) { return NULL; }
    // CGBitmapContext row zero is the image's top; OCR has a bottom origin.
    size_t col=MIN(buffer->width-1,(size_t)(x*buffer->width));
    size_t row=MIN(buffer->height-1,(size_t)((1-y)*buffer->height));
    return buffer->pixels+row*buffer->bytesPerRow+col*4;
}
static BOOL FYPlateDominantColor(FYOCRPixelBuffer *buffer, CGRect box, unsigned char *color) {
    unsigned char samples[63][3]; NSUInteger count=0,best=0,bestIndex=0;
    for (NSUInteger row=0;row<7;row++) for (NSUInteger col=0;col<9;col++) {
        const unsigned char *p=FYPlatePixel(buffer,box.origin.x+box.size.width*(col+.5)/9,
            box.origin.y+box.size.height*(row+.5)/7);
        if (!p) { continue; }
        memcpy(samples[count++],p,3);
    }
    if (count*100<7*9*60) { return NO; }
    for (NSUInteger i=0;i<count;i++) {
        NSUInteger hits=0;
        for (NSUInteger j=0;j<count;j++) if (FYPlateColorNear(samples[i],samples[j])) { hits++; }
        if (hits>best) { best=hits;bestIndex=i; }
    }
    if (best*100<count*55) { return NO; }
    memcpy(color,samples[bestIndex],3);return YES;
}
static BOOL FYPlateBodyHasDistinctBackdrop(FYOCRPixelBuffer *buffer, CGRect box, const unsigned char *color) {
    NSUInteger distinct=0,total=0;
    for (NSUInteger row=0;row<7;row++) for (NSUInteger col=0;col<9;col++) {
        const unsigned char *p=FYPlatePixel(buffer,box.origin.x+box.size.width*(col+.5)/9,
            box.origin.y+box.size.height*(row+.5)/7);
        if (!p) { continue; }
        total++;
        if (abs(p[0]-color[0])>=45 || abs(p[1]-color[1])>=45 || abs(p[2]-color[2])>=45) { distinct++; }
    }
    // Translucent dialogue can show a textured scene. It need not have one
    // uniform color, but most of it must differ from the filled name plate.
    // An edge may clip the sampling collar; require 60% of the grid to remain
    // visible, then measure backdrop evidence only among those valid pixels.
    return total*100>=7*9*60 && distinct*100>=total*80;
}

@implementation FYOCRPixelAnalysis
+ (NSArray<OCRTextItem *> *)itemsByMarkingSpeakerLabels:(NSArray<OCRTextItem *> *)items inImage:(CGImageRef)image {
    if (!image) { return items; }
    NSArray<OCRTextItem *> *band=[FYContentPolicy subtitleBandItems:items];
    // With just a plate and a very short reply, neither row may satisfy the
    // existing text anchor. Test their pixels without changing mode rules.
    if (band.count<2 && items.count==2) {
        band=[items sortedArrayUsingComparator:^NSComparisonResult(OCRTextItem *left, OCRTextItem *right) {
            return FYOCRReadingOrder(left,right);
        }];
    }
    if (band.count<2) { return items; }
    OCRTextItem *label=band[0],*body=band[1];
    CGRect a=label.boundingBox,b=body.boundingBox;
    // The game can sit above OBS controls. The selected band and local plate
    // geometry supply evidence; its absolute position in the window does not.
    CGFloat widestBody=0;
    for (NSUInteger i=1;i<band.count;i++) widestBody=MAX(widestBody,band[i].boundingBox.size.width);
    CGFloat height=MAX(a.size.height,b.size.height),gap=CGRectGetMinY(a)-CGRectGetMaxY(b);
    if (label.lineCount>1 || label.lineTexts.count>1 ||
        [label.text rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location!=NSNotFound ||
        a.size.width<=0 || a.size.height<=0 ||
        a.size.width>MAX(widestBody*.6,height*2.5) || a.size.height<b.size.height*.35 || a.size.height>b.size.height*1.8 ||
        gap< -height*.25 || gap>height*1.2 ||
        CGRectGetMinX(a)>CGRectGetMinX(b)+height*.5) { return items; }
    FYOCRPixelBuffer buffer=FYCreateOCRPixelBuffer(image);
    if (!buffer.pixels) { return items; }
    unsigned char labelColor[3];
    CGRect bodySample=CGRectInset(b,-b.size.height*.15,-b.size.height*.1);
    BOOL confirmed=NO;
    // Tight ink bounds need a collar; smaller embedded video can instead mix
    // the collar with the body at sampling resolution. Try both, requiring the
    // same fill, distinct body and visible plate bounds for either candidate.
    for (NSUInteger attempt=0;attempt<2 && !confirmed;attempt++) {
        CGFloat padding=attempt==0 ? a.size.height*.2 : 0;
        CGRect labelSample=CGRectInset(a,-padding,-padding);
        if (!FYPlateDominantColor(&buffer,labelSample,labelColor) ||
            !FYPlateBodyHasDistinctBackdrop(&buffer,bodySample,labelColor)) { continue; }
        // A broad scene color or a highlight spanning the whole body fails.
        NSUInteger outside=0,total=0;
        for (NSUInteger i=0;i<5;i++) {
            const unsigned char *above=FYPlatePixel(&buffer,CGRectGetMinX(a)+a.size.width*(i+.5)/5,
                CGRectGetMaxY(a)+a.size.height);
            const unsigned char *right=FYPlatePixel(&buffer,CGRectGetMaxX(a)+height*3,
                CGRectGetMinY(a)+a.size.height*(i+.5)/5);
            if (above) { total++;if (!FYPlateColorNear(above,labelColor)) outside++; }
            if (right) { total++;if (!FYPlateColorNear(right,labelColor)) outside++; }
        }
        confirmed=total==10 && outside>=8;
    }
    FYReleaseOCRPixelBuffer(&buffer);
    if (!confirmed) { return items; }
    NSMutableArray *result=[items mutableCopy];
    NSUInteger index=[items indexOfObjectIdenticalTo:label];
    if (index!=NSNotFound) {
        OCRTextItem *copy=FYCopyInlineOCRItem(label);copy.speakerLabel=YES;result[index]=copy;
    }
    return result;
}

+ (NSArray<OCRTextItem *> *)items:(NSArray<OCRTextItem *> *)blocks
           scopedToModalInImage:(CGImageRef)image
                    exclusions:(NSArray<NSValue *> *)exclusionValues {
    if (!image || blocks.count < 2) { return blocks; }
    FYOCRPixelBuffer buffer = FYCreateOCRPixelBuffer(image);
    if (!buffer.pixels) { return blocks; }
    NSUInteger count = exclusionValues.count;
    CGRect *exclusions = count ? calloc(count, sizeof(CGRect)) : NULL;
    if (count && !exclusions) { FYReleaseOCRPixelBuffer(&buffer); return blocks; }
    for (NSUInteger i = 0; i < count; i++) { exclusions[i] = exclusionValues[i].rectValue; }
    CGRect region = CGRectZero;
    BOOL qualifies = FYDetectBrightOCRContentRegion(buffer.pixels, buffer.width, buffer.height,
        buffer.bytesPerRow, &region, NULL, exclusions, count) &&
        FYOCRModalRectQualifiesForCropping(region) &&
        FYOCRModalSurroundingsAreDimmer(buffer.pixels, buffer.width, buffer.height, buffer.bytesPerRow, region);
    free(exclusions);
    FYReleaseOCRPixelBuffer(&buffer);
    if (!qualifies) { return blocks; }

    // 亮块和暗背景本身不足以区分邮件/照片与弹窗。还必须有位于该面板底部的
    // 独立关闭按钮；正文里提到“关闭”、画面角落的“返回”都不能触发裁剪。
    BOOL hasDismiss = NO;
    CGRect footer = CGRectMake(NSMinX(region), MAX((CGFloat)0, NSMinY(region) - 0.13),
                               NSWidth(region), NSHeight(region) * 0.35 + 0.13);
    for (OCRTextItem *item in blocks) {
        NSString *text = [FYNormalizeOCRTextForComparison(item.text) lowercaseString];
        if (![@[@"閉じる", @"とじる", @"关闭", @"關閉", @"close"] containsObject:text]) { continue; }
        if (NSWidth(item.boundingBox) > 0.22 || NSHeight(item.boundingBox) > 0.09 ||
            !CGRectContainsRect(footer, item.boundingBox)) { continue; }
        BOOL covered = NO;
        for (NSValue *value in exclusionValues) {
            if (CGRectIntersectsRect(value.rectValue, item.boundingBox)) { covered = YES; break; }
        }
        if (!covered) { hasDismiss = YES; break; }
    }
    if (!hasDismiss) { return blocks; }
    NSArray *scoped = [self items:blocks inModalRegion:region exclusions:exclusionValues];
    NSMutableArray *inside = [NSMutableArray array];
    for (OCRTextItem *item in scoped) {
        // 页眉/页脚可以向上下延伸；左右边界保持贴合面板，避免重新纳入左栏日期。
        if (NSMinX(item.boundingBox) >= NSMinX(region) - 0.005 &&
            NSMaxX(item.boundingBox) <= NSMaxX(region) + 0.005) { [inside addObject:item]; }
    }
    return inside.count >= 2 ? inside : blocks;
}

+ (NSArray<OCRTextItem *> *)items:(NSArray<OCRTextItem *> *)blocks inModalRegion:(CGRect)modalRect exclusions:(NSArray<NSValue *> *)exclusionValues {
    // 弹窗的橙色页眉/页脚不够亮，纵向外扩一点，避免把弹窗自己的标题丢掉。
    // 不能扩太多，否则上一层页面的文字会重新落进范围里（实测 0.18 会把左侧栏目带回来）。
    CGRect grown = CGRectInset(modalRect, -0.04, -0.13);
    NSMutableArray<OCRTextItem *> *kept = [NSMutableArray array];
    for (OCRTextItem *block in blocks) {
        if (!CGRectContainsRect(grown, block.boundingBox)) { continue; }
        // 我们自己贴的译文面板会盖在弹窗正文上，OCR 会把面板上的字也读出来。
        // 这一类是我们自己画的，直接按面板位置排除，不再当作页面内容。
        BOOL overlapsOwnPanel = NO;
        for (NSValue *value in exclusionValues) {
            CGRect panelRect = value.rectValue;
            CGRect intersection = CGRectIntersection(panelRect, block.boundingBox);
            if (CGRectIsNull(intersection)) { continue; }
            CGFloat blockArea = block.boundingBox.size.width * block.boundingBox.size.height;
            CGFloat overlapArea = intersection.size.width * intersection.size.height;
            if (blockArea > 0 && (overlapArea / blockArea) >= 0.5) { overlapsOwnPanel = YES; break; }
        }
        if (overlapsOwnPanel) { continue; }
        [kept addObject:block];
    }
    // 过滤后剩得太少说明判断不可靠，宁可不裁，避免整屏不翻
    if (kept.count < 2) { return blocks; }
    return kept;
}
@end
