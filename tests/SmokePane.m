#import <Cocoa/Cocoa.h>
#import <PreferencePanes/PreferencePanes.h>

@interface NSPreferencePane (SummaryCheck)
- (NSString *)summaryForState:(NSDictionary *)state alive:(BOOL)alive;
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        if (argc!=2) return 1;
        [NSApplication sharedApplication];
        NSURL *url=[NSURL fileURLWithPath:[NSString stringWithUTF8String:argv[1]]];
        NSBundle *bundle=[NSBundle bundleWithURL:url];
        NSError *error=nil;
        if (![bundle loadAndReturnError:&error]) {
            NSLog(@"Pane failed to load: %@",error);
            return 2;
        }
        Class principal=bundle.principalClass;
        if (![principal isSubclassOfClass:NSPreferencePane.class]) return 3;
        NSPreferencePane *pane=[[principal alloc] initWithBundle:bundle];
        if (![pane loadMainView]) return 4;
        NSDictionary *unsupported=@{@"automatic":@NO,@"cleanupAllowed":@NO,
            @"message":@"This version of Photos is not supported. Automatic optimization is off."};
        if (![[pane summaryForState:unsupported alive:YES] isEqual:@"This version of Photos is not supported."]) return 5;
        if (![[pane summaryForState:@{@"automatic":@NO,@"safetyMessage":@"iCloud disabled"} alive:YES]
              isEqual:@"Check iCloud Photos and Optimize Mac Storage in Photos."]) return 6;
        puts("PASS same embedded Settings pane loaded its native view.");
        puts("PASS unsupported Photos and iCloud recovery have distinct summaries.");
    }
    return 0;
}
