#import <Cocoa/Cocoa.h>
#import <PreferencePanes/PreferencePanes.h>

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
        puts("PASS same embedded Settings pane loaded its native view.");
    }
    return 0;
}
