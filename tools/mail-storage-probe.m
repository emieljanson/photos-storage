#import <Foundation/Foundation.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <dlfcn.h>
#import <unistd.h>

// Capability inspection only. No account mutation, message deletion or purge.
static NSArray *methodsForClass(Class cls) {
    unsigned int count = 0;
    Method *methods = class_copyMethodList(cls, &count);
    NSMutableArray *result = NSMutableArray.array;
    for (unsigned int i = 0; i < count; i++) {
        NSString *name = NSStringFromSelector(method_getName(methods[i]));
        NSString *lower = name.lowercaseString;
        if ([lower containsString:@"purge"] || [lower containsString:@"cache"] ||
            [lower containsString:@"download"] || [lower hasPrefix:@"init"] ||
            [lower containsString:@"shared"] || [lower containsString:@"account"]) {
            [result addObject:@{@"selector":name, @"types":@(method_getTypeEncoding(methods[i]))}];
        }
    }
    free(methods);
    return result;
}

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        alarm(20);
        void *framework = dlopen("/System/Library/PrivateFrameworks/Mail.framework/Mail", RTLD_NOW | RTLD_LOCAL);
        if (!framework) {
            fprintf(stderr, "Unable to load Mail framework: %s\n", dlerror());
            return 1;
        }
        NSMutableDictionary *result = NSMutableDictionary.dictionary;
        for (NSString *name in @[@"MFCacheDeleteAttachmentPurger", @"MailDownloadFolderManager", @"MFMailAccount", @"MFIMAPAccount"]) {
            Class cls = NSClassFromString(name);
            result[name] = @{@"available":@(cls != Nil), @"instance_methods":methodsForClass(cls),
                             @"class_methods":methodsForClass(object_getClass(cls))};
        }
        if (argc == 2 && !strcmp(argv[1], "--estimate")) {
            result[@"estimate_valid"] = @NO;
            result[@"estimate_error"] = @"purger_unverified";
            @try {
                Class cls = NSClassFromString(@"MFCacheDeleteAttachmentPurger");
                Method method = class_getInstanceMethod(cls, NSSelectorFromString(@"purgeableBytesAvailable"));
                SEL initializer = NSSelectorFromString(@"initWithVolumeIdentifier:urgency:");
                Method initMethod = class_getInstanceMethod(cls, initializer);
                id volume = nil;
                NSURL *homeURL = [NSURL fileURLWithPath:NSHomeDirectory()];
                [homeURL getResourceValue:&volume forKey:NSURLVolumeIdentifierKey error:nil];
                if (volume && method && !strcmp(method_getTypeEncoding(method), "Q16@0:8") &&
                    initMethod && !strcmp(method_getTypeEncoding(initMethod), "@28@0:8@16i24")) {
                    id instance = ((id (*)(id, SEL, id, int))objc_msgSend)([cls alloc], initializer, volume, 3);
                    SEL accountsSelector = NSSelectorFromString(@"_getActiveAccounts:inactiveAccounts:");
                    Method accountsMethod = class_getInstanceMethod(cls, accountsSelector);
                    BOOL accountsConfirmed = NO;
                    if (accountsMethod && !strcmp(method_getTypeEncoding(accountsMethod), "v32@0:8^@16^@24")) {
                        id active = nil, inactive = nil;
                        ((void (*)(id, SEL, id __autoreleasing *, id __autoreleasing *))objc_msgSend)(instance, accountsSelector, &active, &inactive);
                        result[@"active_account_count"] = [active respondsToSelector:@selector(count)] ? @([active count]) : NSNull.null;
                        result[@"inactive_account_count"] = [inactive respondsToSelector:@selector(count)] ? @([inactive count]) : NSNull.null;
                        accountsConfirmed = [active respondsToSelector:@selector(count)] && [inactive respondsToSelector:@selector(count)] &&
                            [active count] + [inactive count] > 0;
                    }
                    result[@"estimate_valid"] = @(accountsConfirmed);
                    if (accountsConfirmed) {
                        [result removeObjectForKey:@"estimate_error"];
                        result[@"native_estimate_bytes"] = @(((uint64_t (*)(id, SEL))objc_msgSend)(instance, NSSelectorFromString(@"purgeableBytesAvailable")));
                    }
                    else result[@"estimate_error"] = @"mail_accounts_unverified";
                } else {
                    result[@"estimate_error_reason"] = @"Missing volume identifier or unsupported native method signatures.";
                }
            } @catch (NSException *exception) {
                result[@"estimate_error"] = exception.name;
                result[@"estimate_error_reason"] = exception.reason ?: @"";
            }
        }
        NSData *data = [NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys error:nil];
        if (!data) return 2;
        fwrite(data.bytes, 1, data.length, stdout);
        fputc('\n', stdout);
    }
    return 0;
}
