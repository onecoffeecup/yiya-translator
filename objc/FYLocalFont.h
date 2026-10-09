#pragma once
#import <Cocoa/Cocoa.h>
#import <CoreText/CoreText.h>

// Resolve the theme's optional system fonts without requesting a download.
static inline NSFont * _Nullable FYLocalFontNamed(NSString * _Nonnull name, CGFloat size) {
    static NSSet<NSString *> *availableNames;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        NSArray *names = CFBridgingRelease(CTFontManagerCopyAvailablePostScriptNames());
        availableNames = [NSSet setWithArray:names ?: @[]];
    });
    // NSFont name matching may synchronously download a known optional face,
    // so even a nil-coalescing system fallback must not look up an absent name.
    if (![availableNames containsObject:name]) return nil;
    return [NSFont fontWithName:name size:size];
}
