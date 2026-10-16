#pragma once
#import <Foundation/Foundation.h>
static inline NSString *FYTrim(NSString *value) {
    return [value stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceAndNewlineCharacterSet]];
}
static inline NSString *FYTextHash(NSString *text) {
    // FNV-1a 64-bit，用于缓存键，不用于安全。
    uint64_t hash = 1469598103934665603ULL;
    for (NSUInteger i = 0; i < text.length; i++) {
        unichar c = [text characterAtIndex:i];
        hash ^= (uint64_t)c;
        hash *= 1099511628211ULL;
    }
    return [NSString stringWithFormat:@"%016llx", (unsigned long long)hash];
}

