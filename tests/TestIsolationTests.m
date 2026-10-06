#import "FYTestIsolation.h"
#import "FYLearningStore.h"
#import "FYLearningAnalyzer.h"

static void Check(BOOL condition, const char *message) {
    if (!condition) { fprintf(stderr, "FAIL: %s\n", message); exit(1); }
}

int main(int argc, const char *argv[]) { @autoreleasepool {
    NSString *mode = argc > 1 ? [NSString stringWithUTF8String:argv[1]] : @"positive";
    if ([mode isEqualToString:@"network"]) {
        FYLearningAnalyzer *analyzer = [FYLearningAnalyzer new];
        analyzer.baseURL = @"https://example.invalid/v1";
        analyzer.apiKey = @"synthetic-test-key"; analyzer.model = @"mock";
        [analyzer answerConversation:@[@{@"role":@"user", @"content":@"fixture"}]
                          completion:^(NSString *value, NSError *error) {}];
        Check(NO, "missing mock transport was not blocked");
    } else if ([mode isEqualToString:@"store"]) {
        (void)[[FYLearningStore alloc] initWithDatabasePath:@"/blocked-test-fixture/learning.sqlite3"];
        Check(NO, "non-temporary store was not blocked");
    } else if ([mode isEqualToString:@"sqlite"]) {
        sqlite3 *db = NULL; sqlite3_open("/blocked-test-fixture/learning.sqlite3", &db);
        Check(NO, "direct non-temporary SQLite write was not blocked");
    } else if ([mode isEqualToString:@"symlink"]) {
        NSString *link = [NSTemporaryDirectory() stringByAppendingPathComponent:@"escape"];
        Check([NSFileManager.defaultManager createSymbolicLinkAtPath:link withDestinationPath:@"/tmp" error:NULL], "symlink fixture");
        (void)[[FYLearningStore alloc] initWithDatabasePath:[link stringByAppendingPathComponent:@"forbidden.sqlite"]];
        Check(NO, "escaping symlink was not blocked");
    } else {
        Check([NSUserDefaults.standardUserDefaults objectForKey:@"fixture"] == nil, "fresh isolated preferences");
        [NSUserDefaults.standardUserDefaults setObject:@"synthetic" forKey:@"fixture"];
        Check([[NSUserDefaults.standardUserDefaults objectForKey:@"fixture"] isEqual:@"synthetic"], "preference roundtrip");
        [NSUserDefaults.standardUserDefaults removeObjectForKey:@"fixture"];
        Check([NSUserDefaults.standardUserDefaults objectForKey:@"fixture"] == nil, "preference removal");
        NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:@"allowed.sqlite"];
        (void)[[FYLearningStore alloc] initWithDatabasePath:path];
        sqlite3 *db = NULL;
        Check(sqlite3_open(path.UTF8String, &db) == SQLITE_OK, "temporary SQLite opens");
        Check(sqlite3_exec(db, "CREATE TABLE fixture(value TEXT)", NULL, NULL, NULL) == SQLITE_OK, "temporary SQLite writes");
        sqlite3_close(db);
        NSUInteger before = FYTestCaptureCount();
        CGImageRef image = CGWindowListCreateImage(CGRectNull, kCGWindowListOptionIncludingWindow, 4242, 0);
        Check(image && CGImageGetWidth(image) == 16 && FYTestCaptureCount() == before + 1, "capture is synthetic");
        CGImageRelease(image);
        for (NSString *negative in @[@"network", @"store", @"sqlite", @"symlink"]) {
            NSTask *task = [NSTask new];
            task.executableURL = [NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[0]]];
            task.arguments = @[negative];
            NSPipe *diagnostics = [NSPipe pipe]; task.standardError = diagnostics;
            Check([task launchAndReturnError:NULL], "negative guard subprocess launch");
            [task waitUntilExit];
            NSString *message = [[NSString alloc] initWithData:[diagnostics.fileHandleForReading readDataToEndOfFile] encoding:NSUTF8StringEncoding];
            for (NSString *line in [message componentsSeparatedByString:@"\n"]) {
                if ([line hasPrefix:@"TEST_ISOLATION_ROOT="]) { fprintf(stderr, "%s\n", line.UTF8String); }
            }
            Check([message containsString:@"TEST_ISOLATION_BLOCKED:"], "negative guard must report isolation failure");
            Check(task.terminationReason == NSTaskTerminationReasonExit && task.terminationStatus == 86,
                  "negative guard must fail closed with exit 86");
        }
        puts("PASS: isolated preferences, temporary SQLite, synthetic capture; network/store/direct SQLite/symlink escapes blocked");
    }
} return 0; }
