#import "FYWindowManager.h"
#import "capture/FYDisplayTargetResolver.h"
@interface FYWindowManager () <FYDisplayTargetGeometry>
@end

FYWindowVisibilitySnapshot FYWindowVisibilityInList(uint32_t windowID, pid_t knownPID, NSArray<NSDictionary *> *windows) {
    FYWindowVisibilitySnapshot result={knownPID,NO,NO};
    for (NSDictionary *info in windows) {
        pid_t owner=(pid_t)[info[(id)kCGWindowOwnerPID] intValue];
        // Only the first target entry resolves an unknown PID, matching legacy duplicate handling.
        if (!result.targetOnScreen && [info[(id)kCGWindowNumber] unsignedIntValue] == windowID) {
            result.targetOnScreen=YES;
            if (result.targetPID <= 0) result.targetPID=owner;
        }
        // If PID was just resolved it belongs to this visible entry, so no prefix rescan is needed.
        if (result.targetPID > 0 && owner == result.targetPID) result.ownerHasOnScreenWindow=YES;
        if (result.targetOnScreen && result.ownerHasOnScreenWindow) break;
    }
    return result;
}

BOOL FYTargetQualifiesForOverlay(pid_t frontPID, pid_t targetPID, BOOL targetOnScreen, BOOL ownerHasOnScreenWindow, BOOL interactingWithOverlay) {
    if (interactingWithOverlay) return YES;
    if (frontPID <= 0 || targetPID <= 0 || frontPID != targetPID) return NO;
    return targetOnScreen || ownerHasOnScreenWindow;
}
NSWindowLevel FYOverlayLevelForTarget(pid_t targetPID, NSArray<NSDictionary *> *windows) {
    if (targetPID <= 0) return NSFloatingWindowLevel;
    NSInteger highest=0;
    for (NSDictionary *info in windows) {
        if ((pid_t)[info[(id)kCGWindowOwnerPID] intValue] != targetPID) continue;
        highest=MAX(highest,[info[(id)kCGWindowLayer] integerValue]);
    }
    NSInteger level=MIN(highest+1,(NSInteger)NSPopUpMenuWindowLevel+1);
    return (NSWindowLevel)MAX((NSInteger)NSFloatingWindowLevel,level);
}

BOOL FYOverlayShouldShow(BOOL targetActive, BOOL expanded, BOOL isExpandedPanel) {
    return targetActive && (!expanded || isExpandedPanel);
}

// 建议位：OBS／QuickTime 优先，其次接近全屏的窗口（游戏/投影），其他应用排在后面。
static NSInteger FYWindowSuggestionRankForValues(NSString *owner, NSString *title, CGRect bounds);



// 兼容历史格式：旧代码把窗口名拼成「应用名 - 标题」，新格式是「应用名 · 标题」。
static void FYWindowSplitDisplayName(NSString *name, NSString **outOwner, NSString **outTitle) {
    NSString *value = name ?: @"";
    for (NSString *separator in @[@" · ", @" - "]) {
        NSRange range = [value rangeOfString:separator];
        if (range.location == NSNotFound) { continue; }
        if (outOwner) { *outOwner = [value substringToIndex:range.location]; }
        if (outTitle) { *outTitle = [value substringFromIndex:NSMaxRange(range)]; }
        return;
    }
    if (outOwner) { *outOwner = value; }
    if (outTitle) { *outTitle = @""; }
}

@implementation WindowItem
- (NSString *)effectiveOwnerName {
    if (self.ownerName.length > 0) { return self.ownerName; }
    NSString *owner = nil;
    FYWindowSplitDisplayName(self.displayName, &owner, NULL);
    return owner ?: @"";
}
- (NSString *)effectiveTitle {
    if (self.title.length > 0) { return self.title; }
    if (self.ownerName.length == 0 && self.displayName.length > 0) {
        NSString *title = nil;
        FYWindowSplitDisplayName(self.displayName, NULL, &title);
        return title ?: @"";
    }
    return @"";
}
- (NSInteger)suggestionRank {
    return FYWindowSuggestionRankForValues(self.effectiveOwnerName, self.effectiveTitle, self.bounds);
}
@end

#pragma mark - 显示窗口候选：过滤、建议排序

// 输入法（含候选窗/状态窗）一类的所有者不该出现在候选列表里。
// 按所有者名匹配，不靠窗口标题 —— 标题为空的有效窗口很多，不能拿标题当过滤依据。
static BOOL FYWindowOwnerLooksLikeInputMethod(NSString *owner) {
    if (owner.length == 0) { return NO; }
    static NSArray<NSString *> *needles = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        needles = @[@"输入法", @"Input Method", @"Candidate", @"候補", @"候选",
                    @"Kotoeri", @"Japanese Input", @"GoogleJapaneseInput", @"Google 日文",
                    @"Sogou", @"搜狗", @"Baidu", @"百度", @"QQ Pinyin", @"微信输入", @"WeChat Input",
                    @"Fcitx", @"TextInput", @"TCIM"];
    });
    for (NSString *needle in needles) {
        if ([owner rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) { return YES; }
    }
    return NO;
}

BOOL FYWindowOwnerIsYiya(NSString *owner) {
    return owner.length > 0 && ([owner isEqualToString:@"译芽"] || [owner caseInsensitiveCompare:@"Yiya"] == NSOrderedSame);
}

// 屏幕覆盖率 0–1：窗口盖住某一块屏幕的比例。全屏投影/全屏游戏 ≈ 1。
static CGFloat FYWindowScreenCoverage(CGRect bounds) {
    if (bounds.size.width < 2 || bounds.size.height < 2) { return 0; }
    CGFloat mainTop = NSMaxY(NSScreen.mainScreen.frame);
    CGFloat best = 0;
    for (NSScreen *screen in NSScreen.screens) {
        NSRect frame = screen.frame;
        // CGWindowBounds 的原点在主屏左上；NSScreen.frame 在 AppKit 左下坐标系。
        NSRect quartz = NSMakeRect(NSMinX(frame), mainTop - NSMaxY(frame), NSWidth(frame), NSHeight(frame));
        NSRect intersection = NSIntersectionRect(quartz, bounds);
        if (NSIsEmptyRect(intersection)) { continue; }
        CGFloat total = NSWidth(quartz) * NSHeight(quartz);
        if (total <= 0) { continue; }
        best = MAX(best, NSWidth(intersection) * NSHeight(intersection) / total);
    }
    return best;
}

// 应用自己的设置/属性/统计窗口：不能把它们当成"承载游戏画面的窗口"。
// 只在标题非空时判定 —— 没有标题的窗口可能是有效的游戏/投影窗口。


// 建议位：OBS／QuickTime 优先，其次接近全屏的窗口（全屏游戏、投影），其他应用排在后面。
static NSInteger FYWindowSuggestionRankForValues(NSString *owner, NSString *title, CGRect bounds) {
    BOOL fullscreen = FYWindowScreenCoverage(bounds) >= 0.85;
    BOOL obs = [owner rangeOfString:@"OBS" options:NSCaseInsensitiveSearch].location != NSNotFound;
    if (obs) {
        if (fullscreen) { return 0; }
        for (NSString *needle in @[@"投影", @"预览", @"Projector", @"Preview", @"Fullscreen", @"全屏"]) {
            if ([title rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) { return 1; }
        }
        return 2;
    }
    BOOL quickTime = [owner rangeOfString:@"QuickTime" options:NSCaseInsensitiveSearch].location != NSNotFound;
    if (quickTime) {
        for (NSString *needle in @[@"录影", @"影片录制", @"Movie Recording", @"録画", @"Screen Recording"]) {
            if ([title rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) { return 3; }
        }
        return 4;
    }
    return fullscreen ? 5 : 6;
}

// 建议位 ≤ 这个值 = 精简列表里的"推荐窗口"。
static const NSInteger kWindowSuggestionRankRecommendedMax = 5;

// 排序：建议位 → 应用名 → 标题 → 窗口 ID（保证同一应用的多个窗口顺序稳定、可区分）。
NSComparisonResult FYWindowItemSort(WindowItem *left, WindowItem *right) {
    if (left.suggestionRank != right.suggestionRank) {
        return left.suggestionRank < right.suggestionRank ? NSOrderedAscending : NSOrderedDescending;
    }
    NSComparisonResult byOwner = [left.effectiveOwnerName localizedCaseInsensitiveCompare:right.effectiveOwnerName];
    if (byOwner != NSOrderedSame) { return byOwner; }
    NSComparisonResult byTitle = [left.effectiveTitle localizedCaseInsensitiveCompare:right.effectiveTitle];
    if (byTitle != NSOrderedSame) { return byTitle; }
    if (left.windowID == right.windowID) { return NSOrderedSame; }
    return left.windowID < right.windowID ? NSOrderedAscending : NSOrderedDescending;
}

// 一个 CGWindowList 条目 → 候选窗口。返回 nil = 这扇窗口不该出现在列表里（辅助窗口/太小/非普通层）。
// 窗口是否覆盖了主显示器的大部分（≈全屏投影/全屏预览）。
// kCGWindowBounds 与 CGDisplayBounds 都在"全局显示坐标（左上原点）"里，可直接比。


// 窗口中心落在哪块显示器上（跨屏投影要按它自己那块屏算"是不是全屏"，不能只比主屏）。
static CGRect FYDisplayContainingWindowInfo(NSDictionary *info) {
    CGRect bounds = CGRectZero;
    if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)info[(id)kCGWindowBounds], &bounds)) { return CGRectZero; }
    CGPoint center = CGPointMake(CGRectGetMidX(bounds), CGRectGetMidY(bounds));
    CGDirectDisplayID displays[16] = {0};
    uint32_t count = 0;
    if (CGGetActiveDisplayList(16, displays, &count) != kCGErrorSuccess) { return CGRectZero; }
    for (uint32_t index = 0; index < count; index++) {
        CGRect displayBounds = CGDisplayBounds(displays[index]);
        if (CGRectContainsPoint(displayBounds, center)) { return displayBounds; }
    }
    return CGRectZero;
}

// 窗口在**自己那块显示器**上的覆盖率（≥0.6 视为投影/全屏预览形态）。


WindowItem *FYWindowItemFromInfo(NSDictionary *info) {
    NSNumber *number = info[(NSString *)kCGWindowNumber];
    NSNumber *layer = info[(NSString *)kCGWindowLayer];
    NSNumber *ownerPID = info[(NSString *)kCGWindowOwnerPID];
    NSString *owner = info[(NSString *)kCGWindowOwnerName] ?: @"";
    NSString *title = info[(NSString *)kCGWindowName] ?: @"";
    CGRect bounds = CGRectZero;
    if (!number || !layer || layer.integerValue != 0 || owner.length == 0) { return nil; }
    if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)info[(NSString *)kCGWindowBounds], &bounds)) { return nil; }
    if (bounds.size.width < 160 || bounds.size.height < 100) { return nil; }
    // 译芽自己的浮层、贴译面板、字幕窗：不管层级，都不该出现在候选里。
    if (ownerPID && ownerPID.intValue == getpid()) { return nil; }
    if (FYWindowOwnerIsYiya(owner)) { return nil; }
    if (FYWindowOwnerLooksLikeInputMethod(owner)) { return nil; }
    // 工具提示类：无标题 **而且** 小到放不下一个画面。只按"标题为空"删会误删投影/无标题游戏窗口。
    if (title.length == 0 && (bounds.size.width < 320 || bounds.size.height < 200)) { return nil; }
    WindowItem *item = [[WindowItem alloc] init];
    item.windowID = number.unsignedIntValue;
    item.bounds = bounds;
    item.ownerName = owner;
    item.title = title;
    item.displayName = title.length > 0 ? [NSString stringWithFormat:@"%@ · %@", owner, title] : owner;
    return item;
}




static NSString *Shorten(NSString *value, NSUInteger limit) {
    NSString *trimmed = [value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (trimmed.length <= limit) { return trimmed; }
    return [[trimmed substringToIndex:limit] stringByAppendingString:@"..."];
}

@implementation FYWindowManager
- (NSArray<WindowItem *> *)availableWindowItems {
    NSMutableArray<WindowItem *> *items = [NSMutableArray array];
    NSArray *windowInfos = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID));
    for (NSDictionary *info in windowInfos) {
        WindowItem *item = FYWindowItemFromInfo(info);
        if (item) { [items addObject:item]; }
    }
    // 排序只是"更可能相关的排在前面"：应用名只作参考，不做硬性白名单。
    [items sortUsingComparator:^NSComparisonResult(WindowItem *left, WindowItem *right) {
        return FYWindowItemSort(left, right);
    }];
    return items;
}

- (NSArray<WindowItem *> *)displayedWindowItems:(NSArray<WindowItem *> *)windows showingAll:(BOOL)showAll selectedID:(uint32_t)selected {
    NSArray<WindowItem *> *all = windows ?: @[];
    NSMutableArray<WindowItem *> *recommended = [NSMutableArray array];
    for (WindowItem *item in all) {
        if (item.suggestionRank <= kWindowSuggestionRankRecommendedMax) { [recommended addObject:item]; }
    }
    if (showAll || recommended.count == 0) { return all; }
    if (selected != 0) {
        BOOL present = NO;
        for (WindowItem *item in recommended) {
            if (item.windowID == selected) { present = YES; break; }
        }
        if (!present) {
            for (WindowItem *item in all) {
                if (item.windowID != selected) { continue; }
                [recommended addObject:item];
                [recommended sortUsingComparator:^NSComparisonResult(WindowItem *a, WindowItem *b) { return FYWindowItemSort(a, b); }];
                break;
            }
        }
    }
    return recommended;
}

- (BOOL)hasRecommendedWindowItems:(NSArray<WindowItem *> *)windows {
    for (WindowItem *item in windows ?: @[]) {
        if (item.suggestionRank <= kWindowSuggestionRankRecommendedMax) { return YES; }
    }
    return NO;
}

- (NSString *)windowBaseTitleForItem:(WindowItem *)item {
    NSString *owner = item.effectiveOwnerName ?: @"";
    NSString *title = item.effectiveTitle ?: @"";
    if (title.length == 0 || [title caseInsensitiveCompare:owner] == NSOrderedSame) { return owner; }
    return [NSString stringWithFormat:@"%@ · %@", owner, title];
}

- (NSString *)windowMenuTitleForItem:(WindowItem *)item occurrence:(NSUInteger)occurrence {
    NSString *owner = item.effectiveOwnerName ?: @"";
    NSString *title = Shorten(item.effectiveTitle ?: @"", 40);
    NSString *base = (title.length == 0 || [title caseInsensitiveCompare:owner] == NSOrderedSame)
        ? owner : [NSString stringWithFormat:@"%@ · %@", owner, title];
    if (occurrence > 1) { base = [base stringByAppendingFormat:@" (%lu)", (unsigned long)occurrence]; }
    return base;
}

- (BOOL)liveBoundsForWindowID:(uint32_t)windowID outBounds:(CGRect *)outBounds {
    if (windowID == 0) { return NO; }
    NSArray *infos = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow, windowID));
    for (NSDictionary *info in infos) {
        if ([info[(id)kCGWindowNumber] unsignedIntValue] != windowID) { continue; }
        CGRect bounds = CGRectZero;
        if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)info[(id)kCGWindowBounds], &bounds)) { return NO; }
        if (bounds.size.width < 1 || bounds.size.height < 1) { return NO; }
        if (outBounds) { *outBounds = bounds; }
        return YES;
    }
    return NO;
}

- (WindowItem *)windowItemForID:(uint32_t)windowID {
    if (windowID == 0) { return nil; }
    NSArray *list = CFBridgingRelease(CGWindowListCopyWindowInfo(kCGWindowListOptionIncludingWindow, windowID));
    for (NSDictionary *info in list) {
        if ([info[(id)kCGWindowNumber] unsignedIntValue] != windowID) { continue; }
        WindowItem *item = FYWindowItemFromInfo(info);
        if (item) {
            item.windowID = windowID;   // 以解析目标为准
            return item;
        }
    }
    return nil;
}

- (NSArray<NSDictionary *> *)strongestDisplayTargetCandidates:(NSArray<NSDictionary *> *)candidates { return [FYDisplayTargetResolver strongestDisplayTargetCandidates:candidates]; }

- (uint32_t)resolveDisplayTargetWindowIDInWindowList:(NSArray<NSDictionary *> *)windowList
                                           selectedID:(uint32_t)selected ownerPID:(pid_t)ownerPID
                                           ambiguous:(BOOL *)outAmbiguous
                                                note:(NSString **)outNote { return [FYDisplayTargetResolver resolveWindowList:windowList selectedID:selected ownerPID:ownerPID geometry:self ambiguous:outAmbiguous note:outNote]; }
- (CGRect)displayBoundsContainingWindowInfo:(NSDictionary *)info { return FYDisplayContainingWindowInfo(info); }
- (CGRect)mainDisplayBounds { return CGDisplayBounds(CGMainDisplayID()); }
- (CGFloat)screenCoverageForBounds:(CGRect)bounds { return FYWindowScreenCoverage(bounds); }
@end
