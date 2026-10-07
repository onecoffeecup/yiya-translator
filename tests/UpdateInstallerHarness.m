// Isolated executable for exercising Sparkle's real installer, never the player's app.
#import <Cocoa/Cocoa.h>
#import <Sparkle/Sparkle.h>
#import "FYAppUpdater.h"

static void Record(NSString *name, NSString *text) {
    NSString *root = NSBundle.mainBundle.infoDictionary[@"FYFixtureRoot"];
    [text writeToFile:[root stringByAppendingPathComponent:name] atomically:YES encoding:NSUTF8StringEncoding error:NULL];
}

@interface UpdateHarness : NSObject <NSApplicationDelegate, SPUUserDriver>
@property(nonatomic, strong) SPUUpdater *updater;
@end
@implementation UpdateHarness
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSString *mode = NSBundle.mainBundle.infoDictionary[@"FYFixtureMode"];
    if ([mode isEqualToString:@"menu"]) {
        FYAppUpdater *integration = [FYAppUpdater new];
        NSMenu *menu = [NSMenu new];
        [integration addItemsToApplicationMenu:menu];
        NSMenuItem *check = [menu itemAtIndex:0], *automatic = [menu itemAtIndex:1];
        NSCAssert([check.title isEqualToString:@"检查更新…"] && check.target != nil, @"Check menu is wired");
        NSCAssert([automatic.title isEqualToString:@"自动检查更新"], @"Automatic menu exists");
        [integration start];
        SPUUpdater *core = [[integration valueForKey:@"controller"] updater];
        NSCAssert(core.canCheckForUpdates && !core.automaticallyChecksForUpdates, @"Updater starts with fixture preferences");
        [integration validateMenuItem:automatic];
        NSCAssert(automatic.state == NSControlStateValueOff, @"Automatic checks initially off");
        [NSApp sendAction:automatic.action to:automatic.target from:automatic];
        [integration validateMenuItem:automatic];
        NSCAssert(core.automaticallyChecksForUpdates && automatic.state == NSControlStateValueOn, @"Toggle enables checks");
        [NSApp sendAction:automatic.action to:automatic.target from:automatic];
        NSCAssert(!core.automaticallyChecksForUpdates, @"Toggle restores preference");
        Record(@"menu-passed", @"Native menu and updater startup passed");
        [NSApp terminate:nil];
        return;
    }
    NSString *build = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    if ([build isEqualToString:@"2"]) {
        Record(@"relaunched", build);
        [NSApp terminate:nil];
        return;
    }
    self.updater = [[SPUUpdater alloc] initWithHostBundle:NSBundle.mainBundle
        applicationBundle:NSBundle.mainBundle userDriver:self delegate:nil];
    NSError *error = nil;
    if (![self.updater startUpdater:&error]) {
        Record(@"failure", error.description);
        [NSApp terminate:nil];
        return;
    }
    [self.updater checkForUpdates];
}
- (void)showUpdatePermissionRequest:(SPUUpdatePermissionRequest *)request reply:(void (^)(SUUpdatePermissionResponse *))reply {
    reply([[SUUpdatePermissionResponse alloc] initWithAutomaticUpdateChecks:NO sendSystemProfile:NO]);
}
- (void)showUserInitiatedUpdateCheckWithCancellation:(void (^)(void))cancel {}
- (void)showUpdateFoundWithAppcastItem:(SUAppcastItem *)item state:(SPUUserUpdateState *)state reply:(void (^)(SPUUserUpdateChoice))reply {
    Record(@"found", item.versionString);
    reply(SPUUserUpdateChoiceInstall);
}
- (void)showUpdateReleaseNotesWithDownloadData:(SPUDownloadData *)data {}
- (void)showUpdateReleaseNotesFailedToDownloadWithError:(NSError *)error {}
- (void)showUpdateNotFoundWithError:(NSError *)error acknowledgement:(void (^)(void))ack {
    if ([NSBundle.mainBundle.infoDictionary[@"FYFixtureMode"] isEqualToString:@"empty-feed"]) {
        Record(@"up-to-date", error.description);
    } else {
        Record(@"failure", error.description);
    }
    ack(); [NSApp terminate:nil];
}
- (void)showUpdaterError:(NSError *)error acknowledgement:(void (^)(void))ack {
    Record(@"failure", error.description); ack(); [NSApp terminate:nil];
}
- (void)showDownloadInitiatedWithCancellation:(void (^)(void))cancel {}
- (void)showDownloadDidReceiveExpectedContentLength:(uint64_t)length {}
- (void)showDownloadDidReceiveDataOfLength:(uint64_t)length {}
- (void)showDownloadDidStartExtractingUpdate { Record(@"extracting", @"yes"); }
- (void)showExtractionReceivedProgress:(double)progress {}
- (void)showReadyToInstallAndRelaunch:(void (^)(SPUUserUpdateChoice))reply { reply(SPUUserUpdateChoiceInstall); }
- (void)showInstallingUpdateWithApplicationTerminated:(BOOL)terminated retryTerminatingApplication:(void (^)(void))retry {}
- (void)showUpdateInstalledAndRelaunched:(BOOL)relaunched acknowledgement:(void (^)(void))ack { ack(); }
- (void)dismissUpdateInstallation {}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        UpdateHarness *delegate = [UpdateHarness new];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
