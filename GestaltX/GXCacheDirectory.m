// SPDX-License-Identifier: GPL-3.0-only
#import "GXCacheDirectory.h"
#include <sys/stat.h>
#include <errno.h>
#include <string.h>
#include <unistd.h>

static NSError *GXCacheError(int code, NSURL *url) {
    return [NSError errorWithDomain:NSPOSIXErrorDomain code:code
                           userInfo:@{NSFilePathErrorKey: url.path,
                                      NSLocalizedDescriptionKey:
                                          [NSString stringWithFormat:@"%s (errno %d) at %@",
                                           strerror(code), code, url.path]}];
}

static BOOL GXWithTemporaryCacheLinkUnlocked(NSURL *caches, NSString *target,
                              int64_t (^operation)(void), int64_t *result,
                              NSError **error) {
    NSFileManager *files = NSFileManager.defaultManager;
    (void)files;
    struct stat original;
    BOOL existed = lstat(caches.fileSystemRepresentation, &original) == 0;
    if (!existed && errno != ENOENT) {
        if (error) *error = GXCacheError(errno, caches);
        return NO;
    }
    NSURL *backup = [caches.URLByDeletingLastPathComponent URLByAppendingPathComponent:
                     [NSString stringWithFormat:@".GestaltX-Caches-%@.backup", NSUUID.UUID.UUIDString]];
    if (existed && rename(caches.fileSystemRepresentation, backup.fileSystemRepresentation) != 0) {
        if (error) *error = GXCacheError(errno, backup);
        return NO;
    }

    NSError *setupError = nil;
    BOOL installed = symlink(target.fileSystemRepresentation, caches.fileSystemRepresentation) == 0;
    if (!installed) setupError = GXCacheError(errno, caches);
    struct stat installedLink;
    BOOL identified = NO;
    if (installed) {
        if (lstat(caches.fileSystemRepresentation, &installedLink) != 0) {
            setupError = GXCacheError(errno, caches);
        } else if (!S_ISLNK(installedLink.st_mode)) {
            setupError = GXCacheError(EBUSY, caches);
        } else {
            identified = YES;
        }
    }
    NSError *restoreError = nil;
    @try {
        if (identified) *result = operation();
    } @finally {
        // Do not remove a replacement created by another process. If cleanup
        // cannot finish, leave the saved original in place for recovery.
        BOOL canRestore = YES;
        if (installed) {
            struct stat current;
            if (lstat(caches.fileSystemRepresentation, &current) == 0) {
                if (!identified || !S_ISLNK(current.st_mode) ||
                    current.st_dev != installedLink.st_dev || current.st_ino != installedLink.st_ino) {
                    restoreError = GXCacheError(EBUSY, backup);
                    canRestore = NO;
                } else {
                    canRestore = unlink(caches.fileSystemRepresentation) == 0;
                    if (!canRestore) restoreError = GXCacheError(errno, caches);
                }
            } else if (errno != ENOENT) {
                restoreError = GXCacheError(errno, caches);
                canRestore = NO;
            }
        }
        if (canRestore && existed) {
            if (rename(backup.fileSystemRepresentation, caches.fileSystemRepresentation) != 0) {
                restoreError = GXCacheError(errno, caches);
            }
        } else if (canRestore && installed) {
            if (mkdir(caches.fileSystemRepresentation, 0755) != 0) {
                restoreError = GXCacheError(errno, caches);
            }
        }
    }
    if (error) *error = restoreError ?: setupError;
    return identified && restoreError == nil;
}

BOOL GXWithTemporaryCacheLink(NSURL *caches, NSString *target,
                              int64_t (^operation)(void), int64_t *result,
                              NSError **error) {
    // MobileGestalt and system preferences use different background actors but
    // share the same signed App Group. Never swap its cache link concurrently.
    static NSRecursiveLock *lock;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ lock = NSRecursiveLock.new; });
    [lock lock];
    @try { return GXWithTemporaryCacheLinkUnlocked(caches, target, operation, result, error); }
    @finally { [lock unlock]; }
}
