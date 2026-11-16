#import "../Sources/Agent/PhotoEffectiveSettings.h"
#import <dlfcn.h>

static id nativeReply;

@interface NativeReplyClient : NSObject
@end
@implementation NativeReplyClient
- (instancetype)initWithPhotoLibraryURL:(NSURL *)url { (void)url; return [super init]; }
- (id)cloudClient { return self; }
- (id)getCPLSettings { return nativeReply; }
@end

// Decode the same settings payload that the daemon returns. Only the transport
// is a fixture: all mode/iCloud getters execute this OS's real PLCPLSettings.
static id settingsSnapshot(Class cls, NSInteger mode, BOOL enabled) {
    NSKeyedArchiver *writer=[[NSKeyedArchiver alloc] initRequiringSecureCoding:YES];
    [writer encodeInteger:mode forKey:@"PrefetchMode"];
    [writer encodeBool:enabled forKey:@"iCPLEnabled"];
    [writer encodeInteger:0 forKey:@"CollectionShareRestrictions"];
    [writer encodeObject:nil forKey:@"LibraryIdentifier"];
    [writer encodeObject:nil forKey:@"TransportContainerConfiguration"];
    [writer finishEncoding];
    NSKeyedUnarchiver *reader=[[NSKeyedUnarchiver alloc] initForReadingFromData:writer.encodedData error:nil];
    id settings=[(id<NSCoding>)[cls alloc] initWithCoder:reader];
    [reader finishDecoding];
    return reader.error ? nil : settings;
}

int main(void) {
    @autoreleasepool {
        if (!dlopen("/System/Library/PrivateFrameworks/PhotoLibraryServices.framework/PhotoLibraryServices",RTLD_NOW|RTLD_LOCAL)) return 1;
        Class cls=NSClassFromString(@"PLCPLSettings");
        if (!cls) return 2;
        NSURL *library=[NSURL fileURLWithPath:@"/tmp/NativeSettings.photoslibrary"];
        for (NSInteger mode=0;mode<=2;mode++) {
            for (unsigned enabled=0;enabled<2;enabled++) {
                nativeReply=settingsSnapshot(cls,mode,enabled);
                if (!nativeReply) return 3;
                PhotoSafetyState state=PhotoReadEffectiveSettings(library,NativeReplyClient.class,cls);
                if (state.verified!=(mode<=1)) return 4;
                if (mode<=1 && (state.prefetchMode!=mode || state.cloudPhotosEnabled!=(BOOL)enabled)) return 5;
                __block unsigned operations=0;
                NSMutableDictionary *result=NSMutableDictionary.dictionary;
                BOOL allowed=PhotoRunWithSafetyCheck(^{return state;},^{operations++;},result);
                if (allowed!=(mode==0 && enabled) || operations!=(allowed ? 1U : 0U)) return 6;
            }
        }
        nativeReply=nil;
        if (PhotoReadEffectiveSettings(library,NativeReplyClient.class,cls).verified) return 7;
        puts("PASS real Photos settings getters: optimize/originals/unknown modes, enabled/disabled iCloud, missing reply; no real library is opened or changed.");
    }
    return 0;
}
