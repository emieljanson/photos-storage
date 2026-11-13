#import <Foundation/Foundation.h>

static NSDictionary *StorageCommandPayload(NSString *identifier, NSString *action, NSNumber *value, NSNumber *enabled) {
    NSMutableDictionary *command = [@{@"version":@1, @"id":identifier,
        @"sentAt":@(NSDate.date.timeIntervalSince1970), @"action":action} mutableCopy];
    if (value) command[@"value"] = value;
    if (enabled) command[@"enabled"] = enabled.boolValue ? @YES : @NO;
    return command;
}
