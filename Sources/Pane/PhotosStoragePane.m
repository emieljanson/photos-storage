#import <Cocoa/Cocoa.h>
#import <PreferencePanes/PreferencePanes.h>
#import <sys/stat.h>
#import <unistd.h>
#import "ControlCommand.h"

static NSString *const commandNotification = @"nl.emieljanson.FotoBudget.command";
static NSString *const agentIdentifier = @"nl.emieljanson.FotoBudget";

@interface StorageSliderCell : NSSliderCell
@property double photosFraction;
@property double diskFraction;
@end

@implementation StorageSliderCell
- (void)drawBarInside:(NSRect)rect flipped:(BOOL)flipped {
    (void)flipped;
    CGFloat inset = self.knobThickness / 2;
    NSRect track = NSMakeRect(rect.origin.x + inset, NSMidY(rect) - 3, rect.size.width - 2 * inset, 6);
    if (track.size.width <= 0) return;
    CGFloat opacity = self.enabled ? 1 : 0.45;
    [NSGraphicsContext saveGraphicsState];
    [[NSBezierPath bezierPathWithRoundedRect:track xRadius:3 yRadius:3] addClip];
    [[NSColor.separatorColor colorWithAlphaComponent:0.15 * opacity] setFill];
    NSRectFill(track);
    [[NSColor.labelColor colorWithAlphaComponent:0.13 * opacity] setFill];
    NSRect fill = track;
    fill.size.width *= fmin(1, fmax(0, self.diskFraction));
    NSRectFill(fill);
    [[NSColor.controlAccentColor colorWithAlphaComponent:opacity] setFill];
    fill.size.width = track.size.width * fmin(1, fmax(0, self.photosFraction));
    NSRectFill(fill);
    [NSGraphicsContext restoreGraphicsState];
}
@end

@interface StorageSlider : NSSlider
@property BOOL trackingBudget;
@end

@implementation StorageSlider
- (void)mouseDown:(NSEvent *)event {
    if (!self.enabled) return;
    self.trackingBudget = YES;
    [super mouseDown:event];
    self.trackingBudget = NO;
    [self sendAction:self.action to:self.target];
}
- (void)keyDown:(NSEvent *)event {
    if (!self.enabled || (event.modifierFlags & (NSEventModifierFlagCommand | NSEventModifierFlagControl))) {
        [super keyDown:event];
        return;
    }
    double step = event.modifierFlags & NSEventModifierFlagOption ? 10 : 1;
    switch (event.keyCode) {
        case 123: case 125: self.doubleValue = fmax(self.minValue, self.doubleValue - step); break;
        case 124: case 126: self.doubleValue = fmin(self.maxValue, self.doubleValue + step); break;
        case 115: self.doubleValue = self.minValue; break;
        case 119: self.doubleValue = self.maxValue; break;
        default: [super keyDown:event]; return;
    }
    [self sendAction:self.action to:self.target];
}
@end

@interface PhotosStoragePane : NSPreferencePane
@property(nonatomic, strong) StorageSlider *slider;
@property(nonatomic, strong) NSTextField *photos;
@property(nonatomic, strong) NSTextField *target;
@property(nonatomic, strong) NSTextField *capacity;
@property(nonatomic, strong) NSTextField *disk;
@property(nonatomic, strong) NSTextField *status;
@property(nonatomic, strong) NSTextField *checked;
@property(nonatomic, strong) NSTextField *loginMessage;
@property(nonatomic, strong) NSSwitch *automatic;
@property(nonatomic, strong) NSSwitch *login;
@property(nonatomic, strong) NSButton *access;
@property(nonatomic, strong) NSButton *refresh;
@property(nonatomic, strong) NSTimer *poll;
@property(nonatomic, strong) NSDictionary *snapshot;
@property(nonatomic, copy) NSString *pendingLimitID;
@property NSTimeInterval pendingLimitAt;
@property double pendingLimit;
@end

@implementation PhotosStoragePane

- (NSURL *)controlRoot {
    return [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Library/Application Support/FotoBudget/control"] isDirectory:YES];
}

- (NSTextField *)label:(NSString *)value secondary:(BOOL)secondary {
    NSTextField *label = [NSTextField wrappingLabelWithString:value];
    label.font = [NSFont systemFontOfSize:13];
    if (secondary) label.textColor = NSColor.secondaryLabelColor;
    return label;
}

- (NSStackView *)row:(NSArray<NSView *> *)views {
    NSStackView *row = [NSStackView stackViewWithViews:views];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 12;
    return row;
}

- (NSView *)spacer {
    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return spacer;
}

- (NSBox *)group:(NSArray<NSView *> *)views {
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    NSBox *box = [[NSBox alloc] initWithFrame:NSZeroRect];
    box.boxType = NSBoxCustom;
    box.borderWidth = 0;
    box.cornerRadius = 10;
    box.fillColor = NSColor.controlBackgroundColor;
    [box.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:box.contentView.leadingAnchor constant:16],
        [stack.trailingAnchor constraintEqualToAnchor:box.contentView.trailingAnchor constant:-16],
        [stack.topAnchor constraintEqualToAnchor:box.contentView.topAnchor constant:16],
        [stack.bottomAnchor constraintEqualToAnchor:box.contentView.bottomAnchor constant:-16]
    ]];
    for (NSView *view in views) [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    return box;
}

- (NSView *)loadMainView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 540, 570)];
    self.photos = [self label:@"Photos" secondary:NO];
    self.photos.font = [NSFont systemFontOfSize:15 weight:NSFontWeightMedium];
    self.target = [self label:@"Checking…" secondary:NO];
    self.target.alignment = NSTextAlignmentRight;
    self.slider = [[StorageSlider alloc] initWithFrame:NSZeroRect];
    self.slider.cell = [[StorageSliderCell alloc] init];
    self.slider.minValue = 0;
    self.slider.maxValue = 1;
    self.slider.enabled = NO;
    self.slider.continuous = YES;
    self.slider.target = self;
    self.slider.action = @selector(changeLimit:);
    self.slider.accessibilityLabel = @"Photos storage target in gigabytes";
    self.slider.toolTip = @"Blue shows Photos storage. Gray shows total disk usage. Drag the handle to choose a target. Changes apply after release.";
    self.capacity = [self label:@"…" secondary:YES];
    self.disk = [self label:@"Checking Mac storage…" secondary:YES];
    self.automatic = [[NSSwitch alloc] initWithFrame:NSZeroRect];
    self.automatic.target = self;
    self.automatic.action = @selector(changeAutomatic:);
    self.automatic.accessibilityLabel = @"Automatic monitoring";
    self.automatic.enabled = NO;
    NSStackView *storage = [NSStackView stackViewWithViews:@[
        [self row:@[self.photos, [self spacer], self.target]], self.slider,
        [self row:@[[self label:@"0 GB" secondary:YES], [self spacer], self.capacity]], self.disk
    ]];
    storage.orientation = NSUserInterfaceLayoutOrientationVertical;
    storage.alignment = NSLayoutAttributeLeading;
    storage.spacing = 8;
    for (NSView *child in storage.arrangedSubviews) [child.widthAnchor constraintEqualToAnchor:storage.widthAnchor].active = YES;
    NSTextField *monitoringHint = [self label:@"Checks every five minutes, even when System Settings is closed." secondary:YES];
    monitoringHint.font = [NSFont systemFontOfSize:12];
    NSBox *storageGroup = [self group:@[storage,
        [self row:@[[self label:@"Automatic monitoring" secondary:NO], [self spacer], self.automatic]], monitoringHint]];

    self.login = [[NSSwitch alloc] initWithFrame:NSZeroRect];
    self.login.target = self;
    self.login.action = @selector(changeLogin:);
    self.login.accessibilityLabel = @"Start at login";
    self.loginMessage = [self label:@"" secondary:YES];
    self.loginMessage.hidden = YES;
    NSBox *loginGroup = [self group:@[
        [self row:@[[self label:@"Start at login" secondary:NO], [self spacer], self.login]], self.loginMessage]];
    self.status = [self label:@"Starting background monitoring…" secondary:YES];
    self.checked = [self label:@"" secondary:YES];
    self.checked.font = [NSFont systemFontOfSize:11];
    self.access = [NSButton buttonWithTitle:@"Allow access…" target:self action:@selector(grantAccess:)];
    self.access.hidden = YES;
    self.refresh = [NSButton buttonWithTitle:@"Check now" target:self action:@selector(checkNow:)];
    NSButton *photos = [NSButton buttonWithTitle:@"Open Photos" target:self action:@selector(openPhotos:)];
    NSTextField *footer = [self label:@"The target is not a hard limit. iCloud Photos and Optimize Mac Storage must be on. Only macOS chooses which local copies can be freed; items in your Photos library are not deleted." secondary:YES];
    footer.font = [NSFont systemFontOfSize:12];
    NSStackView *stack = [NSStackView stackViewWithViews:@[storageGroup, loginGroup, self.status,
        self.checked, self.access, [self row:@[photos, [self spacer], self.refresh]], footer]];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 16;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [view addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:view.leadingAnchor constant:24],
        [stack.trailingAnchor constraintEqualToAnchor:view.trailingAnchor constant:-24],
        [stack.topAnchor constraintEqualToAnchor:view.topAnchor constant:24],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:view.bottomAnchor constant:-24]
    ]];
    for (NSView *child in stack.arrangedSubviews) [child.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    self.mainView = view;
    self.initialKeyView = self.slider;
    self.firstKeyView = self.slider;
    self.lastKeyView = self.refresh;
    [self readState];
    return view;
}

- (void)ensureAgent {
    if ([NSRunningApplication runningApplicationsWithBundleIdentifier:agentIdentifier].count) return;
    NSURL *app = [NSURL fileURLWithPath:[NSHomeDirectory() stringByAppendingPathComponent:@"Applications/Photos Storage.app"]];
    NSWorkspaceOpenConfiguration *configuration = [NSWorkspaceOpenConfiguration configuration];
    configuration.activates = NO;
    configuration.arguments = @[@"--background"];
    [NSWorkspace.sharedWorkspace openApplicationAtURL:app configuration:configuration completionHandler:^(NSRunningApplication *application, NSError *error) {
        (void)application;
        if (error) dispatch_async(dispatch_get_main_queue(), ^{
            self.status.stringValue = @"Unable to start monitoring. Reinstall Photos Storage and open this pane again.";
        });
    }];
}

- (void)didSelect {
    [super didSelect];
    [self ensureAgent];
    [self readState];
    self.poll = [NSTimer scheduledTimerWithTimeInterval:3 target:self selector:@selector(readState) userInfo:nil repeats:YES];
}

- (void)willUnselect {
    [self.poll invalidate];
    self.poll = nil;
    [super willUnselect];
}

- (NSString *)send:(NSString *)action value:(NSNumber *)value enabled:(NSNumber *)enabled {
    NSURL *requests = [[self controlRoot] URLByAppendingPathComponent:@"requests" isDirectory:YES];
    NSError *error = nil;
    if (![NSFileManager.defaultManager createDirectoryAtURL:requests withIntermediateDirectories:YES attributes:@{NSFilePosixPermissions:@0700} error:&error]) {
        self.status.stringValue = @"Unable to save the change. Check free disk space and try again.";
        return nil;
    }
    for (NSURL *directory in @[[self controlRoot], requests]) {
        struct stat info;
        if (lstat(directory.fileSystemRepresentation, &info) || !S_ISDIR(info.st_mode) || info.st_uid != getuid() || chmod(directory.fileSystemRepresentation, 0700)) {
            self.status.stringValue = @"The monitoring settings folder could not be verified.";
            return nil;
        }
    }
    NSString *identifier = NSUUID.UUID.UUIDString;
    NSDictionary *command = StorageCommandPayload(identifier, action, value, enabled);
    NSData *data = [NSJSONSerialization dataWithJSONObject:command options:0 error:&error];
    NSURL *file = [requests URLByAppendingPathComponent:[identifier stringByAppendingPathExtension:@"json"]];
    if (!data || ![data writeToURL:file options:NSDataWritingAtomic error:&error] || chmod(file.fileSystemRepresentation, 0600)) {
        self.status.stringValue = @"The change could not be saved. Try again.";
        return nil;
    }
    [self ensureAgent];
    [NSDistributedNotificationCenter.defaultCenter postNotificationName:commandNotification object:nil userInfo:nil deliverImmediately:YES];
    return identifier;
}

- (void)changeLimit:(id)sender {
    (void)sender;
    double value = self.slider.doubleValue >= self.slider.maxValue - 0.5 ? self.slider.maxValue : round(self.slider.doubleValue);
    self.target.stringValue = [NSString stringWithFormat:@"Target %.0f GB", value];
    if (self.slider.trackingBudget) return;
    self.pendingLimit = value;
    self.pendingLimitAt = NSDate.date.timeIntervalSince1970;
    self.pendingLimitID = [self send:@"setLimit" value:@(value) enabled:nil];
}
- (void)changeAutomatic:(id)sender { (void)sender; [self send:@"setAutomatic" value:nil enabled:@(self.automatic.state == NSControlStateValueOn)]; }
- (void)changeLogin:(id)sender { (void)sender; [self send:@"setLogin" value:nil enabled:@(self.login.state == NSControlStateValueOn)]; }
- (void)checkNow:(id)sender { (void)sender; [self send:@"refresh" value:nil enabled:nil]; }
- (void)openPhotos:(id)sender { (void)sender; [self send:@"openPhotos" value:nil enabled:nil]; }
- (void)grantAccess:(id)sender {
    (void)sender;
    NSString *action = [self.snapshot[@"libraryReady"] isEqual:@NO] ? @"grantLibrary" : @"grantPrefetch";
    [self send:action value:nil enabled:nil];
}

- (void)readState {
    NSURL *file = [[self controlRoot] URLByAppendingPathComponent:@"state.json"];
    NSDictionary *attributes = [NSFileManager.defaultManager attributesOfItemAtPath:file.path error:nil];
    if ([attributes fileSize] > 65536) return;
    NSData *data = [NSData dataWithContentsOfURL:file];
    NSDictionary *state = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
    if (![state isKindOfClass:NSDictionary.class] || ![state[@"version"] isEqual:@1]) return;
    self.snapshot = state;
    BOOL alive = kill([state[@"pid"] intValue], 0) == 0;
    BOOL allowed = alive && [state[@"cleanupAllowed"] boolValue];
    double total = [state[@"totalBytes"] doubleValue];
    double used = [state[@"usedBytes"] doubleValue];
    double free = [state[@"freeBytes"] doubleValue];
    BOOL known = total > 0 && free <= total;
    self.slider.enabled = allowed && known;
    self.automatic.enabled = allowed || [state[@"automatic"] boolValue];
    self.automatic.state = [state[@"automatic"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.login.state = [state[@"loginEnabled"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.loginMessage.stringValue = state[@"loginMessage"] ?: @"";
    self.loginMessage.hidden = !self.loginMessage.stringValue.length;
    self.status.stringValue = alive ? state[@"message"] : @"Monitoring is not running. Reopen this pane to start it again.";
    self.refresh.enabled = alive && ![state[@"busy"] boolValue];
    BOOL needsLibrary = [state[@"libraryReady"] isEqual:@NO];
    BOOL needsPrefetch = [state[@"prefetchReady"] isEqual:@NO];
    self.access.hidden = !needsLibrary && !needsPrefetch;
    self.access.enabled = ![state[@"busy"] boolValue];
    self.access.title = needsLibrary ? @"Allow Photos library access…" : @"Allow prefetch settings access…";
    NSNumber *checkTime = state[@"lastCheckAt"];
    if (checkTime) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.timeStyle = NSDateFormatterShortStyle;
        self.checked.stringValue = [@"Last checked " stringByAppendingString:[formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:checkTime.doubleValue]]];
    }
    if (!known) return;
    self.photos.stringValue = [NSString stringWithFormat:@"Photos %.0f GB", used / 1e9];
    self.capacity.stringValue = [NSString stringWithFormat:@"%.0f GB", total / 1e9];
    self.disk.stringValue = [NSString stringWithFormat:@"Mac storage: %.0f GB used · %.0f GB free", (total - free) / 1e9, free / 1e9];
    StorageSliderCell *cell = (StorageSliderCell *)self.slider.cell;
    cell.photosFraction = used / total;
    cell.diskFraction = (total - free) / total;
    self.slider.needsDisplay = YES;
    self.slider.accessibilityHelp = [NSString stringWithFormat:@"Photos uses %.1f GB. Disk capacity %.0f GB. This target is not a hard limit.", used / 1e9, total / 1e9];
    BOOL pending = self.pendingLimitID && ![self.pendingLimitID isEqual:state[@"lastCommandID"]] && NSDate.date.timeIntervalSince1970 - self.pendingLimitAt < 10;
    if (!self.slider.trackingBudget) {
        self.slider.maxValue = total / 1e9;
        self.slider.doubleValue = pending ? self.pendingLimit : [state[@"limitGB"] doubleValue];
        self.target.stringValue = [NSString stringWithFormat:@"Target %.0f GB", self.slider.doubleValue];
    }
}
@end
