#import "FYTranslationTrace.h"
#import <sys/stat.h>
#import <sys/file.h>
#import <fcntl.h>
#import <unistd.h>
#import <errno.h>
#import <math.h>

static const NSUInteger FYTraceByteLimit = 1024 * 1024;
static const NSTimeInterval FYTraceTimeLimit = 300;

static NSString *const FYTraceThreadKey = @"com.nanami.fuyi.text-trace-context";
NSDictionary *FYCurrentTrace(void) { return NSThread.currentThread.threadDictionary[FYTraceThreadKey]; }
void FYTracePerform(NSDictionary *context, void (^work)(void)) {
    if (!context) { work(); return; }
    NSMutableDictionary *local = NSThread.currentThread.threadDictionary;
    id previous = local[FYTraceThreadKey];
    local[FYTraceThreadKey] = context;
    @try { work(); }
    @finally {
        if (previous) { local[FYTraceThreadKey] = previous; }
        else { [local removeObjectForKey:FYTraceThreadKey]; }
    }
}

@interface FYTranslationTrace ()
@property(nonatomic, copy) NSString *directory;
@property(nonatomic, copy) NSTimeInterval (^clock)(void);
@property(nonatomic) NSUInteger maxBytes;
@property(nonatomic, copy) NSString *cappedSession;
@end

@implementation FYTranslationTrace
+ (NSString *)defaultDirectory {
    return [NSString stringWithFormat:@"/tmp/yiya-text-trace-%u", getuid()];
}
+ (instancetype)shared {
    static FYTranslationTrace *trace;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        trace = [[self alloc] initWithDirectory:self.defaultDirectory
                                        clock:^NSTimeInterval { return NSDate.date.timeIntervalSince1970; }
                                     maxBytes:FYTraceByteLimit];
    });
    return trace;
}
- (instancetype)initWithDirectory:(NSString *)directory clock:(NSTimeInterval (^)(void))clock maxBytes:(NSUInteger)maxBytes {
    if ((self = [super init])) {
        _directory = [directory copy];
        _clock = [clock copy];
        _maxBytes = MIN(MAX((NSUInteger)512, maxBytes), FYTraceByteLimit);
    }
    return self;
}
- (BOOL)privateDirectory {
    struct stat st;
    return lstat(self.directory.fileSystemRepresentation, &st) == 0 &&
        S_ISDIR(st.st_mode) && st.st_uid == getuid() && (st.st_mode & 077) == 0;
}
- (NSDictionary *)activeControl {
    // No directory/file creation when disabled, including the first call.
    if (![self privateDirectory]) { return nil; }
    NSString *path = [self.directory stringByAppendingPathComponent:@"control.json"];
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW | O_NONBLOCK);
    if (fd < 0) { return nil; }
    struct stat st;
    BOOL safe = fstat(fd, &st) == 0 && S_ISREG(st.st_mode) && st.st_uid == getuid() &&
        (st.st_mode & 077) == 0 && st.st_nlink == 1 && st.st_size > 0 && st.st_size <= 4096;
    char bytes[4097];
    ssize_t size = safe ? read(fd, bytes, sizeof(bytes)) : -1;
    close(fd);
    if (size <= 0 || size != st.st_size) { return nil; }
    id value = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:bytes length:(NSUInteger)size] options:0 error:NULL];
    if (![value isKindOfClass:NSDictionary.class]) { return nil; }
    NSDictionary *control = value;
    NSString *session = control[@"session"];
    NSNumber *issued = control[@"issued_at"], *expires = control[@"expires_at"];
    if (![session isKindOfClass:NSString.class] || ![[NSUUID alloc] initWithUUIDString:session] ||
        ![issued isKindOfClass:NSNumber.class] || ![expires isKindOfClass:NSNumber.class]) { return nil; }
    NSTimeInterval now = self.clock(), start = issued.doubleValue, end = expires.doubleValue;
    if (!isfinite(now) || !isfinite(start) || !isfinite(end) || start > now ||
        end <= now || end <= start || end - start > FYTraceTimeLimit ||
        [session isEqualToString:self.cappedSession]) { return nil; }
    return control;
}
- (NSDictionary *)beginCycleForWindow:(uint32_t)windowID generation:(NSInteger)generation {
    return [self beginCycleForWindow:windowID generation:generation inputEpoch:0 inputSource:0];
}

- (NSDictionary *)beginCycleForWindow:(uint32_t)windowID
                           generation:(NSInteger)generation
                           inputEpoch:(NSUInteger)inputEpoch
                          inputSource:(NSInteger)inputSource {
    if (!windowID) { return nil; }
    @synchronized (self) {
        NSDictionary *control = [self activeControl];
        if (!control) { return nil; }
        NSDictionary *context = @{@"session": control[@"session"], @"cycle": NSUUID.UUID.UUIDString,
                                  @"window_id": @(windowID), @"generation": @(generation),
                                  @"input_epoch": @(inputEpoch), @"input_source": @(inputSource)};
        [self recordEvent:@"cycle_begin" context:context fields:@{}];
        return context;
    }
}
- (NSDictionary *)requestContextForCycle:(NSDictionary *)cycle {
    if (!cycle) { return nil; }
    NSMutableDictionary *result = [cycle mutableCopy];
    result[@"request_id"] = NSUUID.UUID.UUIDString;
    return [result copy];
}
- (NSDictionary *)frameContextForCycle:(NSDictionary *)cycle index:(uint64_t)index {
    if (!cycle) { return nil; }
    NSMutableDictionary *result = [cycle mutableCopy];
    result[@"frame_id"] = NSUUID.UUID.UUIDString;
    result[@"frame_index"] = @(index);
    return [result copy];
}

// Strict schema: never serialize arbitrary objects, NSError descriptions,
// URLs, headers, payloads, configuration or cache keys (which contain prompts).
static NSDictionary *FYTraceSanitize(NSDictionary *fields) {
    NSSet *textKeys = [NSSet setWithArray:@[@"reason", @"stage", @"route", @"source", @"translation", @"sentence_id", @"identity_request_id"]];
    NSSet *numberKeys = [NSSet setWithArray:@[@"version", @"auto_mode", @"previous_mode", @"mode", @"candidate_mode", @"candidate_hits", @"stable_count", @"stable_required", @"fast_ocr", @"language", @"blocks", @"error_code", @"http_status", @"elapsed_ms", @"cache_hit", @"success", @"applied", @"visible", @"width", @"height", @"generation", @"service_generation", @"frame_index"]];
    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    for (NSString *key in textKeys) {
        id value = fields[key];
        if ([value isKindOfClass:NSString.class]) {
            result[key] = [value substringToIndex:MIN((NSUInteger)16000, [value length])];
            if ([value length] > 16000) { result[@"text_truncated"] = @YES; }
        }
    }
    for (NSString *key in numberKeys) {
        id value = fields[key];
        if ([value isKindOfClass:NSNumber.class] && isfinite([value doubleValue])) { result[key] = value; }
    }
    if ([fields[@"ocr_lines"] isKindOfClass:NSArray.class]) {
        NSMutableArray *lines = [NSMutableArray array];
        for (id raw in fields[@"ocr_lines"]) {
            if (lines.count >= 100) { result[@"lines_truncated"] = @YES; break; }
            if (![raw isKindOfClass:NSDictionary.class]) { continue; }
            NSMutableDictionary *line = [NSMutableDictionary dictionary];
            if ([raw[@"text"] isKindOfClass:NSString.class]) {
                NSString *text = raw[@"text"];
                line[@"text"] = [text substringToIndex:MIN((NSUInteger)2000, text.length)];
                if (text.length > 2000) { line[@"truncated"] = @YES; }
            }
            for (NSString *key in @[@"x", @"y", @"w", @"h"]) {
                id value = raw[key];
                if ([value isKindOfClass:NSNumber.class] && isfinite([value doubleValue])) { line[key] = value; }
            }
            [lines addObject:line];
        }
        result[@"ocr_lines"] = lines;
    }
    return result;
}
- (void)recordEvent:(NSString *)event context:(NSDictionary *)context fields:(NSDictionary *)fields {
    if (!context) { return; }
    @synchronized (self) {
        NSDictionary *control = [self activeControl];
        if (!control || ![context[@"session"] isEqual:control[@"session"]]) { return; }
        NSSet *events = [NSSet setWithArray:@[@"cycle_begin", @"capture", @"task", @"ocr", @"mode", @"stable", @"skip", @"dialogue", @"cache", @"request_submit", @"http_complete", @"request_complete", @"caption_apply", @"caption_drop", @"inline_apply", @"inline_drop"]];
        if (![events containsObject:event]) { return; }
        NSMutableDictionary *record = [FYTraceSanitize(fields) mutableCopy];
        record[@"event"] = event;
        record[@"schema_version"] = @2;
        record[@"event_id"] = NSUUID.UUID.UUIDString;
        record[@"time_unix_ms"] = @(llround(self.clock() * 1000));
        record[@"pid"] = @(getpid());
        // Context also has a strict schema; it cannot smuggle arbitrary data.
        for (NSString *key in @[@"session", @"cycle", @"request_id", @"frame_id", @"http_task_id"]) {
            id value = context[key];
            if ([value isKindOfClass:NSString.class] && [[NSUUID alloc] initWithUUIDString:value]) { record[key] = value; }
        }
        for (NSString *key in @[@"window_id", @"generation", @"input_epoch", @"input_source", @"frame_index"]) {
            if ([context[key] isKindOfClass:NSNumber.class]) { record[key] = context[key]; }
        }
        NSData *json = [NSJSONSerialization dataWithJSONObject:record options:NSJSONWritingSortedKeys error:NULL];
        if (!json || json.length > 128 * 1024) { return; }
        NSMutableData *line = [json mutableCopy];
        [line appendBytes:"\n" length:1];
        NSString *path = [self.directory stringByAppendingPathComponent:@"events.jsonl"];
        int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_NOFOLLOW | O_NONBLOCK, 0600);
        if (fd < 0) { return; }
        struct stat st;
        BOOL safe = fstat(fd, &st) == 0 && S_ISREG(st.st_mode) && st.st_uid == getuid() &&
            (st.st_mode & 077) == 0 && st.st_nlink == 1;
        if (!safe || flock(fd, LOCK_EX | LOCK_NB) != 0) { close(fd); return; }
        if (fstat(fd, &st) != 0 || ![[self activeControl][@"session"] isEqual:context[@"session"]]) {
            flock(fd, LOCK_UN); close(fd); return;
        }
        // Never truncate an earlier session implicitly. The explicit start
        // command clears the old log before publishing its new control token.
        if ((NSUInteger)st.st_size + line.length > self.maxBytes) {
            self.cappedSession = control[@"session"];
            flock(fd, LOCK_UN); close(fd); return;
        }
        lseek(fd, 0, SEEK_END);
        const char *bytes = line.bytes;
        NSUInteger offset = 0;
        while (offset < line.length) {
            ssize_t count = write(fd, bytes + offset, line.length - offset);
            if (count < 0 && errno == EINTR) { continue; }
            if (count <= 0) { break; }
            offset += (NSUInteger)count;
        }
        if (offset != line.length) { ftruncate(fd, st.st_size); }
        flock(fd, LOCK_UN);
        close(fd);
    }
}
@end
