#import "../Sources/Pane/ControlCommand.h"

int main(void) {
    @autoreleasepool {
        NSDictionary *command = StorageCommandPayload(NSUUID.UUID.UUIDString, @"setAutomatic", nil, @(1 == 1));
        NSData *data = [NSJSONSerialization dataWithJSONObject:command options:0 error:nil];
        fwrite(data.bytes, 1, data.length, stdout);
    }
    return 0;
}
