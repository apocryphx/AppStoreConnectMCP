//
//  ASCLocalizationTools.m
//  AppStoreConnectMCP
//

#import "ASCLocalizationTools.h"
#import "ASCClient.h"

@implementation ASCLocalizationTools

+ (nullable NSString *)createVersion:(NSDictionary *)args error:(NSError **)error {
    NSString *appId   = args[@"app_id"];
    NSString *platform = args[@"platform"];
    NSString *version  = args[@"version_string"];
    if (!appId.length || !platform.length || !version.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCLocalizationTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"app_id, platform, and version_string are required"}];
        return nil;
    }

    NSMutableDictionary *attrs = [@{@"platform": platform, @"versionString": version} mutableCopy];
    if (args[@"release_type"]) attrs[@"releaseType"] = args[@"release_type"];
    if (args[@"copyright"])    attrs[@"copyright"]   = args[@"copyright"];

    NSMutableDictionary *rels = [@{
        @"app": @{@"data": @{@"id": appId, @"type": @"apps"}}
    } mutableCopy];
    if (args[@"build_id"]) {
        rels[@"build"] = @{@"data": @{@"id": args[@"build_id"], @"type": @"builds"}};
    }

    NSDictionary *body = @{
        @"data": @{@"type": @"appStoreVersions", @"attributes": attrs, @"relationships": rels}
    };

    NSDictionary *resp = [[ASCClient shared] POST:@"/appStoreVersions" body:body error:error];
    if (!resp) return nil;

    NSDictionary *data = resp[@"data"];
    return [NSString stringWithFormat:@"✓ Created version %@ for %@ (ID: %@).",
            version, platform, data[@"id"] ?: @"?"];
}

+ (nullable NSString *)listVersions:(NSDictionary *)args error:(NSError **)error {
    NSString *appId = args[@"app_id"];
    if (!appId.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCLocalizationTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"app_id is required"}];
        return nil;
    }

    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (args[@"limit"])    params[@"limit"]                 = args[@"limit"];
    if (args[@"platform"]) params[@"filter[platform]"]      = args[@"platform"];
    if (args[@"state"])    params[@"filter[appStoreState]"] = args[@"state"];

    // Use the relationship endpoint — GET /appStoreVersions (collection) returns 403.
    NSString *path = [NSString stringWithFormat:@"/apps/%@/appStoreVersions", appId];
    NSDictionary *resp = [[ASCClient shared] GET:path params:params error:error];
    if (!resp) return nil;

    NSArray *data = resp[@"data"];
    if (![data isKindOfClass:[NSArray class]] || !data.count) return @"No versions found.";

    NSMutableString *out = [NSMutableString stringWithFormat:@"Found %lu version(s):\n\n", (unsigned long)data.count];
    for (NSDictionary *v in data) {
        NSDictionary *attrs = v[@"attributes"] ?: @{};
        [out appendFormat:@"• v%@ — %@ — %@ (ID: %@)\n",
         attrs[@"versionString"] ?: @"?",
         attrs[@"platform"]      ?: @"?",
         attrs[@"appStoreState"] ?: @"?",
         v[@"id"] ?: @"?"];
    }
    return out;
}

+ (nullable NSString *)listLocalizations:(NSDictionary *)args error:(NSError **)error {
    NSString *versionId = args[@"version_id"];
    if (!versionId.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCLocalizationTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"version_id is required"}];
        return nil;
    }

    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (args[@"limit"]) params[@"limit"] = args[@"limit"];

    // Use the relationship endpoint — GET /appStoreVersionLocalizations (collection) may return 403.
    NSString *path = [NSString stringWithFormat:@"/appStoreVersions/%@/appStoreVersionLocalizations", versionId];
    NSDictionary *resp = [[ASCClient shared] GET:path params:params error:error];
    if (!resp) return nil;

    NSArray *data = resp[@"data"];
    if (![data isKindOfClass:[NSArray class]] || !data.count) return @"No localizations found.";

    NSMutableString *out = [NSMutableString stringWithFormat:@"Found %lu localization(s):\n\n", (unsigned long)data.count];
    for (NSDictionary *l in data) {
        NSDictionary *attrs = l[@"attributes"] ?: @{};
        NSString *kw = attrs[@"keywords"] ?: @"(none)";
        if ([kw length] > 80) kw = [[kw substringToIndex:80] stringByAppendingString:@"…"];
        [out appendFormat:@"• %@ (ID: %@)\n  Keywords: %@\n\n",
         attrs[@"locale"] ?: @"?", l[@"id"] ?: @"?", kw];
    }
    return out;
}

+ (nullable NSString *)getLocalization:(NSDictionary *)args error:(NSError **)error {
    NSString *locId = args[@"localization_id"];
    if (!locId.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCLocalizationTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"localization_id is required"}];
        return nil;
    }

    NSString *path = [NSString stringWithFormat:@"/appStoreVersionLocalizations/%@", locId];
    NSDictionary *resp = [[ASCClient shared] GET:path params:nil error:error];
    if (!resp) return nil;

    NSDictionary *attrs = resp[@"data"][@"attributes"] ?: @{};
    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"Locale: %@\n", attrs[@"locale"] ?: @"?"];
    [out appendFormat:@"Description: %@\n\n", attrs[@"description"] ?: @"(none)"];
    [out appendFormat:@"Keywords: %@\n", attrs[@"keywords"] ?: @"(none)"];
    [out appendFormat:@"What's New: %@\n", attrs[@"whatsNew"] ?: @"(none)"];
    if (attrs[@"promotionalText"]) [out appendFormat:@"Promotional Text: %@\n", attrs[@"promotionalText"]];
    if (attrs[@"marketingUrl"])    [out appendFormat:@"Marketing URL: %@\n",    attrs[@"marketingUrl"]];
    if (attrs[@"supportUrl"])      [out appendFormat:@"Support URL: %@\n",      attrs[@"supportUrl"]];
    return out;
}

+ (nullable NSString *)updateLocalization:(NSDictionary *)args error:(NSError **)error {
    NSString *locId = args[@"localization_id"];
    NSString *field = args[@"field"];
    NSString *value = args[@"value"];
    if (!locId.length || !field.length || !value) {
        if (error) *error = [NSError errorWithDomain:@"ASCLocalizationTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"localization_id, field, and value are required"}];
        return nil;
    }

    // Map user-friendly field names to API attribute names
    NSDictionary *fieldMap = @{
        @"description":    @"description",
        @"keywords":       @"keywords",
        @"marketingUrl":   @"marketingUrl",
        @"marketing_url":  @"marketingUrl",
        @"promotionalText":@"promotionalText",
        @"promotional_text":@"promotionalText",
        @"supportUrl":     @"supportUrl",
        @"support_url":    @"supportUrl",
        @"whatsNew":       @"whatsNew",
        @"whats_new":      @"whatsNew",
    };
    NSString *apiField = fieldMap[field] ?: field;

    NSString *path = [NSString stringWithFormat:@"/appStoreVersionLocalizations/%@", locId];
    NSDictionary *body = @{
        @"data": @{
            @"type": @"appStoreVersionLocalizations",
            @"id": locId,
            @"attributes": @{apiField: value}
        }
    };

    NSDictionary *resp = [[ASCClient shared] PATCH:path body:body error:error];
    if (!resp) return nil;
    return [NSString stringWithFormat:@"✓ Updated %@ for localization %@.", field, locId];
}

@end
