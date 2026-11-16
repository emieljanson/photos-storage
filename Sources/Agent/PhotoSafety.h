#pragma once
#import <Foundation/Foundation.h>

typedef struct {
    BOOL verified;
    BOOL cloudPhotosEnabled;
    NSInteger prefetchMode;
} PhotoSafetyState;

enum {
    PhotoModeAccessRequired=-2,
    PhotoModeAccessDenied=-3,
    PhotoModeNativeUnavailable=-4
};

// The helper verifies Photos identifies mode 0 as "optimize" at runtime.
// Missing replies and other modes never authorize an operation.
static BOOL PhotoAnnotateSafety(PhotoSafetyState state, NSMutableDictionary *result) {
    NSString *reason=nil;
    if (!state.verified && state.prefetchMode==PhotoModeAccessRequired) reason=@"photos_status_access_required";
    else if (!state.verified && state.prefetchMode==PhotoModeAccessDenied) reason=@"photos_status_access_denied";
    else if (!state.verified && state.prefetchMode==PhotoModeNativeUnavailable) reason=@"photos_settings_unavailable";
    else if (!state.verified) reason=@"icloud_optimization_unverified";
    else if (!state.cloudPhotosEnabled) reason=@"icloud_photos_disabled";
    else if (state.prefetchMode==1) reason=@"storage_optimization_disabled";
    else if (state.prefetchMode!=0) reason=@"icloud_optimization_unverified";
    result[@"icloud_photos_enabled"]=state.verified ? (state.cloudPhotosEnabled ? @YES : @NO) : NSNull.null;
    result[@"optimized_storage_enabled"]=state.verified && (state.prefetchMode==0 || state.prefetchMode==1)
        ? (state.prefetchMode==0 ? @YES : @NO) : NSNull.null;
    result[@"cleanup_allowed"]=reason ? @NO : @YES;
    if (reason) result[@"safety_error_code"]=reason;
    else [result removeObjectForKey:@"safety_error_code"];
    return reason==nil;
}

static BOOL PhotoRunWithSafetyCheck(PhotoSafetyState (^readState)(void), void (^operation)(void),
                                   NSMutableDictionary *result) {
    if (!PhotoAnnotateSafety(readState(),result)) {
        result[@"error_code"]=result[@"safety_error_code"];
        return NO;
    }
    operation();
    return YES;
}
