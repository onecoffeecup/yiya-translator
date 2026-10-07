#define main FYAppMain
#import "../objc/LiveCaptionTranslator.m"
#undef main
static NSUInteger checks;
static void Check(BOOL pass, NSString *message) {
    checks++; if (!pass) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
static AppDelegate *NewSettingsApp(void) {
    AppDelegate *app = [AppDelegate new];
    [app createMainWindow]; [app createCaptionWindow]; [app loadSettings];
    return app;
}
int main(void) { @autoreleasepool {
    [NSApplication sharedApplication]; [NSApp setActivationPolicy:NSApplicationActivationPolicyAccessory];
    NSUserDefaults *defaults = NSUserDefaults.standardUserDefaults;
    [defaults setObject:@{@"apiKey":@"synthetic-legacy-key", @"baseURL":@"https://example.invalid"} forKey:SettingsKey];
    FYTestLocalAPIKeyValue = nil;
    AppDelegate *app = NewSettingsApp();
    Check(app.apiKeyField.stringValue.length == 0 && !app.credentialLoadFailed, @"first run requests a key without Keychain access");
    Check([defaults objectForKey:SettingsKey][@"apiKey"] == nil, @"legacy key is not reused for a new version");
    app.apiKeyField.stringValue = @"synthetic-local-key";
    FYTestLocalAPIKeyFailWrites = YES;
    [app saveSettings:nil];
    Check(FYTestLocalAPIKeyValue == nil && app.persistedAPIKey.length == 0 && app.serviceErrorLabel.stringValue.length > 0, @"save failure is visible and does not mark the key persisted");
    FYTestLocalAPIKeyFailWrites = NO;
    [app saveSettings:nil];
    Check([FYTestLocalAPIKeyValue isEqual:@"synthetic-local-key"], @"save key to dedicated local store");
    Check([defaults objectForKey:SettingsKey][@"apiKey"] == nil, @"ordinary settings omit credential");
    for (NSUInteger launch = 0; launch < 3; launch++) {
        AppDelegate *reopened = NewSettingsApp();
        Check([reopened.apiKeyField.stringValue isEqual:@"synthetic-local-key"] && !reopened.credentialLoadFailed, @"repeated startups automatically restore key");
        [reopened.mainWindow orderOut:nil]; [reopened.captionPanel orderOut:nil];
    }
    [app clearAPIKey:nil];
    Check(FYTestLocalAPIKeyValue == nil && app.persistedAPIKey.length == 0, @"clear removes persisted key");
    Check([defaults objectForKey:SettingsKey][@"apiKey"] == nil, @"clear does not move key to preferences");
    [app.mainWindow orderOut:nil]; [app.captionPanel orderOut:nil];
    printf("PASS: %lu credential settings checks (isolated defaults/store, no network)\n", (unsigned long)checks);
} return 0; }
