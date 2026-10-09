#import "FYInlineLayoutDebug.h"
#import <sys/stat.h>
#import <unistd.h>
int main(void) { @autoreleasepool {
    NSString *root=[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString];
    NSFileManager *fm=NSFileManager.defaultManager;
    [fm createDirectoryAtPath:root withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:NULL];
    NSDictionary *control=@{@"session":NSUUID.UUID.UUIDString,@"issued_at":@(NSDate.date.timeIntervalSince1970-1),
        @"expires_at":@(NSDate.date.timeIntervalSince1970+120),@"overlay":@NO};
    NSString *path=[root stringByAppendingPathComponent:@"control.json"];
    [[NSJSONSerialization dataWithJSONObject:control options:0 error:NULL] writeToFile:path atomically:YES]; chmod(path.fileSystemRepresentation,0600);
    FYInlineLayoutDebug *debug=[[FYInlineLayoutDebug alloc] initWithDirectory:root];
    CGColorSpaceRef space=CGColorSpaceCreateDeviceRGB();
    CGContextRef bitmap=CGBitmapContextCreate(NULL,16,16,8,64,space,kCGImageAlphaPremultipliedLast);
    CGImageRef image=CGBitmapContextCreateImage(bitmap); CGContextRelease(bitmap); CGColorSpaceRelease(space);
    NSDictionary *context=[debug beginFrameWithImage:image metadata:@{}]; CGImageRelease(image);
    [debug recordDecision:@"synthetic" context:@{@"session":control[@"session"],@"frame_id":@"fixture"}];
    BOOL passed=!debug.isActive && !context && [fm contentsOfDirectoryAtPath:root error:NULL].count==1;
    [fm removeItemAtPath:root error:NULL];
    if (!passed) { fprintf(stderr,"FAIL release diagnostics can be armed by a legal control file\n"); return 1; }
    puts("PASS default/release layout diagnostics: legal control ignored, no files generated");
} return 0; }
