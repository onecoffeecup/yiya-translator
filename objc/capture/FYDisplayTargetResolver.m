#import "FYDisplayTargetResolver.h"
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

static BOOL FYWindowInfoLooksLikePictureWindow(NSDictionary *info) {
    if ([info[(id)kCGWindowLayer] integerValue] != 0) { return NO; }
    CGRect bounds = CGRectZero;
    if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)info[(id)kCGWindowBounds], &bounds)) { return NO; }
    if (bounds.size.width < 320 || bounds.size.height < 200) { return NO; }
    return !FYWindowTitleLooksLikeDialog(info[(id)kCGWindowName] ?: @"");
}

static BOOL FYWindowInfoCoversMainDisplay(NSDictionary *info, id<FYDisplayTargetGeometry> geometry) {
    CGRect bounds = CGRectZero;
    if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)info[(id)kCGWindowBounds], &bounds)) { return NO; }
    CGRect display = [geometry mainDisplayBounds];
    CGFloat displayArea = display.size.width * display.size.height;
    if (displayArea <= 0) { return NO; }
    return (bounds.size.width * bounds.size.height) / displayArea >= 0.85;
}

static CGFloat FYWindowInfoDisplayCoverage(NSDictionary *info, id<FYDisplayTargetGeometry> geometry) {
    CGRect display = [geometry displayBoundsContainingWindowInfo:info];
    CGFloat displayArea = display.size.width * display.size.height;
    if (displayArea <= 0) { return 0; }
    CGRect bounds = CGRectZero;
    if (!CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)info[(id)kCGWindowBounds], &bounds)) { return 0; }
    return (bounds.size.width * bounds.size.height) / displayArea;
}
@implementation FYDisplayTargetResolver
+ (NSArray<NSDictionary *> *)strongestDisplayTargetCandidates:(NSArray<NSDictionary *> *)candidates {
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

+ (uint32_t)resolveWindowList:(NSArray<NSDictionary *> *)windowList selectedID:(uint32_t)selected ownerPID:(pid_t)ownerPID geometry:(id<FYDisplayTargetGeometry>)geometry ambiguous:(BOOL *)outAmbiguous note:(NSString **)outNote {
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
        CGRect selectedDisplay = [geometry displayBoundsContainingWindowInfo:selectedInfo];
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
            CGFloat displayCoverage = FYWindowInfoDisplayCoverage(info, geometry);
            CGRect candidateDisplay = [geometry displayBoundsContainingWindowInfo:info];
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
                                    @"fullscreen": @(FYWindowInfoCoversMainDisplay(info, geometry))}];
        }
        if (candidates.count == 0) { return selected; }
        if (candidates.count == 1) { return [candidates.firstObject[@"id"] unsignedIntValue]; }
        // 多个候选：优先"包含原窗口且同屏"，其次"与原窗口同屏"，再其次"完全包含原窗口"。
        NSArray<NSDictionary *> *strong = [geometry strongestDisplayTargetCandidates:candidates];
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
        if (bounds.size.width >= 320 && bounds.size.height >= 200 && [geometry screenCoverageForBounds:bounds] >= 0.25) {
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
