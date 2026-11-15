#import "CloudEviction.h"

NSInteger PSEvictReviewedUbiquitousItem(NSURL *url,
                                      BOOL (NS_NOESCAPE ^validate)(NSURL *resolvedFileURL),
                                      NSError **error) {
    if (error) *error = nil;
    // Keep this NSURL in Objective-C: Swift URL bridging normalizes references to paths.
    NSURL *reference = url.fileReferenceURL;
    NSURL *resolved = reference.filePathURL;
    if (!reference.isFileReferenceURL || !resolved.isFileURL) {
        if (error) *error = [NSError errorWithDomain:NSCocoaErrorDomain code:NSFileReadUnknownError userInfo:nil];
        return -1;
    }
    if (!validate(resolved)) return 0;
    return [NSFileManager.defaultManager evictUbiquitousItemAtURL:reference error:error] ? 1 : -1;
}
