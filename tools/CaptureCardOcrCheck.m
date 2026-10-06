// 离线核对工具：把**真实画面**送进生产 OCR 与对白提取代码，不做任何替身。
// 用途：验证"采集卡输入"能读到完整对白（录制条不再遮挡中间行）。
// 只读图片、不启动采集、不访问网络、不读写用户设置与学习库。
//
// 用法（普通终端）：
//   CaptureCardOcrCheck <图片路径> [必须出现的子串] [--dialogue-must-contain <子串>] [--fast] [--report <文件>]
//
// 无参数时（用 open 经 LaunchServices 启动）从 /tmp/yiya-capture-card-check/request.json 读取：
//   {"image": "...", "require_line": "...", "dialogue_contains": "...", "fast": false, "report": "..."}
// 经 LaunchServices 启动很关键：Vision 的 Accurate 识别要求调用方是有 bundle 身份的签名应用，
// 直接从终端跑子进程时结果可能不同（会以 CRImageReaderError 或 Metal 归档异常失败）。
#define main FuyiMainForCaptureCardCheck
#import "LiveCaptionTranslator.m"
#undef main
#import <ImageIO/ImageIO.h>
#import <sys/stat.h>

static CGImageRef FYCheckLoadImage(NSString *path) {
    NSURL *url = [NSURL fileURLWithPath:path];
    CGImageSourceRef source = CGImageSourceCreateWithURL((__bridge CFURLRef)url, NULL);
    if (!source) { return NULL; }
    CGImageRef image = CGImageSourceCreateImageAtIndex(source, 0, NULL);
    CFRelease(source);
    return image;
}

static NSString *FYCheckRun(NSString *imagePath, NSString *requiredLine, NSString *requiredDialogue,
                            BOOL fastOCR, BOOL *passed) {
    NSMutableString *report = [NSMutableString string];
    CGImageRef image = FYCheckLoadImage(imagePath);
    if (!image) {
        [report appendFormat:@"读取图片失败: %@\n", imagePath];
        if (passed) { *passed = NO; }
        return report;
    }
    AppDelegate *app = [AppDelegate new];
    NSError *error = nil;
    NSArray<OCRTextItem *> *blocks = nil;
    NSString *text = [app recognizeTextBlocksInImage:image
                                             fastOCR:fastOCR
                                     languageSegment:0
                                              blocks:&blocks
                                               error:&error];
    size_t width = CGImageGetWidth(image), height = CGImageGetHeight(image);
    CGImageRelease(image);
    if (error) {
        [report appendFormat:@"OCR 失败: %@\n", error.localizedDescription];
        if (passed) { *passed = NO; }
        return report;
    }

    [report appendFormat:@"图片: %@ (%zux%zu) 识别级别: %@\n", imagePath.lastPathComponent, width, height,
                         fastOCR ? @"fast" : @"accurate"];
    [report appendFormat:@"OCR 行数: %lu\n", (unsigned long)blocks.count];
    for (OCRTextItem *block in blocks) { [report appendFormat:@"  - %@\n", block.text]; }
    NSString *dialogue = [app dialogueTextFromItems:blocks speakerLabelOnly:NULL];
    [report appendFormat:@"对白提取: %@\n", [dialogue stringByReplacingOccurrencesOfString:@"\n" withString:@" / "]];

    BOOL ok = YES;
    if (requiredLine.length > 0 && ![text containsString:requiredLine]) {
        [report appendFormat:@"失败: OCR 文本缺少 %@\n", requiredLine];
        ok = NO;
    }
    if (requiredDialogue.length > 0 && ![dialogue containsString:requiredDialogue]) {
        [report appendFormat:@"失败: 对白提取缺少 %@\n", requiredDialogue];
        ok = NO;
    }
    [report appendFormat:@"%@\n", ok ? @"PASS" : @"FAIL"];
    if (passed) { *passed = ok; }
    return report;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSString *imagePath = nil, *requiredLine = nil, *requiredDialogue = nil, *reportPath = nil;
        BOOL fastOCR = NO;
        if (argc >= 2) {
            imagePath = @(argv[1]);
            if (argc >= 3 && strncmp(argv[2], "--", 2) != 0) { requiredLine = @(argv[2]); }
            for (int index = 2; index < argc; index++) {
                if (strcmp(argv[index], "--dialogue-must-contain") == 0 && index + 1 < argc) { requiredDialogue = @(argv[index + 1]); }
                if (strcmp(argv[index], "--report") == 0 && index + 1 < argc) { reportPath = @(argv[index + 1]); }
                if (strcmp(argv[index], "--fast") == 0) { fastOCR = YES; }
            }
        } else {
            NSString *directory = @"/tmp/yiya-capture-card-check";
            [[NSFileManager defaultManager] createDirectoryAtPath:directory
                                      withIntermediateDirectories:YES
                                                       attributes:@{NSFilePosixPermissions: @0700}
                                                            error:NULL];
            NSData *data = [NSData dataWithContentsOfFile:[directory stringByAppendingPathComponent:@"request.json"]];
            id parsed = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
            if (![parsed isKindOfClass:NSDictionary.class]) {
                fprintf(stderr, "用法: CaptureCardOcrCheck <图片路径> [必须出现的子串] [--dialogue-must-contain <子串>] [--fast] [--report <文件>]\n");
                return 2;
            }
            imagePath = parsed[@"image"];
            requiredLine = parsed[@"require_line"];
            requiredDialogue = parsed[@"dialogue_contains"];
            fastOCR = [parsed[@"fast"] boolValue];
            reportPath = parsed[@"report"];
        }
        if (imagePath.length == 0) {
            fprintf(stderr, "缺少图片路径\n");
            return 2;
        }
        BOOL passed = NO;
        NSString *report = FYCheckRun(imagePath, requiredLine, requiredDialogue, fastOCR, &passed);
        fputs(report.UTF8String, stdout);
        if (reportPath.length > 0) {
            [report writeToFile:reportPath atomically:YES encoding:NSUTF8StringEncoding error:NULL];
            chmod(reportPath.fileSystemRepresentation, 0600);
        }
        return passed ? 0 : 1;
    }
}
