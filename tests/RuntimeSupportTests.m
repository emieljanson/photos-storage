#import <Foundation/Foundation.h>
#import "../Sources/Agent/PhotoRuntimeSupport.h"

@interface OptimizingPhotos : NSObject
+ (id)descriptionForPrefetchMode:(int64_t)mode;
@end
@implementation OptimizingPhotos
+ (id)descriptionForPrefetchMode:(int64_t)mode { return mode==0 ? @"optimize" : @"originals"; }
@end

@interface ChangedPhotos : NSObject
+ (id)descriptionForPrefetchMode:(int64_t)mode;
@end
@implementation ChangedPhotos
+ (id)descriptionForPrefetchMode:(int64_t)mode { (void)mode; return @"originals"; }
@end

@interface InvalidPhotos : NSObject
+ (id)descriptionForPrefetchMode:(int64_t)mode;
@end
@implementation InvalidPhotos
+ (id)descriptionForPrefetchMode:(int64_t)mode { (void)mode; return @0; }
@end

@interface ChangedSignature : NSObject
+ (NSInteger)descriptionForPrefetchMode:(int64_t)mode;
@end
@implementation ChangedSignature
+ (NSInteger)descriptionForPrefetchMode:(int64_t)mode { return mode; }
@end

int main(void) {
    @autoreleasepool {
        if (!PhotoOptimizationModeRecognized(OptimizingPhotos.class)) return 1;
        if (PhotoOptimizationModeRecognized(ChangedPhotos.class)) return 2;
        if (PhotoOptimizationModeRecognized(InvalidPhotos.class)) return 3;
        if (PhotoOptimizationModeRecognized(ChangedSignature.class)) return 4;
        if (PhotoOptimizationModeRecognized(NSObject.class)) return 5;
        if (PhotoOptimizationModeRecognized(nil)) return 6;
        puts("PASS Photos runtime mode meaning, return type, signature and missing APIs fail closed.");
    }
    return 0;
}
