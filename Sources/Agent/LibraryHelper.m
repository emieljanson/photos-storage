#import <Foundation/Foundation.h>
#import <Photos/Photos.h>
#import <objc/message.h>
#import <objc/runtime.h>
#import <sys/mount.h>
#import "LibraryFootprint.h"
#import "PhotoSafetyMetadata.h"
#import <dlfcn.h>
#import <errno.h>
#import <fcntl.h>
#import <sys/file.h>
#import <sys/stat.h>
#import <sys/statvfs.h>
#import <unistd.h>

// The helper reads library sizes and small settings/status files, never Photos databases or media content. Apple's registered
// Photos service selects disposable local resources. This helper never selects or unlinks media.
// Private ABI reference: github.com/1architect/macspace-releases,
// Platform/CacheDelete/CacheDelete.swift. Keep private calls in this child process.
typedef CFTypeRef (*Query)(CFDictionaryRef);
typedef CFTypeRef (*Purge)(CFDictionaryRef, void (^)(CFDictionaryRef));
static NSString *const serviceID = @"com.apple.photolibraryd.cacheDelete";

static void emit(NSDictionary *result) {
    NSData *data = [NSJSONSerialization dataWithJSONObject:result options:0 error:nil];
    if (data) { fwrite(data.bytes, 1, data.length, stdout); fputc('\n', stdout); }
}

static NSURL *activeLibrary(void) {
    Class cls=PHPhotoLibrary.class;
    SEL selector=NSSelectorFromString(@"systemPhotoLibraryURL");
    Method method=class_getClassMethod(cls,selector);
    if (!method || strcmp(method_getTypeEncoding(method),"@16@0:8")) return nil;
    NSURL *url=((NSURL *(*)(id,SEL))objc_msgSend)(cls,selector);
    struct stat info;
    if (!url.isFileURL || ![url.pathExtension isEqual:@"photoslibrary"] ||
        lstat(url.fileSystemRepresentation,&info) || !S_ISDIR(info.st_mode) || info.st_uid!=getuid()) return nil;
    return url;
}

static BOOL sameLibrary(NSURL *expected, struct stat identity) {
    NSURL *current=activeLibrary();
    struct stat info;
    return current && [current.path isEqual:expected.path] &&
        !lstat(current.fileSystemRepresentation,&info) && info.st_ino==identity.st_ino && info.st_dev==identity.st_dev;
}

static PhotoSafetyState readPhotoSafety(NSURL *library) {
    return PhotoReadMetadataSafety(library);
}

static BOOL measure(NSURL *library, NSMutableDictionary *result) {
    struct statvfs info;
    uint64_t bytes=0, files=0;
    if (statvfs(library.fileSystemRepresentation,&info) || !libraryFootprint(library,&bytes,&files)) return NO;
    uint64_t total=info.f_blocks*info.f_frsize, available=info.f_bavail*info.f_frsize;
    if (!total || available>total) return NO;
    result[@"quota_bytes"]=@(total);
    result[@"free_bytes"]=@(available);
    result[@"used_bytes"]=@(bytes);
    result[@"library_files"]=@(files);
    result[@"library_path"]=library.path;
    return YES;
}

static int acquireOperationLock(void) {
    NSString *directory=[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/FotoBudget"];
    if (![NSFileManager.defaultManager createDirectoryAtPath:directory withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil]) return -1;
    struct stat parent;
    if (lstat(directory.fileSystemRepresentation,&parent) || !S_ISDIR(parent.st_mode) || parent.st_uid!=getuid()) return -1;
    NSString *path=[directory stringByAppendingPathComponent:@"cache-operation.lock"];
    int lock=open(path.fileSystemRepresentation,O_CREAT|O_RDWR|O_NOFOLLOW,0600);
    if (lock<0) return -1;
    struct stat info;
    if (fstat(lock,&info) || !S_ISREG(info.st_mode) || info.st_uid!=getuid() || flock(lock,LOCK_EX|LOCK_NB)) {
        close(lock); return -1;
    }
    return lock;
}

static NSDictionary *queryPhotos(Query query, NSURL *volume, BOOL *valid) {
    CFTypeRef raw = query((__bridge CFDictionaryRef)@{
        @"CACHE_DELETE_VOLUME":volume.path, @"CACHE_DELETE_URGENCY_LIMIT":@4,
        @"CACHE_DELETE_NO_CACHE":@YES, @"CACHE_DELETE_SERVICES":@[serviceID]});
    id answer = CFBridgingRelease(raw);
    if (![answer isKindOfClass:NSDictionary.class] || answer[@"CACHE_DELETE_ERROR"]) return nil;
    *valid = YES;
    for (NSString *key in answer) {
        if (![key hasPrefix:@"CACHE_DELETE_"] && [answer[key] isKindOfClass:NSNumber.class] && ![key isEqual:serviceID]) *valid = NO;
    }
    return answer;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        NSMutableDictionary *result = [@{@"ok":@NO,@"quota_bytes":@0,@"free_bytes":@0,
            @"used_bytes":@0,@"eligible_bytes":@0,@"requested_bytes":@0,
            @"reported_purged_bytes":@0,@"measured_freed_bytes":@0} mutableCopy];
        BOOL execute = argc == 3 && strcmp(argv[1], "--purge-bytes") == 0;
        BOOL snapshot = argc == 2 && strcmp(argv[1], "--snapshot") == 0;
        BOOL safetyOnly = argc == 2 && strcmp(argv[1], "--safety") == 0;
        if (!execute && !snapshot && !safetyOnly) { result[@"error_code"]=@"invalid_arguments"; emit(result); return 2; }
        uint64_t requested = 0;
        if (execute) {
            char *end = NULL;
            errno = 0;
            requested = strtoull(argv[2], &end, 10);
            if (errno || !end || *end || argv[2][0]=='-' || !requested || requested > 256ULL*1024*1024) {
                result[@"error_code"]=@"invalid_amount"; emit(result); return 2;
            }
        }
        NSDictionary *version = [NSDictionary dictionaryWithContentsOfFile:@"/System/Library/CoreServices/SystemVersion.plist"];
        if (![version[@"ProductBuildVersion"] isEqual:@"26B123"]) {
            result[@"error_code"]=@"untested_macos"; emit(result); return 3;
        }
        alarm(95);
        NSURL *library=activeLibrary();
        struct stat identity;
        struct statfs filesystem;
        if (!library || lstat(library.fileSystemRepresentation,&identity) ||
            statfs(library.fileSystemRepresentation,&filesystem)) {
            result[@"error_code"]=@"volume_unavailable"; emit(result); return 4;
        }
        result[@"library_path"]=library.path;
        BOOL safe=PhotoAnnotateSafety(readPhotoSafety(library),result);
        if (!sameLibrary(library,identity)) { result[@"error_code"]=@"library_changed"; emit(result); return 4; }
        if (safetyOnly || (execute && !safe)) {
            result[@"ok"]=@(safe);
            if (!safe) result[@"error_code"]=result[@"safety_error_code"];
            emit(result); return safe ? 0 : 10;
        }
        NSURL *volume=[NSURL fileURLWithPath:@(filesystem.f_mntonname) isDirectory:YES];
        id uuid=nil;
        if (![volume getResourceValue:&uuid forKey:NSURLVolumeUUIDStringKey error:nil]) {
            result[@"error_code"]=@"volume_identity_unavailable"; emit(result); return 4;
        }
        if (!measure(library,result)) {
            result[@"error_code"]=@"library_scan_unavailable"; emit(result); return 4;
        }
        if (!sameLibrary(library,identity)) {
            result[@"error_code"]=@"library_changed"; emit(result); return 4;
        }
        result[@"volume_uuid"]=[uuid description];
        void *framework = dlopen("/System/Library/PrivateFrameworks/CacheDelete.framework/CacheDelete", RTLD_NOW|RTLD_LOCAL);
        Query query = framework ? (Query)dlsym(framework,"CacheDeleteCopyItemizedPurgeableSpaceWithInfo") : NULL;
        Purge purge = framework ? (Purge)dlsym(framework,"CacheDeletePurgeSpaceWithInfoSync") : NULL;
        if (!query || !purge) { result[@"error_code"]=@"api_unavailable"; emit(result); return 5; }
        BOOL filterValid = NO;
        NSDictionary *estimate = queryPhotos(query,volume,&filterValid);
        if (!estimate || !filterValid) { result[@"error_code"]=@"scope_not_verified"; emit(result); return 6; }
        uint64_t eligible = [estimate[serviceID] isKindOfClass:NSNumber.class] ? [estimate[serviceID] unsignedLongLongValue] : 0;
        result[@"eligible_bytes"]=@(eligible);
        if (snapshot || !eligible) { result[@"ok"]=@YES; emit(result); return 0; }
        int lock=acquireOperationLock();
        if (lock<0) { result[@"error_code"]=@"operation_busy"; emit(result); return 8; }
        filterValid=NO;
        estimate=queryPhotos(query,volume,&filterValid);
        if (!estimate || !filterValid || !measure(library,result) || !sameLibrary(library,identity)) {
            close(lock); result[@"error_code"]=@"scope_not_verified"; emit(result); return 6;
        }
        eligible=[estimate[serviceID] isKindOfClass:NSNumber.class] ? [estimate[serviceID] unsignedLongLongValue] : 0;
        requested=MIN(requested,eligible);
        result[@"eligible_bytes"]=@(eligible);
        if (!requested) { close(lock); result[@"ok"]=@YES; emit(result); return 0; }
        uint64_t usedBefore=[result[@"used_bytes"] unsignedLongLongValue];
        result[@"requested_bytes"]=@(requested);
        dispatch_semaphore_t done=dispatch_semaphore_create(0);
        __block NSDictionary *answer=nil;
        void (^callback)(CFDictionaryRef)=[^(CFDictionaryRef raw) {
            if (raw && CFGetTypeID(raw)==CFDictionaryGetTypeID()) answer=[(__bridge NSDictionary *)raw copy];
            dispatch_semaphore_signal(done);
        } copy];
        __block CFTypeRef token=NULL;
        BOOL permitted=PhotoRunWithSafetyCheck(^{
            if (!sameLibrary(library,identity)) return (PhotoSafetyState){NO,NO,-1};
            PhotoSafetyState state=readPhotoSafety(library);
            return sameLibrary(library,identity) ? state : (PhotoSafetyState){NO,NO,-1};
        }, ^{ token=purge((__bridge CFDictionaryRef)@{
            @"CACHE_DELETE_VOLUME":volume.path,@"CACHE_DELETE_URGENCY":@4,
            @"CACHE_DELETE_AMOUNT":@(requested),@"CACHE_DELETE_SERVICES":@[serviceID],
            @"CACHE_DELETE_QUERY_AFTER_PURGE":@YES},callback); },result);
        if (!permitted) { close(lock); result[@"requested_bytes"]=@0; emit(result); return 10; }
        BOOL answered=dispatch_semaphore_wait(done,dispatch_time(DISPATCH_TIME_NOW,90*NSEC_PER_SEC))==0;
        if (token) CFRelease(token);
        if (answered) [NSThread sleepForTimeInterval:2];
        BOOL measured=measure(library,result) && sameLibrary(library,identity);
        close(lock);
        alarm(0);
        if (measured) {
            uint64_t usedAfter=[result[@"used_bytes"] unsignedLongLongValue];
            result[@"measured_freed_bytes"]=@(usedBefore>usedAfter ? usedBefore-usedAfter : 0);
        }
        if ([answer[@"CACHE_DELETE_AMOUNT"] isKindOfClass:NSNumber.class]) result[@"reported_purged_bytes"]=answer[@"CACHE_DELETE_AMOUNT"];
        BOOL responseScopeValid = YES;
        for (NSString *key in answer) {
            if (![key hasPrefix:@"CACHE_DELETE_"] && [answer[key] isKindOfClass:NSNumber.class] && ![key isEqual:serviceID]) responseScopeValid = NO;
        }
        if (!answered || !answer) result[@"error_code"]=@"operation_unconfirmed";
        else if (!responseScopeValid) result[@"error_code"]=@"scope_not_verified";
        else if (answer[@"CACHE_DELETE_ERROR"]) result[@"error_code"]=@"native_refusal";
        else if (!measured) result[@"error_code"]=@"measurement_unavailable";
        else result[@"ok"]=@YES;
        emit(result);
        return [result[@"ok"] boolValue] ? 0 : 9;
    }
}
