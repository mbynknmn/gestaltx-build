// SPDX-License-Identifier: GPL-3.0-only
// Copyright (C) 2026 huamidev
// 来源：LCSign 的 LCEntitlementsReader（Sources/LCEntitlementsReader）。
// Runtime entitlement-reading approach adapted from LCSign.
// GestaltX adds strict Mach-O bounds checks and effective SecTask lookup.
#import "GXEntitlementsReader.h"
#include <mach-o/dyld.h>
#include <mach-o/loader.h>
#include <mach-o/fat.h>
#include <libkern/OSByteOrder.h>
#include <dlfcn.h>

static BOOL GXRange(NSUInteger offset, NSUInteger length, NSUInteger size) {
    return offset <= size && length <= size - offset;
}
static uint32_t GX32(const uint8_t *p, NSUInteger offset) {
    uint32_t value; memcpy(&value, p + offset, sizeof(value)); return value;
}
static uint64_t GX64(const uint8_t *p, NSUInteger offset) {
    uint64_t value; memcpy(&value, p + offset, sizeof(value)); return value;
}
static void GXLog(NSString *message) {
    [[NSNotificationCenter defaultCenter] postNotificationName:@"GestaltX.worse_query.log" object:nil
                                                      userInfo:@{@"message": [@"App Group: " stringByAppendingString:message]}];
}
static NSDictionary *GXSignature(const uint8_t *bytes, NSUInteger size) {
    if (size < 12 || OSSwapBigToHostInt32(GX32(bytes, 0)) != 0xfade0cc0) return nil;
    NSUInteger total = OSSwapBigToHostInt32(GX32(bytes, 4));
    NSUInteger count = OSSwapBigToHostInt32(GX32(bytes, 8));
    if (total < 12 || total > size || count > (total - 12) / 8) return nil;
    for (NSUInteger i = 0; i < count; i++) {
        NSUInteger offset = OSSwapBigToHostInt32(GX32(bytes, 12 + i * 8 + 4));
        if (!GXRange(offset, 8, total)) continue;
        uint32_t magic = OSSwapBigToHostInt32(GX32(bytes, offset));
        NSUInteger length = OSSwapBigToHostInt32(GX32(bytes, offset + 4));
        if (magic != 0xfade7171 || length < 8 || !GXRange(offset, length, total)) continue;
        NSData *plist = [NSData dataWithBytes:bytes + offset + 8 length:length - 8];
        id value = [NSPropertyListSerialization propertyListWithData:plist options:NSPropertyListImmutable format:NULL error:nil];
        if ([value isKindOfClass:NSDictionary.class]) return value;
    }
    return nil;
}
static NSDictionary *GXThin(const uint8_t *bytes, NSUInteger size) {
    if (size < sizeof(struct mach_header)) return nil;
    uint32_t magic = GX32(bytes, 0);
    BOOL is64 = magic == MH_MAGIC_64;
    if (!is64 && magic != MH_MAGIC) return nil;
    NSUInteger headerSize = is64 ? sizeof(struct mach_header_64) : sizeof(struct mach_header);
    if (size < headerSize) return nil;
    uint32_t count = GX32(bytes, 16), commandBytes = GX32(bytes, 20);
    if (!GXRange(headerSize, commandBytes, size) || count > commandBytes / sizeof(struct load_command)) return nil;
    NSUInteger cursor = headerSize, end = headerSize + commandBytes;
    for (uint32_t i = 0; i < count; i++) {
        if (!GXRange(cursor, sizeof(struct load_command), end)) return nil;
        uint32_t command = GX32(bytes, cursor), length = GX32(bytes, cursor + 4);
        if (length < sizeof(struct load_command) || !GXRange(cursor, length, end)) return nil;
        if (command == LC_CODE_SIGNATURE) {
            if (length < sizeof(struct linkedit_data_command)) return nil;
            NSUInteger offset = GX32(bytes, cursor + 8), signatureSize = GX32(bytes, cursor + 12);
            if (!GXRange(offset, signatureSize, size)) return nil;
            return GXSignature(bytes + offset, signatureSize);
        }
        cursor += length;
    }
    return nil;
}
static NSArray *GXEffectiveGroups(void) {
    typedef CFTypeRef (*CreateTask)(CFAllocatorRef);
    typedef CFTypeRef (*CopyEntitlement)(CFTypeRef, CFStringRef, CFErrorRef *);
    void *library = dlopen("/System/Library/Frameworks/Security.framework/Security", RTLD_LAZY | RTLD_LOCAL);
    if (!library) return nil;
    CreateTask create = (CreateTask)dlsym(library, "SecTaskCreateFromSelf");
    CopyEntitlement copy = (CopyEntitlement)dlsym(library, "SecTaskCopyValueForEntitlement");
    NSArray *groups = nil;
    if (create && copy) {
        CFTypeRef task = create(NULL);
        if (task) {
            CFTypeRef value = copy(task, CFSTR("com.apple.security.application-groups"), NULL);
            if (value) {
                if (CFGetTypeID(value) == CFArrayGetTypeID()) groups = [(__bridge NSArray *)value copy];
                CFRelease(value);
            }
            CFRelease(task);
        }
    }
    dlclose(library);
    return groups;
}
@implementation GXEntitlementsReader
+ (NSDictionary *)entitlementsInMachOData:(NSData *)data {
    const uint8_t *bytes = data.bytes;
    NSUInteger size = data.length;
    if (size < sizeof(struct fat_header)) return nil;
    NSDictionary *thin = GXThin(bytes, size);
    if (thin) return thin;
    uint32_t magic = OSSwapBigToHostInt32(GX32(bytes, 0));
    BOOL is64 = magic == FAT_MAGIC_64;
    if (!is64 && magic != FAT_MAGIC) return nil;
    NSUInteger count = OSSwapBigToHostInt32(GX32(bytes, 4));
    NSUInteger stride = is64 ? sizeof(struct fat_arch_64) : sizeof(struct fat_arch);
    if (count > (size - sizeof(struct fat_header)) / stride) return nil;
    const struct mach_header *loaded = _dyld_get_image_header(0);
    for (NSUInteger i = 0; i < count; i++) {
        NSUInteger item = sizeof(struct fat_header) + i * stride;
        cpu_type_t cpu = (cpu_type_t)OSSwapBigToHostInt32(GX32(bytes, item));
        cpu_subtype_t subtype = (cpu_subtype_t)OSSwapBigToHostInt32(GX32(bytes, item + 4));
        if (loaded && (cpu != loaded->cputype || (subtype & ~CPU_SUBTYPE_MASK) != (loaded->cpusubtype & ~CPU_SUBTYPE_MASK))) continue;
        uint64_t offset = is64 ? OSSwapBigToHostInt64(GX64(bytes, item + 8)) : OSSwapBigToHostInt32(GX32(bytes, item + 8));
        uint64_t length = is64 ? OSSwapBigToHostInt64(GX64(bytes, item + 16)) : OSSwapBigToHostInt32(GX32(bytes, item + 12));
        if (offset > NSUIntegerMax || length > NSUIntegerMax || !GXRange((NSUInteger)offset, (NSUInteger)length, size)) continue;
        NSDictionary *value = GXThin(bytes + offset, (NSUInteger)length);
        if (value) return value;
    }
    return nil;
}
+ (NSString *)usableAppGroup { return [self usableAppGroups].firstObject; }
+ (NSArray<NSString *> *)usableAppGroups {
    NSArray *groups = GXEffectiveGroups();
    if (groups) {
        GXLog([NSString stringWithFormat:@"effective signature contains %lu group(s)", (unsigned long)groups.count]);
    } else {
        const char *mainImage = _dyld_get_image_name(0);
        NSString *path = mainImage ? [NSString stringWithUTF8String:mainImage] : NSBundle.mainBundle.executablePath;
        NSData *binary = path ? [NSData dataWithContentsOfFile:path options:NSDataReadingMappedIfSafe error:nil] : nil;
        NSDictionary *entitlements = binary ? [self entitlementsInMachOData:binary] : nil;
        id value = entitlements[@"com.apple.security.application-groups"];
        if ([value isKindOfClass:NSArray.class]) groups = value;
        GXLog([NSString stringWithFormat:@"dyld main-image signature contains %lu group(s)", (unsigned long)groups.count]);
    }
    NSMutableOrderedSet<NSString *> *candidates = [NSMutableOrderedSet orderedSet];
    NSBundle *bundle = NSBundle.mainBundle;
    if ([bundle.bundleURL.pathExtension isEqualToString:@"appex"]) {
        NSURL *parent = bundle.bundleURL.URLByDeletingLastPathComponent.URLByDeletingLastPathComponent;
        bundle = [NSBundle bundleWithURL:parent] ?: bundle;
    }
    NSString *bundleGroup = [@"group." stringByAppendingString:bundle.bundleIdentifier ?: @""];
    for (NSString *preferred in @[bundleGroup, @"group.com.huami.gestultx"]) {
        if ([groups containsObject:preferred]) [candidates addObject:preferred];
    }
    for (id group in [groups sortedArrayUsingComparator:^NSComparisonResult(id a, id b) {
        return [[a description] compare:[b description]];
    }]) {
        if ([group isKindOfClass:NSString.class] && [group hasPrefix:@"group."]) [candidates addObject:group];
    }
    NSMutableArray<NSString *> *usable = [NSMutableArray array];
    for (NSString *candidate in candidates) {
        if ([[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:candidate]) [usable addObject:candidate];
    }
    GXLog(usable.count ? @"selected accessible signed App Groups" : @"no signed App Group has an accessible container");
    return usable;
}
@end
