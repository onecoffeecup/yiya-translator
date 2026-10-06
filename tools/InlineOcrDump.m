// 独立 OCR 夹具导出工具：把真实截图跑一遍**生产同配置**的 Vision OCR，
// 导出「行文本 + 归一化框 + 置信度」的 JSON，供贴译布局验证使用。
// 只读图片、不启动应用、不访问网络、不读写用户设置与学习库。
//
// 配置对齐 objc/LiveCaptionTranslator.m 的
// recognizeTextItemsInImage:fastOCR:languageSegment:error:（OCRTextItem 分支）：
//   recognitionLevel = Accurate、usesLanguageCorrection = YES、recognitionLanguages = @[@"ja-JP"]
//   minimumTextHeight = clamp(48.0 / imageHeight, 0.005, 0.10)
//   丢弃 trim 后长度 < 2 的行；丢弃 boundingBox 宽 < 0.010 或高 < 0.006 的行
//   confidence 取 [[observation topCandidates:1] firstObject].confidence
// 输出顺序也照生产：先按行顶（MaxY）自上而下（相差 > 0.025 算不同行），再按 x 从左到右。
//
// 用法：
//   InlineOcrDump <png路径> [--lang ja-JP]
// 成功时 JSON 写 stdout；失败时 stderr 说明原因并以非 0 退出。

#import <Foundation/Foundation.h>
#import <CoreGraphics/CoreGraphics.h>
#import <ImageIO/ImageIO.h>
#import <Vision/Vision.h>

// 与 objc/LiveCaptionTranslator.m 里的 Trim 等价。
static NSString *FYTrim(NSString *value) {
    if (!value) { return @""; }
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}

// 定点小数：最多 6 位，去掉末尾多余的 0，避免 0.10000000000000001 这类噪声。
static NSString *FYNumberString(double value) {
    if (fabs(value) < 1e-9) { return @"0"; }
    char buffer[64];
    snprintf(buffer, sizeof(buffer), "%.6f", value);
    size_t length = strlen(buffer);
    while (length > 0 && buffer[length - 1] == '0') { buffer[--length] = '\0'; }
    if (length > 0 && buffer[length - 1] == '.') { buffer[--length] = '\0'; }
    if (length == 0 || strcmp(buffer, "-0") == 0) { return @"0"; }
    return @(buffer);
}

// 最小 JSON 字符串转义（UTF-8 原样输出，控制字符转义）。
static NSString *FYJSONString(NSString *value) {
    NSMutableString *out = [NSMutableString stringWithCapacity:value.length + 2];
    [out appendString:@"\""];
    for (NSUInteger index = 0; index < value.length; index++) {
        unichar character = [value characterAtIndex:index];
        switch (character) {
            case '"': [out appendString:@"\\\""]; break;
            case '\\': [out appendString:@"\\\\"]; break;
            case '\n': [out appendString:@"\\n"]; break;
            case '\r': [out appendString:@"\\r"]; break;
            case '\t': [out appendString:@"\\t"]; break;
            default:
                if (character < 0x20) {
                    [out appendFormat:@"\\u%04x", (unsigned int)character];
                } else {
                    [out appendFormat:@"%C", character];
                }
                break;
        }
    }
    [out appendString:@"\""];
    return out;
}

static void FYFail(NSString *message) {
    fprintf(stderr, "%s\n", message.UTF8String);
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *imagePath = nil;
        NSString *language = @"ja-JP";

        for (int index = 1; index < argc; index++) {
            if (strcmp(argv[index], "--lang") == 0) {
                if (index + 1 >= argc) {
                    FYFail(@"--lang 后面要跟语言代码，例如 --lang en-US");
                    return 2;
                }
                language = @(argv[++index]);
                continue;
            }
            if (strncmp(argv[index], "--", 2) == 0) {
                FYFail([NSString stringWithFormat:@"未知参数: %s", argv[index]]);
                return 2;
            }
            if (imagePath.length > 0) {
                FYFail([NSString stringWithFormat:@"一次只能处理一张图片（已指定 %@）", imagePath]);
                return 2;
            }
            imagePath = @(argv[index]);
        }

        if (imagePath.length == 0) {
            FYFail(@"用法: InlineOcrDump <png路径> [--lang ja-JP]");
            return 2;
        }

        NSURL *url = [NSURL fileURLWithPath:imagePath];
        CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
        if (!source) {
            FYFail([NSString stringWithFormat:@"读取图片失败: %@", imagePath]);
            return 1;
        }
        CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
        CFRelease(source);
        if (!image) {
            FYFail([NSString stringWithFormat:@"解码图片失败: %@", imagePath]);
            return 1;
        }

        size_t imageWidth = CGImageGetWidth(image);
        size_t imageHeight = CGImageGetHeight(image);

        __block NSMutableArray<NSDictionary *> *lines = [NSMutableArray array];
        __block NSError *requestError = nil;

        VNRecognizeTextRequest *request = [[VNRecognizeTextRequest alloc] initWithCompletionHandler:^(VNRequest *innerRequest, NSError *error) {
            if (error) {
                requestError = error;
                return;
            }
            for (VNRecognizedTextObservation *observation in innerRequest.results) {
                VNRecognizedText *candidate = [[observation topCandidates:1] firstObject];
                NSString *text = FYTrim(candidate.string);
                if (text.length < 2) { continue; }
                CGRect box = observation.boundingBox;
                if (box.size.width < 0.010 || box.size.height < 0.006) { continue; }
                [lines addObject:@{
                    @"text": text,
                    @"x": @(box.origin.x),
                    @"y": @(box.origin.y),
                    @"w": @(box.size.width),
                    @"h": @(box.size.height),
                    @"confidence": @(candidate.confidence),
                }];
            }
        }];

        request.recognitionLevel = VNRequestTextRecognitionLevelAccurate;
        request.usesLanguageCorrection = YES;
        request.recognitionLanguages = @[language];
        CGFloat adaptiveMinH = imageHeight > 0 ? (48.0 / (CGFloat)imageHeight) : 0.02;
        if (adaptiveMinH < 0.005) { adaptiveMinH = 0.005; }
        if (adaptiveMinH > 0.10) { adaptiveMinH = 0.10; }
        request.minimumTextHeight = adaptiveMinH;
        fprintf(stderr, "OCRCFG lang=%s img=%zux%zu minH=%.4f\n", language.UTF8String, imageWidth, imageHeight, adaptiveMinH);

        NSError *error = nil;
        VNImageRequestHandler *handler = [[VNImageRequestHandler alloc] initWithCGImage:image options:@{}];
        BOOL ok = [handler performRequests:@[request] error:&error];
        if (!ok) {
            CGImageRelease(image);
            FYFail([NSString stringWithFormat:@"OCR 引擎执行失败: %@", error.localizedDescription ?: @"未知错误"]);
            return 1;
        }
        if (requestError) {
            CGImageRelease(image);
            FYFail([NSString stringWithFormat:@"OCR 识别失败: %@", requestError.localizedDescription ?: @"未知错误"]);
            return 1;
        }

        // 与生产相同的排序：行顶自上而下，同一行内 x 从左到右。
        [lines sortUsingComparator:^NSComparisonResult(NSDictionary *left, NSDictionary *right) {
            CGFloat leftTop = [left[@"y"] doubleValue] + [left[@"h"] doubleValue];
            CGFloat rightTop = [right[@"y"] doubleValue] + [right[@"h"] doubleValue];
            if (fabs(leftTop - rightTop) > 0.025) {
                return leftTop > rightTop ? NSOrderedAscending : NSOrderedDescending;
            }
            double leftX = [left[@"x"] doubleValue];
            double rightX = [right[@"x"] doubleValue];
            if (leftX < rightX) { return NSOrderedAscending; }
            if (leftX > rightX) { return NSOrderedDescending; }
            return NSOrderedSame;
        }];

        NSMutableString *out = [NSMutableString string];
        [out appendFormat:@"{\"image\":{\"path\":%@,\"width\":%zu,\"height\":%zu},\n",
                            FYJSONString(imagePath), imageWidth, imageHeight];
        [out appendString:@" \"lines\":["];
        if (lines.count > 0) {
            [out appendString:@"\n"];
            for (NSUInteger index = 0; index < lines.count; index++) {
                NSDictionary *line = lines[index];
                [out appendFormat:@"  {\"text\":%@,\"x\":%@,\"y\":%@,\"w\":%@,\"h\":%@,\"confidence\":%@}%@\n",
                                    FYJSONString(line[@"text"]),
                                    FYNumberString([line[@"x"] doubleValue]),
                                    FYNumberString([line[@"y"] doubleValue]),
                                    FYNumberString([line[@"w"] doubleValue]),
                                    FYNumberString([line[@"h"] doubleValue]),
                                    FYNumberString([line[@"confidence"] doubleValue]),
                                    (index + 1 < lines.count ? @"," : @"")];
            }
            [out appendString:@" "];
        }
        [out appendString:@"]}\n"];

        CGImageRelease(image);

        NSData *data = [out dataUsingEncoding:NSUTF8StringEncoding];
        fwrite(data.bytes, 1, data.length, stdout);
        fflush(stdout);

        if (lines.count == 0) {
            FYFail([NSString stringWithFormat:@"警告: %@ 没有识别到任何符合阈值的文本行", imagePath]);
        }
        return 0;
    }
}
