#import "FYAppUpdater.h"
#import <Sparkle/Sparkle.h>

@interface FYAppUpdater ()
@property(nonatomic, strong) SPUStandardUpdaterController *controller;
@end

@implementation FYAppUpdater
- (instancetype)init {
    self = [super init];
    if (self) {
        _controller = [[SPUStandardUpdaterController alloc] initWithStartingUpdater:NO
            updaterDelegate:nil userDriverDelegate:nil];
    }
    return self;
}

- (void)addItemsToApplicationMenu:(NSMenu *)menu {
    NSMenuItem *check = [menu addItemWithTitle:@"检查更新…"
        action:@selector(checkForUpdates:) keyEquivalent:@""];
    check.target = self.controller;
    NSMenuItem *automatic = [menu addItemWithTitle:@"自动检查更新"
        action:@selector(toggleAutomaticChecks:) keyEquivalent:@""];
    automatic.target = self;
    [menu addItem:NSMenuItem.separatorItem];
}

- (void)start { [self.controller startUpdater]; }

- (void)toggleAutomaticChecks:(id)sender {
    self.controller.updater.automaticallyChecksForUpdates =
        !self.controller.updater.automaticallyChecksForUpdates;
}

- (BOOL)validateMenuItem:(NSMenuItem *)item {
    if (item.action == @selector(toggleAutomaticChecks:)) {
        item.state = self.controller.updater.automaticallyChecksForUpdates ? NSControlStateValueOn : NSControlStateValueOff;
        return YES;
    }
    return NO;
}
@end
