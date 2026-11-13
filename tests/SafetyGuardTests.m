#import <Foundation/Foundation.h>
#import "../Sources/Agent/PhotoSafety.h"

static BOOL checkState(PhotoSafetyState state, BOOL expected, NSString *reason) {
    __block unsigned operations=0, reads=0;
    NSMutableDictionary *result=[NSMutableDictionary dictionary];
    BOOL allowed=PhotoRunWithSafetyCheck(^{ reads++; return state; }, ^{ operations++; }, result);
    return CFGetTypeID((__bridge CFTypeRef)result[@"cleanup_allowed"])==CFBooleanGetTypeID() &&
        allowed==expected && operations==(expected ? 1U : 0U) && reads==1 &&
        [result[@"cleanup_allowed"] boolValue]==expected &&
        (reason ? [result[@"error_code"] isEqual:reason] : result[@"error_code"]==nil);
}

int main(void) {
    @autoreleasepool {
        if (!checkState((PhotoSafetyState){YES,YES,0},YES,nil)) return 1;
        if (!checkState((PhotoSafetyState){YES,NO,0},NO,@"icloud_photos_disabled")) return 2;
        if (!checkState((PhotoSafetyState){YES,YES,1},NO,@"storage_optimization_disabled")) return 3;
        if (!checkState((PhotoSafetyState){NO,YES,0},NO,@"icloud_optimization_unverified")) return 4;
        if (!checkState((PhotoSafetyState){YES,YES,2},NO,@"icloud_optimization_unverified")) return 5;
        if (!checkState((PhotoSafetyState){YES,YES,-1},NO,@"icloud_optimization_unverified")) return 6;
        __block BOOL optimizationChanged=NO;
        __block unsigned operations=0;
        PhotoSafetyState (^read)(void)=^{ return (PhotoSafetyState){YES,YES,optimizationChanged ? 1 : 0}; };
        NSMutableDictionary *result=[NSMutableDictionary dictionary];
        if (!PhotoAnnotateSafety(read(),result)) return 7;
        optimizationChanged=YES;
        if (PhotoRunWithSafetyCheck(read,^{ operations++; },result) || operations) return 8;
        puts("PASS: iCloud off, originals mode, unknown state/mode and changed settings block the operation; only confirmed optimization permits it.");
        return 0;
    }
}
