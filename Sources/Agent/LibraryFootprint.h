#import <Foundation/Foundation.h>
#import <fts.h>
#import <sys/stat.h>

static BOOL libraryFootprint(NSURL *url, uint64_t *bytes, uint64_t *files) {
    struct stat root;
    if (lstat(url.fileSystemRepresentation,&root) || !S_ISDIR(root.st_mode) || root.st_uid != getuid()) return NO;
    char *paths[] = {strdup(url.fileSystemRepresentation), NULL};
    if (!paths[0]) return NO;
    FTS *tree = fts_open(paths,FTS_PHYSICAL|FTS_XDEV|FTS_NOCHDIR,NULL);
    if (!tree) { free(paths[0]); return NO; }
    NSMutableSet<NSNumber *> *inodes = [NSMutableSet set];
    uint64_t total = 0, count = 0;
    BOOL complete = YES;
    for (;;) {
        errno = 0;
        FTSENT *entry = fts_read(tree);
        if (!entry) { if (errno) complete = NO; break; }
        if (entry->fts_info==FTS_ERR || entry->fts_info==FTS_DNR || entry->fts_info==FTS_NS) {
            if (entry->fts_errno!=ENOENT) { complete=NO; break; }
            continue;
        }
        if (entry->fts_info!=FTS_F && entry->fts_info!=FTS_D) continue;
        struct stat *info = entry->fts_statp;
        if (info->st_dev!=root.st_dev) { fts_set(tree,entry,FTS_SKIP); continue; }
        NSNumber *inode = @((uint64_t)info->st_ino);
        if ([inodes containsObject:inode]) continue;
        [inodes addObject:inode];
        if (info->st_blocks<0 || UINT64_MAX-total < (uint64_t)info->st_blocks*512) { complete=NO; break; }
        total += (uint64_t)info->st_blocks*512;
        if (entry->fts_info==FTS_F) count++;
    }
    fts_close(tree);
    free(paths[0]);
    struct stat final;
    if (lstat(url.fileSystemRepresentation,&final) || final.st_ino!=root.st_ino || final.st_dev!=root.st_dev) complete=NO;
    if (!complete) return NO;
    *bytes=total;
    *files=count;
    return YES;
}
