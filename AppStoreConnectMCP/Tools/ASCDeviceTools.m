//
//  ASCDeviceTools.m
//  AppStoreConnectMCP
//

#import "ASCDeviceTools.h"
#import "ASCClient.h"

@implementation ASCDeviceTools

+ (nullable NSString *)listDevices:(NSDictionary *)args error:(NSError **)error {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (args[@"limit"])    params[@"limit"]            = args[@"limit"];
    if (args[@"sort"])     params[@"sort"]             = args[@"sort"];
    if (args[@"platform"]) params[@"filter[platform]"] = args[@"platform"];
    if (args[@"status"])   params[@"filter[status]"]   = args[@"status"];

    NSDictionary *resp = [[ASCClient shared] GET:@"/devices" params:params error:error];
    if (!resp) return nil;

    NSArray *data = resp[@"data"];
    if (![data isKindOfClass:[NSArray class]] || !data.count) return @"No devices found.";

    NSMutableString *out = [NSMutableString stringWithFormat:@"Found %lu device(s):\n\n", (unsigned long)data.count];
    for (NSDictionary *d in data) {
        NSDictionary *attrs = d[@"attributes"] ?: @{};
        [out appendFormat:@"• %@ (%@)\n  UDID: %@\n  Platform: %@ | Class: %@ | Status: %@\n  Added: %@\n\n",
         attrs[@"name"]        ?: @"?",
         attrs[@"model"]       ?: @"",
         attrs[@"udid"]        ?: @"?",
         attrs[@"platform"]    ?: @"?",
         attrs[@"deviceClass"] ?: @"?",
         attrs[@"status"]      ?: @"?",
         attrs[@"addedDate"]   ?: @"?"];
    }
    return out;
}

@end
