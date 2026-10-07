#import "FYWindowManager.h"

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
static BOOL FYWindowTitleLooksLikeDialog(NSString *title) {
    if (title.length == 0) { return NO; }
    static NSArray<NSString *> *needles = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        needles = @[@"设置", @"偏好", @"属性", @"关于", @"统计", @"日志", @"更新", @"滤镜", @"交互", @"重命名",
                    @"Settings", @"Preferences", @"Properties", @"About", @"Stats", @"Log", @"Update",
                    @"Filters", @"Interact", @"Rename"];
    });
    for (NSString *needle in needles) {
        if ([title rangeOfString:needle options:NSCaseInsensitiveSearch].location != NSNotFound) { return YES; }
    }
    return NO;
}

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
static BOOL FYWindowInfoCoversMainDisplay(NSDictionary *info) {
    CGRect bounds = CGRectZero;
    if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)info[(id)kCGWindowBounds], &bounds)) { return NO; }
    CGRect display = CGDisplayBounds(CGMainDisplayID());
    CGFloat displayArea = display.size.width * display.size.height;
    if (displayArea <= 0) { return NO; }
    return (bounds.size.width * bounds.size.height) / displayArea >= 0.85;
}

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
static CGFloat FYWindowInfoDisplayCoverage(NSDictionary *info) {
    CGRect display = FYDisplayContainingWindowInfo(info);
    CGFloat displayArea = display.size.width * display.size.height;
    if (displayArea <= 0) { return 0; }
    CGRect bounds = CGRectZero;
    if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)info[(id)kCGWindowBounds], &bounds)) { return 0; }
    return (bounds.size.width * bounds.size.height) / displayArea;
}

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


static BOOL FYWindowInfoLooksLikePictureWindow(NSDictionary *info) {
    if ([info[(id)kCGWindowLayer] integerValue] != 0) { return NO; }
    CGRect bounds = CGRectZero;
    if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)info[(id)kCGWindowBounds], &bounds)) { return NO; }
    if (bounds.size.width < 320 || bounds.size.height < 200) { return NO; }
    return !FYWindowTitleLooksLikeDialog(info[(id)kCGWindowName] ?: @"");
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

- (NSArray<NSDictionary *> *)strongestDisplayTargetCandidates:(NSArray<NSDictionary *> *)candidates {
    NSArray<NSArray<NSDictionary *> *> *tiers = @[
        // ① 包含原窗口 + 与原窗口同屏（同屏全屏预览）
        ({ NSMutableArray *list = [NSMutableArray array];
           for (NSDictionary *c in candidates) { if ([c[@"contains"] boolValue] && [c[@"sameDisplay"] boolValue]) { [list addObject:c]; } }
           list; }),
        // ② 与原窗口同屏的投影形态
        ({ NSMutableArray *list = [NSMutableArray array];
           for (NSDictionary *c in candidates) { if ([c[@"sameDisplay"] boolValue]) { [list addObject:c]; } }
           list; }),
        // ③ 包含原窗口（可能换了显示器，但几何上就是原窗口那画面）
        ({ NSMutableArray *list = [NSMutableArray array];
           for (NSDictionary *c in candidates) { if ([c[@"contains"] boolValue]) { [list addObject:c]; } }
           list; })
    ];
    for (NSArray<NSDictionary *> *tier in tiers) {
        if (tier.count == 1) { return tier; }
        if (tier.count > 1) { return @[]; }
    }
    return @[];
}

- (uint32_t)resolveDisplayTargetWindowIDInWindowList:(NSArray<NSDictionary *> *)windowList
                                           selectedID:(uint32_t)selected ownerPID:(pid_t)ownerPID
                                           ambiguous:(BOOL *)outAmbiguous
                                                note:(NSString **)outNote {
    if (outAmbiguous) { *outAmbiguous = NO; }
    if (selected == 0) {
        if (outNote) { *outNote = @"请先选择显示窗口"; }
        return 0;
    }
    NSDictionary *selectedInfo = nil;
    for (NSDictionary *info in windowList) {
        if ([info[(id)kCGWindowNumber] unsignedIntValue] == selected) { selectedInfo = info; break; }
    }
    pid_t targetPID = 0;
    for (NSDictionary *info in windowList) {
        if ([info[(id)kCGWindowNumber] unsignedIntValue] == selected) {
            targetPID = (pid_t)[info[(id)kCGWindowOwnerPID] intValue];
            break;
        }
    }
    // 选中窗口不在屏幕上时（IncludingWindow 仍能查到所有者）也可能有投影接管。
    // 查不到所有者 = 观察不到这扇窗口（已关闭，或离线夹具）：沿用用户选择，保持既有行为，
    // 由「刷新窗口」那条路径给"原窗口已关闭，请重新选择"的明确提示。
    if (targetPID <= 0) { targetPID = ownerPID; }
    if (targetPID <= 0) { return selected; }

    NSMutableArray<NSDictionary *> *pictureWindows = [NSMutableArray array];
    for (NSDictionary *info in windowList) {
        if ((pid_t)[info[(id)kCGWindowOwnerPID] intValue] != targetPID) { continue; }
        if (!FYWindowInfoLooksLikePictureWindow(info)) { continue; }
        [pictureWindows addObject:info];
    }
    if (pictureWindows.count == 0) {
        // 这个应用此刻没有可当画布的窗口（只剩设置面板/被最小化）：沿用用户选择，但不猜别的窗口。
        if (selectedInfo) { return selected; }
        if (outNote) { *outNote = @"暂时找不到游戏画面所在窗口，请重新选择"; }
        return 0;
    }

    CGRect selectedBounds = CGRectZero;
    BOOL selectedUsable = selectedInfo && FYWindowInfoLooksLikePictureWindow(selectedInfo) &&
        CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)selectedInfo[(id)kCGWindowBounds], &selectedBounds);

    if (selectedUsable) {
        // 画面窗口按前台顺序（CGWindowList 就是前→后）排在选中窗口前面的那些。
        // 接管判据不再用"面积必须大 30%"（OBS 主窗口接近满屏时，全屏投影常常只大 20% 左右，
        // 会被这条否定掉，于是贴译留在旧窗口坐标上）。改用**几何覆盖关系**为主证据：
        //   · 同一应用（owner 相同）、是画面窗口、且排在选中窗口**前面**（投影/全屏预览在上层）；
        //   · 它基本盖住选中窗口（交叠 ≥ 选中窗口面积的 60%）→ 它显示的就是同一块画面；
        //   · "接近整屏"（≥ 主显示器 85%）作为全屏状态证据；"完全包含原窗口"作为强证据。
        // 多个候选时只有"完全包含 + 接近整屏"的那一个才接管，否则判为不可靠：
        // 隐藏旧贴译并提示重新选择（绝不猜、也不选"同进程最大的那个"）。
        CGFloat selectedArea = MAX((CGFloat)1, selectedBounds.size.width * selectedBounds.size.height);
        CGRect selectedDisplay = FYDisplayContainingWindowInfo(selectedInfo);
        NSMutableArray<NSDictionary *> *candidates = [NSMutableArray array];
        for (NSDictionary *info in windowList) {
            uint32_t wid = [info[(id)kCGWindowNumber] unsignedIntValue];
            if (wid == selected) { break; }                          // 只看排在选中窗口**前面**的
            if ((pid_t)[info[(id)kCGWindowOwnerPID] intValue] != targetPID) { continue; }
            if (!FYWindowInfoLooksLikePictureWindow(info)) { continue; }
            CGRect bounds = CGRectZero;
            if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)info[(id)kCGWindowBounds], &bounds)) { continue; }
            // 投影形态的证据（**交叠不是必要条件** —— 跨显示器的全屏投影与原窗口可以完全不相交）：
            //   · 在自己那块显示器上接近整屏（≥0.6）→ 全屏投影/全屏预览；
            //   · 或者基本包含原窗口（≥0.9，同屏全屏预览）。
            CGFloat displayCoverage = FYWindowInfoDisplayCoverage(info);
            CGRect candidateDisplay = FYDisplayContainingWindowInfo(info);
            CGRect inter = CGRectIntersection(bounds, selectedBounds);
            CGFloat overlap = CGRectIsNull(inter) ? 0 : (inter.size.width * inter.size.height) / selectedArea;
            BOOL displayUnresolvable = CGRectIsEmpty(candidateDisplay);
            CGFloat area = bounds.size.width * bounds.size.height;
            // 显示器查不到时（跨屏/夹具/刚接上的屏）：同 owner、画面窗口、排在前面、且不小于原窗口
            // 的大窗口仍然按"可能是投影"处理 —— 不能因为算不出覆盖率就静默沿用旧窗口。
            BOOL projectorShape = displayCoverage >= 0.6 ||
                                  (displayUnresolvable && area >= selectedArea * 0.9);
            BOOL containsSelected = overlap >= 0.9;
            if (!projectorShape && !containsSelected) { continue; }  // 同进程的小弹窗/设置面板不接管
            BOOL sameDisplayAsSelected = !CGRectIsEmpty(selectedDisplay) && !CGRectIsEmpty(candidateDisplay) &&
                                         CGRectEqualToRect(candidateDisplay, selectedDisplay);
            [candidates addObject:@{@"id": @(wid), @"overlap": @(overlap),
                                    @"displayCoverage": @(displayCoverage),
                                    @"contains": @(containsSelected),
                                    @"sameDisplay": @(sameDisplayAsSelected),
                                    @"fullscreen": @(FYWindowInfoCoversMainDisplay(info))}];
        }
        if (candidates.count == 0) { return selected; }
        if (candidates.count == 1) { return [candidates.firstObject[@"id"] unsignedIntValue]; }
        // 多个候选：优先"包含原窗口且同屏"，其次"与原窗口同屏"，再其次"完全包含原窗口"。
        NSArray<NSDictionary *> *strong = [self strongestDisplayTargetCandidates:candidates];
        if (strong.count == 1) { return [strong.firstObject[@"id"] unsignedIntValue]; }
        // 仍然分不出来：不静默沿用旧窗口，交给调用方隐藏旧贴译并提示重选。
        if (outAmbiguous) { *outAmbiguous = YES; }
        if (outNote) { *outNote = @"检测到多个可能是游戏画面的窗口，请重新选择显示窗口"; }
        return 0;
    }

    // 选中窗口不在屏幕上：找同进程里最大的那个画面窗口。
    uint32_t dominantID = 0;
    CGFloat dominantArea = 0;
    CGFloat runnerUpArea = 0;
    for (NSDictionary *info in pictureWindows) {
        CGRect bounds = CGRectZero;
        if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)info[(id)kCGWindowBounds], &bounds)) { continue; }
        CGFloat area = bounds.size.width * bounds.size.height;
        if (area > dominantArea) {
            runnerUpArea = dominantArea;
            dominantArea = area;
            dominantID = [info[(id)kCGWindowNumber] unsignedIntValue];
        } else if (area > runnerUpArea) {
            runnerUpArea = area;
        }
    }
    if (dominantID == 0) {
        if (outNote) { *outNote = @"暂时找不到游戏画面所在窗口，请重新选择"; }
        return 0;
    }
    if (pictureWindows.count == 1) {
        CGRect bounds = CGRectZero;
        CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)pictureWindows.firstObject[(id)kCGWindowBounds], &bounds);
        // 唯一的候选也太小（例如只剩一个设置面板）时不接管，避免把贴译贴到一个小弹窗上。
        if (bounds.size.width >= 320 && bounds.size.height >= 200 && FYWindowScreenCoverage(bounds) >= 0.25) {
            return dominantID;
        }
        if (outNote) { *outNote = @"暂时找不到游戏画面所在窗口，请重新选择"; }
        return 0;
    }
    // 多个候选：只有"主画面明显更大"时才跟随，否则提示选择，不猜。
    if (runnerUpArea > 0 && dominantArea >= runnerUpArea * 1.5) {
        return dominantID;
    }
    if (outAmbiguous) { *outAmbiguous = YES; }
    if (outNote) { *outNote = @"检测到多个可能是游戏画面的窗口，请重新选择显示窗口"; }
    return 0;
}
@end
