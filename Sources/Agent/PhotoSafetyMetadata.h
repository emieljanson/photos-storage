#import "PhotoSafety.h"
#import <fcntl.h>
#import <sys/stat.h>
#import <unistd.h>
#import <errno.h>

static NSData *PhotoReadOpenedMetadata(int parent, int *failure) {
    struct stat before,after;
    if (fstat(parent,&before) || !S_ISREG(before.st_mode) || before.st_uid!=getuid() ||
        before.st_size<0 || before.st_size>2*1024*1024) { close(parent); *failure=EINVAL; return nil; }
    NSMutableData *data=[NSMutableData dataWithLength:(NSUInteger)before.st_size];
    NSUInteger offset=0;
    while (offset<data.length) {
        ssize_t count=read(parent,(char *)data.mutableBytes+offset,data.length-offset);
        if (count<0 && errno==EINTR) continue;
        if (count<=0) { close(parent); *failure=EIO; return nil; }
        offset+=(NSUInteger)count;
    }
    BOOL stable=!fstat(parent,&after) && before.st_dev==after.st_dev && before.st_ino==after.st_ino &&
        before.st_size==after.st_size && before.st_mtimespec.tv_sec==after.st_mtimespec.tv_sec &&
        before.st_mtimespec.tv_nsec==after.st_mtimespec.tv_nsec && before.st_ctimespec.tv_sec==after.st_ctimespec.tv_sec &&
        before.st_ctimespec.tv_nsec==after.st_ctimespec.tv_nsec;
    close(parent);
    if (!stable) { *failure=EAGAIN; return nil; }
    return data;
}

// Never follow a link inside the library, or accept a partial/changing file.
static NSData *PhotoReadMetadata(int root, NSString *relative, int *failure) {
    *failure=0;
    int parent=dup(root);
    if (parent<0) { *failure=errno; return nil; }
    NSArray *parts=[relative componentsSeparatedByString:@"/"];
    for (NSUInteger i=0;i<parts.count;i++) {
        NSString *part=parts[i];
        if (!part.length || [part isEqual:@".."] || [part isEqual:@"."]) { close(parent); *failure=EINVAL; return nil; }
        BOOL last=i+1==parts.count;
        int child=openat(parent,part.fileSystemRepresentation,O_RDONLY|O_NOFOLLOW|O_CLOEXEC|(last?0:O_DIRECTORY));
        int saved=errno; close(parent); parent=child;
        if (child<0) { *failure=saved; return nil; }
    }
    struct stat opened,current;
    if (fstat(parent,&opened)) { *failure=errno; close(parent); return nil; }
    NSData *data=PhotoReadOpenedMetadata(parent,failure);
    if (!data) return nil;
    if (fstatat(root,relative.fileSystemRepresentation,&current,AT_SYMLINK_NOFOLLOW) ||
        opened.st_dev!=current.st_dev || opened.st_ino!=current.st_ino || opened.st_size!=current.st_size ||
        opened.st_mtimespec.tv_sec!=current.st_mtimespec.tv_sec || opened.st_mtimespec.tv_nsec!=current.st_mtimespec.tv_nsec ||
        opened.st_ctimespec.tv_sec!=current.st_ctimespec.tv_sec || opened.st_ctimespec.tv_nsec!=current.st_ctimespec.tv_nsec) {
        *failure=EAGAIN; return nil;
    }
    return data;
}

static id PhotoReadPlist(int root, NSString *relative, int *failure) {
    NSData *data=PhotoReadMetadata(root,relative,failure);
    return data ? [NSPropertyListSerialization propertyListWithData:data options:NSPropertyListImmutable format:nil error:nil] : nil;
}

static BOOL PhotoIsBoolean(id value) {
    return value && CFGetTypeID((__bridge CFTypeRef)value)==CFBooleanGetTypeID();
}

static NSNumber *PhotoLatestCloudEnablement(id log) {
    if (![log isKindOfClass:NSArray.class]) return nil;
    NSDate *latest=nil; NSNumber *enabled=nil;
    for (id entry in log) {
        if (![entry isKindOfClass:NSDictionary.class]) return nil;
        if (![entry[@"type"] isEqual:@"iCPL"]) continue;
        NSDate *date=entry[@"timestamp"]; id flag=entry[@"enabled"];
        if (![date isKindOfClass:NSDate.class] || date.timeIntervalSinceNow>60 || !PhotoIsBoolean(flag)) return nil;
        if (!latest || [date compare:latest]==NSOrderedDescending) { latest=date; enabled=flag; }
        else if ([date isEqual:latest] && enabled.boolValue!=[flag boolValue]) return nil;
    }
    return enabled;
}

static PhotoSafetyState PhotoReadMetadataSafety(NSURL *library) {
    PhotoSafetyState unknown={NO,NO,-1};
    int root=open(library.fileSystemRepresentation,O_RDONLY|O_DIRECTORY|O_NOFOLLOW|O_CLOEXEC);
    if (root<0) return unknown;
    @try {
        int failure=0;
        id local=PhotoReadPlist(root,@"private/com.apple.photolibraryd/appPrivateData.plist",&failure);
        if (![local isKindOfClass:NSDictionary.class]) return unknown;
        id settings=[local valueForKeyPath:@"Library.CPL"];
        if (![settings isKindOfClass:NSDictionary.class]) return unknown;
        id storedMode=settings[@"PrefetchMode"];
        // Require an explicitly recorded choice for this library. Missing mode
        // is not treated as Apple's implicit default, and legacy global flags
        // are not used: they remained unchanged in a real originals-mode test.
        if (![storedMode isKindOfClass:NSNumber.class] || PhotoIsBoolean(storedMode) ||
            CFNumberIsFloatType((__bridge CFNumberRef)storedMode)) return unknown;
        NSInteger mode=[storedMode integerValue];
        if (mode!=0 && mode!=1) return unknown;
        NSNumber *account=PhotoLatestCloudEnablement(PhotoReadPlist(root,@"private/com.apple.accountsd/cloudServiceEnableLog.plist",&failure));
        NSNumber *daemon=PhotoLatestCloudEnablement(PhotoReadPlist(root,@"private/com.apple.photolibraryd/cloudServiceEnableLog.plist",&failure));
        if (!account || !daemon) return unknown;
        if (!account.boolValue || !daemon.boolValue) return (PhotoSafetyState){YES,NO,mode};
        id status=PhotoReadPlist(root,@"resources/cpl/cloudsync.noindex/syncstatus.plist",&failure);
        if (![status isKindOfClass:NSDictionary.class] || !PhotoIsBoolean(status[@"iCloudLibraryExists"]) || ![status[@"iCloudLibraryExists"] boolValue]) return unknown;
        if (!PhotoReadMetadata(root,@"resources/cpl/cloudsync.noindex/cpl_enabled_marker",&failure)) return unknown;
        if (PhotoReadMetadata(root,@"resources/cpl/disableICloudPhotos",&failure)) return (PhotoSafetyState){YES,NO,mode};
        if (failure!=ENOENT) return unknown;
        if (PhotoReadMetadata(root,@"resources/cpl/cloudsync.noindex/pauseICloudPhotos",&failure) || failure!=ENOENT) return unknown;
        return (PhotoSafetyState){YES,YES,mode};
    } @catch (__unused NSException *exception) { return unknown; }
    @finally { close(root); }
}
