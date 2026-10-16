#import "app/FYAppDelegate.h"
#import "FYAppDiagnostics.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        FYInstallCrashMetadata();
        NSApplication *application = [FYApplication sharedApplication];
        AppDelegate *delegate = [[AppDelegate alloc] init];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
