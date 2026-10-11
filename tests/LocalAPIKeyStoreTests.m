#import "FYLocalAPIKeyStore.h"
static NSUInteger checks;
static void Check(BOOL pass, NSString *message) {
    checks++; if (!pass) { fprintf(stderr, "FAIL: %s\n", message.UTF8String); exit(1); }
}
int main(void) { @autoreleasepool {
    NSString *root = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSString *path = [root stringByAppendingPathComponent:@"credentials/api-key.json"];
    NSString *value = nil;
    Check(FYReadAPIKeyFile(path, @"0.2.0", &value) == FYAPIKeyNotFound && !value, @"first launch has no credential");
    Check(FYWriteAPIKeyFile(path, @"0.2.0", @"synthetic-local-key") == FYAPIKeySuccess, @"save local credential");
    struct stat info;
    Check(stat(path.fileSystemRepresentation, &info) == 0 && (info.st_mode & 0777) == 0600, @"file is user read/write only");
    Check(stat(path.stringByDeletingLastPathComponent.fileSystemRepresentation, &info) == 0 && (info.st_mode & 0777) == 0700, @"credential directory is private");
    for (NSUInteger launch = 0; launch < 3; launch++) {
        value = nil;
        Check(FYReadAPIKeyFile(path, @"0.2.0", &value) == FYAPIKeySuccess && [value isEqual:@"synthetic-local-key"], @"repeated launches retain credential");
    }
    Check(FYReadAPIKeyFile(path, @"0.2.0", &value) == FYAPIKeySuccess && [value isEqual:@"synthetic-local-key"], @"same release after development rebuild still restores key");
    Check(FYWriteAPIKeyFile(path, @"0.2.1", @"synthetic-local-key") == FYAPIKeySuccess, @"save credential before a patch upgrade");
    NSData *savedCredential = [NSData dataWithContentsOfFile:path];
    for (NSString *version in @[@"0.2.2", @"0.3.0", @"1.0.0", @"0.2.0"]) {
        value = nil;
        Check(FYReadAPIKeyFile(path, version, &value) == FYAPIKeySuccess && [value isEqual:@"synthetic-local-key"], @"patch, minor, major upgrades and downgrade retain credential");
    }
    Check([[NSData dataWithContentsOfFile:path] isEqual:savedCredential], @"cross-version reads preserve the existing credential file without migration");
    NSDictionary *record = [NSJSONSerialization JSONObjectWithData:savedCredential options:0 error:NULL];
    Check([record[@"version"] isEqual:@"0.2.1"], @"saved version remains metadata after cross-version reads");
    NSData *before = [NSData dataWithContentsOfFile:path];
    Check(FYWriteAPIKeyFile(path, @"0.3.0", [@"x" stringByPaddingToLength:70000 withString:@"x" startingAtIndex:0]) == FYAPIKeyWriteError &&
        [[NSData dataWithContentsOfFile:path] isEqual:before], @"failed save preserves prior file");
    Check(FYReadAPIKeyFile(path, @"0.3.0", &value) == FYAPIKeySuccess && [value isEqual:@"synthetic-local-key"], @"failed save after upgrade keeps the old credential readable");
    NSString *link = [root stringByAppendingPathComponent:@"linked-key"];
    Check(symlink(path.fileSystemRepresentation, link.fileSystemRepresentation) == 0 && FYReadAPIKeyFile(link, @"0.2.0", &value) == FYAPIKeyReadError, @"do not follow credential symlinks");
    Check(FYWriteAPIKeyFile(path, @"0.2.0/12", @"synthetic-local-key") == FYAPIKeySuccess &&
        FYReadAPIKeyFile(path, @"0.2.0", &value) == FYAPIKeySuccess && [value isEqual:@"synthetic-local-key"], @"accept the short-lived version/build file format");
    savedCredential = [NSData dataWithContentsOfFile:path];
    Check(FYReadAPIKeyFile(path, @"0.3.0", &value) == FYAPIKeySuccess && [value isEqual:@"synthetic-local-key"], @"version/build legacy file restores across application versions");
    Check([[NSData dataWithContentsOfFile:path] isEqual:savedCredential], @"legacy cross-version read does not rewrite the file");
    Check(FYWriteAPIKeyFile(path, @"0.2.0", @"synthetic-replacement-key") == FYAPIKeySuccess, @"same release can save a replacement");
    Check(FYReadAPIKeyFile(path, @"0.2.0", &value) == FYAPIKeySuccess && [value isEqual:@"synthetic-replacement-key"], @"same release retains replacement");
    Check(FYReadAPIKeyFile(path, @"1.0.0", &value) == FYAPIKeySuccess && [value isEqual:@"synthetic-replacement-key"], @"later release retains replacement");
    Check(FYWriteAPIKeyFile(path, @"0.2.0", @"") == FYAPIKeySuccess && ![NSFileManager.defaultManager fileExistsAtPath:path], @"clear removes the file");
    value = @"synthetic-stale-value";
    Check(FYReadAPIKeyFile(path, @"1.0.0", &value) == FYAPIKeyNotFound && !value, @"new version cannot restore an explicitly cleared key");
    Check(FYWriteAPIKeyFile(path, @"0.2.0", @"") == FYAPIKeySuccess, @"clear missing file is harmless");
    [@"invalid-json" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    Check(FYReadAPIKeyFile(path, @"0.2.0", &value) == FYAPIKeyReadError, @"corrupt file is reported instead of silently overwritten");
    [NSFileManager.defaultManager removeItemAtPath:root error:NULL];
    printf("PASS: %lu local API key checks (synthetic credentials only)\n", (unsigned long)checks);
} return 0; }
