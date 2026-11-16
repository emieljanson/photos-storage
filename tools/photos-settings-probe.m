// Read-only native settings probe. Authorization is requested only with the
// explicit --request-access option, from a bundle with a Photos usage message.
#import <AppKit/AppKit.h>
#import <Photos/Photos.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <unistd.h>
#import "../Sources/Agent/PhotoEffectiveSettings.h"

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc==2 && !strcmp(argv[1],"--request-access")) {
            [NSApplication sharedApplication];
            [NSApp activateIgnoringOtherApps:YES];
            __block BOOL finished=NO;
            [PHPhotoLibrary requestAuthorizationForAccessLevel:PHAccessLevelReadWrite handler:^(PHAuthorizationStatus status) {
                (void)status;
                dispatch_async(dispatch_get_main_queue(),^{finished=YES;});
            }];
            while (!finished) [NSRunLoop.currentRunLoop runUntilDate:[NSDate dateWithTimeIntervalSinceNow:0.1]];
        } else if (argc==3 && !strcmp(argv[1],"--check-helper")) {
            NSTask *helper=[NSTask new];
            helper.executableURL=[NSURL fileURLWithPath:@(argv[2])];
            NSPipe *output=NSPipe.pipe;
            helper.standardOutput=output;
            NSError *error=nil;
            if (![helper launchAndReturnError:&error]) return 2;
            NSData *data=[output.fileHandleForReading readDataToEndOfFile];
            [helper waitUntilExit];
            fwrite(data.bytes,1,data.length,stdout);
            return helper.terminationStatus;
        } else if (argc!=1) { return 2; }
        alarm(20);
        dlopen("/System/Library/PrivateFrameworks/PhotoLibraryServices.framework/PhotoLibraryServices",RTLD_NOW|RTLD_LOCAL);
        SEL selector=NSSelectorFromString(@"systemPhotoLibraryURL");
        Method method=class_getClassMethod(PHPhotoLibrary.class,selector);
        if (!method || strcmp(method_getTypeEncoding(method),"@16@0:8")) return 2;
        NSURL *url=((id(*)(id,SEL))objc_msgSend)(PHPhotoLibrary.class,selector);
        PhotoSafetyState state=PhotoReadEffectiveSettings(url,NSClassFromString(@"PLAssetsdClient"),NSClassFromString(@"PLCPLSettings"));
        NSMutableDictionary *result=[@{@"authorization":@([PHPhotoLibrary authorizationStatusForAccessLevel:PHAccessLevelReadWrite]),
            @"verified":@(state.verified),@"prefetch_mode":@(state.prefetchMode)} mutableCopy];
        __block BOOL operation=NO;
        PhotoRunWithSafetyCheck(^{return state;},^{operation=YES;},result);
        result[@"would_allow_cleanup"]=@(operation);
        NSData *data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys error:nil];
        if (!data) return 3;
        fwrite(data.bytes,1,data.length,stdout); fputc('\n',stdout);
        return state.verified ? 0 : 1;
    }
}
