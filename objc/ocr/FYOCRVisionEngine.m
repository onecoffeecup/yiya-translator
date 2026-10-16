#import "FYOCRVisionEngine.h"
#import <Vision/Vision.h>

@implementation FYOCRVisionEngine
- (NSArray<OCRTextItem *> *)recognizeTextItemsInImage:(CGImageRef)image fastOCR:(BOOL)fastOCR languageSegment:(NSInteger)languageSegment rawObserver:(FYOCRVisionRawObserver)rawObserver error:(NSError **)error {
    __block NSMutableArray<OCRTextItem *> *items = [NSMutableArray array];
    __block NSError *requestError = nil;


    VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest *request, NSError *innerError) {
        if (innerError) {
            requestError = innerError;
            return;
        }

        NSMutableArray *diagnosticRaw=rawObserver ? [NSMutableArray array] : nil;
        for (VNRecognizedTextObservation *observation in request.results) {
            VNRecognizedText *candidate = [[observation topCandidates:1] firstObject];
            if (diagnosticRaw) {
                OCRTextItem *raw=[OCRTextItem new]; raw.text=candidate.string ?: @""; raw.boundingBox=observation.boundingBox; raw.confidence=candidate.confidence;
                [diagnosticRaw addObject:raw];
            }
            NSString *line = [candidate.string stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
            if (line.length < 2) { continue; }
            if (observation.boundingBox.size.width < 0.010 || observation.boundingBox.size.height < 0.006) { continue; }

            OCRTextItem *item = [[OCRTextItem alloc] init];
            item.text = line;
            item.boundingBox = observation.boundingBox;
            if ([line rangeOfCharacterFromSet:NSCharacterSet.newlineCharacterSet].location != NSNotFound) {
                NSMutableArray<NSString *> *lineTexts = [NSMutableArray array];
                NSMutableArray<NSValue *> *lineBoxes = [NSMutableArray array];
                [candidate.string enumerateSubstringsInRange:NSMakeRange(0, candidate.string.length)
                                                     options:NSStringEnumerationByLines
                                                  usingBlock:^(NSString *substring, NSRange substringRange, NSRange enclosingRange, BOOL *stop) {
                    NSString *part = [substring stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
                    if (part.length == 0) { return; }
                    VNRectangleObservation *rangeBox = [candidate boundingBoxForRange:substringRange error:nil];
                    [lineTexts addObject:part];
                    [lineBoxes addObject:[NSValue valueWithRect:rangeBox ? rangeBox.boundingBox : CGRectZero]];
                }];
                if (lineTexts.count > 1) {
                    item.text = [lineTexts componentsJoinedByString:@"\n"];
                    item.lineTexts = lineTexts;
                    item.lineBoxes = lineBoxes;
                    item.lineCount = lineTexts.count;
                    item.lastLineBox = lineBoxes.lastObject.rectValue;
                }
            }
            // 保留识别置信度：分组/布局只把它用于诊断，不当作几何证据。
            item.confidence = candidate.confidence;
            [items addObject:item];
        }
        if (rawObserver) rawObserver(diagnosticRaw);
    }];

    request.recognitionLevel = fastOCR ? VNRequestTextRecognitionLevelFast : VNRequestTextRecognitionLevelAccurate;
    request.usesLanguageCorrection = !fastOCR;
    request.recognitionLanguages = languageSegment == 1 ? @[@"en-US"] : @[@"ja-JP"];
    // minimumTextHeight 是相对图像高度的比例，固定值会在不同窗口尺寸下失效：
    // 实测 2727×1536 截图时 0.02 正好，但运行时窗口 1710×963 里对白文字占 0.054，
    // 0.02 会把它当“太小的字”漏掉 → 整句对白凭空消失。
    // 改成按绝对像素换算：准确模式目标为 48px，快速模式为 32px，随图像高度自适应。
    CGFloat imageHeight = (CGFloat)CGImageGetHeight(image);
    // 实测：对白文字高 52px，但 minH 设成 28px 仍读不到，要设到 48px 才读到。
    // Vision 的这个阈值不是“小于就丢弃”的线性开关，实际有效值比文字高度略低几像素。
    CGFloat targetTextPixels = fastOCR ? 32.0 : 48.0;
    CGFloat adaptiveMinH = imageHeight > 0 ? (targetTextPixels / imageHeight) : 0.02;
    if (adaptiveMinH < 0.005) { adaptiveMinH = 0.005; }
    if (adaptiveMinH > 0.10) { adaptiveMinH = 0.10; }
    request.minimumTextHeight = adaptiveMinH;
    if (self.configurationObserver) {
        self.configurationObserver(fastOCR, languageSegment, CGImageGetWidth(image), CGImageGetHeight(image), request.minimumTextHeight);
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
