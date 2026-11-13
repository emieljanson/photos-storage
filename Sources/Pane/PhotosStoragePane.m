#import <Cocoa/Cocoa.h>
#import <PreferencePanes/PreferencePanes.h>
#import <sys/stat.h>
#import <unistd.h>
#import "ControlCommand.h"

static NSString *const commandNotification = @"nl.emieljanson.FotoBudget.command";
static NSString *const agentIdentifier = @"nl.emieljanson.FotoBudget";

@interface PhotosStoragePane : NSPreferencePane <NSMenuDelegate>
@property(nonatomic, strong) NSPopUpButton *targetPicker;
@property(nonatomic, strong) NSTextField *photos;
@property(nonatomic, strong) NSTextField *status;
@property(nonatomic, strong) NSTextField *details;
@property(nonatomic, strong) NSTextField *checked;
@property(nonatomic, strong) NSTextField *loginMessage;
@property(nonatomic, strong) NSSwitch *automatic;
@property(nonatomic, strong) NSSwitch *login;
@property(nonatomic, strong) NSSwitch *updates;
@property(nonatomic, strong) NSButton *checkUpdates;
@property(nonatomic, strong) NSButton *access;
@property(nonatomic, strong) NSButton *recovery;
@property(nonatomic, strong) NSButton *refresh;
@property(nonatomic, strong) NSPanel *optionsPanel;
@property(nonatomic, strong) NSPanel *customPanel;
@property(nonatomic, strong) NSTextField *customInput;
@property(nonatomic, strong) NSTextField *customError;
@property(nonatomic, strong) NSTimer *poll;
@property(nonatomic, strong) NSDictionary *snapshot;
@property(nonatomic, copy) NSString *pendingLimitID;
@property NSTimeInterval pendingLimitAt;
@property double pendingLimit;
@property BOOL targetMenuTracking;
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

- (NSView *)spacer {
    NSView *spacer = [[NSView alloc] initWithFrame:NSZeroRect];
    [spacer setContentHuggingPriority:NSLayoutPriorityDefaultLow forOrientation:NSLayoutConstraintOrientationHorizontal];
    return spacer;
}

- (NSStackView *)row:(NSArray<NSView *> *)views {
    NSStackView *row = [NSStackView stackViewWithViews:views];
    row.orientation = NSUserInterfaceLayoutOrientationHorizontal;
    row.alignment = NSLayoutAttributeCenterY;
    row.spacing = 10;
    return row;
}

- (NSStackView *)setting:(NSString *)title control:(NSView *)control {
    NSStackView *row = [self row:@[[self label:title secondary:NO], [self spacer], control]];
    [row.heightAnchor constraintGreaterThanOrEqualToConstant:36].active = YES;
    return row;
}

- (NSSwitch *)miniSwitch:(NSString *)title action:(SEL)action {
    NSSwitch *control = [[NSSwitch alloc] initWithFrame:NSMakeRect(0, 0, 36, 16)];
    control.controlSize = NSControlSizeMini;
    control.target = self;
    control.action = action;
    control.accessibilityLabel = title;
    [control.widthAnchor constraintEqualToConstant:36].active = YES;
    [control.heightAnchor constraintEqualToConstant:16].active = YES;
    return control;
}

- (NSBox *)group:(NSArray<NSView *> *)rows {
    NSMutableArray<NSView *> *views = [NSMutableArray array];
    for (NSView *row in rows) {
        if (views.count) {
            NSBox *separator = [[NSBox alloc] initWithFrame:NSZeroRect];
            separator.boxType = NSBoxSeparator;
            [views addObject:separator];
        }
        [views addObject:row];
    }
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 0;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    NSBox *box = [[NSBox alloc] initWithFrame:NSZeroRect];
    box.boxType = NSBoxCustom;
    box.borderWidth = 0;
    box.cornerRadius = 10;
    box.contentViewMargins = NSZeroSize;
    box.fillColor = [NSColor colorWithName:@"PhotosStorageGroupedBackground" dynamicProvider:^NSColor *(NSAppearance *appearance) {
        NSString *match = [appearance bestMatchFromAppearancesWithNames:@[NSAppearanceNameAqua, NSAppearanceNameDarkAqua]];
        return [NSColor colorWithWhite:[match isEqual:NSAppearanceNameDarkAqua] ? 0.14 : 0.97 alpha:1];
    }];
    [box.contentView addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:box.contentView.leadingAnchor constant:10],
        [stack.trailingAnchor constraintEqualToAnchor:box.contentView.trailingAnchor constant:-10],
        [stack.topAnchor constraintEqualToAnchor:box.contentView.topAnchor],
        [stack.bottomAnchor constraintEqualToAnchor:box.contentView.bottomAnchor]
    ]];
    for (NSView *view in views) [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
    return box;
}

- (void)place:(NSArray<NSView *> *)views in:(NSView *)container margin:(CGFloat)margin {
    NSStackView *stack = [NSStackView stackViewWithViews:views];
    stack.orientation = NSUserInterfaceLayoutOrientationVertical;
    stack.alignment = NSLayoutAttributeLeading;
    stack.spacing = 12;
    stack.translatesAutoresizingMaskIntoConstraints = NO;
    [container addSubview:stack];
    [NSLayoutConstraint activateConstraints:@[
        [stack.leadingAnchor constraintEqualToAnchor:container.leadingAnchor constant:margin],
        [stack.trailingAnchor constraintEqualToAnchor:container.trailingAnchor constant:-margin],
        [stack.topAnchor constraintEqualToAnchor:container.topAnchor constant:margin],
        [stack.bottomAnchor constraintLessThanOrEqualToAnchor:container.bottomAnchor constant:-margin]
    ]];
    for (NSView *view in views) [view.widthAnchor constraintEqualToAnchor:stack.widthAnchor].active = YES;
}

- (NSButton *)button:(NSString *)title action:(SEL)action {
    NSButton *button = [NSButton buttonWithTitle:title target:self action:action];
    button.controlSize = NSControlSizeSmall;
    button.font = [NSFont systemFontOfSize:13];
    return button;
}

- (NSView *)loadMainView {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 500, 280)];
    view.autoresizingMask = NSViewWidthSizable;
    self.photos = [self label:@"Calculating…" secondary:YES];
    self.targetPicker = [[NSPopUpButton alloc] initWithFrame:NSZeroRect pullsDown:NO];
    self.targetPicker.font = [NSFont systemFontOfSize:13];
    self.targetPicker.bordered = NO;
    self.targetPicker.target = self;
    self.targetPicker.action = @selector(changeTarget:);
    self.targetPicker.accessibilityLabel = @"Storage target";
    self.targetPicker.toolTip = @"Choose an approximate local storage target for Photos.";
    self.targetPicker.enabled = NO;
    [self.targetPicker addItemWithTitle:@"Checking…"];
    self.automatic = [self miniSwitch:@"Optimize storage" action:@selector(changeAutomatic:)];
    self.automatic.enabled = NO;
    self.automatic.toolTip = @"Automatically check local Photos storage every five minutes.";
    NSBox *storage = [self group:@[
        [self setting:@"Photos on this Mac" control:self.photos],
        [self setting:@"Storage target" control:[self row:@[[self label:@"Around" secondary:YES], self.targetPicker]]],
        [self setting:@"Optimize storage" control:self.automatic]
    ]];
    self.status = [self label:@"Checking…" secondary:YES];
    self.status.font = [NSFont systemFontOfSize:12];
    self.access = [self button:@"Allow access…" action:@selector(grantAccess:)];
    self.access.hidden = YES;
    self.recovery = [self button:@"Open Photos…" action:@selector(openPhotos:)];
    self.recovery.hidden = YES;
    NSButton *options = [self button:@"Options…" action:@selector(showOptions:)];
    [self place:@[storage, self.status, self.access, self.recovery,
        [self row:@[[self spacer], options]]] in:view margin:20];
    self.mainView = view;
    self.initialKeyView = self.targetPicker;
    self.firstKeyView = self.targetPicker;
    self.lastKeyView = options;
    [self readState];
    return view;
}

- (void)presentPanel:(NSPanel *)panel {
    if (!self.mainView.window) return;
    panel.titleVisibility = NSWindowTitleHidden;
    panel.titlebarAppearsTransparent = YES;
    panel.backgroundColor = NSColor.textBackgroundColor;
    [self.mainView.window beginSheet:panel completionHandler:nil];
}

- (void)closePanel:(NSPanel *)panel {
    [panel.sheetParent endSheet:panel];
    [panel orderOut:nil];
}

- (void)closeOptions:(id)sender { (void)sender; [self closePanel:self.optionsPanel]; }

- (void)showOptions:(id)sender {
    (void)sender;
    if (self.optionsPanel.sheetParent) return;
    self.optionsPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 440, 340)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    self.optionsPanel.title = @"Photos Storage Options";
    self.login = [self miniSwitch:@"Start at login" action:@selector(changeLogin:)];
    self.updates = [self miniSwitch:@"Automatic updates" action:@selector(changeUpdates:)];
    self.checkUpdates = [self button:@"Check for Updates…" action:@selector(checkForUpdates:)];
    self.checked = [self label:@"Checking…" secondary:YES];
    NSBox *settings = [self group:@[
        [self setting:@"Start at login" control:self.login],
        [self setting:@"Automatic updates" control:self.updates],
        [self setting:@"Photos Storage" control:self.checkUpdates],
        [self setting:@"Last checked" control:self.checked]
    ]];
    self.loginMessage = [self label:@"" secondary:YES];
    self.loginMessage.hidden = YES;
    self.details = [self label:@"" secondary:YES];
    self.details.font = [NSFont systemFontOfSize:12];
    NSTextField *explanation = [self label:@"Checks every five minutes, even with System Settings closed. Only removable local copies are freed. Your photo library is never deleted." secondary:YES];
    explanation.font = [NSFont systemFontOfSize:12];
    self.refresh = [self button:@"Check Now" action:@selector(checkNow:)];
    NSButton *open = [self button:@"Open Photos" action:@selector(openPhotos:)];
    NSButton *done = [self button:@"Done" action:@selector(closeOptions:)];
    done.keyEquivalent = @"\r";
    [self place:@[settings, self.loginMessage, self.details, explanation,
        [self row:@[open, self.refresh, [self spacer], done]]]
        in:self.optionsPanel.contentView margin:20];
    [self readState];
    [self presentPanel:self.optionsPanel];
}

- (void)showCustomTarget {
    self.customPanel = [[NSPanel alloc] initWithContentRect:NSMakeRect(0, 0, 360, 190)
        styleMask:NSWindowStyleMaskTitled backing:NSBackingStoreBuffered defer:NO];
    self.customPanel.title = @"Storage Target";
    NSTextField *title = [self label:@"Storage target" secondary:NO];
    title.font = [NSFont systemFontOfSize:13 weight:NSFontWeightSemibold];
    self.customInput = [[NSTextField alloc] initWithFrame:NSZeroRect];
    self.customInput.stringValue = [NSString stringWithFormat:@"%.0f", [self.snapshot[@"limitGB"] doubleValue]];
    self.customInput.accessibilityLabel = @"Custom storage target in gigabytes";
    self.customInput.target = self;
    self.customInput.action = @selector(applyCustomTarget:);
    [self.customInput.widthAnchor constraintEqualToConstant:80].active = YES;
    self.customError = [self label:@"" secondary:YES];
    self.customError.hidden = YES;
    double maximum = floor([self.snapshot[@"totalBytes"] doubleValue] / 1e9);
    NSTextField *hint = [self label:[NSString stringWithFormat:@"Choose a whole number from 20 to %.0f GB.", maximum] secondary:YES];
    hint.font = [NSFont systemFontOfSize:12];
    NSButton *cancel = [self button:@"Cancel" action:@selector(cancelCustomTarget:)];
    cancel.keyEquivalent = @"\033";
    NSButton *done = [self button:@"Done" action:@selector(applyCustomTarget:)];
    done.keyEquivalent = @"\r";
    [self place:@[title, [self row:@[self.customInput, [self label:@"GB" secondary:NO], [self spacer]]],
        hint, self.customError, [self row:@[[self spacer], cancel, done]]]
        in:self.customPanel.contentView margin:20];
    [self presentPanel:self.customPanel];
    [self.customPanel makeFirstResponder:self.customInput];
    [self.customInput selectText:nil];
}

- (void)cancelCustomTarget:(id)sender {
    (void)sender;
    [self closePanel:self.customPanel];
    [self readState];
}

- (void)applyCustomTarget:(id)sender {
    (void)sender;
    NSString *text = [self.customInput.stringValue stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    NSScanner *scanner = [NSScanner scannerWithString:text];
    scanner.locale = NSLocale.currentLocale;
    double value = 0;
    double maximum = floor([self.snapshot[@"totalBytes"] doubleValue] / 1e9);
    if (![scanner scanDouble:&value] || !scanner.isAtEnd || !isfinite(value) || value < 20 || value > maximum || floor(value) != value) {
        self.customError.stringValue = [NSString stringWithFormat:@"Enter a whole number between 20 and %.0f.", maximum];
        self.customError.hidden = NO;
        return;
    }
    [self requestTarget:value];
    [self closePanel:self.customPanel];
}

- (void)menuWillOpen:(NSMenu *)menu { if (menu == self.targetPicker.menu) self.targetMenuTracking = YES; }
- (void)menuDidClose:(NSMenu *)menu { if (menu == self.targetPicker.menu) self.targetMenuTracking = NO; }

- (void)updateTargetMenu:(double)value capacity:(double)capacity {
    if (self.targetMenuTracking || self.customPanel.sheetParent) return;
    NSMutableSet<NSNumber *> *values = [NSMutableSet setWithArray:@[@20, @30, @50, @75, @100, @150, @200]];
    if (value >= 20) [values addObject:@(value)];
    [self.targetPicker removeAllItems];
    for (NSNumber *choice in [[values allObjects] sortedArrayUsingSelector:@selector(compare:)]) {
        if (choice.doubleValue > capacity) continue;
        [self.targetPicker addItemWithTitle:[NSString stringWithFormat:@"%.0f GB", choice.doubleValue]];
        self.targetPicker.lastItem.representedObject = choice;
        if (fabs(choice.doubleValue - value) < 0.001) [self.targetPicker selectItem:self.targetPicker.lastItem];
    }
    [self.targetPicker.menu addItem:NSMenuItem.separatorItem];
    [self.targetPicker addItemWithTitle:@"Custom…"];
    self.targetPicker.lastItem.tag = -1;
    self.targetPicker.menu.delegate = self;
}

- (void)ensureAgent {
    if ([NSRunningApplication runningApplicationsWithBundleIdentifier:agentIdentifier].count) return;
    NSURL *app = nil;
    for (NSString *path in @[@"/Applications/Photos Storage.app",
        [NSHomeDirectory() stringByAppendingPathComponent:@"Applications/Photos Storage.app"]]) {
        NSBundle *bundle = [NSBundle bundleWithPath:path];
        if ([bundle.bundleIdentifier isEqual:agentIdentifier] &&
            [[bundle objectForInfoDictionaryKey:@"CFBundleExecutable"] isEqual:@"PhotosStorage"]) {
            app = bundle.bundleURL;
            break;
        }
    }
    if (!app) {
        self.status.stringValue = @"Move Photos Storage to Applications, then reopen this pane.";
        self.status.hidden = NO;
        return;
    }
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

- (void)requestTarget:(double)value {
    self.pendingLimit = value;
    self.pendingLimitAt = NSDate.date.timeIntervalSince1970;
    self.pendingLimitID = [self send:@"setLimit" value:@(value) enabled:nil];
}

- (void)changeTarget:(id)sender {
    (void)sender;
    if (self.targetPicker.selectedItem.tag == -1) [self showCustomTarget];
    else [self requestTarget:[self.targetPicker.selectedItem.representedObject doubleValue]];
}
- (void)changeAutomatic:(id)sender { (void)sender; [self send:@"setAutomatic" value:nil enabled:@(self.automatic.state == NSControlStateValueOn)]; }
- (void)changeLogin:(id)sender { (void)sender; [self send:@"setLogin" value:nil enabled:@(self.login.state == NSControlStateValueOn)]; }
- (void)changeUpdates:(id)sender { (void)sender; [self send:@"setUpdates" value:nil enabled:@(self.updates.state == NSControlStateValueOn)]; }
- (void)checkForUpdates:(id)sender { (void)sender; [self send:@"checkForUpdates" value:nil enabled:nil]; }
- (void)checkNow:(id)sender { (void)sender; [self send:@"refresh" value:nil enabled:nil]; }
- (void)openPhotos:(id)sender { (void)sender; [self send:@"openPhotos" value:nil enabled:nil]; }
- (void)grantAccess:(id)sender {
    (void)sender;
    [self send:@"showSetup" value:nil enabled:nil];
}

- (NSString *)summaryForState:(NSDictionary *)state alive:(BOOL)alive {
    if (!alive) return @"Monitoring is not running. Reopen this pane to start it.";
    if ([state[@"libraryReady"] isEqual:@NO] || [state[@"prefetchReady"] isEqual:@NO]) return @"Allow access to continue.";
    if (state[@"safetyMessage"]) return @"Check iCloud Photos and Optimize Mac Storage in Photos.";
    NSString *message = state[@"message"] ?: @"";
    if ([state[@"busy"] boolValue]) return [message containsString:@"freeing"] ? @"Optimizing…" : @"Checking…";
    if ([message containsString:@"not responding"]) return @"Waiting for macOS. Will try again.";
    if (![state[@"automatic"] boolValue]) return @"Automatic optimization is off.";
    return @"";
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
    BOOL known = total > 0;
    self.targetPicker.enabled = allowed && known;
    self.automatic.enabled = allowed || [state[@"automatic"] boolValue];
    self.automatic.state = [state[@"automatic"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.login.state = [state[@"loginEnabled"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.updates.state = [state[@"automaticUpdates"] boolValue] ? NSControlStateValueOn : NSControlStateValueOff;
    self.updates.enabled = alive && state[@"automaticUpdates"] != nil;
    self.checkUpdates.enabled = alive && [state[@"canCheckForUpdates"] boolValue];
    self.loginMessage.stringValue = state[@"loginMessage"] ?: @"";
    self.loginMessage.hidden = !self.loginMessage.stringValue.length;
    self.status.stringValue = [self summaryForState:state alive:alive];
    self.status.hidden = !self.status.stringValue.length;
    self.status.toolTip = state[@"message"];
    self.details.stringValue = state[@"message"] ?: @"";
    self.refresh.enabled = alive && ![state[@"busy"] boolValue];
    BOOL needsLibrary = [state[@"libraryReady"] isEqual:@NO];
    BOOL needsPrefetch = [state[@"prefetchReady"] isEqual:@NO];
    self.access.hidden = !needsLibrary && !needsPrefetch;
    self.access.enabled = ![state[@"busy"] boolValue];
    self.access.title = needsLibrary ? @"Allow Photos Library…" : @"Allow Settings Access…";
    self.recovery.hidden = !state[@"safetyMessage"] || needsLibrary || needsPrefetch;
    NSNumber *checkTime = state[@"lastCheckAt"];
    if (checkTime) {
        NSDateFormatter *formatter = [[NSDateFormatter alloc] init];
        formatter.timeStyle = NSDateFormatterShortStyle;
        self.checked.stringValue = [formatter stringFromDate:[NSDate dateWithTimeIntervalSince1970:checkTime.doubleValue]];
    }
    if (!known) return;
    self.photos.stringValue = [NSString stringWithFormat:@"%.1f GB", [state[@"usedBytes"] doubleValue] / 1e9];
    BOOL pending = self.pendingLimitID && ![self.pendingLimitID isEqual:state[@"lastCommandID"]] && NSDate.date.timeIntervalSince1970 - self.pendingLimitAt < 10;
    [self updateTargetMenu:pending ? self.pendingLimit : [state[@"limitGB"] doubleValue] capacity:total / 1e9];
}
@end
