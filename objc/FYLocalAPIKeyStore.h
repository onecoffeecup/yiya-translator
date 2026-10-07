#pragma once
#import <Foundation/Foundation.h>
#include <errno.h>
#include <fcntl.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/stat.h>
#include <unistd.h>

typedef NS_ENUM(NSInteger, FYAPIKeyStatus) {
    FYAPIKeySuccess, FYAPIKeyNotFound, FYAPIKeyReadError, FYAPIKeyWriteError
};

// Credentials live outside the app/source tree and are scoped to a released
// marketing version. Development builds of one release reuse the key.
static NSString *FYAPIKeyVersion(void) {
    NSDictionary *info = NSBundle.mainBundle.infoDictionary;
    return info[@"CFBundleShortVersionString"] ?: @"development";
}
static NSString *FYAPIKeyFilePath(void) {
#ifdef FY_TEST_ISOLATED_CREDENTIAL_STORE
    return [NSTemporaryDirectory() stringByAppendingPathComponent:@"credentials/api-key.json"];
#else
    NSString *support = [NSSearchPathForDirectoriesInDomains(NSApplicationSupportDirectory, NSUserDomainMask, YES) firstObject];
    return [support stringByAppendingPathComponent:@"com.nanami.fuyi/credentials/api-key.json"];
#endif
}
static FYAPIKeyStatus FYReadAPIKeyFile(NSString *path, NSString *version, NSString **value) {
    if (value) { *value = nil; }
    if (!path.length || !version.length) { return FYAPIKeyReadError; }
    int fd = open(path.fileSystemRepresentation, O_RDONLY | O_NOFOLLOW);
    if (fd < 0) { return errno == ENOENT ? FYAPIKeyNotFound : FYAPIKeyReadError; }
    struct stat info;
    if (fstat(fd, &info) || !S_ISREG(info.st_mode) || info.st_uid != getuid() ||
        info.st_size <= 0 || info.st_size > 65536 || fchmod(fd, 0600)) {
        close(fd); return FYAPIKeyReadError;
    }
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)info.st_size];
    NSUInteger offset = 0;
    while (offset < data.length) {
        ssize_t count = read(fd, (uint8_t *)data.mutableBytes + offset, data.length - offset);
        if (count < 0 && errno == EINTR) { continue; }
        if (count <= 0) { close(fd); return FYAPIKeyReadError; }
        offset += (NSUInteger)count;
    }
    close(fd);
    id record = [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL];
    if (![record isKindOfClass:NSDictionary.class] || ![record[@"version"] isKindOfClass:NSString.class] ||
        ![record[@"apiKey"] isKindOfClass:NSString.class]) { return FYAPIKeyReadError; }
    // Accept files produced briefly by the version/build implementation too.
    // A later release still cannot reuse an earlier release's key.
    NSString *storedVersion = [record[@"version"] componentsSeparatedByString:@"/"].firstObject;
    if (![storedVersion isEqualToString:version]) { return FYAPIKeyNotFound; }
    if (value) { *value = record[@"apiKey"]; }
    return FYAPIKeySuccess;
}
static FYAPIKeyStatus FYWriteAPIKeyFile(NSString *path, NSString *version, NSString *value) {
    if (!path.length || !version.length) { return FYAPIKeyWriteError; }
    if (!value.length) {
        return unlink(path.fileSystemRepresentation) == 0 || errno == ENOENT ? FYAPIKeySuccess : FYAPIKeyWriteError;
    }
    NSString *folder = path.stringByDeletingLastPathComponent;
    if (![NSFileManager.defaultManager createDirectoryAtPath:folder withIntermediateDirectories:YES
        attributes:@{NSFilePosixPermissions:@0700} error:NULL]) { return FYAPIKeyWriteError; }
    struct stat info;
    if (lstat(folder.fileSystemRepresentation, &info) || !S_ISDIR(info.st_mode) ||
        info.st_uid != getuid() || chmod(folder.fileSystemRepresentation, 0700)) { return FYAPIKeyWriteError; }
    NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"version":version, @"apiKey":value}
        options:0 error:NULL];
    if (!data.length || data.length > 65536) { return FYAPIKeyWriteError; }
    char *temporary = strdup([[folder stringByAppendingPathComponent:@".api-key-XXXXXX"] fileSystemRepresentation]);
    if (!temporary) { return FYAPIKeyWriteError; }
    int fd = mkstemp(temporary); // mode 0600 from creation, including the atomic replacement.
    BOOL success = fd >= 0;
    NSUInteger offset = 0;
    while (success && offset < data.length) {
        ssize_t count = write(fd, (const uint8_t *)data.bytes + offset, data.length - offset);
        if (count < 0 && errno == EINTR) { continue; }
        if (count <= 0) { success = NO; break; }
        offset += (NSUInteger)count;
    }
    if (success && fsync(fd)) { success = NO; }
    if (fd >= 0 && close(fd)) { success = NO; }
    if (success && rename(temporary, path.fileSystemRepresentation)) { success = NO; }
    if (!success) { unlink(temporary); }
    free(temporary);
    return success ? FYAPIKeySuccess : FYAPIKeyWriteError;
}

#ifdef FY_TEST_ISOLATED_CREDENTIAL_STORE
static NSString *FYTestLocalAPIKeyValue;
static BOOL FYTestLocalAPIKeyFailWrites;
static FYAPIKeyStatus FYReadAPIKey(NSString **value) {
    if (value) { *value = FYTestLocalAPIKeyValue; }
    return FYTestLocalAPIKeyValue ? FYAPIKeySuccess : FYAPIKeyNotFound;
}
static FYAPIKeyStatus FYWriteAPIKey(NSString *value) {
    if (FYTestLocalAPIKeyFailWrites) { return FYAPIKeyWriteError; }
    FYTestLocalAPIKeyValue = value.length ? [value copy] : nil;
    return FYAPIKeySuccess;
}
#else
static FYAPIKeyStatus FYReadAPIKey(NSString **value) {
    return FYReadAPIKeyFile(FYAPIKeyFilePath(), FYAPIKeyVersion(), value);
}
static FYAPIKeyStatus FYWriteAPIKey(NSString *value) {
    return FYWriteAPIKeyFile(FYAPIKeyFilePath(), FYAPIKeyVersion(), value);
}
#endif
