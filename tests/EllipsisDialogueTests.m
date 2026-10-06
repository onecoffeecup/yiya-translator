// 「省略号导致对白漏句」专项验证（2026-10-06）。
//
// 覆盖：
//   1. 含有效日文文字的行，在任何框宽、任何数量/形式的省略号下都必须保留
//      （用户现场案例「あれは・・・・・・」框宽 0.115987 曾被整行删除）；
//   2. 纯省略号/纯标点（没有假名汉字）仍然过滤；
//   3. 对白与贴译两条路径用同一份过滤函数，行为一致；
//   4. 「琥一／あれは・・・・・・／話し合いだ。」的完整对白提取；
//   5. 通过 mock 翻译服务确认**最终请求**里确实带上两句原文。
//
// 只做隔离验证：真实网络被 FYTestIsolation 拦下，这里注入 mock session；
// 不接触用户数据、不安装/重启正式应用。

#import "LearningAppTestSupport.h"
#import <objc/runtime.h>

static NSUInteger gFailures = 0;
static void Check(BOOL ok, NSString *message) {
    if (ok) {
        NSLog(@"PASS %@", message);
    } else {
        gFailures += 1;
        NSLog(@"FAIL %@", message);
    }
}

// 日志里把换行显示成 ⏎，方便直接核对“两句话都在”。
static NSString *Visible(NSString *text) {
    return [[text ?: @"" stringByReplacingOccurrencesOfString:@"\n" withString:@"⏎"]
            stringByReplacingOccurrencesOfString:@"\r" withString:@""];
}

static OCRTextItem *Line(NSString *text, CGRect box) {
    OCRTextItem *item = [[OCRTextItem alloc] init];
    item.text = text;
    item.boundingBox = box;
    item.confidence = 0.9;
    return item;
}

static NSTextField *Field(NSString *text) {
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 200, 24)];
    field.stringValue = text ?: @"";
    return field;
}

#pragma mark - mock 翻译服务

static NSMutableArray<NSString *> *gSubmittedSources = nil;
static NSUInteger gMockRequests = 0;

@interface EllipsisMockTask : NSObject
@property(nonatomic, copy) void (^response)(void);
@end
@implementation EllipsisMockTask
- (void)resume { if (self.response) { self.response(); } }
- (void)cancel {}
@end

@interface EllipsisMockSession : NSObject
@end
@implementation EllipsisMockSession
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                            completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion {
    // 只检查测试用的虚构请求体；不打印任何凭据。
    NSDictionary *body = [NSJSONSerialization JSONObjectWithData:request.HTTPBody options:0 error:NULL];
    NSString *source = [body[@"messages"] lastObject][@"content"];
    if ([source isKindOfClass:NSString.class]) { [gSubmittedSources addObject:source]; }
    gMockRequests += 1;
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"choices": @[@{@"message": @{@"content": @"测试译文"}}]}
                                                   options:0 error:NULL];
    NSHTTPURLResponse *response = [[NSHTTPURLResponse alloc] initWithURL:request.URL
                                                              statusCode:200
                                                             HTTPVersion:@"HTTP/1.1"
                                                            headerFields:@{}];
    EllipsisMockTask *task = [EllipsisMockTask new];
    task.response = ^{ completion(data, response, nil); };
    return (NSURLSessionDataTask *)task;
}
@end

@interface FYTestURLSession (EllipsisMock)
+ (id)ellipsisMockSession;
@end
@implementation FYTestURLSession (EllipsisMock)
+ (id)ellipsisMockSession { return [EllipsisMockSession new]; }
@end

#pragma mark - 1. 过滤：真实台词必须保留，纯标点才丢弃

static void TestFilterKeepsRealDialogue(void) {
    AppDelegate *app = [[AppDelegate alloc] init];
    // 用户要求覆盖的句子：不同数量与形式的省略号
    NSArray<NSString *> *lines = @[
        @"あれは・・・・・・", @"そうだ・・・", @"どれど......", @"え……", @"退学って・・・・・・"
    ];
    NSArray<NSNumber *> *widths = @[@(0.05), @(0.115987), @(0.16), @(0.30)];
    for (NSString *line in lines) {
        for (NSNumber *width in widths) {
            OCRTextItem *item = Line(line, CGRectMake(0.29, 0.11, width.doubleValue, 0.055));
            Check(![app shouldIgnoreInlineText:line normalized:NormalizeForComparison(line)
                                   boundingBox:item.boundingBox strict:YES],
                  [NSString stringWithFormat:@"对白路径保留「%@」（框宽 %.6f）", line, width.doubleValue]);
            Check(![app shouldIgnoreInlineText:line normalized:NormalizeForComparison(line)
                                   boundingBox:item.boundingBox strict:NO],
                  [NSString stringWithFormat:@"贴译路径保留「%@」（框宽 %.6f）", line, width.doubleValue]);
        }
    }
    // 「え……」只有一个有效字符，也必须保留
    OCRTextItem *single = Line(@"え……", CGRectMake(0.29, 0.11, 0.03, 0.05));
    Check(![app shouldIgnoreInlineText:@"え……" normalized:NormalizeForComparison(@"え……")
                           boundingBox:single.boundingBox strict:YES],
          @"「え……」只有一个有效字符也必须保留");

    // 纯省略号 / 纯标点 / 空白：没有可译内容，仍然过滤
    for (NSString *pure in @[@"・・・・・・・", @"......", @"……", @"、、、", @"！！！", @"　", @""]) {
        OCRTextItem *item = Line(pure, CGRectMake(0.29, 0.11, 0.116, 0.055));
        Check([app shouldIgnoreInlineText:pure normalized:NormalizeForComparison(pure)
                              boundingBox:item.boundingBox strict:YES],
              [NSString stringWithFormat:@"纯标点行仍然过滤 <%@>", pure.length ? pure : @"(空)"]);
    }

    // 同一句话在不同点数下保持稳定（不再时有时无）
    NSMutableArray<NSString *> *variants = [NSMutableArray array];
    for (NSUInteger count = 2; count <= 8; count++) {
        NSMutableString *text = [NSMutableString stringWithString:@"あれは"];
        for (NSUInteger index = 0; index < count; index++) { [text appendString:@"・"]; }
        [variants addObject:[text copy]];
    }
    for (NSString *variant in variants) {
        OCRTextItem *item = Line(variant, CGRectMake(0.29, 0.11, 0.116, 0.055));
        Check(![app shouldIgnoreInlineText:variant normalized:NormalizeForComparison(variant)
                               boundingBox:item.boundingBox strict:YES],
              [NSString stringWithFormat:@"省略号数量变化不影响保留（%@ 个点）", @(variant.length - 3)]);
    }
}

#pragma mark - 2. 对白提取：琥一 / あれは・・・・・・ / 話し合いだ。

static NSString *ExtractDialogueText(AppDelegate *app, NSArray<OCRTextItem *> *items) {
    NSArray<OCRTextItem *> *band = SubtitleBandItemsFromBlocks(items);
    NSMutableArray<OCRTextItem *> *dialogueItems = [NSMutableArray array];
    NSMutableArray<OCRTextItem *> *optionItems = [NSMutableArray array];
    SplitDialogueAndOptionsFromItems(band, items, dialogueItems, optionItems);
    NSArray<OCRTextItem *> *source = dialogueItems.count > 0 ? dialogueItems : items;
    BOOL speakerOnly = NO;
    return [app dialogueTextFromItems:source speakerLabelOnly:&speakerOnly];
}

static void TestFullDialogueExtraction(void) {
    AppDelegate *app = [[AppDelegate alloc] init];
    // 用户截图现场比例：名字框在上，`あれは・・・・・・` 框宽 0.115987，台词在下。
    NSArray<OCRTextItem *> *items = @[
        Line(@"琥一", CGRectMake(0.302, 0.235, 0.055, 0.030)),
        Line(@"あれは・・・・・・", CGRectMake(0.290, 0.115, 0.115987, 0.055)),
        Line(@"話し合いだ。", CGRectMake(0.290, 0.055, 0.200, 0.055))
    ];
    NSArray<OCRTextItem *> *band = SubtitleBandItemsFromBlocks(items);
    Check(band.count >= 2, [NSString stringWithFormat:@"字幕带至少含两行（实际 %lu）", (unsigned long)band.count]);
    NSString *text = ExtractDialogueText(app, items);
    Check([text containsString:@"あれは"], [NSString stringWithFormat:@"完整对白含「あれは・・・・・・」<实际：%@>", Visible(text)]);
    Check([text containsString:@"話し合いだ。"], [NSString stringWithFormat:@"完整对白含「話し合いだ。」<实际：%@>", Visible(text)]);
}

#pragma mark - 3. mock 翻译服务：最终请求必须带两句原文

static void TestMockTranslationRequestContainsBothLines(void) {
    AppDelegate *app = [[AppDelegate alloc] init];
    app.apiKeyField = Field(@"test-key");
    app.baseURLField = Field(@"https://example.invalid/v1");
    app.modelField = Field(@"test-model");

    NSArray<OCRTextItem *> *items = @[
        Line(@"琥一", CGRectMake(0.302, 0.235, 0.055, 0.030)),
        Line(@"あれは・・・・・・", CGRectMake(0.290, 0.115, 0.115987, 0.055)),
        Line(@"話し合いだ。", CGRectMake(0.290, 0.055, 0.200, 0.055))
    ];
    NSString *dialogueText = ExtractDialogueText(app, items);
    Check(dialogueText.length > 0, @"提取出的对白文本非空");

    gSubmittedSources = [NSMutableArray array];
    gMockRequests = 0;
    __block NSString *translated = nil;
    __block NSError *translationError = nil;
    [app translateText:dialogueText completion:^(NSString *value, NSError *error) {
        translated = value;
        translationError = error;
    }];
    Pump(^BOOL { return translated != nil || translationError != nil; });

    Check(translationError == nil, [NSString stringWithFormat:@"mock 翻译服务无错误（%@）", translationError.localizedDescription ?: @""]);
    Check(gMockRequests == 1, [NSString stringWithFormat:@"只发出一次翻译请求（实际 %lu）", (unsigned long)gMockRequests]);
    NSString *submitted = gSubmittedSources.lastObject ?: @"";
    Check([submitted containsString:@"あれは"],
          [NSString stringWithFormat:@"最终请求包含「あれは・・・・・・」<实际：%@>", Visible(submitted)]);
    Check([submitted containsString:@"話し合いだ。"],
          [NSString stringWithFormat:@"最终请求包含「話し合いだ。」<实际：%@>", Visible(submitted)]);
    Check([submitted componentsSeparatedByString:@"\n"].count >= 2,
          @"最终请求里两句话是分开的两行（不是被合并/截断成一句）");
}

#pragma mark - 4. 贴译路径：同一条台词不能被二次删除

static void TestInlinePathKeepsSameLines(void) {
    AppDelegate *app = [[AppDelegate alloc] init];
    NSArray<OCRTextItem *> *items = @[
        Line(@"あれは・・・・・・", CGRectMake(0.29, 0.60, 0.115987, 0.055)),
        Line(@"え……", CGRectMake(0.29, 0.52, 0.05, 0.05)),
        Line(@"・・・・・・・", CGRectMake(0.29, 0.44, 0.116, 0.055))
    ];
    NSArray<OCRTextItem *> *kept = [app filteredInlineTextItems:items strict:NO];
    NSMutableArray<NSString *> *texts = [NSMutableArray array];
    for (OCRTextItem *item in kept) { [texts addObject:item.text]; }
    Check([texts containsObject:@"あれは・・・・・・"], @"贴译路径保留「あれは・・・・・・」");
    Check([texts containsObject:@"え……"], @"贴译路径保留「え……」");
    Check(![texts containsObject:@"・・・・・・・"], @"贴译路径仍然丢弃纯省略号行");
}

int main(void) { @autoreleasepool {
    [NSApplication sharedApplication];
    // 注入 mock 翻译服务：真实网络在隔离环境里会被直接判失败。
    method_exchangeImplementations(class_getClassMethod(FYTestURLSession.class, @selector(sharedSession)),
                                   class_getClassMethod(FYTestURLSession.class, @selector(ellipsisMockSession)));

    NSLog(@"== 1. 过滤：真实台词保留 / 纯标点丢弃 ==");
    TestFilterKeepsRealDialogue();
    NSLog(@"== 2. 完整对白提取 ==");
    TestFullDialogueExtraction();
    NSLog(@"== 3. mock 翻译服务请求体 ==");
    TestMockTranslationRequestContainsBothLines();
    NSLog(@"== 4. 贴译路径一致性 ==");
    TestInlinePathKeepsSameLines();

    if (gFailures == 0) {
        NSLog(@"省略号对白回归通过：真实台词在两条路径、各种框宽与省略号形式下都保留，纯标点仍被过滤，最终请求含两句原文。");
        return 0;
    }
    NSLog(@"省略号对白回归失败：%lu 项", (unsigned long)gFailures);
    return 1;
} }
