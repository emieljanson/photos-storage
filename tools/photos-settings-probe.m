// Read-only native settings probe. Authorization is requested only with the
// explicit --request-access option, from a bundle with a Photos usage message.
#import <AppKit/AppKit.h>
#import <Photos/Photos.h>
#import <dlfcn.h>
#import <objc/message.h>
#import <unistd.h>
#import <fcntl.h>
#import <signal.h>
#import "../Sources/Agent/PhotoEffectiveSettings.h"
#import "../Sources/Agent/PhotoSafetyMetadata.h"

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
            helper.arguments=@[@"--safety"];
            NSPipe *output=NSPipe.pipe;
            helper.standardOutput=output;
            dispatch_semaphore_t finished=dispatch_semaphore_create(0);
            helper.terminationHandler=^(NSTask *task) { (void)task; dispatch_semaphore_signal(finished); };
            NSError *error=nil;
            if (![helper launchAndReturnError:&error]) return 2;
            if (dispatch_semaphore_wait(finished,dispatch_time(DISPATCH_TIME_NOW,20*NSEC_PER_SEC))) {
                if (helper.running) [helper terminate];
                if (dispatch_semaphore_wait(finished,dispatch_time(DISPATCH_TIME_NOW,NSEC_PER_SEC)) && helper.running) {
                    kill(helper.processIdentifier,SIGKILL);
                }
                puts("{\"error\":\"helper_timeout\"}");
                return 124;
            }
            [helper waitUntilExit];
            int fd=output.fileHandleForReading.fileDescriptor;
            int flags=fcntl(fd,F_GETFL);
            if (flags<0 || fcntl(fd,F_SETFL,flags|O_NONBLOCK)<0) return 2;
            char buffer[4096];
            NSUInteger total=0;
            for (;;) {
                ssize_t count=read(fd,buffer,sizeof(buffer));
                if (count<0 && errno==EINTR) continue;
                if (count<0 && errno!=EAGAIN && errno!=EWOULDBLOCK) return 2;
                if (count<=0) break;
                total+=(NSUInteger)count;
                if (total>65536) return 2;
                fwrite(buffer,1,(size_t)count,stdout);
            }
            return helper.terminationStatus;
        } else if (argc!=1 && !(argc==2 && !strcmp(argv[1],"--safety"))) { return 2; }
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
        PhotoSafetyState metadata=PhotoReadMetadataSafety(url,^{return state;});
        PhotoRunWithSafetyCheck(^{return metadata;},^{operation=YES;},result);
        result[@"metadata_allows_cleanup"]=@(operation);
        NSData *data=[NSJSONSerialization dataWithJSONObject:result options:NSJSONWritingSortedKeys error:nil];
        if (!data) return 3;
        fwrite(data.bytes,1,data.length,stdout); fputc('\n',stdout);
        return state.verified ? 0 : 1;
    }
}
