#import <Foundation/Foundation.h>
#import "../Sources/Agent/PhotoSafetyMetadata.h"

int main(void) {
    @autoreleasepool {
        NSFileManager *fm=NSFileManager.defaultManager;
        NSURL *home=[fm.temporaryDirectory URLByAppendingPathComponent:[@"FotoBudget-safety-" stringByAppendingString:NSUUID.UUID.UUIDString]];
        NSURL *library=[home URLByAppendingPathComponent:@"Pictures/Fixture.photoslibrary"];
        NSString *account=@"private/com.apple.accountsd/cloudServiceEnableLog.plist";
        NSString *daemon=@"private/com.apple.photolibraryd/cloudServiceEnableLog.plist";
        NSString *local=@"private/com.apple.photolibraryd/appPrivateData.plist";
        NSString *marker=@"resources/cpl/cloudsync.noindex/cpl_enabled_marker";
        void (^write)(NSURL *,NSString *,id)=^(NSURL *root,NSString *path,id value) {
            NSURL *url=[root URLByAppendingPathComponent:path];
            NSCAssert([fm createDirectoryAtURL:url.URLByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:nil],@"fixture directory");
            NSData *data=[value isKindOfClass:NSData.class] ? value :
                [NSPropertyListSerialization dataWithPropertyList:value format:NSPropertyListBinaryFormat_v1_0 options:0 error:nil];
            NSCAssert([data writeToURL:url atomically:YES],@"fixture file");
        };
        NSDate *date=[NSDate dateWithTimeIntervalSinceNow:-10];
        NSArray *enabled=@[@{@"type":@"iCPL",@"timestamp":date,@"enabled":@YES}];
        __block unsigned checks=0;
        __block PhotoSafetyState (^nativeReader)(void)=nil;
        BOOL (^check)(BOOL)=^BOOL(BOOL expected) {
            PhotoSafetyState state=PhotoReadMetadataSafety(library,nativeReader);
            __block unsigned operations=0;
            NSMutableDictionary *result=[NSMutableDictionary dictionary];
            BOOL allowed=PhotoRunWithSafetyCheck(^{return state;},^{operations++;},result);
            checks++;
            if (allowed!=expected || operations!=(expected?1U:0U)) {
                fprintf(stderr,"FAIL case %u\n",checks);return NO;
            }
            return YES;
        };
        @try {
            write(library,account,enabled); write(library,daemon,enabled);
            write(library,local,@{@"Library":@{@"CPL":@{@"PrefetchMode":@0}}});
            write(library,@"resources/cpl/cloudsync.noindex/syncstatus.plist",@{@"iCloudLibraryExists":@YES});
            write(library,marker,NSData.data);
            if (!check(YES)) return 1;
            NSArray *cplEnabled=@[@{@"type":@"CPL",@"timestamp":date,@"enabled":@YES}];
            write(library,account,cplEnabled); write(library,daemon,cplEnabled);
            if (!check(YES)) { fprintf(stderr,"CPL enable logs must be recognized.\n"); return 16; }
            write(library,local,@{@"Library":@{@"CPL":@{}}}); if(!check(NO))return 17;
            write(library,local,@{@"Library":@{@"CPL":@{@"PrefetchMode":@0}}});
            write(library,account,enabled); if(!check(YES))return 18;
            NSDate *later=[date dateByAddingTimeInterval:1];
            write(library,account,[enabled arrayByAddingObject:@{@"type":@"CPL",@"timestamp":later,@"enabled":@NO}]); if(!check(NO))return 19;
            write(library,account,[cplEnabled arrayByAddingObject:@{@"type":@"iCPL",@"timestamp":later,@"enabled":@NO}]); if(!check(NO))return 20;
            write(library,account,[enabled arrayByAddingObject:@{@"type":@"CPL",@"timestamp":date,@"enabled":@NO}]); if(!check(NO))return 21;
            write(library,account,cplEnabled);
            write(library,daemon,[cplEnabled arrayByAddingObject:@{@"type":@"CPL",@"timestamp":later,@"enabled":@NO}]); if(!check(NO))return 22;
            write(library,daemon,@[@{@"type":@"CPL",@"timestamp":date,@"enabled":@"true"}]); if(!check(NO))return 23;
            write(library,account,enabled); write(library,daemon,enabled);
            __block unsigned nativeReads=0;
            __block PhotoSafetyState nativeState={YES,YES,0};
            nativeReader=^{nativeReads++; return nativeState;};
            if(!check(YES) || nativeReads!=0) return 24;
            write(library,local,@{@"Library":@{@"CPL":@{@"iCPLEnabled":@YES}}});
            if(!check(YES) || nativeReads!=1) {
                fprintf(stderr,"A missing recorded choice must use a confirmed native optimize reply.\n");return 25;
            }
            nativeState=(PhotoSafetyState){YES,YES,1}; if(!check(NO))return 26;
            nativeState=(PhotoSafetyState){YES,NO,0}; if(!check(NO))return 27;
            nativeState=(PhotoSafetyState){NO,NO,-1}; if(!check(NO))return 28;
            nativeState=(PhotoSafetyState){YES,YES,2}; if(!check(NO))return 29;
            nativeState=(PhotoSafetyState){NO,NO,PhotoModeAccessRequired}; if(!check(NO))return 30;
            nativeState=(PhotoSafetyState){YES,YES,0};
            write(library,daemon,@[]);
            unsigned before=nativeReads;
            if(!check(NO) || nativeReads!=before)return 31;
            write(library,daemon,enabled);
            write(library,@"resources/cpl/disableICloudPhotos",NSData.data);
            if(!check(NO) || nativeReads!=before)return 32;
            [fm removeItemAtURL:[library URLByAppendingPathComponent:@"resources/cpl/disableICloudPhotos"] error:nil];
            write(library,local,@{@"Library":@{@"CPL":@{@"PrefetchMode":@"0"}}});
            if(!check(NO) || nativeReads!=before)return 33;
            write(library,local,@{@"Library":@{@"CPL":@{}}});
            nativeReader=^{
                write(library,@"resources/cpl/disableICloudPhotos",NSData.data);
                return (PhotoSafetyState){YES,YES,0};
            };
            if(!check(NO)) { fprintf(stderr,"iCloud disabled during the native request must block cleanup.\n");return 35; }
            [fm removeItemAtURL:[library URLByAppendingPathComponent:@"resources/cpl/disableICloudPhotos"] error:nil];
            nativeReader=^{
                write(library,daemon,@[@{@"type":@"CPL",@"timestamp":NSDate.date,@"enabled":@NO}]);
                return (PhotoSafetyState){YES,YES,0};
            };
            if(!check(NO)) { fprintf(stderr,"New disable logs during the native request must block cleanup.\n");return 36; }
            write(library,daemon,enabled);
            nativeReader=^{
                write(library,local,@{@"Library":@{@"CPL":@{@"PrefetchMode":@1}}});
                return (PhotoSafetyState){YES,YES,0};
            };
            if(!check(NO))return 34;
            nativeReader=nil;
            write(library,local,@{@"Library":@{@"CPL":@{@"PrefetchMode":@1}}}); if(!check(NO))return 2;
            write(library,local,@{@"Library":@{@"CPL":@{}}}); if(!check(NO))return 3;
            write(library,local,@{@"Library":@{@"CPL":@{@"PrefetchMode":@"0"}}}); if(!check(NO))return 4;
            write(library,local,@{@"Library":@{@"CPL":@{@"PrefetchMode":@NO}}}); if(!check(NO))return 4;
            write(library,local,@{@"Library":@{@"CPL":@{@"PrefetchMode":@0}}});
            [fm removeItemAtURL:[library URLByAppendingPathComponent:marker] error:nil]; if(!check(NO))return 5;
            write(library,marker,NSData.data);
            write(library,account,[enabled arrayByAddingObject:@{@"type":@"iCPL",@"timestamp":NSDate.date,@"enabled":@NO}]); if(!check(NO))return 6;
            write(library,account,[enabled arrayByAddingObject:@{@"type":@"collection-shares",@"timestamp":NSDate.date,@"enabled":@NO}]); if(!check(YES))return 7;
            write(library,local,@{@"Library":@{@"CPL":@{@"PrefetchMode":@1}}}); if(!check(NO))return 9;
            write(library,local,@{@"Library":@{@"CPL":@{@"PrefetchMode":@0}}}); if(!check(YES))return 10;
            write(library,daemon,@[]); if(!check(NO))return 11;
            write(library,daemon,@[@{@"type":@"iCPL",@"timestamp":[NSDate dateWithTimeIntervalSinceNow:3600],@"enabled":@YES}]); if(!check(NO))return 12;
            write(library,daemon,enabled);
            NSURL *link=[library URLByAppendingPathComponent:daemon];
            [fm removeItemAtURL:link error:nil];
            NSCAssert(!symlink([library URLByAppendingPathComponent:account].fileSystemRepresentation,link.fileSystemRepresentation),@"fixture symlink"); if(!check(NO))return 13;
            [fm removeItemAtURL:link error:nil]; write(library,daemon,enabled);
            write(library,@"resources/cpl/disableICloudPhotos",NSData.data); if(!check(NO))return 14;
            [fm removeItemAtURL:[library URLByAppendingPathComponent:@"resources/cpl/disableICloudPhotos"] error:nil];
            write(library,local,[@"invalid plist" dataUsingEncoding:NSUTF8StringEncoding]); if(!check(NO))return 15;
            printf("PASS %u metadata safety cases; all disallowed cases execute zero operations.\n",checks);
        } @finally { [fm removeItemAtURL:home error:nil]; }
        return 0;
    }
}
