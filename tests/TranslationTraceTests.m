#import <Foundation/Foundation.h>
#import "FYTranslationTrace.h"
#import <sys/stat.h>
#import <unistd.h>

static void Check(BOOL passed, NSString *message) {
    if (!passed) { NSLog(@"FAIL %@", message); exit(2); }
}
static NSString *Arm(NSString *directory, NSTimeInterval now, NSTimeInterval duration) {
    NSString *session = NSUUID.UUID.UUIDString;
    NSDictionary *control = @{@"session": session, @"issued_at": @(now), @"expires_at": @(now + duration)};
    NSString *path = [directory stringByAppendingPathComponent:@"control.json"];
    [[NSJSONSerialization dataWithJSONObject:control options:0 error:NULL] writeToFile:path atomically:YES];
    chmod(path.fileSystemRepresentation, 0600);
    return session;
}
static NSUInteger TraceFileSize(NSString *path) {
    return [[[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL] fileSize];
}
int main(void) { @autoreleasepool {
    char root[] = "/tmp/yiya-trace-unit-XXXXXX";
    Check(mkdtemp(root) != NULL, @"isolated temp directory");
    NSString *directory = @(root);
    NSString *log = [directory stringByAppendingPathComponent:@"events.jsonl"];
    NSString *control = [directory stringByAppendingPathComponent:@"control.json"];
    __block NSTimeInterval now = 1000;
    FYTranslationTrace *trace = [[FYTranslationTrace alloc] initWithDirectory:directory clock:^{ return now; } maxBytes:1024 * 1024];
    Check([trace beginCycleForWindow:42 generation:1] == nil && ![NSFileManager.defaultManager fileExistsAtPath:log], @"disabled creates no log");
    Arm(directory, now, 120);
    Check([trace beginCycleForWindow:0 generation:1] == nil, @"no selected window means no cycle");
    NSDictionary *cycle = [trace beginCycleForWindow:42 generation:7];
    NSDictionary *frame = [trace frameContextForCycle:cycle index:19];
    NSDictionary *request = [trace requestContextForCycle:frame];
    Check(![trace frameContextForCycle:nil index:19] && !cycle[@"frame_id"], @"frame context is immutable and disabled is cheap");
    Check([request[@"frame_id"] isEqual:frame[@"frame_id"]] && [request[@"frame_index"] intValue] == 19,
          @"request retains captured frame identity");
    Check(cycle != nil && [request[@"cycle"] isEqual:cycle[@"cycle"]] && request[@"request_id"] != nil, @"cycle/request correlation");
    [trace recordEvent:@"ocr" context:cycle fields:@{@"ocr_lines": @[@{@"text": @"美代は占い", @"x": @0.2, @"y": @0.1, @"w": @0.5, @"h": @0.05, @"headers": @"SECRET_IN_LINE"}], @"Authorization": @"Bearer SECRET_TOKEN", @"api_key": @"SECRET_KEY", @"payload": @"SECRET_BODY", @"error": [NSError errorWithDomain:@"SECRET_DOMAIN" code:1 userInfo:@{NSLocalizedDescriptionKey:@"SECRET_ERROR"}]}];
    [trace recordEvent:@"request_complete" context:request fields:@{@"translation": @"美代迷上占卜了", @"success": @YES}];
    NSString *text = [NSString stringWithContentsOfFile:log encoding:NSUTF8StringEncoding error:NULL];
    Check([text containsString:@"美代"] && ![text containsString:@"SECRET"] && ![text containsString:@"Bearer"] && ![text containsString:@"Authorization"], @"strict schema excludes credentials, headers, errors and raw payloads");
    NSMutableSet *eventIDs = [NSMutableSet new];
    for (NSString *line in [text componentsSeparatedByString:@"\n"]) {
        if (!line.length) { continue; }
        NSDictionary *record = [NSJSONSerialization JSONObjectWithData:[line dataUsingEncoding:NSUTF8StringEncoding] options:0 error:NULL];
        Check(record && [record[@"cycle"] isEqual:cycle[@"cycle"]] && [record[@"window_id"] intValue] == 42 && record[@"time_unix_ms"], @"parseable timed selected-window JSONL");
        Check([record[@"schema_version"] intValue] == 2 && [[NSUUID alloc] initWithUUIDString:record[@"event_id"]] &&
              ![eventIDs containsObject:record[@"event_id"]], @"versioned unique events");
        [eventIDs addObject:record[@"event_id"]];
    }
    struct stat st; stat(log.fileSystemRepresentation, &st);
    Check((st.st_mode & 077) == 0, @"private file permissions");
    NSUInteger size = TraceFileSize(log);
    [NSFileManager.defaultManager removeItemAtPath:control error:NULL];
    [trace recordEvent:@"caption_apply" context:request fields:@{@"translation": @"停止后不记录"}];
    Check(TraceFileSize(log) == size && [trace beginCycleForWindow:42 generation:7] == nil, @"dynamic stop blocks old callbacks and new cycles");
    Arm(directory, now, 2);
    NSDictionary *second = [trace beginCycleForWindow:42 generation:7];
    size = TraceFileSize(log);
    [trace recordEvent:@"caption_apply" context:request fields:@{@"translation": @"旧会话不得串入新会话"}];
    Check(TraceFileSize(log) == size, @"session rearm rejects stale callback");
    now += 3;
    [trace recordEvent:@"caption_apply" context:second fields:@{}];
    Check(TraceFileSize(log) == size && [trace beginCycleForWindow:42 generation:7] == nil, @"timeout stops without timer or UI");
    Arm(directory, now, 301);
    Check([trace beginCycleForWindow:42 generation:7] == nil, @"cannot arm beyond five minutes");
    [NSFileManager.defaultManager removeItemAtPath:log error:NULL];
    Arm(directory, now, 120);
    FYTranslationTrace *small = [[FYTranslationTrace alloc] initWithDirectory:directory clock:^{ return now; } maxBytes:1024];
    NSDictionary *smallCycle = [small beginCycleForWindow:42 generation:1];
    for (int i = 0; i < 100; i++) { [small recordEvent:@"caption_apply" context:smallCycle fields:@{@"translation": @"限额不会写出半行，也不会继续扩张。"}]; }
    Check(TraceFileSize(log) <= 1024 && TraceFileSize(log) > 0 && [small beginCycleForWindow:42 generation:1] == nil, @"size cap blocks session");
    text = [NSString stringWithContentsOfFile:log encoding:NSUTF8StringEncoding error:NULL];
    Check([text hasSuffix:@"\n"], @"cap leaves complete JSONL records");
    [NSFileManager.defaultManager removeItemAtPath:log error:NULL];
    NSString *outside = [directory stringByAppendingPathComponent:@"outside"];
    [@"untouched" writeToFile:outside atomically:YES encoding:NSUTF8StringEncoding error:NULL];
    symlink(outside.fileSystemRepresentation, log.fileSystemRepresentation);
    Arm(directory, now, 120);
    [trace beginCycleForWindow:42 generation:1];
    Check([[NSString stringWithContentsOfFile:outside encoding:NSUTF8StringEncoding error:NULL] isEqual:@"untouched"], @"reject log symlink");
    [NSFileManager.defaultManager removeItemAtPath:control error:NULL];
    symlink(outside.fileSystemRepresentation, control.fileSystemRepresentation);
    Check([trace beginCycleForWindow:42 generation:1] == nil, @"reject control symlink");
    [NSFileManager.defaultManager removeItemAtPath:directory error:NULL];
    puts("PASS TranslationTraceTests: disabled, enable, correlation, schema, stop, timeout, rearm, size cap, permissions, symlinks; no UI/capture/network");
} return 0; }
