#import "FYGeometryManager.h"

double FYConsumeCaptureMappingGrids(NSDictionary *entry, double *scene, size_t width, size_t height,
    double *templ, size_t templateWidth, size_t templateHeight) {
    double score=FYCaptureMappingScoreInGrids(entry,scene,width,height,templ,templateWidth,templateHeight);
    free(templ);free(scene);
    return score;
}

FYCaptureCandidateResult FYSelectCaptureCandidate(const double *scene, size_t width, size_t height,
    const double *templ, size_t templateWidth, size_t templateHeight, CGFloat videoAspect, NSRect windowFrame,
    BOOL (^estimateFit)(NSRect *), NSDictionary *(^existingEntry)(void), NSInteger version,
    void (^preferredFit)(double,double), void (^keptCache)(double,double,double)) {
    FYCaptureCandidateResult result={NSZeroRect,0,-2,NO};
    result.bestScore=FYSearchCaptureGrid(scene,width,height,templ,templateWidth,templateHeight,videoAspect,&result.bestRect);
    NSRect fitRect=NSZeroRect;
    if (estimateFit(&fitRect)) {
        NSRect fitGrid=FYCaptureGridRectFromWindow(fitRect,windowFrame,width,height);
        result.fitScore=FYSignatureCorrelation(scene,width,height,(NSInteger)fitGrid.origin.x,(NSInteger)fitGrid.origin.y,
            (size_t)fitGrid.size.width,(size_t)fitGrid.size.height,templ,templateWidth,templateHeight);
        CGFloat searchWidth=result.bestRect.size.width/(CGFloat)width*NSWidth(windowFrame);
        if (FYShouldPreferCaptureFit(result.fitScore,result.bestScore,NSWidth(fitRect)>searchWidth*1.35)) {
            if (preferredFit) preferredFit(result.bestScore,result.fitScore);
            result.bestScore=result.fitScore;result.bestRect=fitGrid;
        }
    }
    NSDictionary *existing=existingEntry();
    if (existing && FYCaptureMappingVersion(existing,version)==FYCaptureMappingVersionCurrentAutomatic) {
        double score=FYCaptureMappingScoreInGrids(existing,scene,width,height,templ,templateWidth,templateHeight);
        if (FYShouldKeepCachedCaptureMapping(score,result.bestScore)) {
            if (keptCache) keptCache(score,result.bestScore,result.fitScore);
            result.keepExisting=YES;
        }
    }
    return result;
}

@implementation FYCaptureMappingCache
- (NSDictionary *)entryForWindowID:(uint32_t)windowID { return self.entries[[NSString stringWithFormat:@"%u",windowID]]; }
- (void)storeEntry:(NSDictionary *)entry forWindowID:(uint32_t)windowID {
    if (!self.entries) self.entries=[NSMutableDictionary dictionary];
    self.entries[[NSString stringWithFormat:@"%u",windowID]]=entry;
}
- (void)removeWindowID:(uint32_t)windowID { [self.entries removeObjectForKey:[NSString stringWithFormat:@"%u",windowID]]; }
@end

FYCaptureMappingVersionStatus FYCaptureMappingVersion(NSDictionary *entry, NSInteger currentVersion) {
    if (![entry[@"source"] isEqualToString:@"auto"]) return FYCaptureMappingVersionNonAutomatic;
    return [entry[@"mappingVersion"] integerValue]<currentVersion ? FYCaptureMappingVersionStaleAutomatic : FYCaptureMappingVersionCurrentAutomatic;
}

NSMutableDictionary *FYFilterCaptureMappings(NSDictionary *savedRects, NSInteger currentVersion) {
    NSMutableDictionary *kept=[NSMutableDictionary dictionary];
    for (id key in savedRects) {
        id entry=savedRects[key];
        if (![entry isKindOfClass:NSDictionary.class]) continue;
        if (FYCaptureMappingVersion(entry,currentVersion)==FYCaptureMappingVersionStaleAutomatic) continue;
        kept[key]=entry;
    }
    return kept;
}

@implementation FYAutoLocateSchedule
- (BOOL)isThrottled { return self.lastAttemptDate && -[self.lastAttemptDate timeIntervalSinceNow]<3.0; }
@end

@implementation FYMappingValidationSchedule
- (BOOL)beginValidationAt:(NSDate *)now {
    BOOL due=!self.lastValidationDate || [now timeIntervalSinceDate:self.lastValidationDate]>=2.0;
    if (!due) return NO;
    self.lastValidationDate=now;
    return YES;
}
@end

BOOL FYEstimatedCaptureDisplayRect(CGSize frameSize, NSRect windowFrame, NSRect *outRect) {
    if (frameSize.width<2 || frameSize.height<2 || NSWidth(windowFrame)<2 || NSHeight(windowFrame)<2) return NO;
    CGFloat scale=MIN(NSWidth(windowFrame)/frameSize.width,NSHeight(windowFrame)/frameSize.height);
    if (!isfinite(scale) || scale<=0) return NO;
    NSRect rect=NSMakeRect(NSMinX(windowFrame)+(NSWidth(windowFrame)-frameSize.width*scale)/2,
        NSMinY(windowFrame)+(NSHeight(windowFrame)-frameSize.height*scale)/2,frameSize.width*scale,frameSize.height*scale);
    if (NSWidth(rect)<2 || NSHeight(rect)<2) return NO;
    if (outRect) *outRect=NSIntegralRect(rect);
    return YES;
}

NSRect FYCaptureGridRectFromWindow(NSRect fitRect, NSRect windowFrame, size_t width, size_t height) {
    NSInteger fx=(NSInteger)llround((NSMinX(fitRect)-NSMinX(windowFrame))/NSWidth(windowFrame)*(CGFloat)width);
    NSInteger fw=(NSInteger)llround(NSWidth(fitRect)/NSWidth(windowFrame)*(CGFloat)width);
    NSInteger fy=(NSInteger)llround((1.0-(NSMinY(fitRect)-NSMinY(windowFrame))/NSHeight(windowFrame)-NSHeight(fitRect)/NSHeight(windowFrame))*(CGFloat)height);
    NSInteger fh=(NSInteger)llround(NSHeight(fitRect)/NSHeight(windowFrame)*(CGFloat)height);
    fx=MAX((NSInteger)0,MIN((NSInteger)width-8,fx));
    fy=MAX((NSInteger)0,MIN((NSInteger)height-6,fy));
    fw=MAX((NSInteger)8,MIN(fw,(NSInteger)width-fx));
    fh=MAX((NSInteger)6,MIN(fh,(NSInteger)height-fy));
    return NSMakeRect(fx,fy,fw,fh);
}

NSRect FYWindowRectFromCaptureGrid(NSRect gridRect, size_t width, size_t height, NSRect windowFrame) {
    CGFloat nx=gridRect.origin.x/(CGFloat)width;
    CGFloat nw=gridRect.size.width/(CGFloat)width;
    CGFloat nh=gridRect.size.height/(CGFloat)height;
    CGFloat ny=1.0-(gridRect.origin.y+gridRect.size.height)/(CGFloat)height;
    return NSMakeRect(NSMinX(windowFrame)+nx*NSWidth(windowFrame), NSMinY(windowFrame)+ny*NSHeight(windowFrame),
        nw*NSWidth(windowFrame), nh*NSHeight(windowFrame));
}

BOOL FYBuildCaptureGrids(CGImageRef frameImage, CGImageRef windowImage, CGSize frameSize,
    NSRect (^windowFrame)(void), size_t sceneWidth, double **outTempl, size_t *outTW, size_t *outTH,
    double **outScene, size_t *outWW, size_t *outWH, CGFloat *outAspect, NSString **outReason) {
    CGFloat videoAspect = frameSize.width / MAX((CGFloat)1, frameSize.height);
    const size_t TW = 40;
    size_t TH = MAX((size_t)8, (size_t)lround(TW / MAX((CGFloat)0.1, videoAspect)));
    double *templ = FYGrayGridFromImage(frameImage, TW, TH);
    CGImageRelease(frameImage);

    NSRect windowRect = windowFrame();
    CGFloat windowAspect = NSWidth(windowRect) / MAX((CGFloat)1, NSHeight(windowRect));
    size_t WW = MAX((size_t)80, sceneWidth);
    size_t WH = MAX((size_t)40, (size_t)lround(WW / MAX((CGFloat)0.1, windowAspect)));
    double *scene = FYGrayGridFromImage(windowImage, WW, WH);
    CGImageRelease(windowImage);
    if (!templ || !scene) {
        free(templ); free(scene);
        if (outReason) { *outReason = @"无法读取画面像素"; }
        return NO;
    }
    FYNormalizeSignature(templ, TW * TH);
    double templVar = 0;
    for (size_t i = 0; i < TW * TH; i++) { templVar += templ[i] * templ[i]; }
    if (templVar < 1e-3) {   // 纯色画面：没有可比对的结构
        free(templ); free(scene);
        if (outReason) { *outReason = @"采集卡画面没有可用细节"; }
        return NO;
    }
    if (outTempl) { *outTempl = templ; } else { free(templ); }
    if (outScene) { *outScene = scene; } else { free(scene); }
    if (outTW) { *outTW = TW; }
    if (outTH) { *outTH = TH; }
    if (outWW) { *outWW = WW; }
    if (outWH) { *outWH = WH; }
    if (outAspect) { *outAspect = videoAspect; }
    return YES;
}

CGImageRef FYCopyCapturedRegion(CGImageRef image, CGRect topLeftRegion) {
    if (!image) return NULL;
    CGRect crop=[FYGeometryManager pixelCropForTopLeftRegion:topLeftRegion
        imageWidth:CGImageGetWidth(image) imageHeight:CGImageGetHeight(image)];
    return CGImageCreateWithImageInRect(image,crop);
}

BOOL FYGeometryDeliveryIsStale(NSInteger generation, NSInteger currentGeneration, uint32_t targetID, uint32_t currentTargetID) {
    return generation != currentGeneration || (targetID != 0 && targetID != currentTargetID);
}

// CGImage → 小尺寸灰度网格。用于「按内容比对」，不是按宽高比猜。
double *FYGrayGridFromImage(CGImageRef image, size_t gridW, size_t gridH) {
    if (!image || gridW < 4 || gridH < 4) { return NULL; }
    uint8_t *bytes = calloc(gridW * gridH, 1);
    if (!bytes) { return NULL; }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceGray();
    CGContextRef ctx = CGBitmapContextCreate(bytes, gridW, gridH, 8, gridW, space, kCGImageAlphaNone);
    CGColorSpaceRelease(space);
    if (!ctx) { free(bytes); return NULL; }
    CGContextSetInterpolationQuality(ctx, kCGInterpolationHigh);
    CGContextDrawImage(ctx, CGRectMake(0, 0, gridW, gridH), image);
    CGContextRelease(ctx);
    double *grid = malloc(sizeof(double) * gridW * gridH);
    if (!grid) { free(bytes); return NULL; }
    for (size_t i = 0; i < gridW * gridH; i++) { grid[i] = bytes[i]; }
    free(bytes);
    return grid;
}

// 模板归一化成零均值、单位方差：这样比对只反映结构，不受亮度/色彩管线差异影响。
void FYNormalizeSignature(double *values, size_t count) {
    if (!values || count == 0) { return; }
    double sum = 0;
    for (size_t i = 0; i < count; i++) { sum += values[i]; }
    double mean = sum / count;
    double var = 0;
    for (size_t i = 0; i < count; i++) { double d = values[i] - mean; var += d * d; }
    double sd = sqrt(var / count);
    if (sd < 1e-6) { sd = 1; }
    for (size_t i = 0; i < count; i++) { values[i] = (values[i] - mean) / sd; }
}

// 候选区域与模板的归一化互相关（模板已零均值单位方差）。
double FYSignatureCorrelation(const double *scene, size_t sw, size_t sh,
                                     NSInteger x, NSInteger y, size_t cw, size_t ch,
                                     const double *templ, size_t tw, size_t th) {
    if (x < 0 || y < 0 || cw == 0 || ch == 0) { return -2; }
    if (x + (NSInteger)cw > (NSInteger)sw || y + (NSInteger)ch > (NSInteger)sh) { return -2; }
    double sum = 0, sum2 = 0, dot = 0;
    size_t n = tw * th;
    for (size_t j = 0; j < th; j++) {
        NSInteger sy = y + (NSInteger)((double)j * ch / th);
        if (sy >= (NSInteger)sh) { sy = (NSInteger)sh - 1; }
        const double *row = scene + (size_t)sy * sw;
        const double *trow = templ + j * tw;
        for (size_t i = 0; i < tw; i++) {
            NSInteger sx = x + (NSInteger)((double)i * cw / tw);
            if (sx >= (NSInteger)sw) { sx = (NSInteger)sw - 1; }
            double v = row[sx];
            sum += v; sum2 += v * v; dot += v * trow[i];
        }
    }
    double mean = sum / n;
    double var = sum2 / n - mean * mean;
    if (var < 1e-6) { return -1; }
    return dot / (n * sqrt(var));
}

// 在一对已生成的网格上给「缓存矩形」打分（网格第 0 行 = 图像顶部 → 这里再翻一次 y）。
double FYCaptureMappingScoreInGrids(NSDictionary *entry, const double *scene, size_t WW, size_t WH,
                                    const double *templ, size_t TW, size_t TH) {
    if (!entry || !scene || !templ || WW < 8 || WH < 8) { return -99; }
    CGFloat nx = [entry[@"nx"] doubleValue];
    CGFloat ny = [entry[@"ny"] doubleValue];
    CGFloat nw = [entry[@"nw"] doubleValue];
    CGFloat nh = [entry[@"nh"] doubleValue];
    NSInteger gx = (NSInteger)llround(nx * (CGFloat)WW);
    NSInteger gy = (NSInteger)llround((1.0 - ny - nh) * (CGFloat)WH);
    NSInteger gw = (NSInteger)llround(nw * (CGFloat)WW);
    NSInteger gh = (NSInteger)llround(nh * (CGFloat)WH);
    gx = MAX((NSInteger)0, MIN((NSInteger)WW - 4, gx));
    gy = MAX((NSInteger)0, MIN((NSInteger)WH - 4, gy));
    gw = MAX((NSInteger)8, MIN(gw, (NSInteger)WW - gx));
    gh = MAX((NSInteger)6, MIN(gh, (NSInteger)WH - gy));
    return FYSignatureCorrelation(scene, WW, WH, gx, gy, (size_t)gw, (size_t)gh, templ, TW, TH);
}

BOOL FYShouldPreferCaptureFit(double fitScore, double searchScore, BOOL clearlySmaller) { return fitScore > searchScore + 0.005 || (clearlySmaller && fitScore > searchScore - 0.02); }
BOOL FYShouldKeepCachedCaptureMapping(double existingScore, double bestScore) { return existingScore >= 0.5 && bestScore < existingScore + 0.05; }
double FYSearchCaptureGrid(const double *scene, size_t WW, size_t WH, const double *templ,
                           size_t TW, size_t TH, CGFloat videoAspect, NSRect *outRect) {
    // ① 粗搜：画面在窗口里占 25%–100% 宽，位置按网格走
    double best = -2;
    NSRect bestRect = NSZeroRect;
    for (NSInteger step = 0; step <= 30; step++) {
        CGFloat fraction = 0.25 + 0.75 * (CGFloat)step / 30.0;
        size_t cw = MAX((size_t)12, (size_t)lround(WW * fraction));
        size_t ch = MAX((size_t)8, (size_t)lround(cw / MAX((CGFloat)0.1, videoAspect)));
        if (ch > WH || cw > WW) { continue; }
        NSInteger spanX = (NSInteger)WW - (NSInteger)cw;
        NSInteger spanY = (NSInteger)WH - (NSInteger)ch;
        NSInteger steps = 14;
        for (NSInteger iy = 0; iy <= steps; iy++) {
            NSInteger y = spanY <= 0 ? 0 : (NSInteger)llround((double)spanY * iy / steps);
            for (NSInteger ix = 0; ix <= steps; ix++) {
                NSInteger x = spanX <= 0 ? 0 : (NSInteger)llround((double)spanX * ix / steps);
                double score = FYSignatureCorrelation(scene, WW, WH, x, y, cw, ch, templ, TW, TH);
                if (score > best) { best = score; bestRect = NSMakeRect(x, y, cw, ch); }
            }
        }
    }
    // ② 细搜：在最佳候选附近 1 像素步长、更细的尺度
    if (best > 0.2) {
        NSInteger baseW = (NSInteger)bestRect.size.width;
        for (NSInteger dw = -12; dw <= 12; dw += 2) {
            size_t cw = (size_t)MAX((NSInteger)12, baseW + dw);
            size_t ch = MAX((size_t)8, (size_t)lround(cw / MAX((CGFloat)0.1, videoAspect)));
            if (cw > WW || ch > WH) { continue; }
            NSInteger spanX = (NSInteger)WW - (NSInteger)cw;
            NSInteger spanY = (NSInteger)WH - (NSInteger)ch;
            NSInteger cx = (NSInteger)llround(bestRect.origin.x * (CGFloat)spanX / MAX((CGFloat)1, (CGFloat)(WW - (NSInteger)bestRect.size.width)));
            NSInteger cy = (NSInteger)llround(bestRect.origin.y * (CGFloat)spanY / MAX((CGFloat)1, (CGFloat)(WH - (NSInteger)bestRect.size.height)));
            for (NSInteger dy = -10; dy <= 10; dy++) {
                NSInteger y = MAX((NSInteger)0, MIN(spanY, cy + dy));
                for (NSInteger dx = -10; dx <= 10; dx++) {
                    NSInteger x = MAX((NSInteger)0, MIN(spanX, cx + dx));
                    double score = FYSignatureCorrelation(scene, WW, WH, x, y, cw, ch, templ, TW, TH);
                    if (score > best) { best = score; bestRect = NSMakeRect(x, y, cw, ch); }
                }
            }
        }
    }
    if (outRect) { *outRect = bestRect; }
    return best;
}

@implementation FYGeometryManager
+ (NSDictionary *)captureMappingForRect:(NSRect)rect windowFrame:(NSRect)frame videoAspect:(CGFloat)aspect deviceID:(NSString *)deviceID source:(NSString *)source confidence:(CGFloat)confidence version:(NSInteger)version {
    if (NSWidth(rect) < 2 || NSHeight(rect) < 2 || NSWidth(frame) < 2 || NSHeight(frame) < 2) { return nil; }
    return @{@"nx":@((NSMinX(rect)-NSMinX(frame))/NSWidth(frame)),
             @"ny":@((NSMinY(rect)-NSMinY(frame))/NSHeight(frame)),
             @"nw":@(NSWidth(rect)/NSWidth(frame)), @"nh":@(NSHeight(rect)/NSHeight(frame)),
             @"windowAspect":@(NSWidth(frame)/NSHeight(frame)), @"videoAspect":@(aspect>0?aspect:1.0),
             @"deviceID":deviceID?:@"", @"source":source?:@"auto", @"confidence":@(confidence), @"mappingVersion":@(version)};
}
+ (NSRect)captureMappingRect:(NSDictionary *)entry windowFrame:(NSRect)frame {
    return NSMakeRect(NSMinX(frame)+[entry[@"nx"] doubleValue]*NSWidth(frame),
                      NSMinY(frame)+[entry[@"ny"] doubleValue]*NSHeight(frame),
                      [entry[@"nw"] doubleValue]*NSWidth(frame), [entry[@"nh"] doubleValue]*NSHeight(frame));
}
+ (NSString *)captureMappingWindowReason:(NSDictionary *)entry windowFrame:(NSRect)frame {
    if (NSWidth(frame) < 2 || NSHeight(frame) < 2) { return @"目标窗口尺寸无效，无法定位画面区域。"; }
    CGFloat aspect = NSWidth(frame) / NSHeight(frame);
    if (fabs(aspect - [entry[@"windowAspect"] doubleValue]) > 0.02) { return @"目标窗口比例已变化。"; }
    return nil;
}
+ (NSString *)captureMappingInputReason:(NSDictionary *)entry frameSize:(CGSize)size hasFrameSize:(BOOL)hasSize deviceID:(NSString *)deviceID {
    if (hasSize && size.height > 1 && fabs(size.width / size.height - [entry[@"videoAspect"] doubleValue]) > 0.02) {
        return @"采集画面比例已变化（可能换了输入源或设备）。";
    }
    NSString *calibratedDevice = entry[@"deviceID"] ?: @"";
    if (calibratedDevice.length > 0 && ![calibratedDevice isEqualToString:deviceID ?: @""]) { return @"采集卡设备已变化。"; }
    return nil;
}
+ (BOOL)captureMappingScoreIsStale:(double)score unavailableValue:(double)unavailable {
    return score > unavailable && score < 0.30;
}
+ (CGRect)pixelCropForTopLeftRegion:(CGRect)region imageWidth:(size_t)width imageHeight:(size_t)height {
    CGRect crop = CGRectMake(floor(region.origin.x * width), floor(region.origin.y * height),
                             MAX(1, floor(region.size.width * width)), MAX(1, floor(region.size.height * height)));
    return CGRectIntersection(crop, CGRectMake(0, 0, width, height));
}
+ (NSRect)appKitFrameForQuartzBounds:(CGRect)bounds mainScreenTop:(CGFloat)top {
    return NSMakeRect(bounds.origin.x, top - bounds.origin.y - bounds.size.height, bounds.size.width, bounds.size.height);
}
+ (NSRect)frameForNormalizedBox:(CGRect)box inViewport:(NSRect)viewport {
    return NSIntegralRect(NSMakeRect(NSMinX(viewport) + box.origin.x * NSWidth(viewport),
                                    NSMinY(viewport) + box.origin.y * NSHeight(viewport),
                                    box.size.width * NSWidth(viewport), box.size.height * NSHeight(viewport)));
}
+ (NSRect)frameForTopLeftNormalizedBox:(CGRect)box inViewport:(NSRect)viewport {
    return NSIntegralRect(NSMakeRect(NSMinX(viewport) + box.origin.x * NSWidth(viewport),
                                    NSMaxY(viewport) - (box.origin.y + box.size.height) * NSHeight(viewport),
                                    box.size.width * NSWidth(viewport), box.size.height * NSHeight(viewport)));
}
+ (CGRect)quartzRectFromSelection:(CGRect)selection panelFrame:(NSRect)panelFrame mainScreenTop:(CGFloat)top {
    return CGRectMake(panelFrame.origin.x + selection.origin.x, top - NSMaxY(panelFrame) + selection.origin.y,
                      selection.size.width, selection.size.height);
}
@end
