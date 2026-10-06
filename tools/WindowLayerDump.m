// 只读窗口层级诊断：看前台应用、各窗口的 CGWindowLayer 与是否在屏幕上。
// 用于排查「OBS 全屏预览/预览投影把译芽字幕窗挡住或挤掉」这类问题。
// 不截屏、不读窗口内容、不申请任何权限（只读窗口列表元数据）。
#import <Cocoa/Cocoa.h>
#import <CoreGraphics/CoreGraphics.h>

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        BOOL all = NO, json = NO;
        for (int i = 1; i < argc; i++) {
            if (strcmp(argv[i], "--all") == 0) { all = YES; }
            if (strcmp(argv[i], "--json") == 0) { json = YES; }
        }
        NSRunningApplication *front = NSWorkspace.sharedWorkspace.frontmostApplication;
        if (json) {
            NSArray *infos = CFBridgingRelease(CGWindowListCopyWindowInfo(
                kCGWindowListOptionOnScreenOnly | kCGWindowListExcludeDesktopElements, kCGNullWindowID));
            NSMutableArray *windows = [NSMutableArray array];
            for (NSDictionary *info in infos) {
                CGRect bounds = CGRectZero;
                CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)info[(id)kCGWindowBounds], &bounds);
                [windows addObject:@{
                    @"owner": info[(id)kCGWindowOwnerName] ?: @"",
                    @"pid": info[(id)kCGWindowOwnerPID] ?: @0,
                    @"layer": info[(id)kCGWindowLayer] ?: @0,
                    @"window_id": info[(id)kCGWindowNumber] ?: @0,
                    @"name": info[(id)kCGWindowName] ?: @"",
                    @"x": @(bounds.origin.x), @"y": @(bounds.origin.y),
                    @"w": @(bounds.size.width), @"h": @(bounds.size.height),
                }];
            }
            NSDictionary *record = @{
                @"time_unix_ms": @((long long)(NSDate.date.timeIntervalSince1970 * 1000)),
                @"frontmost_name": front.localizedName ?: @"",
                @"frontmost_pid": @(front.processIdentifier),
                @"frontmost_bundle": front.bundleIdentifier ?: @"",
                @"screens": @(NSScreen.screens.count),
                @"windows": windows,
            };
            NSData *data = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:NULL];
            fwrite(data.bytes, 1, data.length, stdout);
            fputc('\n', stdout);
            return 0;
        }
        printf("前台应用: %s (pid %d, %s)\n", front.localizedName.UTF8String ?: "?", front.processIdentifier,
               front.bundleIdentifier.UTF8String ?: "?");
        printf("屏幕数: %lu\n", (unsigned long)NSScreen.screens.count);
        for (NSScreen *screen in NSScreen.screens) {
            printf("  屏幕: %.0fx%.0f frame=(%.0f,%.0f) visible=(%.0f,%.0f,%.0f,%.0f)\n",
                   screen.frame.size.width, screen.frame.size.height,
                   screen.frame.origin.x, screen.frame.origin.y,
                   screen.visibleFrame.origin.x, screen.visibleFrame.origin.y,
                   screen.visibleFrame.size.width, screen.visibleFrame.size.height);
        }
        NSArray *infos = CFBridgingRelease(CGWindowListCopyWindowInfo(
            (all ? kCGWindowListOptionAll : kCGWindowListOptionOnScreenOnly) | kCGWindowListExcludeDesktopElements,
            kCGNullWindowID));
        NSMutableArray *rows = [NSMutableArray array];
        for (NSDictionary *info in infos) {
            NSString *owner = info[(id)kCGWindowOwnerName] ?: @"";
            NSNumber *layer = info[(id)kCGWindowLayer] ?: @0;
            NSNumber *pid = info[(id)kCGWindowOwnerPID] ?: @0;
            NSNumber *number = info[(id)kCGWindowNumber] ?: @0;
            NSString *name = info[(id)kCGWindowName] ?: @"";
            CGRect bounds = CGRectZero;
            CGRectMakeWithDictionaryRepresentation((__bridge CFDictionaryRef)info[(id)kCGWindowBounds], &bounds);
            [rows addObject:@{@"owner": owner, @"layer": layer, @"pid": pid, @"number": number,
                              @"name": name, @"bounds": [NSValue valueWithRect:NSRectFromCGRect(bounds)]}];
        }
        [rows sortUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
            NSInteger la = [a[@"layer"] integerValue], lb = [b[@"layer"] integerValue];
            if (la != lb) { return la > lb ? NSOrderedAscending : NSOrderedDescending; }
            return [a[@"owner"] localizedCaseInsensitiveCompare:b[@"owner"]];
        }];
        printf("\n%-22s %5s %7s %10s  %-26s %s\n", "窗口所属", "层级", "pid", "windowID", "位置大小", "标题");
        for (NSDictionary *row in rows) {
            NSRect rect = [row[@"bounds"] rectValue];
            BOOL interesting = [row[@"owner"] containsString:@"OBS"] ||
                               [row[@"owner"] containsString:@"QuickTime"] ||
                               [row[@"owner"] containsString:@"译芽"] ||
                               [row[@"owner"] containsString:@"LiveCaptionTranslator"];
            printf("%s%-22s %5ld %7d %10u  %-26s %s\n",
                   interesting ? "→ " : "  ",
                   [row[@"owner"] UTF8String], (long)[row[@"layer"] integerValue],
                   [row[@"pid"] intValue], [row[@"number"] unsignedIntValue],
                   NSStringFromRect(rect).UTF8String,
                   ([row[@"name"] length] > 0 ? [row[@"name"] UTF8String] : ""));
        }
        printf("\n提示：CGWindowLayer 越大越靠上；译芽字幕窗显示时是 3（NSFloatingWindowLevel）。\n");
    }
    return 0;
}
