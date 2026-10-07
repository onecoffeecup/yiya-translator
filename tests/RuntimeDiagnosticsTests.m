#import <Foundation/Foundation.h>
#import "FYRuntimeDiagnostics.h"
#import <math.h>

static void Check(BOOL condition, NSString *message) {
    if (!condition) { NSLog(@"FAIL: %@", message); exit(1); }
}
static BOOL HasCode(NSArray *findings, NSString *code) {
    for (NSDictionary *finding in findings) { if ([finding[@"code"] isEqual:code]) { return YES; } }
    return NO;
}
int main(void) { @autoreleasepool {
    __block NSTimeInterval now = 1000;
    FYRuntimeDiagnostics *recorder = [[FYRuntimeDiagnostics alloc] initWithClock:^{ return now; } capacity:3];
    [recorder recordEvent:@"ocr" fields:@{@"window_id": @7, @"blocks": @0, @"elapsed_ms": @(NAN), @"api_key": @"SECRET_KEY", @"source": @"PRIVATE_DIALOGUE", @"ocr_lines": @[@"PRIVATE_DIALOGUE"]}];
    [recorder recordEvent:@"UNKNOWN_SECRET_EVENT" fields:@{}];
    Check(recorder.recentEvents.count == 1, @"only recognized events");
    Check(!recorder.recentEvents.firstObject[@"elapsed_ms"], @"reject non-finite values");
    NSMutableDictionary *snapshot = [@{@"screen_permission": @NO, @"own_windows": @1, @"external_windows": @0,
        @"candidate_windows": @0, @"selected_window_id": @7, @"display_window_id": @7,
        @"selected_is_self": @YES, @"selected_exists": @YES, @"selected_role": @"yiya",
        @"input_source": @0, @"api_key": @"SECRET_KEY", @"base_url": @"https://PRIVATE_ENDPOINT",
        @"app_version": @"0.1.0", @"windows": @[@{@"window_id": @7, @"role": @"yiya", @"name": @"PRIVATE_WINDOW_TITLE", @"owner": @"PRIVATE_APP_NAME"}]} mutableCopy];
    NSDictionary *report = [recorder reportForSnapshot:snapshot];
    NSString *json = [[NSString alloc] initWithData:[NSJSONSerialization dataWithJSONObject:report options:0 error:NULL] encoding:NSUTF8StringEncoding];
    Check(![json containsString:@"SECRET"] && ![json containsString:@"PRIVATE"], @"export excludes secrets, content, titles and endpoint");
    Check(HasCode(report[@"findings"], @"self_selected") && HasCode(report[@"findings"], @"only_self_visible") && HasCode(report[@"findings"], @"screen_permission_missing"), @"M1 reported self-only scenario diagnosed");
    snapshot[@"selected_is_self"] = @NO; snapshot[@"selected_role"] = @"quicktime";
    snapshot[@"screen_permission"] = @YES; snapshot[@"external_windows"] = @1; snapshot[@"candidate_windows"] = @1;
    [recorder recordEvent:@"ocr" fields:@{@"window_id": @7, @"blocks": @5, @"error_code": @0}];
    Check(!HasCode([recorder reportForSnapshot:snapshot][@"findings"], @"ocr_empty"), @"latest successful OCR supersedes earlier empty frame");
    [recorder recordEvent:@"capture" fields:@{@"window_id": @8, @"success": @NO}];
    Check(!HasCode([recorder reportForSnapshot:snapshot][@"findings"], @"capture_failed"), @"other window failures do not apply");
    [recorder recordEvent:@"http" fields:@{@"window_id": @7, @"generation": @1, @"http_status": @401}];
    snapshot[@"generation"] = @2;
    Check(!HasCode([recorder reportForSnapshot:snapshot][@"findings"], @"translation_request_failed"), @"obsolete requests do not diagnose current target");
    snapshot[@"generation"] = @1;
    Check(HasCode([recorder reportForSnapshot:snapshot][@"findings"], @"translation_request_failed"), @"current HTTP status diagnosed");
    Check(recorder.recentEvents.count == 3 && [[recorder reportForSnapshot:snapshot][@"discarded_events"] unsignedIntegerValue] > 0, @"bounded ring reports discarded events");
    now += 301;
    Check(recorder.recentEvents.count == 0, @"five-minute expiry also applies when idle");
    snapshot[@"input_source"] = @1; snapshot[@"screen_permission"] = @NO; snapshot[@"camera_authorized"] = @YES;
    Check(!HasCode([recorder reportForSnapshot:snapshot][@"findings"], @"screen_permission_missing"), @"capture card does not require screen permission");
    snapshot[@"quicktime_running"] = @YES; snapshot[@"quicktime_windows"] = @0;
    Check(HasCode([recorder reportForSnapshot:snapshot][@"findings"], @"quicktime_not_visible"), @"running QuickTime without visible movie window is distinguished");
    NSString *directory = [NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    [NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    NSURL *url = [NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"诊断.json"]];
    NSError *error = nil;
    Check([FYRuntimeDiagnostics writeReport:report toURL:url error:&error], @"export writes parseable artifact");
    NSDictionary *decoded = [NSJSONSerialization JSONObjectWithData:[NSData dataWithContentsOfURL:url] options:0 error:NULL];
    Check([decoded isEqual:report], @"saved report is the frozen incident, not later state");
    Check(![FYRuntimeDiagnostics writeReport:report toURL:[NSURL fileURLWithPath:[directory stringByAppendingPathComponent:@"missing/file.json"]] error:&error] && error, @"write failures are reported");
    [NSFileManager.defaultManager removeItemAtPath:directory error:NULL];
    puts("PASS RuntimeDiagnosticsTests: privacy, self-only detection, recovery, target isolation, bounded history, expiry, export and errors");
} return 0; }
