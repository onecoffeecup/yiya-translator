#import "FYTestIsolation.h"
#import "FYLearningStore.h"
#import <objc/runtime.h>
#include <stdlib.h>
#include <stdio.h>
#include <limits.h>
#undef NSUserDefaults
#undef NSURLSession
#undef NSTemporaryDirectory
#undef CGWindowListCreateImage
#undef sqlite3_open
#undef sqlite3_open_v2

static void FYIsolationFailure(const char *reason) __attribute__((noreturn));
static void FYIsolationFailure(const char *reason) {
    // Never print request contents, configuration, or external paths.
    fprintf(stderr, "TEST_ISOLATION_BLOCKED: %s\n", reason);
    fflush(stderr);
    _Exit(86);
}

NSString *FYTestTemporaryDirectory(void) {
    static NSString *root;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        char pattern[] = "/tmp/yiya-tests-XXXXXX";
        char *directory = mkdtemp(pattern);
        if (!directory) { FYIsolationFailure("cannot create private temporary directory"); }
        char canonical[PATH_MAX];
        if (!realpath(directory, canonical)) { FYIsolationFailure("cannot resolve private temporary directory"); }
        root = [NSString stringWithUTF8String:canonical];
        fprintf(stderr, "TEST_ISOLATION_ROOT=%s\n", root.UTF8String);
    });
    return root;
}

static NSString *FYCanonicalPath(NSString *path) {
    if (!path.isAbsolutePath || [path.pathComponents containsObject:@".."]) { return nil; }
    // realpath the nearest EXISTING ancestor: Foundation may leave a symlink
    // unresolved when the database leaf does not exist yet.
    NSMutableArray<NSString *> *tail = [NSMutableArray new];
    NSString *ancestor = path;
    char canonical[PATH_MAX];
    while (!realpath(ancestor.fileSystemRepresentation, canonical)) {
        if ([ancestor isEqualToString:@"/"] || !ancestor.length) { return nil; }
        [tail insertObject:ancestor.lastPathComponent atIndex:0];
        ancestor = ancestor.stringByDeletingLastPathComponent;
    }
    NSString *result = [NSString stringWithUTF8String:canonical];
    for (NSString *component in tail) { result = [result stringByAppendingPathComponent:component]; }
    return result;
}
static BOOL FYIsTemporaryPath(NSString *path) {
    NSString *resolved = FYCanonicalPath(path);
    return [resolved hasPrefix:[FYTestTemporaryDirectory() stringByAppendingString:@"/"]];
}

@implementation FYTestDefaults {
    NSMutableDictionary *_values;
}
+ (instancetype)standardUserDefaults {
    static FYTestDefaults *defaults;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ defaults = [self new]; });
    return defaults;
}
- (instancetype)init { if ((self = [super init])) { _values = [NSMutableDictionary new]; } return self; }
- (id)objectForKey:(NSString *)key { @synchronized(self) { return _values[key]; } }
- (void)setObject:(id)value forKey:(NSString *)key { @synchronized(self) { _values[key] = [value copy]; } }
- (void)removeObjectForKey:(NSString *)key { @synchronized(self) { [_values removeObjectForKey:key]; } }
@end

@implementation FYTestURLSession
+ (instancetype)sharedSession { return [self new]; }
- (NSURLSessionDataTask *)dataTaskWithRequest:(NSURLRequest *)request
                          completionHandler:(void (^)(NSData *, NSURLResponse *, NSError *))completion {
    FYIsolationFailure("real network fallback; inject a mock transport");
}
@end

// Validate before FYLearningStore can create directories or open a database.
@implementation FYLearningStore (TestIsolation)
+ (void)load {
    Method original = class_getInstanceMethod(self, @selector(initWithDatabasePath:));
    Method guarded = class_getInstanceMethod(self, @selector(fy_test_initWithDatabasePath:));
    if (!original || !guarded) { FYIsolationFailure("store guard could not be installed"); }
    method_exchangeImplementations(original, guarded);
}
- (instancetype)fy_test_initWithDatabasePath:(NSString *)path {
    if (!FYIsTemporaryPath(path)) { FYIsolationFailure("learning store outside private temporary directory"); }
    return [self fy_test_initWithDatabasePath:path];
}
@end

int FYTestSQLiteOpenV2(const char *path, sqlite3 **db, int flags, const char *vfs) {
    NSString *name = path ? [NSString stringWithUTF8String:path] : nil;
    BOOL temporary = FYIsTemporaryPath(name);
    // The only non-fixture DB permitted is the bundled reference dictionary, read-only.
    NSString *dictionary = FYCanonicalPath([NSFileManager.defaultManager.currentDirectoryPath
        stringByAppendingPathComponent:@"resources/learning/reference/reference.sqlite"]);
    BOOL reference = (flags & SQLITE_OPEN_READONLY) && !(flags & (SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE))
        && [FYCanonicalPath(name) isEqualToString:dictionary];
    if (!temporary && !reference) { FYIsolationFailure("database access outside test allowlist"); }
    return sqlite3_open_v2(path, db, flags, vfs);
}
int FYTestSQLiteOpen(const char *path, sqlite3 **db) {
    return FYTestSQLiteOpenV2(path, db, SQLITE_OPEN_READWRITE | SQLITE_OPEN_CREATE, NULL);
}

static NSUInteger captures;
static CGImageRef fixtureWindowImage;
NSUInteger FYTestCaptureCount(void) { return captures; }
void FYTestSetWindowImage(CGImageRef image) {
    if (fixtureWindowImage) { CGImageRelease(fixtureWindowImage); }
    fixtureWindowImage = image ? CGImageRetain(image) : NULL;
}
CGImageRef FYTestWindowImage(CGRect rect, CGWindowListOption options,
                            CGWindowID window, CGWindowImageOption imageOptions) {
    captures++;
    if (fixtureWindowImage) { return CGImageRetain(fixtureWindowImage); }
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGContextRef context = CGBitmapContextCreate(NULL, 16, 16, 8, 64, space, kCGImageAlphaPremultipliedLast);
    CGColorSpaceRelease(space);
    if (!context) { FYIsolationFailure("cannot create synthetic capture"); }
    CGImageRef image = CGBitmapContextCreateImage(context);
    CGContextRelease(context);
    return image;
}

__attribute__((constructor)) static void FYPrepareTestProcess(void) {
    @autoreleasepool {
        (void)FYTestTemporaryDirectory();
#if FY_TEST_REQUIRES_UI
        if (!getenv("FY_TEST_ALLOW_UI") || strcmp(getenv("FY_TEST_ALLOW_UI"), "1")) {
            FYIsolationFailure("UI tests need an explicitly reserved desktop session");
        }
#endif
    }
}
