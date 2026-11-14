#import <Foundation/Foundation.h>
#import <objc/message.h>
#import <objc/runtime.h>

// Ask this Photos version what mode 0 means before interpreting library metadata.
static BOOL PhotoOptimizationModeRecognized(Class manager) {
    SEL selector=NSSelectorFromString(@"descriptionForPrefetchMode:");
    Method method=manager ? class_getClassMethod(manager,selector) : NULL;
    if (!method || strcmp(method_getTypeEncoding(method),"@24@0:8q16")) return NO;
    id description=((id (*)(id,SEL,int64_t))objc_msgSend)(manager,selector,0);
    return [description isKindOfClass:NSString.class] && [description isEqual:@"optimize"];
}
