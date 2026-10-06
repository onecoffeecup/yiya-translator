#import <Cocoa/Cocoa.h>
#import <signal.h>
#import <fcntl.h>
#import <unistd.h>

// Crash metadata only: no captured images, OCR text, prompts or credentials.
// Ordinary capture diagnostics remain behind FuyiDiagEnabled().
static int FYCrashLogFD = -1;
static void FYCrashLifecycle(NSString *event) {
    NSData *bytes = [[NSString stringWithFormat:@"%@ %@ pid=%d\n", NSDate.date, event, getpid()] dataUsingEncoding:NSUTF8StringEncoding];
    if (FYCrashLogFD >= 0) { write(FYCrashLogFD, bytes.bytes, bytes.length); }
}
static void FYLogException(NSException *exception) {
    NSString *entry = [NSString stringWithFormat:@"%@ exception=%@\n%@\n", NSDate.date, exception.name,
                       [exception.callStackSymbols componentsJoinedByString:@"\n"]];
    NSData *bytes = [entry dataUsingEncoding:NSUTF8StringEncoding];
    if (FYCrashLogFD >= 0) { write(FYCrashLogFD, bytes.bytes, bytes.length); }
}
static void FYLogFatalSignal(int value) {
    // Only async-signal-safe operations. Let the default handler terminate and
    // preserve the OS crash report; never try to resume a corrupted process.
    const char prefix[] = "fatal signal=";
    char digits[3] = {(char)('0'+value/10), (char)('0'+value%10), '\n'};
    if (FYCrashLogFD >= 0) { write(FYCrashLogFD, prefix, sizeof(prefix)-1); write(FYCrashLogFD, digits, sizeof(digits)); }
    signal(value, SIG_DFL); raise(value);
}
static void FYInstallCrashMetadata(void) {
    NSString *directory = [NSSearchPathForDirectoriesInDomains(NSLibraryDirectory, NSUserDomainMask, YES).firstObject stringByAppendingPathComponent:@"Logs/浮译"];
    [[NSFileManager defaultManager] createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:nil error:NULL];
    NSString *path = [directory stringByAppendingPathComponent:@"crash-metadata.log"];
    NSDictionary *attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:path error:NULL];
    if ([attributes fileSize] > 1024*1024) {
        [[NSFileManager defaultManager] removeItemAtPath:[path stringByAppendingString:@".previous"] error:NULL];
        [[NSFileManager defaultManager] moveItemAtPath:path toPath:[path stringByAppendingString:@".previous"] error:NULL];
    }
    FYCrashLogFD = open(path.fileSystemRepresentation, O_WRONLY|O_APPEND|O_CREAT, 0600);
    NSString *startup = [NSString stringWithFormat:@"%@ startup pid=%d\n", NSDate.date, getpid()];
    NSData *bytes = [startup dataUsingEncoding:NSUTF8StringEncoding];
    if (FYCrashLogFD >= 0) { write(FYCrashLogFD, bytes.bytes, bytes.length); }
    NSSetUncaughtExceptionHandler(FYLogException);
    for (NSNumber *number in @[@(SIGABRT), @(SIGSEGV), @(SIGBUS), @(SIGILL), @(SIGFPE)]) { signal(number.intValue, FYLogFatalSignal); }
}
@interface FYApplication : NSApplication
@end
@implementation FYApplication
- (void)reportException:(NSException *)exception { FYLogException(exception); [super reportException:exception]; }
@end
