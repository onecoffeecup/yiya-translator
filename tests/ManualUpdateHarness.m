// Visible, isolated rehearsal using the production menu and Sparkle standard UI.
#import <Cocoa/Cocoa.h>
#import <CommonCrypto/CommonDigest.h>
#import <sqlite3.h>
#import "FYAppUpdater.h"
#import "FYLocalAPIKeyStore.h"

static NSDictionary *ReadJSON(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    id result = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    return [result isKindOfClass:NSDictionary.class] ? result : @{};
}

static NSString *HashFile(NSString *path) {
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return @"";
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(data.bytes, (CC_LONG)data.length, digest);
    NSMutableString *text = [NSMutableString new];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [text appendFormat:@"%02x", digest[i]];
    return text;
}

static NSUInteger Permissions(NSString *path) {
    return [[NSFileManager.defaultManager attributesOfItemAtPath:path error:NULL][NSFilePosixPermissions] unsignedIntegerValue] & 0777;
}

static BOOL IsTrue(NSDictionary *record, NSString *key) { return [record[key] boolValue]; }

static NSDictionary *VerifyPlayerData(NSString *root) {
    NSDictionary *baseline = ReadJSON([root stringByAppendingPathComponent:@"baseline.json"]);
    NSString *dataRoot = baseline[@"data_root"] ?: @"";
    NSString *keyPath = [dataRoot stringByAppendingPathComponent:@"credentials/api-key.json"];
    NSString *keyValue = nil;
    BOOL keyReadable = FYReadAPIKeyFile(keyPath, FYAPIKeyVersion(), &keyValue) == FYAPIKeySuccess &&
        [keyValue isEqualToString:@"SYNTHETIC-MANUAL-UPDATE-ONLY"];
    NSDictionary *settings = ReadJSON([dataRoot stringByAppendingPathComponent:@"settings.json"]);
    NSInteger wordCount = -1;
    sqlite3 *database = NULL;
    if (sqlite3_open_v2([[dataRoot stringByAppendingPathComponent:@"learning.sqlite3"] fileSystemRepresentation],
                       &database, SQLITE_OPEN_READONLY, NULL) == SQLITE_OK) {
        sqlite3_stmt *query = NULL;
        if (sqlite3_prepare_v2(database, "select count(*) from saved_words", -1, &query, NULL) == SQLITE_OK &&
            sqlite3_step(query) == SQLITE_ROW) wordCount = sqlite3_column_int(query, 0);
        sqlite3_finalize(query);
    }
    if (database) sqlite3_close(database);
    NSMutableDictionary *record = [@{
        @"build": NSBundle.mainBundle.infoDictionary[@"CFBundleVersion"],
        @"version": FYAPIKeyVersion(), @"pid": @(getpid()),
        @"application_path": NSBundle.mainBundle.bundlePath,
        @"application_path_matches": @([NSBundle.mainBundle.bundlePath isEqualToString:baseline[@"installed_app"]]),
        @"key_readable": @(keyReadable),
        @"credential_permissions_ok": @(Permissions(keyPath) == 0600 && Permissions(keyPath.stringByDeletingLastPathComponent) == 0700),
        @"font_size": settings[@"font_size"] ?: @0, @"saved_word_count": @(wordCount)
    } mutableCopy];
    NSDictionary *files = @{@"credentials_unchanged": @"credentials/api-key.json",
                            @"settings_unchanged": @"settings.json", @"learning_unchanged": @"learning.sqlite3"};
    BOOL unchanged = YES;
    for (NSString *field in files) {
        NSString *relative = files[field];
        BOOL matches = [HashFile([dataRoot stringByAppendingPathComponent:relative]) isEqualToString:baseline[@"hashes"][relative]];
        record[field] = @(matches);
        unchanged = unchanged && matches;
    }
    NSDictionary *original = ReadJSON([root stringByAppendingPathComponent:@"launch-build-13.json"]);
    record[@"relaunched"] = @([record[@"build"] isEqualToString:@"14"] && [original[@"pid"] intValue] > 0 &&
                              [original[@"pid"] intValue] != getpid() && [original[@"build"] isEqualToString:@"13"]);
    record[@"data_preserved"] = @(unchanged && keyReadable && IsTrue(record, @"credential_permissions_ok") &&
                                  [record[@"font_size"] integerValue] == 24 && wordCount == 1);
    record[@"upgrade_passed"] = @(IsTrue(record, @"data_preserved") && IsTrue(record, @"relaunched") &&
                                  IsTrue(record, @"application_path_matches"));
    return record;
}

@interface ManualUpdateHarness : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) FYAppUpdater *integration;
@property(nonatomic, strong) NSMenuItem *checkItem;
@property(nonatomic, strong) NSButton *checkButton;
@end

@implementation ManualUpdateHarness
- (NSTextField *)label:(NSString *)text size:(CGFloat)size bold:(BOOL)bold {
    NSTextField *field = [NSTextField wrappingLabelWithString:text];
    field.font = [NSFont systemFontOfSize:size weight:bold ? NSFontWeightSemibold : NSFontWeightRegular];
    field.selectable = YES;
    field.translatesAutoresizingMaskIntoConstraints = NO;
    field.textColor = NSColor.labelColor;
    return field;
}
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    NSString *root = NSBundle.mainBundle.infoDictionary[@"FYFixtureRoot"];
    NSDictionary *record = VerifyPlayerData(root);
    BOOL newer = [record[@"build"] isEqualToString:@"14"];
    NSString *reportName = newer ? @"verification.json" : @"launch-build-13.json";
    [[NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingPrettyPrinted error:NULL]
        writeToFile:[root stringByAppendingPathComponent:reportName] atomically:YES];

    self.integration = [FYAppUpdater new];
    NSMenu *main = [NSMenu new], *applicationMenu = [NSMenu new];
    NSMenuItem *applicationItem = [main addItemWithTitle:@"译芽更新验收" action:NULL keyEquivalent:@""];
    applicationItem.submenu = applicationMenu;
    [self.integration addItemsToApplicationMenu:applicationMenu];
    self.checkItem = [applicationMenu itemAtIndex:0];
    [applicationMenu addItemWithTitle:@"退出译芽更新验收" action:@selector(terminate:) keyEquivalent:@"q"];
    NSApp.mainMenu = main;

    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 560, 340)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskMiniaturizable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"译芽更新验收";
    self.window.releasedWhenClosed = NO;
    self.window.contentMinSize = NSMakeSize(500, 320);
    NSStackView *stack = [[NSStackView alloc] initWithFrame:NSZeroRect];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [self.window.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:self.window.contentView.leadingAnchor constant:28],
        [stack.trailingAnchor constraintEqualToAnchor:self.window.contentView.trailingAnchor constant:-28],
        [stack.topAnchor constraintEqualToAnchor:self.window.contentView.topAnchor constant:28],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:self.window.contentView.bottomAnchor constant:-24]
    ]];
    NSString *headline = newer ? (IsTrue(record, @"upgrade_passed") ? @"升级成功，测试资料已保留" : @"升级后的检查发现异常") : @"准备体验应用内更新";
    [stack addArrangedSubview:[self label:headline size:24 bold:YES]];
    [stack addArrangedSubview:[self label:[NSString stringWithFormat:@"当前版本 0.2.1 · build %@\n本次演练：build 13 → 14", record[@"build"]] size:16 bold:NO]];
    NSString *details = [NSString stringWithFormat:@"合成 API Key：%@　字体设置：%@\n收藏：%ld 条　资料文件：%@",
        IsTrue(record, @"key_readable") ? @"可读取" : @"检查失败",
        [record[@"font_size"] integerValue] == 24 ? @"24，已保留" : @"检查失败",
        (long)[record[@"saved_word_count"] integerValue], IsTrue(record, @"data_preserved") ? @"完整" : @"检查失败"];
    [stack addArrangedSubview:[self label:details size:14 bold:NO]];
    NSString *hint = newer ? @"检查结果已保存。关闭本窗口即可结束演练。" : @"点击检查后，在更新弹窗中安装；重启后这里会显示结果。";
    [stack addArrangedSubview:[self label:hint size:14 bold:NO]];
    self.checkButton = [NSButton buttonWithTitle:@"检查测试更新" target:self action:@selector(checkUpdates:)];
    self.checkButton.bezelStyle = NSBezelStyleRounded;
    self.checkButton.keyEquivalent = @"\r";
    self.checkButton.accessibilityLabel = @"检查测试更新";
    [stack addArrangedSubview:self.checkButton];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
    [self.integration start];
    [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(refreshButton:) userInfo:nil repeats:YES];
    if (!newer && [NSProcessInfo.processInfo.arguments containsObject:@"--check-update"]) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, NSEC_PER_SEC), dispatch_get_main_queue(), ^{ [self checkUpdates:nil]; });
    }
}
- (void)refreshButton:(id)sender {
    id target = self.checkItem.target;
    self.checkButton.enabled = [target respondsToSelector:@selector(validateMenuItem:)] ? [target validateMenuItem:self.checkItem] : YES;
}
- (void)checkUpdates:(id)sender {
    [self refreshButton:nil];
    if (self.checkButton.enabled) [NSApp sendAction:self.checkItem.action to:self.checkItem.target from:self.checkItem];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { return YES; }
@end

int main(void) {
    @autoreleasepool {
        NSApplication *application = NSApplication.sharedApplication;
        [application setActivationPolicy:NSApplicationActivationPolicyRegular];
        ManualUpdateHarness *delegate = [ManualUpdateHarness new];
        application.delegate = delegate;
        [application run];
    }
    return 0;
}
