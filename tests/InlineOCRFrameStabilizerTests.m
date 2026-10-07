#import <Cocoa/Cocoa.h>
#import "FYOCRManager.h"

static NSUInteger checks = 0;
static void Expect(BOOL condition, NSString *message) {
    checks++;
    if (!condition) { NSLog(@"FAIL %@", message); exit(1); }
}
static OCRTextItem *Item(NSString *text, CGFloat x, CGFloat y, CGFloat w, CGFloat h) {
    OCRTextItem *item = [OCRTextItem new];
    item.text = text;
    item.boundingBox = CGRectMake(x, y, w, h);
    item.lineTexts = @[text];
    item.lineBoxes = @[[NSValue valueWithRect:item.boundingBox]];
    item.lineCount = 1;
    item.blockKind = InlineBlockKindShort;
    return item;
}
static NSArray<OCRTextItem *> *Scene(NSString *club, NSString *remark, CGFloat jitter) {
    return @[
        Item(@"クラブ", .517, .201, .070, .041),
        Item(club, .608 + jitter, .201, .072, .041),
        Item(@"備考", .515, .130, .048, .047),
        Item(remark, .609, .079 + jitter, .203, .101),
        Item(@"プロフィールを見る", .010, .003, .182, .036)
    ];
}
static NSString *Club(NSArray<OCRTextItem *> *items) {
    for (OCRTextItem *item in items) if (CGRectGetMidX(item.boundingBox) > .60 && CGRectGetMidY(item.boundingBox) > .20) return item.text;
    return nil;
}
static BOOL HasText(NSArray<OCRTextItem *> *items, NSString *text) {
    for (OCRTextItem *item in items) if ([item.text isEqualToString:text]) return YES;
    return NO;
}
int main(void) { @autoreleasepool {
    FYInlineOCRFrameStabilizer *tracker = [FYInlineOCRFrameStabilizer new];
    NSString *remark = @"桜井琥一の弟。\nスリルは彼の活力。";
    NSArray *base = Scene(@"帰宅部", remark, 0);
    Expect([tracker observeItems:base].count == 0 && !tracker.ready, @"首帧只建立候选");
    Expect([tracker observeItems:base].count == 5 && tracker.ready, @"第二帧确认页面");
    for (NSInteger frame = 0; frame < 10; frame++) {
        NSString *noise = frame % 2 ? @"帰宅部" : @"•帰宅部";
        NSArray *stable = [tracker observeItems:Scene(noise, remark, frame % 2 ? .001 : -.001)];
        Expect([Club(stable) isEqualToString:@"帰宅部"], @"交替误读保留已确认的社团值");
    }
    NSArray *merged = @[
        Item(@"クラブ", .517, .201, .070, .041),
        Item(@"帰宅部\n桜井琥一の弟。\nスリルは彼の活力。", .608, .079, .204, .163),
        Item(@"備考", .515, .130, .048, .047),
        Item(@"プロフィールを見る", .010, .003, .182, .036)
    ];
    NSArray *afterMerge = [tracker observeItems:merged];
    Expect(HasText(afterMerge, @"帰宅部") && HasText(afterMerge, remark), @"一帧错误合并不替换两条已确认文本");
    for (NSInteger frame = 0; frame < 8; frame++) {
        NSArray *stable = [tracker observeItems:merged];
        Expect(stable.count == base.count && HasText(stable, @"帰宅部") && HasText(stable, remark),
               @"持续误合并也不能吞掉已确认的独立字段");
    }
    for (NSInteger frame = 0; frame < 3; frame++) {
        Expect([tracker observeItems:[merged arrayByAddingObjectsFromArray:base]].count == base.count,
               @"合并框和独立框同时出现不会创建重复字段");
    }
    [tracker observeItems:base];
    NSArray *changed = Scene(@"吹奏楽部", remark, 0);
    Expect([Club([tracker observeItems:changed]) isEqualToString:@"帰宅部"], @"真实修改第一帧仍保留旧值");
    Expect([Club([tracker observeItems:changed]) isEqualToString:@"帰宅部"], @"真实修改第二帧仍保留旧值");
    Expect([Club([tracker observeItems:changed]) isEqualToString:@"吹奏楽部"], @"真实修改第三帧更新该字段");
    NSArray *moved = Scene(@"吹奏楽部", remark, .015);
    CGFloat before = [Club([tracker observeItems:moved]) length];
    Expect(before > 0, @"移动第一帧仍可读");
    NSArray *afterMove = [tracker observeItems:moved];
    OCRTextItem *clubItem = nil;
    for (OCRTextItem *item in afterMove) if ([item.text isEqualToString:@"吹奏楽部"]) clubItem = item;
    Expect(clubItem && fabs(CGRectGetMinX(clubItem.boundingBox) - .623) < .002, @"持续位移两帧后更新几何");
    NSArray *page = @[
        Item(@"別のページ", .10, .85, .20, .05),
        Item(@"新しい項目", .40, .65, .20, .05),
        Item(@"戻る", .80, .05, .10, .05)
    ];
    Expect(HasText([tracker observeItems:page], @"吹奏楽部"), @"换页第一帧不清旧内容");
    Expect(HasText([tracker observeItems:page], @"別のページ"), @"换页第二帧及时接受新页面");

    [tracker reset]; [tracker observeItems:base]; [tracker observeItems:base];
    NSArray *missingClub = @[base[0], base[2], base[3], base[4]];
    [tracker observeItems:changed]; [tracker observeItems:changed];
    [tracker observeItems:missingClub];
    Expect([Club([tracker observeItems:changed]) isEqualToString:@"帰宅部"], @"漏帧会打断文本连续确认，不能累计旧次数");
    [tracker observeItems:base];
    for (NSInteger frame = 0; frame < 2; frame++) {
        Expect(HasText([tracker observeItems:missingClub], @"帰宅部"), @"短暂漏字保留该字段");
    }
    Expect(!HasText([tracker observeItems:missingClub], @"帰宅部"), @"持续消失只移除该字段");
    Expect(!HasText([tracker observeItems:base], @"帰宅部"), @"消失后的字段首次出现只建立候选");
    Expect(HasText([tracker observeItems:base], @"帰宅部"), @"字段再次连续出现后恢复");

    [tracker reset]; [tracker observeItems:base]; [tracker observeItems:base];
    [tracker observeItems:Scene(@"帰宅部", remark, .015)];
    NSArray *oppositeMove = [tracker observeItems:Scene(@"帰宅部", remark, -.015)];
    OCRTextItem *stableClub = nil;
    for (OCRTextItem *item in oppositeMove) if ([item.text isEqualToString:@"帰宅部"]) stableClub = item;
    Expect(fabs(stableClub.boundingBox.origin.x - .608) < .001, @"方向相反的坐标跳动不算持续位移");

    [tracker reset];
    NSMutableArray *mutableFrame = [Scene(@"帰宅部", remark, 0) mutableCopy];
    [tracker observeItems:mutableFrame];
    ((OCRTextItem *)mutableFrame[1]).text = @"変更された値";
    [tracker observeItems:base];
    Expect(HasText([tracker observeItems:base], @"帰宅部"), @"候选帧保存快照，不依赖调用者后续修改");
    NSLog(@"PASS InlineOCRFrameStabilizerTests: %lu checks", (unsigned long)checks);
    return 0;
}}
