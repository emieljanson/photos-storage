#import "../Sources/Agent/PhotoEffectiveSettings.h"

static NSInteger mode;
static BOOL cloudEnabled=YES, keepOriginals, noReply, throws;
static NSURL *boundLibrary;
static unsigned reads;

@interface NativeSettingsFixture : NSObject
@end
@implementation NativeSettingsFixture
- (NSInteger)prefetchMode { return mode; }
- (BOOL)isKeepOriginalsEnabled { return keepOriginals; }
- (BOOL)isICPLEnabled { return cloudEnabled; }
@end

@interface CloudFixture : NSObject
@end
@implementation CloudFixture
- (id)getCPLSettings {
    reads++;
    if (throws) [NSException raise:@"Unavailable" format:@"Fixture failure"];
    return noReply ? nil : [NativeSettingsFixture new];
}
@end

@interface ClientFixture : NSObject
@end
@implementation ClientFixture
- (instancetype)initWithPhotoLibraryURL:(NSURL *)url {
    self=[super init];
    if (self) boundLibrary=url;
    return self;
}
- (id)cloudClient { return [CloudFixture new]; }
@end

@interface ChangedSettingsFixture : NSObject
@end
@implementation ChangedSettingsFixture
- (id)prefetchMode { return @0; }
- (BOOL)isKeepOriginalsEnabled { return NO; }
- (BOOL)isICPLEnabled { return YES; }
@end

int main(void) {
    @autoreleasepool {
        NSURL *library=[NSURL fileURLWithPath:@"/tmp/EffectiveSettings.photoslibrary"];
        PhotoSafetyState (^readState)(void)=^{
            return PhotoReadEffectiveSettings(library,ClientFixture.class,NativeSettingsFixture.class);
        };
        PhotoSafetyState state=readState();
        NSCAssert(state.verified && state.cloudPhotosEnabled && state.prefetchMode==0,@"Native optimize mode must verify");
        NSCAssert([boundLibrary isEqual:library] && reads==1,@"Read must bind to the requested library");
        __block unsigned operations=0;
        NSMutableDictionary *result=NSMutableDictionary.dictionary;
        NSCAssert(PhotoRunWithSafetyCheck(^{return state;},^{operations++;},result) && operations==1,@"Only verified optimize mode permits cleanup");
        mode=1; keepOriginals=YES;
        state=readState();
        NSCAssert(state.verified && state.prefetchMode==1 && reads==2,@"A fresh read must observe originals mode");
        NSCAssert(!PhotoRunWithSafetyCheck(^{return state;},^{operations++;},result) && operations==1,@"Originals mode must execute zero cleanup operations");
        mode=0; keepOriginals=NO;
        state=readState();
        NSCAssert(state.verified && state.prefetchMode==0 && reads==3,@"A fresh read must observe switching back");
        cloudEnabled=NO;
        NSCAssert(!readState().cloudPhotosEnabled,@"Native iCloud disablement must be preserved");
        cloudEnabled=YES;
        keepOriginals=YES;
        NSCAssert(!readState().verified,@"Contradictory native getters must fail closed");
        keepOriginals=NO; mode=2;
        NSCAssert(!readState().verified,@"Unknown native modes must fail closed");
        mode=0; noReply=YES;
        NSCAssert(!readState().verified,@"A missing or unauthorized reply must never mean optimize");
        noReply=NO; throws=YES;
        NSCAssert(!readState().verified,@"Native exceptions must fail closed");
        throws=NO;
        NSCAssert(!PhotoReadEffectiveSettings(library,ClientFixture.class,ChangedSettingsFixture.class).verified,@"Changed method signatures must fail closed");
        NSCAssert(!PhotoReadEffectiveSettings(library,NSObject.class,NativeSettingsFixture.class).verified,@"Missing client APIs must fail closed");
        NSCAssert(!PhotoReadEffectiveSettings(library,ClientFixture.class,NSObject.class).verified,@"Missing settings APIs must fail closed");
        NSCAssert(!PhotoReadEffectiveSettings(library,ClientFixture.class,nil).verified,@"Missing settings class must fail closed");
        NSCAssert(!PhotoReadEffectiveSettings([NSURL URLWithString:@"https://example.com"],ClientFixture.class,NativeSettingsFixture.class).verified,@"Non-file libraries must fail closed");
        puts("PASS native effective settings: library binding, fresh mode reads, disabled iCloud, missing replies, contradictions, exceptions and ABI changes.");
    }
    return 0;
}
