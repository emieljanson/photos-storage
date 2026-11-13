#import <Foundation/Foundation.h>
#import "../Sources/Agent/LibraryFootprint.h"

int main(void) {
    @autoreleasepool {
        NSFileManager *manager=NSFileManager.defaultManager;
        NSURL *base=[manager.temporaryDirectory URLByAppendingPathComponent:[@"FotoBudget-test-" stringByAppendingString:NSUUID.UUID.UUIDString] isDirectory:YES];
        NSURL *root=[base URLByAppendingPathComponent:@"library" isDirectory:YES];
        NSURL *child=[root URLByAppendingPathComponent:@"child" isDirectory:YES];
        NSURL *large=[root URLByAppendingPathComponent:@"large"];
        NSURL *small=[child URLByAppendingPathComponent:@"small"];
        NSURL *outside=[base URLByAppendingPathComponent:@"outside"];
        BOOL passed=NO;
        @try {
            if (![manager createDirectoryAtURL:child withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil]) return 2;
            if (![[NSMutableData dataWithLength:1024*1024] writeToURL:large atomically:YES] ||
                ![[NSMutableData dataWithLength:8192] writeToURL:small atomically:YES] ||
                ![[NSMutableData dataWithLength:2*1024*1024] writeToURL:outside atomically:YES]) return 3;
            NSURL *hardlink=[root URLByAppendingPathComponent:@"same-file"];
            NSURL *externalLink=[root URLByAppendingPathComponent:@"outside-link"];
            if (link(large.fileSystemRepresentation,hardlink.fileSystemRepresentation) ||
                symlink(outside.fileSystemRepresentation,externalLink.fileSystemRepresentation)) return 4;
            uint64_t expected=0;
            for (NSURL *url in @[root,child,large,small]) {
                struct stat info;
                if (lstat(url.fileSystemRepresentation,&info)) return 5;
                expected+=(uint64_t)info.st_blocks*512;
            }
            uint64_t bytes=0, files=0;
            if (!libraryFootprint(root,&bytes,&files) || bytes!=expected || files!=2) return 6;
            if (libraryFootprint(large,&bytes,&files) || libraryFootprint(externalLink,&bytes,&files)) return 7;
            if (chmod(child.fileSystemRepresentation,0000)) return 8;
            if (libraryFootprint(root,&bytes,&files)) return 9;
            passed=YES;
        } @finally {
            chmod(child.fileSystemRepresentation,0700);
            [manager removeItemAtURL:base error:nil];
        }
        puts(passed ? "PASS hardlinks counted once; symlinks not followed; invalid roots and incomplete scans rejected" : "FAIL");
        return passed ? 0 : 1;
    }
}
