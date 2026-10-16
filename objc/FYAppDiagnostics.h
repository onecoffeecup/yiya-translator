#pragma once
#import <Cocoa/Cocoa.h>

FOUNDATION_EXPORT void FYInstallCrashMetadata(void);
FOUNDATION_EXPORT void FYCrashLifecycle(NSString *event);

@interface FYApplication : NSApplication
@end
