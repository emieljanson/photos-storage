#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <unistd.h>

// Read-only research. This executable does not resolve or call a purge function.
int main(void) {
    @autoreleasepool {
        alarm(20);
        void *framework = dlopen("/System/Library/PrivateFrameworks/CacheDelete.framework/CacheDelete", RTLD_NOW | RTLD_LOCAL);
        CFTypeRef (*query)(CFDictionaryRef) = framework ? dlsym(framework, "CacheDeleteCopyItemizedPurgeableSpaceWithInfo") : NULL;
        if (!query) return 1;
        id answer = CFBridgingRelease(query((__bridge CFDictionaryRef)@{
            @"CACHE_DELETE_VOLUME":@"/System/Volumes/Data",
            @"CACHE_DELETE_URGENCY_LIMIT":@4, @"CACHE_DELETE_NO_CACHE":@YES
        }));
        if (![answer isKindOfClass:NSDictionary.class]) return 2;
        NSMutableDictionary *counts = NSMutableDictionary.dictionary;
        for (NSString *key in answer) {
            if (![key hasPrefix:@"CACHE_DELETE_"] && [answer[key] isKindOfClass:NSNumber.class]) {
                counts[key] = answer[key];
            }
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:@{@"services":counts,
            @"reported_error":answer[@"CACHE_DELETE_ERROR"] ?: NSNull.null} options:NSJSONWritingSortedKeys error:nil];
        if (!data) return 3;
        fwrite(data.bytes, 1, data.length, stdout);
        fputc('\n', stdout);
    }
    return 0;
}
