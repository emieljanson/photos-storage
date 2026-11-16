#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Returns 1 after a native request, 0 when validation refuses it, or -1 on error.
FOUNDATION_EXPORT NSInteger PSEvictReviewedUbiquitousItem(
    NSURL *url,
    BOOL (NS_NOESCAPE ^validate)(NSURL *resolvedFileURL),
    NSError * _Nullable * _Nullable error) NS_SWIFT_NOTHROW;

NS_ASSUME_NONNULL_END
