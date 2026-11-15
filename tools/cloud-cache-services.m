#import <Foundation/Foundation.h>
#import <dlfcn.h>
#import <unistd.h>

static id JSONError(id value) {
    if (!value) return NSNull.null;
    if ([value isKindOfClass:NSError.class]) {
        NSError *error = value;
        return @{@"domain":error.domain, @"code":@(error.code)};
    }
    if ([NSJSONSerialization isValidJSONObject:@[value]]) return value;
    return @{@"unsupported_type":NSStringFromClass([value class])};
}

// Read-only research. This executable does not resolve or call a purge function.
int main(void) {
    @autoreleasepool {
        alarm(20);
        void *framework = dlopen("/System/Library/PrivateFrameworks/CacheDelete.framework/CacheDelete", RTLD_NOW | RTLD_LOCAL);
        if (!framework) {
            fprintf(stderr, "Unable to load CacheDelete: %s\n", dlerror());
            return 1;
        }
        CFTypeRef (*query)(CFDictionaryRef) = dlsym(framework, "CacheDeleteCopyItemizedPurgeableSpaceWithInfo");
        if (!query) {
            fprintf(stderr, "Unable to resolve CacheDelete estimate function: %s\n", dlerror());
            return 1;
        }
        id answer = CFBridgingRelease(query((__bridge CFDictionaryRef)@{
            @"CACHE_DELETE_VOLUME":@"/System/Volumes/Data",
            @"CACHE_DELETE_URGENCY_LIMIT":@4, @"CACHE_DELETE_NO_CACHE":@YES
        }));
        if (![answer isKindOfClass:NSDictionary.class]) return 2;
        NSMutableDictionary *counts = NSMutableDictionary.dictionary;
        for (NSString *key in answer) {
            if ([key isKindOfClass:NSString.class] && ![key hasPrefix:@"CACHE_DELETE_"] && [answer[key] isKindOfClass:NSNumber.class]) {
                counts[key] = answer[key];
            }
        }
        NSDictionary *result = @{@"services":counts, @"reported_error":JSONError(answer[@"CACHE_DELETE_ERROR"])};
        NSError *error = nil;
        NSData *data = [NSJSONSerialization isValidJSONObject:result] ?
            [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys error:&error] : nil;
        if (!data) {
            fprintf(stderr, "Unable to serialize CacheDelete estimate (%s, %ld).\n", error.domain.UTF8String ?: "invalid JSON", (long)error.code);
            return 3;
        }
        fwrite(data.bytes, 1, data.length, stdout);
        fputc('\n', stdout);
    }
    return 0;
}
