//
//  ASCBundleIDTools.m
//  AppStoreConnectMCP
//

#import "ASCBundleIDTools.h"
#import "ASCClient.h"

@implementation ASCBundleIDTools

+ (nullable NSString *)createBundleId:(NSDictionary *)args error:(NSError **)error {
    NSString *identifier = args[@"identifier"];
    NSString *name       = args[@"name"];
    NSString *platform   = args[@"platform"];
    if (!identifier.length || !name.length || !platform.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCBundleIDTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"identifier, name, and platform are required"}];
        return nil;
    }

    NSDictionary *body = @{
        @"data": @{
            @"type": @"bundleIds",
            @"attributes": @{@"identifier": identifier, @"name": name, @"platform": platform}
        }
    };

    NSDictionary *resp = [[ASCClient shared] POST:@"/bundleIds" body:body error:error];
    if (!resp) return nil;

    NSDictionary *data = resp[@"data"];
    return [NSString stringWithFormat:@"✓ Created bundle ID %@ (ID: %@).", identifier, data[@"id"] ?: @"?"];
}

+ (nullable NSString *)listBundleIds:(NSDictionary *)args error:(NSError **)error {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (args[@"limit"])             params[@"limit"]               = args[@"limit"];
    if (args[@"sort"])              params[@"sort"]                = args[@"sort"];
    if (args[@"filter_identifier"]) params[@"filter[identifier]"]  = args[@"filter_identifier"];
    if (args[@"filter_name"])       params[@"filter[name]"]        = args[@"filter_name"];

    NSDictionary *resp = [[ASCClient shared] GET:@"/bundleIds" params:params error:error];
    if (!resp) return nil;

    NSArray *data = resp[@"data"];
    if (![data isKindOfClass:[NSArray class]] || !data.count) return @"No bundle IDs found.";

    NSMutableString *out = [NSMutableString stringWithFormat:@"Found %lu bundle ID(s):\n\n", (unsigned long)data.count];
    for (NSDictionary *b in data) {
        NSDictionary *attrs = b[@"attributes"] ?: @{};
        [out appendFormat:@"• %@ — %@ (%@) (ID: %@)\n",
         attrs[@"identifier"] ?: @"?", attrs[@"name"] ?: @"", attrs[@"platform"] ?: @"", b[@"id"] ?: @"?"];
    }
    return out;
}

+ (nullable NSString *)getBundleIdInfo:(NSDictionary *)args error:(NSError **)error {
    NSString *bundleIdId = args[@"bundle_id_id"];
    if (!bundleIdId.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCBundleIDTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"bundle_id_id is required"}];
        return nil;
    }

    NSString *path = [NSString stringWithFormat:@"/bundleIds/%@", bundleIdId];
    NSDictionary *resp = [[ASCClient shared] GET:path params:nil error:error];
    if (!resp) return nil;

    NSDictionary *attrs = resp[@"data"][@"attributes"] ?: @{};
    return [NSString stringWithFormat:@"Bundle ID: %@\nName: %@\nPlatform: %@\nSeed ID: %@\nID: %@",
            attrs[@"identifier"] ?: @"?", attrs[@"name"] ?: @"",
            attrs[@"platform"]   ?: @"?", attrs[@"seedId"] ?: @"?",
            resp[@"data"][@"id"] ?: @"?"];
}

+ (nullable NSString *)enableCapability:(NSDictionary *)args error:(NSError **)error {
    NSString *bundleIdId    = args[@"bundle_id_id"];
    NSString *capabilityType = args[@"capability_type"];
    if (!bundleIdId.length || !capabilityType.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCBundleIDTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"bundle_id_id and capability_type are required"}];
        return nil;
    }

    NSDictionary *body = @{
        @"data": @{
            @"type": @"bundleIdCapabilities",
            @"attributes": @{@"capabilityType": capabilityType, @"settings": @[]},
            @"relationships": @{
                @"bundleId": @{@"data": @{@"id": bundleIdId, @"type": @"bundleIds"}}
            }
        }
    };

    NSDictionary *resp = [[ASCClient shared] POST:@"/bundleIdCapabilities" body:body error:error];
    if (!resp) return nil;

    return [NSString stringWithFormat:@"✓ Enabled %@ for bundle ID %@.", capabilityType, bundleIdId];
}

+ (nullable NSString *)disableCapability:(NSDictionary *)args error:(NSError **)error {
    NSString *capabilityId = args[@"capability_id"];
    if (!capabilityId.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCBundleIDTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"capability_id is required"}];
        return nil;
    }

    NSString *path = [NSString stringWithFormat:@"/bundleIdCapabilities/%@", capabilityId];
    BOOL ok = [[ASCClient shared] DELETE:path body:nil error:error];
    if (!ok) return nil;
    return [NSString stringWithFormat:@"✓ Disabled capability %@.", capabilityId];
}

@end
