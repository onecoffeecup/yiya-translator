#import "FYOCRManager.h"
#import <Vision/Vision.h>

@implementation FYContentModeStability
- (NSInteger)observeMode:(NSInteger)detected {
    if (detected==self.detectedMode) { self.candidateMode=detected;self.candidateHits=0;return self.detectedMode; }
    if (self.candidateMode==detected) self.candidateHits+=1;
    else { self.candidateMode=detected;self.candidateHits=1; }
    if (self.candidateHits>=2) { self.detectedMode=detected;self.candidateHits=0; }
    return self.detectedMode;
}
@end

BOOL FYApplyOCRRefinement(NSArray<OCRTextItem *> *coarse, BOOL autoFit,
    NSString *(^recognizer)(CGRect, NSArray<OCRTextItem *> **, NSError **), void (^acceptedObserver)(void),
    NSString **outText, NSArray<OCRTextItem *> **outBlocks) {
    NSString *fineText=nil;NSArray<OCRTextItem *> *fineBlocks=nil;
    if (!FYRecognizeOCRRefinement(coarse,autoFit,recognizer,&fineText,&fineBlocks)) return NO;
    if (acceptedObserver) acceptedObserver();
    NSArray *merged=[FYOCRManager mergeCoarseItems:coarse refinedItems:fineBlocks];
    if (outBlocks) *outBlocks=merged;
    if (outText) *outText=[[merged valueForKey:@"text"] componentsJoinedByString:@"\n"];
    return YES;
}

BOOL FYRecognizeOCRRefinement(NSArray<OCRTextItem *> *coarse, BOOL autoFit,
    NSString *(^recognizer)(CGRect, NSArray<OCRTextItem *> **, NSError **), NSString **outText, NSArray<OCRTextItem *> **outBlocks) {
    CGRect region=CGRectZero;
    if (!FYOCRRefinementRegion(coarse,autoFit,FYOCRFittedTextArea(coarse),&region)) return NO;
    NSError *error=nil;NSArray<OCRTextItem *> *blocks=nil;
    NSString *text=recognizer(region,&blocks,&error);
    if (error || FYNormalizeOCRTextForComparison(text).length==0) return NO;
    if (outText) *outText=text;
    if (outBlocks) *outBlocks=blocks;
    return YES;
}

CGFloat FYOCRFittedTextArea(NSArray<OCRTextItem *> *blocks) {
    CGFloat minX=1,minY=1,maxX=0,maxY=0;BOOL any=NO;
    for (OCRTextItem *block in blocks) {
        if (FYNormalizeOCRTextForComparison(block.text).length<2) continue;
        minX=MIN(minX,CGRectGetMinX(block.boundingBox));minY=MIN(minY,CGRectGetMinY(block.boundingBox));
        maxX=MAX(maxX,CGRectGetMaxX(block.boundingBox));maxY=MAX(maxY,CGRectGetMaxY(block.boundingBox));any=YES;
    }
    return any ? (maxX-minX)*(maxY-minY) : 0;
}

@implementation FYOCRStabilityOwner
- (BOOL)observe:(NSString *)normalized equivalent:(BOOL (^)(NSString *, NSString *))equivalent {
    if (equivalent(normalized,self.candidate)) self.count++;
    else { self.candidate=normalized; self.count=1; }
    return self.count>=2;
}
- (void)reset { self.candidate=@""; self.count=0; }
@end

BOOL FYOCRRefinementRegion(NSArray<OCRTextItem *> *blocks, BOOL autoFit, CGFloat fittedArea, CGRect *outRegion) {
    if (!autoFit || !(fittedArea > 0 && fittedArea <= .16) || !blocks.count) return NO;
    CGFloat minX=1,minY=1,maxX=0,maxY=0; BOOL any=NO;
    for (OCRTextItem *block in blocks) {
        if (FYNormalizeOCRTextForComparison(block.text).length < 2) continue;
        CGRect b=block.boundingBox;
        minX=MIN(minX,CGRectGetMinX(b));minY=MIN(minY,CGRectGetMinY(b));
        maxX=MAX(maxX,CGRectGetMaxX(b));maxY=MAX(maxY,CGRectGetMaxY(b));any=YES;
    }
    if (!any) return NO;
    minX=MAX(0,minX-.03);minY=MAX(0,minY-.03);
    maxX=MIN(1,maxX+.03);maxY=MIN(1,maxY+.03);
    if (outRegion) *outRegion=CGRectMake(minX,minY,MAX((CGFloat).05,maxX-minX),MAX((CGFloat).05,maxY-minY));
    return YES;
}

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
        double normalizedY = (double)y / (double)height;
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

@implementation OCRTextItem
@end

NSString *FYNormalizeOCRTextForComparison(NSString *value) {
    if (!value) { return @""; }
    NSString *trimmed = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSMutableString *result = [NSMutableString stringWithCapacity:trimmed.length];
    NSCharacterSet *spaces = NSCharacterSet.whitespaceAndNewlineCharacterSet;
    for (NSUInteger index = 0; index < trimmed.length; index++) {
        unichar character = [trimmed characterAtIndex:index];
        if (character == 0x3000 || [spaces characterIsMember:character]) { continue; }
        [result appendFormat:@"%C", character];
    }
    return result;
}

static CGFloat FYOCRTextCoverage(NSString *text, NSString *covered) {
    if (text.length == 0) { return 0; }
    NSMutableDictionary<NSString *, NSNumber *> *pool = [NSMutableDictionary dictionary];
    for (NSUInteger index = 0; index < covered.length; index++) {
        NSString *unit = [covered substringWithRange:NSMakeRange(index, 1)];
        pool[unit] = @(pool[unit].integerValue + 1);
    }
    NSUInteger coveredCount = 0;
    for (NSUInteger index = 0; index < text.length; index++) {
        NSString *unit = [text substringWithRange:NSMakeRange(index, 1)];
        NSInteger available = pool[unit].integerValue;
        if (available > 0) { pool[unit] = @(available - 1); coveredCount += 1; }
    }
    return (CGFloat)coveredCount / (CGFloat)text.length;
}

static NSComparisonResult FYOCRReadingOrder(OCRTextItem *left, OCRTextItem *right) {
    CGFloat delta = CGRectGetMaxY(left.boundingBox) - CGRectGetMaxY(right.boundingBox);
    if (fabs(delta) > 0.025) { return delta > 0 ? NSOrderedAscending : NSOrderedDescending; }
    if (left.boundingBox.origin.x < right.boundingBox.origin.x) { return NSOrderedAscending; }
    if (left.boundingBox.origin.x > right.boundingBox.origin.x) { return NSOrderedDescending; }
    return NSOrderedSame;
}

@implementation FYOCRManager
+ (void)splitSpeakerAndBody:(NSString *)text speaker:(NSString **)outSpeaker body:(NSString **)outBody {
    NSString *speaker=nil,*body=text ?: @"";
    NSArray<NSString *> *lines=[body componentsSeparatedByString:@"\n"];
    if (lines.count>=2) {
        NSString *first=[lines.firstObject stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (first.length>0 && ([self looksLikeSpeakerName:first] || [self looksLikeSpeakerFurigana:first])) {
            NSUInteger consumed=1;speaker=first;
            if (lines.count>=3) {
                NSString *second=[lines[1] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                if ([self looksLikeSpeakerFurigana:first] && [self looksLikeSpeakerName:second]) {
                    speaker=[NSString stringWithFormat:@"%@ %@",first,second];consumed=2;
                }
            }
            body=[[lines subarrayWithRange:NSMakeRange(consumed,lines.count-consumed)] componentsJoinedByString:@"\n"];
        }
    }
    if (outSpeaker) *outSpeaker=speaker;
    if (outBody) *outBody=body;
}
+ (NSString *)postprocessedTextForItems:(NSArray<OCRTextItem *> *)items renderedTexts:(NSSet<NSString *> *)renderedTexts blocks:(NSArray<OCRTextItem *> **)outBlocks {
    items=[self itemsExcludingOwnOverlay:items renderedTexts:renderedTexts];
    items=[self resolveOverlappingItems:items];
    if (outBlocks) *outBlocks=items;
    return [[items valueForKey:@"text"] componentsJoinedByString:@"\n"] ?: @"";
}
+ (NSString *)recognizeEnlargedImage:(CGImageRef)image visionRegion:(CGRect)region
    recognizer:(NSString *(^)(CGImageRef, NSArray<OCRTextItem *> **, NSError **))recognizer
    blocks:(NSArray<OCRTextItem *> **)outBlocks error:(NSError **)error {
    CGRect crop=CGRectZero;
    CGImageRef scaled=[self copyEnlargedImage:image visionRegion:region pixelCrop:&crop];
    if (!scaled) return @"";
    NSArray<OCRTextItem *> *localBlocks=nil;
    NSString *text=recognizer(scaled,&localBlocks,error);
    [self remapItems:localBlocks fromPixelCrop:crop imageSize:CGSizeMake(CGImageGetWidth(image),CGImageGetHeight(image))];
    if (outBlocks) *outBlocks=localBlocks;
    CGImageRelease(scaled);
    return text;
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

+ (NSInteger)contentModeForItems:(NSArray<OCRTextItem *> *)blocks fallback:(NSInteger)fallbackSegment {
    if (blocks.count == 0) { return fallbackSegment; }

    // UI 特征优先否决：画面里有「戻る / 詳細 / メニュー」这类按钮，或者是文本密集的列表/菜单页，
    // 就走贴译整屏，而不是把某条宽行当对白。
    // 现实依据：列表页里也有很宽的行（实测 0.26），光凭“有没有宽行”分不出对白和列表。
    if ([self looksLikeUIFrame:blocks]) { return 1; }

    // 再看有没有成形的对白框：有就按对白处理，别被街景招牌/公告牌带偏
    if ([self subtitleBandItems:blocks].count > 0) { return 0; }

    // 一帧只读到角落操作提示，或短台词被 OCR 截成 1~2 字时，不据此切换已确认的模式。
    if (blocks.count <= 2 && [self UITokenHitCount:blocks] == 0) {
        BOOL hasCentralDialogueFragment = NO;
        BOOL onlyCornerHints = YES;
        for (OCRTextItem *block in blocks) {
            CGRect box = block.boundingBox;
            if ([self containsJapaneseKana:block.text] && CGRectGetMidY(box) >= 0.10 &&
                CGRectGetMidY(box) <= 0.38 && CGRectGetMinX(box) >= 0.18 &&
                CGRectGetMaxX(box) <= 0.78 && box.size.height >= 0.035) {
                hasCentralDialogueFragment = YES;
            }
            if (!(CGRectGetMinX(box) >= 0.80 && CGRectGetMidY(box) <= 0.12)) {
                onlyCornerHints = NO;
            }
        }
        if (hasCentralDialogueFragment || onlyCornerHints) { return fallbackSegment; }
    }

    return 1;
}

// 说话人名字框：短、没有句末标点、不含平假名（实测 `萩尾九段` / `片霧秋兵` / `ルード`）。
// 这类框会被 OCR 单独读成一行，或单独成一簇被当成「选项」，
// 于是在学习库里各占一条「最近台词」，把 5 条额度从真台词那里挤掉。
+ (BOOL)looksLikeSpeakerName:(NSString *)raw {
    NSString *text = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length == 0 || text.length > 10) { return NO; }
    NSCharacterSet *enders = [NSCharacterSet characterSetWithCharactersInString:@"。．.！!？?"];
    if ([enders characterIsMember:[text characterAtIndex:text.length - 1]]) { return NO; }
    BOOL hasNameGlyph = NO;
    for (NSUInteger index = 0; index < text.length; index++) {
        unichar character = [text characterAtIndex:index];
        // 带平假名的一律不是名字行（`うん、空いてるよ` / `我の手落ちだ` 都要留作正文）。
        if (character >= 0x3040 && character <= 0x309F) { return NO; }
        if ((character >= 0x4E00 && character <= 0x9FFF) ||
            (character >= 0x30A0 && character <= 0x30FF)) { hasNameGlyph = YES; }
    }
    return hasNameGlyph;
}

// 名字框上方的假名注音被 OCR 单独读成一行（实测 `かたぎりし、ゆうの` / `＜だん`）。
+ (BOOL)looksLikeSpeakerFurigana:(NSString *)raw {
    NSString *text = [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (text.length < 2 || text.length > 12) { return NO; }
    NSCharacterSet *enders = [NSCharacterSet characterSetWithCharactersInString:@"。．.！!？?"];
    if ([enders characterIsMember:[text characterAtIndex:text.length - 1]]) { return NO; }
    NSUInteger kana = 0, glyphs = 0;
    for (NSUInteger index = 0; index < text.length; index++) {
        unichar character = [text characterAtIndex:index];
        if (character == ' ' || character == '\t') { continue; }
        glyphs += 1;
        if ((character >= 0x3040 && character <= 0x30FF) ||
            (character >= 0x31F0 && character <= 0x31FF)) { kana += 1; }
    }
    return glyphs > 0 && kana * 10 >= glyphs * 6;
}

// 一簇全是名字/注音（且至少有一行是名字），才当成名字框 —— 宽度上限防止把整行正文吞进来。
+ (BOOL)looksLikeSpeakerLabelCluster:(NSArray<OCRTextItem *> *)cluster {
    if (cluster.count == 0 || cluster.count > 3) { return NO; }
    BOOL hasName = NO;
    CGFloat widest = 0;
    for (OCRTextItem *item in cluster) {
        widest = MAX(widest, item.boundingBox.size.width);
        if ([self looksLikeSpeakerName:item.text]) { hasName = YES; continue; }
        if (![self looksLikeSpeakerFurigana:item.text]) { return NO; }
    }
    return hasName && widest <= 0.35;
}

// 单独一行是不是名字框的一部分：名字本身，或紧贴其上方的假名注音。
+ (BOOL)isSpeakerLabelItem:(OCRTextItem *)item inPool:(NSArray<OCRTextItem *> *)pool {
    if ([self looksLikeSpeakerName:item.text]) { return item.boundingBox.size.width <= 0.35; }
    if (![self looksLikeSpeakerFurigana:item.text]) { return NO; }
    for (OCRTextItem *other in pool) {
        if (other == item || ![self looksLikeSpeakerName:other.text]) { continue; }
        // 底左原点：注音的 midY 更大（更靠上），名字紧贴在它下面。
        if (CGRectGetMidY(other.boundingBox) >= CGRectGetMidY(item.boundingBox)) { continue; }
        if (CGRectGetMidY(item.boundingBox) - CGRectGetMaxY(other.boundingBox) > 0.05) { continue; }
        CGFloat overlap = MIN(CGRectGetMaxX(item.boundingBox), CGRectGetMaxX(other.boundingBox)) -
                          MAX(CGRectGetMinX(item.boundingBox), CGRectGetMinX(other.boundingBox));
        if (overlap >= item.boundingBox.size.width * 0.5) { return YES; }
    }
    return NO;
}

// 整帧只有说话人名字（可以带注音）—— 正文没读到。这种帧写进学习库只会白占一条额度。
// 必须真的有一行是名字：短句 `はい` 也满足“假名行”的判定，不能被当成名字框丢掉。
+ (BOOL)dialogueFrameIsSpeakerLabelOnly:(NSArray<NSString *> *)lines {
    if (lines.count == 0) { return NO; }
    BOOL hasName = NO;
    for (NSString *line in lines) {
        if ([self looksLikeSpeakerName:line]) { hasName = YES; continue; }
        if ([self looksLikeSpeakerFurigana:line]) { continue; }
        return NO;
    }
    return hasName;
}

// 把 band 拆成「对白」和「选项」两组。
// 做法：先按垂直间距把 band 分成一簇一簇（连续的行 ≤0.12，隔开的就是不同簇），
// 再把位于画面下半部的簇判为对白框，其余在上方的簇判为选项。
// 依据：视觉小说的对白框固定在画面下方，选项浮在上方；
// 这样就算选项自身的行距比较大，也不会把两个选项拆到两组里去。
+ (void)splitDialogueAndOptions:(NSArray<OCRTextItem *> *)band
                     allBlocks:(NSArray<OCRTextItem *> *)allBlocks
                      dialogue:(NSMutableArray<OCRTextItem *> *)outDialogue
                       options:(NSMutableArray<OCRTextItem *> *)outOptions {
    if (band.count == 0) { return; }

    // band 已按从上到下排序；这里切成簇
    NSMutableArray<NSMutableArray<OCRTextItem *> *> *clusters = [NSMutableArray array];
    NSMutableArray<OCRTextItem *> *current = nil;
    for (OCRTextItem *item in band) {
        if (!current) {
            current = [NSMutableArray arrayWithObject:item];
            [clusters addObject:current];
            continue;
        }
        CGFloat gap = fabs(CGRectGetMidY(current.lastObject.boundingBox) - CGRectGetMidY(item.boundingBox));
        if (gap <= 0.12) {
            [current addObject:item];
        } else {
            current = [NSMutableArray arrayWithObject:item];
            [clusters addObject:current];
        }
    }

    // 簇里最宽的一条所在位置，就是这一簇贴在画面的哪一带
    NSMutableArray<NSNumber *> *clusterWidths = [NSMutableArray array];
    for (NSMutableArray<OCRTextItem *> *cluster in clusters) {
        CGFloat widest = 0;
        for (OCRTextItem *item in cluster) { widest = MAX(widest, item.boundingBox.size.width); }
        [clusterWidths addObject:@(widest)];
    }

    // 选“对白簇”：最宽的成型行在画面下半部的那个簇；没有就退回整屏最宽的一条所在的簇
    NSInteger dialogueCluster = -1;
    CGFloat bestWidth = -1;
    for (NSUInteger index = 0; index < clusters.count; index++) {
        NSMutableArray<OCRTextItem *> *cluster = clusters[index];
        for (OCRTextItem *item in cluster) {
            if (![self isFormedTextLine:item]) { continue; }
            if (CGRectGetMidY(item.boundingBox) > 0.42) { continue; }
            if (item.boundingBox.size.width > bestWidth) {
                bestWidth = item.boundingBox.size.width;
                dialogueCluster = (NSInteger)index;
            }
        }
    }
    if (dialogueCluster < 0) {
        for (NSUInteger index = 0; index < clusters.count; index++) {
            CGFloat widest = clusterWidths[index].doubleValue;
            if (widest > bestWidth) {
                bestWidth = widest;
                dialogueCluster = (NSInteger)index;
            }
        }
    }

    // 名字/注音框紧贴在对白框上方，却会被拆成独立一簇丢进「选项」。
    // 实测 `萩尾九段`（名字框）就被标成「选项」单独记了一条学习记录。
    // 这里把它连同紧邻上方的注音一起并回对白框。
    NSInteger labelRunStart = dialogueCluster;
    while (labelRunStart > 0 && [self looksLikeSpeakerLabelCluster:clusters[labelRunStart - 1]]) { labelRunStart -= 1; }

    for (NSUInteger index = 0; index < clusters.count; index++) {
        if ((NSInteger)index >= labelRunStart && (NSInteger)index <= dialogueCluster) {
            if (outDialogue) { [outDialogue addObjectsFromArray:clusters[index]]; }
        } else {
            if (outOptions) { [outOptions addObjectsFromArray:clusters[index]]; }
        }
    }

    // 选项区离对白框往往比较远，band 的“紧收拢”会把它整个漏掉。
    // 这里补一遍：把 band 之外、但和对白框**水平对齐**的行也当作选项收进来。
    // 对齐标准取得比较严（重叠 ≥ 较窄那条的 55%），因为街景招牌通常只和对白框擦边。
    if (outOptions && dialogueCluster >= 0) {
        OCRTextItem *dialogueAnchor = nil;
        CGFloat anchorWidth = 0;
        for (OCRTextItem *item in clusters[dialogueCluster]) {
            if (item.boundingBox.size.width > anchorWidth) {
                anchorWidth = item.boundingBox.size.width;
                dialogueAnchor = item;
            }
        }
        if (dialogueAnchor) {
            NSArray<OCRTextItem *> *pool = allBlocks ?: band;
            for (OCRTextItem *item in pool) {
                if ([outOptions containsObject:item]) { continue; }
                if ([clusters[dialogueCluster] containsObject:item]) { continue; }
                if (FYNormalizeOCRTextForComparison(item.text).length < 2) { continue; }
                if (item.boundingBox.size.width < 0.10) { continue; }
                // 名字框/注音不是选项：实测 `萩尾九段` 会被这条补漏收进选项，单独占一条记录。
                if ([self isSpeakerLabelItem:item inPool:pool]) { continue; }
                // 只补对白框上方的
                if (CGRectGetMidY(item.boundingBox) <= CGRectGetMidY(dialogueAnchor.boundingBox)) { continue; }
                CGFloat overlapLeft = MAX(CGRectGetMinX(item.boundingBox), CGRectGetMinX(dialogueAnchor.boundingBox));
                CGFloat overlapRight = MIN(CGRectGetMaxX(item.boundingBox), CGRectGetMaxX(dialogueAnchor.boundingBox));
                CGFloat overlap = overlapRight - overlapLeft;
                CGFloat narrower = MIN(item.boundingBox.size.width, dialogueAnchor.boundingBox.size.width);
                if (overlap <= 0 || overlap < narrower * 0.55) { continue; }
                [outOptions addObject:item];
            }
        }
    }
}

+ (BOOL)containsJapaneseKana:(NSString *)value {
    for (NSUInteger index = 0; index < value.length; index++) {
        unichar character = [value characterAtIndex:index];
        if ((character >= 0x3040 && character <= 0x30ff) || (character >= 0x31f0 && character <= 0x31ff)) {
            return YES;
        }
    }
    return NO;
}

// 从整窗 OCR 里挑出“对白框”那几行：取最低的一条长行当锚点，再收拢它附近的行。
// 目的：街景招牌、公告牌这类环境文本不该混进对白翻译。
// 对白/选项的文字块：幅面够大、字数够多。街景招牌、图标标签这类零碎短文本天然被排除。
+ (BOOL)isFormedTextLine:(OCRTextItem *)block {
    NSString *normalized = FYNormalizeOCRTextForComparison(block.text);
    if (normalized.length >= 8 && block.boundingBox.size.width >= 0.20) { return YES; }
    // 0.15 太贴近现实边缘：对白框被 UI 遮住一半时宽度会掉到 0.13 左右，
    // 只差一点点就被判成“不成型”，整条对白就丢了。放宽到 0.12。
    if (normalized.length >= 6 && block.boundingBox.size.width >= 0.12) { return YES; }
    return NO;
}

// 挑出“对白 + 选项”这些需要翻译的文字块。
// 做法：以画面**下半部**里最宽的一条成型行作锚点（视觉小说的对白框在下半部，而且通常最宽），
// 再把与它水平大幅重叠、纵向邻接的块一起收进来。
// 注意 Vision 的 boundingBox 是底左原点：y 越大越靠近画面顶端。
// 能不能当“对白框”的锚点。
// 对白框的现实特征：① 贴在画面很靠下的位置 ② 框里有一条像台词的宽行。
// 判得严一点很重要 —— 文本密集的功能 UI 里也有不少宽行，放松了就会把 UI 误判成对白、
// 于是整屏文字被塞进字幕窗，而该贴译的内容反而没人管。
// “短句对白”锚点：只在对白框通篇短句时兜底使用。
// 门槛刻意比 IsDialogueAnchorCandidate 低（实测「思い出した。」是 6 字 / 0.13 宽）。
+ (BOOL)isShortDialogueAnchor:(OCRTextItem *)block {
    NSString *normalized = FYNormalizeOCRTextForComparison(block.text);
    if (normalized.length < 4) { return NO; }
    if (block.boundingBox.size.height < 0.026) { return NO; }
    if (CGRectGetMidY(block.boundingBox) > 0.45) { return NO; }
    if (block.boundingBox.size.width < 0.06) { return NO; }
    // 纯数字/日期样式的一小串不当对白
    return YES;
}

+ (BOOL)isUnpunctuatedSingleLineDialogue:(NSString *)text box:(CGRect)box {
    NSString *normalized = FYNormalizeOCRTextForComparison(text);
    return normalized.length >= 4 && normalized.length <= 14 && [self containsJapaneseKana:normalized] &&
        box.size.height >= 0.043 && box.size.width >= 0.08 && box.size.width <= 0.30 &&
        CGRectGetMinX(box) >= 0.18 && CGRectGetMaxX(box) <= 0.78 &&
        CGRectGetMidY(box) >= 0.10 && CGRectGetMidY(box) <= 0.38;
}

+ (BOOL)isCornerHelpButton:(OCRTextItem *)block {
    CGRect box = block.boundingBox;
    return CGRectGetMinX(box) >= 0.80 && CGRectGetMidY(box) <= 0.12 &&
        [FYNormalizeOCRTextForComparison(block.text) containsString:@"操作説明"];
}

// 单行对白：整屏只有一句台词（没有名字框、没有第二行）。
// 之前“短句兜底”要求它和相邻行堆叠，于是单行对白被误杀（band=0 → 被判成界面贴译）。
// 台词几乎都以句末标点结尾，而街景招牌通常没有 —— 用这个区分。
+ (BOOL)isSingleLineDialogue:(OCRTextItem *)block {
    NSString *normalized = FYNormalizeOCRTextForComparison(block.text);
    if (normalized.length < 4) { return NO; }
    // 门槛放到 0.05：台词本来就短（实测「行くぞ。」只有 0.08 宽）。
    // 真正的防误判靠“必须以句末标点结尾”，不靠宽度。
    if (block.boundingBox.size.width < 0.05) { return NO; }
    if (block.boundingBox.size.height < 0.026) { return NO; }
    if (CGRectGetMidY(block.boundingBox) > 0.45) { return NO; }
    NSCharacterSet *enders = [NSCharacterSet characterSetWithCharactersInString:@"。！!？?…・、"];
    if ([enders characterIsMember:[normalized characterAtIndex:normalized.length - 1]]) { return YES; }
    // 视觉小说的单行台词不一定有标点；名字框也可能被 OCR 完全漏掉。
    return [self isUnpunctuatedSingleLineDialogue:normalized box:block.boundingBox];
}

+ (BOOL)isDialogueAnchor:(OCRTextItem *)block {
    if (![self isFormedTextLine:block]) { return NO; }
    if (block.boundingBox.size.height < 0.026) { return NO; }
    CGFloat midY = CGRectGetMidY(block.boundingBox);
    if (midY > 0.32) { return NO; }
    CGFloat width = block.boundingBox.size.width;
    NSUInteger length = FYNormalizeOCRTextForComparison(block.text).length;
    return width >= 0.22 || length >= 10;
}

+ (NSArray<OCRTextItem *> *)subtitleBandItems:(NSArray<OCRTextItem *> *)blocks {
    // 锚点不要只看“整屏最宽”：选项里出现「・・・・」这类省略号时可能比对白还宽，
    // 那样会把选项当锚点、真正的对白反而被排除。
    // 也**不再**退回“画面里最低的成型行” —— 那正是把密集文本 UI 误判成对白的元凶。
    // 找不到真正的对白锚点就返回空，让判别走 UI/贴译路线。
    OCRTextItem *anchor = nil;
    BOOL usedShortAnchorFallback = NO;
    for (OCRTextItem *block in blocks) {
        if (![self isDialogueAnchor:block]) { continue; }
        if (!anchor || block.boundingBox.size.width > anchor.boundingBox.size.width) { anchor = block; }
    }

    // 兜底：对白框里**通篇都是短句**时，上面一条都当不了锚点。
    // 真实例子：「思い出した。」6 字/0.13 宽 + 名字「？？？」——整框没有长行，
    // 结果字幕带为空、一个字都不翻。
    // 但不能见到短行就当对白（散落的街景招牌也是短行），
    // 所以要求它**和另一行紧挨着堆叠**：对白框的行距很紧，招牌之间不会这么近。
    // 注意：anchor 可能已经被设成一个“勉强合格”的错读（实测名字框的 `？？？`
    // 被 OCR 读成平假名 `ことと`，长度够格但其实是噪声）。
    // 这时也要走兜底 —— 否则真正的那句「思い出した。」永远进不来。
    // 判定标准是：当前 anchor **是否真的和相邻行堆叠**（孤零零一条不算对白）。
    // 只对**弱锚点**（短而窄）要求堆叠：孤零零一条短行不像对白框。
    // 长行锚点不受影响 —— 单行对白框本来就靠一条长行成立（有测试守着这一点）。
    if (anchor) {
        BOOL weakAnchor = anchor.boundingBox.size.width < 0.16
            && FYNormalizeOCRTextForComparison(anchor.text).length < 10;
        if (weakAnchor) {
            BOOL anchorStacked = NO;
            for (OCRTextItem *other in blocks) {
                if (other == anchor) { continue; }
                if (FYNormalizeOCRTextForComparison(other.text).length < 2) { continue; }
                if (fabs(CGRectGetMidY(other.boundingBox) - CGRectGetMidY(anchor.boundingBox)) >= 0.10) { continue; }
                CGFloat otherLeft = MAX(CGRectGetMinX(other.boundingBox), CGRectGetMinX(anchor.boundingBox));
                CGFloat otherRight = MIN(CGRectGetMaxX(other.boundingBox), CGRectGetMaxX(anchor.boundingBox));
                if (otherRight - otherLeft <= 0) { continue; }
                anchorStacked = YES;
                break;
            }
            // 没堆叠也要留意：它可能只是名字框，而真正的对白在下面更宽的那条
            if (!anchorStacked) {
                OCRTextItem *better = nil;
                for (OCRTextItem *other in blocks) {
                    if (other == anchor || ![self isShortDialogueAnchor:other]) { continue; }
                    if (other.boundingBox.size.width <= anchor.boundingBox.size.width) { continue; }
                    if (!better || other.boundingBox.size.width > better.boundingBox.size.width) { better = other; }
                }
                if (better) {
                    anchor = better;
                    usedShortAnchorFallback = YES;
                } else {
                    anchor = nil;
                }
            }
        }
    }

    if (!anchor) {
        // 单行对白：允许单独一条以句末标点结尾的短句当锚点
        for (OCRTextItem *block in blocks) {
            if (![self isSingleLineDialogue:block]) { continue; }
            anchor = block;
            usedShortAnchorFallback = YES;
            break;
        }
    }

    if (!anchor) {
        for (OCRTextItem *block in blocks) {
            if (![self isShortDialogueAnchor:block]) { continue; }
            CGFloat midY = CGRectGetMidY(block.boundingBox);
            BOOL stacked = NO;
            for (OCRTextItem *other in blocks) {
                if (other == block) { continue; }
                if (FYNormalizeOCRTextForComparison(other.text).length < 2) { continue; }
                if (fabs(CGRectGetMidY(other.boundingBox) - midY) >= 0.10) { continue; }
                // 同一组文字框水平上要对得上
                CGFloat overlapLeft = MAX(CGRectGetMinX(other.boundingBox), CGRectGetMinX(block.boundingBox));
                CGFloat overlapRight = MIN(CGRectGetMaxX(other.boundingBox), CGRectGetMaxX(block.boundingBox));
                if (overlapRight - overlapLeft <= 0) { continue; }
                stacked = YES;
                break;
            }
            if (!stacked) { continue; }
            if (!anchor || block.boundingBox.size.width > anchor.boundingBox.size.width) {
                anchor = block;
                usedShortAnchorFallback = YES;
            }
        }
    }
    if (!anchor) { return @[]; }

    // 兜底否决：这一组里如果没有任何“像对白”的实质长行（够宽或够长），
    // 那它就不是对白框，而是招牌/按钮之类，宁可不翻。
    BOOL hasSubstantialLine = NO;
    for (OCRTextItem *block in blocks) {
        if (block.boundingBox.size.width >= 0.20) { hasSubstantialLine = YES; break; }
        if (FYNormalizeOCRTextForComparison(block.text).length >= 8 && block.boundingBox.size.width >= 0.15) {
            hasSubstantialLine = YES;
            break;
        }
    }
    // 短句兜底路径不能再用“必须有长行”否决 —— 整框都是短句正是它要处理的情况，
    // 它已经用“和相邻行紧挨堆叠”把散落的招牌挡在外面了。
    if (!hasSubstantialLine && !usedShortAnchorFallback) { return @[]; }

    NSMutableArray<OCRTextItem *> *candidates = [NSMutableArray array];
    for (OCRTextItem *block in blocks) {
        if (block == anchor) { continue; }
        if (FYNormalizeOCRTextForComparison(block.text).length < 2) { continue; }
        // 宽度门槛故意放宽到 0.04：对白框里的短句本来就很窄
        // （实测「平気。」只有 0.06 宽、「それより、」0.10），
        // 旧门槛 0.10 会把它们直接剔除 —— 用户看到的就是“第一句没翻译”。
        // 真正防止把菜单/招牌收进来的是下面扩张循环里的“水平重叠 + 紧邻”双条件。
        if (block.boundingBox.size.width < 0.04) { continue; }
        [candidates addObject:block];
    }

    NSMutableArray<OCRTextItem *> *band = [NSMutableArray arrayWithObject:anchor];
    for (NSInteger direction = 0; direction < 2; direction++) {
        CGFloat frontierMidY = CGRectGetMidY(anchor.boundingBox);
        while (YES) {
            OCRTextItem *next = nil;
            CGFloat bestGap = CGFLOAT_MAX;
            for (OCRTextItem *candidate in candidates) {
                CGFloat gap = CGRectGetMidY(candidate.boundingBox) - frontierMidY;
                if (direction == 0 && gap >= 0) { continue; }
                if (direction == 1 && gap <= 0) { continue; }
                // 收拢窗口要“紧”：只把真正连续的相邻行算作一段。
                // 放太宽（曾经是 0.35）会把选项区和对白框连成一片，拆不分家。
                // 但仍需要一点余量：对白框里第一行常和后面几行隔得较开
                // （实测「平気。」与下一行差 0.062），窗口太紧会把首行切掉。
                if (fabs(gap) >= 0.20) { continue; }
                // 水平重叠要占较窄那一条的一半以上：同一组文字框通常对齐，
                // 而街景招牌/背景文字与对白框只是擦边重叠，会被这一条挡住。
                CGFloat overlapLeft = MAX(CGRectGetMinX(candidate.boundingBox), CGRectGetMinX(anchor.boundingBox));
                CGFloat overlapRight = MIN(CGRectGetMaxX(candidate.boundingBox), CGRectGetMaxX(anchor.boundingBox));
                CGFloat overlap = overlapRight - overlapLeft;
                CGFloat narrower = MIN(candidate.boundingBox.size.width, anchor.boundingBox.size.width);
                if (overlap <= 0 || overlap < narrower * 0.5) { continue; }
                if (fabs(gap) < bestGap) {
                    next = candidate;
                    bestGap = fabs(gap);
                }
            }
            if (!next) { break; }
            [band addObject:next];
            [candidates removeObject:next];
            frontierMidY = CGRectGetMidY(next.boundingBox);
        }
    }

    [band sortUsingComparator:^NSComparisonResult(OCRTextItem *left, OCRTextItem *right) {
        CGFloat leftMidY = CGRectGetMidY(left.boundingBox);
        CGFloat rightMidY = CGRectGetMidY(right.boundingBox);
        if (fabs(leftMidY - rightMidY) < 0.01) { return NSOrderedSame; }
        // 底左原点：midY 大的在画面上方，按从上到下输出
        return leftMidY > rightMidY ? NSOrderedAscending : NSOrderedDescending;
    }];
    return band;
}

// 判定“这一帧看起来像功能界面”：小按钮、菜单词、密集短文本、贴边文字
// 画面里出现几个游戏 UI 特有的按钮/菜单词？
// 这是区分“功能 UI”和“剧情对白”最可靠的单一信号 ——
// 新闻、列表、菜单页一定带「戻る / 詳細 / メニュー」这类词，对白框不会。
//
// 匹配必须精确：早期用 containsString 会误判 ——
// 日文那边的 "River Books" 会命中 "ok"，对白 "これでプレゼントはOK。" 也会命中 "ok"。
+ (BOOL)textHitsUIToken:(NSString *)text {
    NSString *normalized = FYNormalizeOCRTextForComparison(text);
    if (normalized.length == 0) { return NO; }
    NSString *lower = normalized.lowercaseString;

    // 日文按钮词：整条相等，或者出现在开头（「詳細を見る」「戻る」这类）
    NSArray<NSString *> *japaneseTokens = @[@"戻る", @"戻", @"閉じる", @"詳細", @"次へ",
                                            @"決定", @"設定", @"メニュー", @"スキップ"];
    for (NSString *token in japaneseTokens) {
        if ([normalized isEqualToString:token] || [normalized hasPrefix:token]) { return YES; }
    }

    // 拉丁词：必须是独立词，不能在别的单词里（避免 "Books" → "ok"）
    NSArray<NSString *> *latinTokens = @[@"back", @"close", @"menu", @"next", @"ok",
                                         @"cancel", @"skip", @"setting", @"settings", @"web"];
    NSCharacterSet *letters = [NSCharacterSet letterCharacterSet];
    for (NSString *token in latinTokens) {
        NSRange searchRange = NSMakeRange(0, lower.length);
        while (searchRange.length > 0) {
            NSRange found = [lower rangeOfString:token options:0 range:searchRange];
            if (found.location == NSNotFound) { break; }
            BOOL leftFree = (found.location == 0) ||
                            ![letters characterIsMember:[lower characterAtIndex:found.location - 1]];
            NSUInteger after = found.location + found.length;
            BOOL rightFree = (after >= lower.length) ||
                             ![letters characterIsMember:[lower characterAtIndex:after]];
            if (leftFree && rightFree) { return YES; }
            NSUInteger next = found.location + found.length;
            if (next >= lower.length) { break; }
            searchRange = NSMakeRange(next, lower.length - next);
        }
    }
    return NO;
}

+ (NSUInteger)UITokenHitCount:(NSArray<OCRTextItem *> *)blocks {
    NSUInteger tokenHitCount = 0;
    for (OCRTextItem *block in blocks) {
        if ([self textHitsUIToken:block.text]) { tokenHitCount += 1; }
    }
    return tokenHitCount;
}

+ (BOOL)isFurigana:(OCRTextItem *)small nearLargerLineInItems:(NSArray<OCRTextItem *> *)blocks {
    CGRect box = small.boundingBox;
    NSString *text = FYNormalizeOCRTextForComparison(small.text);
    if (text.length < 2 || box.size.width > 0.14 || box.size.height > 0.035) { return NO; }
    NSUInteger kanaCount = 0;
    for (NSUInteger index = 0; index < text.length; index++) {
        unichar character = [text characterAtIndex:index];
        if ((character >= 0x3040 && character <= 0x30ff) ||
            (character >= 0x31f0 && character <= 0x31ff)) { kanaCount += 1; }
    }
    if (kanaCount * 4 < text.length * 3) { return NO; }
    for (OCRTextItem *larger in blocks) {
        if (larger == small) { continue; }
        CGRect parent = larger.boundingBox;
        if (parent.size.width < box.size.width * 1.6 || parent.size.height < box.size.height * 1.5) { continue; }
        if (CGRectGetMidY(box) <= CGRectGetMidY(parent) || CGRectGetMidY(box) - CGRectGetMaxY(parent) > 0.05) { continue; }
        CGFloat overlap = MIN(CGRectGetMaxX(box), CGRectGetMaxX(parent)) - MAX(CGRectGetMinX(box), CGRectGetMinX(parent));
        if (overlap >= box.size.width * 0.65) { return YES; }
    }
    return NO;
}

+ (BOOL)looksLikeUIFrame:(NSArray<OCRTextItem *> *)blocks {
    NSUInteger smallBoxCount = 0;
    NSUInteger edgeCount = 0;
    NSUInteger wideLineCount = 0;
    NSUInteger textBlockCount = 0;
    CGFloat totalWidth = 0;
    NSUInteger tokenHitCount = [self UITokenHitCount:blocks];

    for (OCRTextItem *block in blocks) {
        NSString *normalized = FYNormalizeOCRTextForComparison(block.text);
        if (normalized.length == 0) { continue; }
        textBlockCount += 1;
        totalWidth += block.boundingBox.size.width;

        BOOL smallBox = normalized.length <= 8 && block.boundingBox.size.height < 0.036 &&
            block.boundingBox.size.width < 0.20 && ![self isFurigana:block nearLargerLineInItems:blocks];
        if (smallBox) { smallBoxCount += 1; }
        if (block.boundingBox.size.width >= 0.32) { wideLineCount += 1; }

        BOOL nearEdge = block.boundingBox.origin.y < 0.10 || CGRectGetMaxY(block.boundingBox) > 0.90;
        if (nearEdge && normalized.length <= 12) { edgeCount += 1; }
    }

    if (tokenHitCount >= 2) { return YES; }
    if (tokenHitCount >= 1 && (smallBoxCount >= 2 || edgeCount >= 3)) { return YES; }
    if (smallBoxCount >= 4) { return YES; }
    if (blocks.count >= 5 && smallBoxCount >= 3) { return YES; }
    // 贴边文字很多、且完全没有宽行 —— 但这必须**同时**带上 UI 按钮词才算数。
    // 单独用贴边信号太弱：对白游戏的字幕框本身就贴着画面底部，
    // 实测城镇对白帧 edge=4（其中还包含我们自己浮窗的文字），会把对白误判成 UI。
    if (edgeCount >= 4 && wideLineCount == 0 && tokenHitCount >= 1) { return YES; }

    // 文本密集 = 列表 / 菜单 / 新闻页。
    // 判据用“实质行数”（够宽、够长的行），实测能干净分开：
    //   新闻列表页 8 行，对白帧 3 行。纯招牌画面只有 1~2 行。
    // 不用“平均宽度”，因为街景招牌会把平均值拉低，反而误伤对白帧。
    NSUInteger substantialLineCount = 0;
    for (OCRTextItem *block in blocks) {
        NSString *normalized = FYNormalizeOCRTextForComparison(block.text);
        if (normalized.length == 0) { continue; }
        CGFloat width = block.boundingBox.size.width;
        if (width >= 0.15) { substantialLineCount += 1; continue; }
        if (normalized.length >= 8 && width >= 0.13 && block.boundingBox.size.height >= 0.030) {
            substantialLineCount += 1;
        }
    }
    if (substantialLineCount >= 6) { return YES; }

    (void)textBlockCount;
    (void)totalWidth;
    return NO;
}

// OCR 常把紧邻对白的小按钮粘进同一行：实测 `思い出した。` 被读成 `思い出した。使用`。
// 直接发去翻译，模型会照着输出「想起来了。使用」—— 按钮文字混进了字幕。
// 规则：句末标点之后只剩一小段**纯汉字**（2~4 字），且整串里有假名，就把它当按钮切掉。
+ (NSString *)dialogueTextWithoutTrailingButton:(NSString *)text {
    NSString *trimmed = (text ? [text stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"");
    if (trimmed.length == 0) { return trimmed; }

    NSCharacterSet *kanaSet = [NSCharacterSet characterSetWithCharactersInString:
        @"ぁあぃいぅうぇえぉおかがきぎくぐけげこごさざしじすずせぜそぞただちぢっつづてでとどなにぬねのはばぱひびぴふぶぷへべぺほぼぽまみむめもゃやゅゆょよらりるれろゎわゐゑをんァアィイゥウェエォオカガキギクグケゲコゴサザシジスズセゼソゾタダチヂッツヅテデトドナニヌネノハバパヒビピフブプヘベペホボポマミムメモャヤュユョヨラリルレロヮワヰヱヲンヴー"];
    BOOL hasKana = NO;
    for (NSUInteger index = 0; index < trimmed.length; index++) {
        if ([kanaSet characterIsMember:[trimmed characterAtIndex:index]]) { hasKana = YES; break; }
    }
    if (!hasKana) { return trimmed; }

    // 从末尾往前吃掉 2~4 个纯汉字，并要求它前面是句末标点
    NSUInteger end = trimmed.length;
    NSUInteger runStart = end;
    while (runStart > 0) {
        unichar character = [trimmed characterAtIndex:runStart - 1];
        if (character >= 0x4E00 && character <= 0x9FFF) { runStart -= 1; continue; }
        break;
    }
    NSUInteger hanRun = end - runStart;
    if (hanRun < 2 || hanRun > 4 || runStart == 0) { return trimmed; }

    NSCharacterSet *sentenceEnd = [NSCharacterSet characterSetWithCharactersInString:@"。．.!！?？、，,…」』）)"];
    if (![sentenceEnd characterIsMember:[trimmed characterAtIndex:runStart - 1]]) { return trimmed; }

    return [[trimmed substringToIndex:runStart] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
}

+ (CGImageRef)copyEnlargedImage:(CGImageRef)image visionRegion:(CGRect)region pixelCrop:(CGRect *)outCrop {
    size_t imageWidth = CGImageGetWidth(image);
    size_t imageHeight = CGImageGetHeight(image);
    if (imageWidth < 2 || imageHeight < 2) { return NULL; }

    // Region and OCR boxes use Vision's bottom-left origin; CGImage cropping
    // uses the top-left origin. Convert both the crop and its returned boxes.
    CGRect crop = CGRectMake(floor(region.origin.x * imageWidth),
                             floor((1.0 - region.origin.y - region.size.height) * imageHeight),
                             MAX((size_t)2, floor(region.size.width * imageWidth)),
                             MAX((size_t)2, floor(region.size.height * imageHeight)));
    crop = CGRectIntersection(crop, CGRectMake(0, 0, imageWidth, imageHeight));
    if (crop.size.width < 2 || crop.size.height < 2) { return NULL; }

    CGImageRef cropped = CGImageCreateWithImageInRect(image, crop);
    if (!cropped) { return NULL; }

    // 放大 2 倍，但对最长边设硬上限：超过约 1800px 之后 OCR 精度基本不再提升，
    // 耗时却随像素数线性增长 —— 之前上限 4000 会跑出 3000x950 这种巨图，一轮好几秒。
    size_t scaledWidth = MIN((size_t)(crop.size.width * 2.0), (size_t)1800);
    size_t scaledHeight = MIN((size_t)(crop.size.height * 2.0), (size_t)1800);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, scaledWidth, scaledHeight, 8, 0, space,
                                                 kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) {
        CGImageRelease(cropped);
        return NULL;
    }
    CGContextSetInterpolationQuality(context, kCGInterpolationHigh);
    CGContextDrawImage(context, CGRectMake(0, 0, scaledWidth, scaledHeight), cropped);
    CGImageRef scaled = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    CGImageRelease(cropped);
    if (!scaled) { return NULL; }

    if (outCrop) { *outCrop = crop; }
    return scaled;
}

+ (void)remapItems:(NSArray<OCRTextItem *> *)items fromPixelCrop:(CGRect)crop imageSize:(CGSize)imageSize {
    CGFloat baseX = crop.origin.x / imageSize.width, baseY = 1.0 - CGRectGetMaxY(crop) / imageSize.height;
    CGFloat scaleX = crop.size.width / imageSize.width, scaleY = crop.size.height / imageSize.height;
    for (OCRTextItem *block in items) {
        CGRect b = block.boundingBox;
        block.boundingBox = CGRectMake(baseX + b.origin.x * scaleX, baseY + b.origin.y * scaleY,
                                       b.size.width * scaleX, b.size.height * scaleY);
        CGRect last = block.lastLineBox;
        if (!CGRectIsEmpty(last)) {
            block.lastLineBox = CGRectMake(baseX + last.origin.x * scaleX, baseY + last.origin.y * scaleY,
                                          last.size.width * scaleX, last.size.height * scaleY);
        }
    }
}

- (NSString *)recognizeTextInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)languageSegment error:(NSError **)error {
    __block NSString *recognizedText = @"";
    __block NSError *requestError = nil;

    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest *request, NSError *innerError) {
        if (innerError) {
            requestError = innerError;
            return;
        }

        NSMutableArray<NSString *> *lines = [NSMutableArray array];
        for (VNRecognizedTextObservation *observation in request.results) {
            VNRecognizedText *candidate = [[observation topCandidates:1] firstObject];
            NSString *line = candidate.string;
            if (line.length > 0) {
                [lines addObject:line];
            }
        }
        recognizedText = [FYOCRManager textFromRecognizedLines:lines];
    }];

    request.recognitionLevel = fastOCR ? VNRequestTextRecognitionLevelFast : VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = !fastOCR;
    request.recognitionLanguages = languageSegment == 1 ? @[@"en-US"] : @[@"ja-JP"];
    // minimumTextHeight 是**相对图像高度的比例**，所以固定值会在不同窗口尺寸下失效：
    // 实测 2727×1536 截图时 0.02 正好，但运行时窗口是 1710×963（更小），
    // 对白文字占到归一化 0.054 —— 0.02 就把它当“太小的字”漏掉了，表现为整句对白消失。
    // 改成按“绝对像素”目标换算：至少要能读到约 28px 高的字，随图像高度自适应。
    CGFloat imageHeight = (CGFloat)CGImageGetHeight(image);
    // 实测：对白文字高 52px，但 minH 设成 28px 仍读不到，要设到 48px 才读到。
    // Vision 的这个阈值不是“小于就丢弃”的线性开关，实际有效值比文字高度略低几像素。
    CGFloat targetTextPixels = fastOCR ? 32.0 : 48.0;
    CGFloat adaptiveMinH = imageHeight > 0 ? (targetTextPixels / imageHeight) : 0.02;
    if (adaptiveMinH < 0.005) { adaptiveMinH = 0.005; }
    if (adaptiveMinH > 0.10) { adaptiveMinH = 0.10; }
    request.minimumTextHeight = adaptiveMinH;
    if (self.configurationObserver) {
        self.configurationObserver(fastOCR, languageSegment, CGImageGetWidth(image), CGImageGetHeight(image), adaptiveMinH);
    }

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];
    BOOL ok = [handler performRequests:@[request] error:error];
    if (!ok) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"LiveCaptionTranslator"
                                         code:900
                                     userInfo:@{NSLocalizedDescriptionKey: @"OCR 引擎执行失败，已跳过这一轮。"}];
        }
        return @"";
    }
    if (requestError && error) { *error = requestError; }
    return recognizedText ?: @"";
}

// 这两串是「译芽」自己画在屏幕上的状态栏文字（状态行 + 句数行）。
// 它们常常正好压在目标窗口上（实测在左下角），于是被下一轮 OCR 读回来当成正文：
// 混进字幕带、占住锚点位置，把真正的对白行挤出字幕带（实测「平気。」就是这么丢的）。
+ (BOOL)isOwnOverlayText:(NSString *)raw {
    NSString *t = raw ? [raw stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet] : @"";
    if (t.length == 0) { return NO; }
    NSString *lower = t.lowercaseString;
    // 翻译全失败时状态串会长成「翻译失败：<服务端报错>」，形状不固定，用前缀识别
    if ([t hasPrefix:@"翻译失败："] || [t hasPrefix:@"翻译失败:"]) { return YES; }
    NSArray<NSString *> *needles = @[@"译文已更新", @"自动判别", @"翻译界面", @"正在翻译",
                                     @"等待文本稳定", @"已暂停", @"本次 ", @"OCr ".lowercaseString];
    // 短且**完全没有日文假名/汉字**的碎片：`？？？` 之类的字形被误读成拉丁字母
    // （实测名字框读成 `iee`、`ことと`）。这类东西发去翻译只会得到编造的译文。
    if (t.length <= 6) {
        BOOL hasKanaOrKanji = NO;
        for (NSUInteger index = 0; index < t.length; index++) {
            unichar character = [t characterAtIndex:index];
            if ((character >= 0x3040 && character <= 0x30FF) ||
                (character >= 0x4E00 && character <= 0x9FFF)) { hasKanaOrKanji = YES; break; }
        }
        if (!hasKanaOrKanji) { return YES; }
    }

    // 状态行被 OCR 截断成片段时（实测 `翻译 0.6s 总 0.8s`）关键词会丢，但**计时格式**还在。
    // 游戏正文里不会出现 `0.6s` 这种「数字.数字s」的秒表写法，所以这条很安全。
    BOOL hasTimingPattern = NO;
    {
        NSRegularExpression *regex = [NSRegularExpression regularExpressionWithPattern:@"[0-9]+\\.[0-9]+s"
                                                                              options:0
                                                                                error:NULL];
        if (regex) {
            NSRange full = NSMakeRange(0, t.length);
            hasTimingPattern = [regex firstMatchInString:t options:0 range:full] != nil;
        }
    }
    if (hasTimingPattern) { return YES; }

    BOOL hasNeedle = NO;
    for (NSString *needle in needles) {
        if ([t containsString:needle] || [lower containsString:needle.lowercaseString]) { hasNeedle = YES; break; }
    }
    if (!hasNeedle) { return NO; }
    // 状态行一定带数字（秒数）。这里放宽到“含数字”即可：
    // OCR 常把它读花（实测 `译文已要新・OCR 0.25南译0.3550.55）。••`），
    // 原来要求含「秒/句/s」就漏过了 —— 于是这行乱码混进字幕带、被当成台词送去翻译，
    // 模型自然给出一句完全不相干的译文。
    BOOL hasDigit = NO;
    for (NSUInteger index = 0; index < t.length; index++) {
        unichar character = [t characterAtIndex:index];
        if (character >= '0' && character <= '9') { hasDigit = YES; break; }
    }
    if (hasDigit) { return YES; }

    BOOL looksStatus = [t containsString:@"s"] || [t containsString:@"S"] || [t containsString:@"秒"];
    BOOL looksCount = [t containsString:@"句"];
    return looksStatus || looksCount;
}

// 从 OCR 结果里剔除我们自己的浮窗文字。
// 两种来源：
//   ① 形状可辨的状态栏（IsOwnOverlayText）
//   ② 我们刚画上去的译文（由调用方传入已渲染过的文本）——
//      贴译面板会盖住原文，下一轮 OCR 必然把它们读回来；
//      若不过滤，这些中文会被当成“原文”再翻一次，对白框里就会混进重复/错位的句子。
+ (NSArray<OCRTextItem *> *)itemsExcludingOwnOverlay:(NSArray<OCRTextItem *> *)items
                                     renderedTexts:(NSSet<NSString *> *)renderedTexts {
    if (items.count == 0) { return items; }
    NSMutableArray<OCRTextItem *> *kept = [NSMutableArray arrayWithCapacity:items.count];
    for (OCRTextItem *item in items) {
        if ([self isOwnOverlayText:item.text]) { continue; }
        if (renderedTexts.count > 0) {
            NSString *normalized = FYNormalizeOCRTextForComparison(item.text);
            if (normalized.length > 0 && [renderedTexts containsObject:normalized]) { continue; }
        }
        [kept addObject:item];
    }
    return kept;
}

// 我们画过的所有译文（字幕窗 + 贴译面板），归一化后供 OCR 去重
+ (NSSet<NSString *> *)renderedTranslationSetForCaption:(NSString *)captionText inlineCache:(NSDictionary *)inlineCache {
    NSMutableSet<NSString *> *set = [NSMutableSet set];
    NSString *normalizedCaption = FYNormalizeOCRTextForComparison(captionText);
    if (normalizedCaption.length >= 2) { [set addObject:normalizedCaption]; }
    for (NSString *value in inlineCache.allValues) {
        if (![value isKindOfClass:NSString.class]) { continue; }
        NSString *normalized = FYNormalizeOCRTextForComparison(value);
        if (normalized.length >= 2) { [set addObject:normalized]; }
    }
    return set;
}

// Deduplication needs geometry AND bidirectional character coverage, never text alone.
// Inner blocks must lie >=85% inside and cover >=85% of the outer area;
// both character coverages must reach 80%. Same-sized duplicates retain the first.
// These are the existing thresholds, including summed (not union) covered area.
+ (NSArray<OCRTextItem *> *)resolveOverlappingItems:(NSArray<OCRTextItem *> *)items {
    if (items.count < 2) { return items ?: @[]; }
    NSMutableIndexSet *redundant = [NSMutableIndexSet indexSet];
    for (NSUInteger outerIndex = 0; outerIndex < items.count; outerIndex++) {
        if ([redundant containsIndex:outerIndex]) { continue; }
        OCRTextItem *outer = items[outerIndex]; CGRect outerBox = outer.boundingBox;
        CGFloat outerArea = outerBox.size.width * outerBox.size.height;
        NSString *outerText = FYNormalizeOCRTextForComparison(outer.text ?: @"");
        if (outerArea <= 0 || outerText.length == 0) { continue; }
        NSMutableArray<NSNumber *> *insideIndexes = [NSMutableArray array]; CGFloat coveredArea = 0;
        for (NSUInteger innerIndex = 0; innerIndex < items.count; innerIndex++) {
            if (innerIndex == outerIndex || [redundant containsIndex:innerIndex]) { continue; }
            OCRTextItem *inner = items[innerIndex]; CGRect box = inner.boundingBox;
            CGFloat boxArea = box.size.width * box.size.height; if (boxArea <= 0) { continue; }
            CGRect intersection = CGRectIntersection(outerBox, box); if (CGRectIsNull(intersection)) { continue; }
            CGFloat intersectionArea = intersection.size.width * intersection.size.height;
            if (intersectionArea / boxArea < 0.85) { continue; }
            if (CGRectGetWidth(box) >= CGRectGetWidth(outerBox) - 0.001 && CGRectGetHeight(box) >= CGRectGetHeight(outerBox) - 0.001 && innerIndex > outerIndex) { continue; }
            [insideIndexes addObject:@(innerIndex)]; coveredArea += intersectionArea;
        }
        if (insideIndexes.count == 0 || coveredArea / outerArea < 0.85) { continue; }
        NSArray<NSNumber *> *sorted = [insideIndexes sortedArrayUsingComparator:^NSComparisonResult(NSNumber *left, NSNumber *right) {
            // Preserve the original coverage traversal; coverage itself counts characters.
            OCRTextItem *a = items[left.unsignedIntegerValue];
            OCRTextItem *b = items[right.unsignedIntegerValue];
            CGFloat delta = CGRectGetMaxY(b.boundingBox) - CGRectGetMaxY(a.boundingBox);
            if (fabs(delta) > 0.025) { return delta > 0 ? NSOrderedAscending : NSOrderedDescending; }
            if (a.boundingBox.origin.x < b.boundingBox.origin.x) { return NSOrderedAscending; }
            if (a.boundingBox.origin.x > b.boundingBox.origin.x) { return NSOrderedDescending; }
            return NSOrderedSame;
        }];
        NSMutableString *innerRaw = [NSMutableString string];
        for (NSNumber *index in sorted) [innerRaw appendString:FYNormalizeOCRTextForComparison(items[index.unsignedIntegerValue].text ?: @"")];
        if (innerRaw.length == 0) { continue; }
        if (FYOCRTextCoverage(outerText, innerRaw) >= 0.8 && FYOCRTextCoverage(innerRaw, outerText) >= 0.8) [redundant addIndex:outerIndex];
    }
    if (redundant.count == 0) { return items; }
    NSMutableArray<OCRTextItem *> *kept = [NSMutableArray array];
    for (NSUInteger index = 0; index < items.count; index++) if (![redundant containsIndex:index]) [kept addObject:items[index]];
    return kept;
}

+ (NSArray<OCRTextItem *> *)mergeCoarseItems:(NSArray<OCRTextItem *> *)coarse refinedItems:(NSArray<OCRTextItem *> *)refined {
    if (!refined.count) { return [self resolveOverlappingItems:coarse]; }
    NSMutableArray<OCRTextItem *> *merged = [refined mutableCopy];
    for (OCRTextItem *original in coarse) {
        BOOL replaced = NO;
        for (OCRTextItem *better in refined) {
            CGRect a = original.boundingBox, b = better.boundingBox;
            CGFloat overlapY = MIN(CGRectGetMaxY(a), CGRectGetMaxY(b)) - MAX(CGRectGetMinY(a), CGRectGetMinY(b));
            CGFloat overlapX = MIN(CGRectGetMaxX(a), CGRectGetMaxX(b)) - MAX(CGRectGetMinX(a), CGRectGetMinX(b));
            if (b.size.height >= a.size.height * 0.6 && overlapY > MIN(a.size.height,b.size.height) * 0.45 && overlapX > 0) { replaced = YES; break; }
        }
        if (!replaced) [merged addObject:original];
    }
    [merged sortUsingComparator:^NSComparisonResult(OCRTextItem *left, OCRTextItem *right) { return FYOCRReadingOrder(left, right); }];
    return [self resolveOverlappingItems:merged];
}
+ (NSString *)textFromRecognizedLines:(NSArray<NSString *> *)lines {
    NSMutableArray<NSString *> *kept = [NSMutableArray array];
    for (NSString *value in lines) {
        NSString *line = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
        if (line.length > 0) { [kept addObject:line]; }
    }
    return [kept componentsJoinedByString:@"\n"];
}

- (NSArray<OCRTextItem *> *)recognizeTextItemsInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)languageSegment error:(NSError **)error {
    __block NSMutableArray<OCRTextItem *> *items = [NSMutableArray array];
    __block NSError *requestError = nil;

    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest *request, NSError *innerError) {
        if (innerError) {
            requestError = innerError;
            return;
        }

        for (VNRecognizedTextObservation *observation in request.results) {
            VNRecognizedText *candidate = [[observation topCandidates:1] firstObject];
            NSString *line = [candidate.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (line.length < 2) { continue; }
            if (observation.boundingBox.size.width < 0.010 || observation.boundingBox.size.height < 0.006) { continue; }

            OCRTextItem *item = [[OCRTextItem alloc] init];
            item.text = line;
            item.boundingBox = observation.boundingBox;
            // 保留识别置信度：分组/布局只把它用于诊断，不当作几何证据。
            item.confidence = candidate.confidence;
            [items addObject:item];
        }
    }];

    request.recognitionLevel = fastOCR ? VNRequestTextRecognitionLevelFast : VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = !fastOCR;
    request.recognitionLanguages = languageSegment == 1 ? @[@"en-US"] : @[@"ja-JP"];
    // minimumTextHeight 是相对图像高度的比例，固定值会在不同窗口尺寸下失效：
    // 实测 2727×1536 截图时 0.02 正好，但运行时窗口 1710×963 里对白文字占 0.054，
    // 0.02 会把它当“太小的字”漏掉 → 整句对白凭空消失。
    // 改成按绝对像素换算：目标至少读到约 28px 高的字，随图像高度自适应。
    CGFloat imageHeight = (CGFloat)CGImageGetHeight(image);
    // 实测：对白文字高 52px，但 minH 设成 28px 仍读不到，要设到 48px 才读到。
    // Vision 的这个阈值不是“小于就丢弃”的线性开关，实际有效值比文字高度略低几像素。
    CGFloat targetTextPixels = fastOCR ? 32.0 : 48.0;
    CGFloat adaptiveMinH = imageHeight > 0 ? (targetTextPixels / imageHeight) : 0.02;
    if (adaptiveMinH < 0.005) { adaptiveMinH = 0.005; }
    if (adaptiveMinH > 0.10) { adaptiveMinH = 0.10; }
    request.minimumTextHeight = adaptiveMinH;
    if (self.configurationObserver) {
        self.configurationObserver(fastOCR, languageSegment, CGImageGetWidth(image), CGImageGetHeight(image), adaptiveMinH);
    }

    VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];
    BOOL ok = [handler performRequests:@[request] error:error];
    if (!ok) {
        if (error && !*error) {
            *error = [NSError errorWithDomain:@"LiveCaptionTranslator"
                                         code:900
                                     userInfo:@{NSLocalizedDescriptionKey: @"OCR 引擎执行失败，已跳过这一轮。"}];
        }
        return @[];
    }
    if (requestError && error) { *error = requestError; }

    [items sortUsingComparator:^NSComparisonResult(OCRTextItem *left, OCRTextItem *right) {
        return FYOCRReadingOrder(left, right);
    }];

    return items;
}
@end
