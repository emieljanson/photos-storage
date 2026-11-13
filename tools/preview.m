#import "../Sources/Pane/PhotosStoragePane.m"

@interface PreviewPane : PhotosStoragePane
@property(nonatomic, strong) NSURL *fixtureRoot;
@end

@implementation PreviewPane
- (NSURL *)controlRoot { return self.fixtureRoot; }
- (void)ensureAgent {}
- (NSString *)send:(NSString *)action value:(NSNumber *)value enabled:(NSNumber *)enabled {
    (void)action; (void)value; (void)enabled;
    return nil;
}
@end

@interface PreviewDelegate : NSObject <NSApplicationDelegate>
@property(nonatomic, strong) NSWindow *window;
@property(nonatomic, strong) PreviewPane *pane;
@property(nonatomic, strong) NSSegmentedControl *scenarios;
@property(nonatomic, strong) NSSegmentedControl *appearances;
@end

@implementation PreviewDelegate
- (void)applicationDidFinishLaunching:(NSNotification *)notification {
    (void)notification;
    self.pane = [[PreviewPane alloc] initWithBundle:NSBundle.mainBundle];
    self.pane.fixtureRoot = [NSURL fileURLWithPath:[NSTemporaryDirectory() stringByAppendingPathComponent:NSUUID.UUID.UUIDString] isDirectory:YES];
    [NSFileManager.defaultManager createDirectoryAtURL:self.pane.fixtureRoot withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:nil];
    self.window = [[NSWindow alloc] initWithContentRect:NSMakeRect(0, 0, 500, 400)
        styleMask:NSWindowStyleMaskTitled | NSWindowStyleMaskClosable | NSWindowStyleMaskResizable
        backing:NSBackingStoreBuffered defer:NO];
    self.window.title = @"Photos Storage — UI Preview";
    self.window.contentMinSize = NSMakeSize(500, 400);
    NSView *view = [self.pane loadMainView];
    view.frame = NSMakeRect(0, 84, 500, 316);
    view.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
    [self.window.contentView addSubview:view];
    self.scenarios = [NSSegmentedControl segmentedControlWithLabels:@[@"Demo data", @"Worst case", @"Empty", @"Access", @"Unsafe", @"Small disk", @"Stopped"]
        trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(changeScenario:)];
    self.scenarios.controlSize = NSControlSizeSmall;
    self.scenarios.translatesAutoresizingMaskIntoConstraints = NO;
    [self.window.contentView addSubview:self.scenarios];
    [NSLayoutConstraint activateConstraints:@[
        [self.scenarios.centerXAnchor constraintEqualToAnchor:self.window.contentView.centerXAnchor],
        [self.scenarios.bottomAnchor constraintEqualToAnchor:self.window.contentView.bottomAnchor constant:-48]
    ]];
    self.appearances = [NSSegmentedControl segmentedControlWithLabels:@[@"System", @"Light", @"Dark", @"High contrast"]
        trackingMode:NSSegmentSwitchTrackingSelectOne target:self action:@selector(changeAppearance:)];
    self.appearances.controlSize = NSControlSizeSmall;
    self.appearances.translatesAutoresizingMaskIntoConstraints = NO;
    [self.window.contentView addSubview:self.appearances];
    [NSLayoutConstraint activateConstraints:@[
        [self.appearances.centerXAnchor constraintEqualToAnchor:self.window.contentView.centerXAnchor],
        [self.appearances.bottomAnchor constraintEqualToAnchor:self.window.contentView.bottomAnchor constant:-12]
    ]];
    self.appearances.selectedSegment = [NSUserDefaults.standardUserDefaults integerForKey:@"appearance"];
    [self changeAppearance:nil];
    self.scenarios.selectedSegment = [NSUserDefaults.standardUserDefaults integerForKey:@"scenario"];
    [self changeScenario:nil];
    [self.window center];
    [self.window makeKeyAndOrderFront:nil];
    [NSApp activateIgnoringOtherApps:YES];
}

- (void)changeAppearance:(id)sender {
    (void)sender;
    NSInteger selection = self.appearances.selectedSegment;
    [NSUserDefaults.standardUserDefaults setInteger:selection forKey:@"appearance"];
    NSArray<NSAppearanceName> *names = @[NSAppearanceNameAqua, NSAppearanceNameDarkAqua, NSAppearanceNameAccessibilityHighContrastDarkAqua];
    self.window.appearance = selection > 0 ? [NSAppearance appearanceNamed:names[selection - 1]] : nil;
}

- (void)changeScenario:(id)sender {
    (void)sender;
    NSInteger scenario = self.scenarios.selectedSegment;
    [NSUserDefaults.standardUserDefaults setInteger:scenario forKey:@"scenario"];
    NSMutableDictionary *state = [@{@"version":@1, @"pid":@(getpid()), @"totalBytes":@500000000000,
        @"freeBytes":@60000000000, @"usedBytes":@25500000000, @"limitGB":@30,
        @"automatic":@YES, @"loginEnabled":@YES, @"automaticUpdates":@YES, @"canCheckForUpdates":@YES,
        @"libraryReady":@YES, @"prefetchReady":@YES, @"cleanupAllowed":@YES,
        @"lastCheckAt":@(NSDate.date.timeIntervalSince1970), @"message":@"Local Photos storage is within your target."} mutableCopy];
    switch (scenario) {
        case 1:
            state[@"totalBytes"] = @16000000000000;
            state[@"usedBytes"] = @12843900000000;
            state[@"limitGB"] = @15000;
            state[@"message"] = @"macOS could not finish checking the local photo library. Open Photos and let synchronization finish, then check again. If this continues, close Photos and restart your Mac before trying again.";
            state[@"loginMessage"] = @"Allow Photos Storage in System Settings → General → Login Items & Extensions to start monitoring when you sign in.";
            break;
        case 2:
            state = [@{@"version":@1, @"pid":@(getpid()), @"busy":@YES, @"message":@"Checking storage…"} mutableCopy];
            break;
        case 3:
            state[@"libraryReady"] = @NO;
            state[@"cleanupAllowed"] = @NO;
            state[@"automatic"] = @NO;
            break;
        case 4:
            state[@"cleanupAllowed"] = @NO;
            state[@"automatic"] = @NO;
            state[@"safetyMessage"] = @"Enable iCloud Photos and Optimize Mac Storage in Photos before continuing.";
            break;
        case 5:
            state[@"totalBytes"] = @10000000000;
            state[@"usedBytes"] = @8000000000;
            state[@"freeBytes"] = @1000000000;
            state[@"limitGB"] = @20;
            break;
        case 6:
            state[@"pid"] = @0;
            break;
        default: break;
    }
    NSData *data = [NSJSONSerialization dataWithJSONObject:state options:0 error:nil];
    [data writeToURL:[self.pane.fixtureRoot URLByAppendingPathComponent:@"state.json"] atomically:YES];
    [self.pane readState];
}
- (BOOL)applicationShouldTerminateAfterLastWindowClosed:(NSApplication *)sender { (void)sender; return YES; }
- (void)applicationWillTerminate:(NSNotification *)notification {
    (void)notification;
    [NSFileManager.defaultManager removeItemAtURL:self.pane.fixtureRoot error:nil];
}
@end

int main(void) {
    @autoreleasepool {
        NSApplication *app = NSApplication.sharedApplication;
        [app setActivationPolicy:NSApplicationActivationPolicyRegular];
        PreviewDelegate *delegate = [PreviewDelegate new];
        app.delegate = delegate;
        [app run];
    }
    return 0;
}
