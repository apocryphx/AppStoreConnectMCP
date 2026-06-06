//
//  ASCAppsTools.m
//  AppStoreConnectMCP
//

#import "ASCAppsTools.h"
#import "ASCClient.h"

@implementation ASCAppsTools

+ (nullable NSString *)listApps:(NSDictionary *)args error:(NSError **)error {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (args[@"limit"])     params[@"limit"]             = args[@"limit"];
    if (args[@"bundle_id"]) params[@"filter[bundleId]"]  = args[@"bundle_id"];

    NSDictionary *resp = [[ASCClient shared] GET:@"/apps" params:params error:error];
    if (!resp) return nil;

    NSArray *data = resp[@"data"];
    if (![data isKindOfClass:[NSArray class]] || !data.count) {
        return @"No apps found.";
    }

    NSMutableString *out = [NSMutableString stringWithFormat:@"Found %lu app(s):\n\n", (unsigned long)data.count];
    for (NSDictionary *app in data) {
        NSString *appId  = app[@"id"] ?: @"?";
        NSDictionary *attrs = app[@"attributes"] ?: @{};
        NSString *name   = attrs[@"name"] ?: @"(unnamed)";
        NSString *bundle = attrs[@"bundleId"] ?: @"";
        NSString *sku    = attrs[@"sku"] ?: @"";
        [out appendFormat:@"• %@ (ID: %@)\n  Bundle: %@\n  SKU: %@\n\n", name, appId, bundle, sku];
    }
    return out;
}

+ (nullable NSString *)getAppInfo:(NSDictionary *)args error:(NSError **)error {
    NSString *appId = args[@"app_id"];
    if (!appId.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCAppsTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"app_id is required"}];
        return nil;
    }

    NSString *path = [NSString stringWithFormat:@"/apps/%@", appId];
    NSDictionary *resp = [[ASCClient shared] GET:path params:nil error:error];
    if (!resp) return nil;

    NSDictionary *data  = resp[@"data"];
    NSDictionary *attrs = data[@"attributes"] ?: @{};

    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"App: %@\n", attrs[@"name"] ?: @"(unnamed)"];
    [out appendFormat:@"ID: %@\n", data[@"id"] ?: @"?"];
    [out appendFormat:@"Bundle ID: %@\n", attrs[@"bundleId"] ?: @""];
    [out appendFormat:@"SKU: %@\n", attrs[@"sku"] ?: @""];
    [out appendFormat:@"Primary Locale: %@\n", attrs[@"primaryLocale"] ?: @""];
    if (attrs[@"contentRightsDeclaration"]) {
        [out appendFormat:@"Content Rights: %@\n", attrs[@"contentRightsDeclaration"]];
    }
    return out;
}

@end
