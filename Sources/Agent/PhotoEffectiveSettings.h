#import "PhotoSafety.h"
#import <objc/runtime.h>

@protocol PhotoSettingsReading
- (NSInteger)prefetchMode;
- (BOOL)isKeepOriginalsEnabled;
- (BOOL)isICPLEnabled;
@end

@protocol PhotoCloudSettingsReading
- (id)getCPLSettings;
@end

@protocol PhotoSettingsClient
- (instancetype)initWithPhotoLibraryURL:(NSURL *)url;
- (id)cloudClient;
@end

static BOOL PhotoInstanceMethodMatches(Class cls, NSString *name, const char *encoding) {
    Method method=cls ? class_getInstanceMethod(cls,NSSelectorFromString(name)) : NULL;
    return method && !strcmp(method_getTypeEncoding(method),encoding);
}

static BOOL PhotoEffectiveSettingsAvailable(Class clientClass, Class settingsClass) {
    return settingsClass &&
        PhotoInstanceMethodMatches(clientClass,@"initWithPhotoLibraryURL:","@24@0:8@16") &&
        PhotoInstanceMethodMatches(clientClass,@"cloudClient","@16@0:8") &&
        PhotoInstanceMethodMatches(settingsClass,@"prefetchMode","q16@0:8") &&
        PhotoInstanceMethodMatches(settingsClass,@"isKeepOriginalsEnabled","B16@0:8") &&
        PhotoInstanceMethodMatches(settingsClass,@"isICPLEnabled","B16@0:8");
}

static PhotoSafetyState PhotoReadEffectiveSettings(NSURL *library, Class clientClass, Class settingsClass) {
    PhotoSafetyState unknown={NO,NO,-1};
    if (!library.isFileURL || !PhotoEffectiveSettingsAvailable(clientClass,settingsClass)) return unknown;
    @try {
        id<PhotoSettingsClient> client=[(id<PhotoSettingsClient>)[clientClass alloc] initWithPhotoLibraryURL:library];
        id cloud=[client cloudClient];
        if (!PhotoInstanceMethodMatches([cloud class],@"getCPLSettings","@16@0:8")) return unknown;
        id<PhotoSettingsReading> settings=[(id<PhotoCloudSettingsReading>)cloud getCPLSettings];
        if (![(id)settings isKindOfClass:settingsClass]) return unknown;
        NSInteger mode=[settings prefetchMode];
        if ((mode!=0 && mode!=1) || [settings isKeepOriginalsEnabled]!=(mode==1)) return unknown;
        return (PhotoSafetyState){YES,[settings isICPLEnabled],mode};
    } @catch (__unused NSException *exception) { return unknown; }
}
