//
//  ASCBetaTools.m
//  AppStoreConnectMCP
//

#import "ASCBetaTools.h"
#import "ASCClient.h"

@implementation ASCBetaTools

+ (nullable NSString *)listBetaGroups:(NSDictionary *)args error:(NSError **)error {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (args[@"limit"])  params[@"limit"]       = args[@"limit"];
    if (args[@"app_id"]) params[@"filter[app]"] = args[@"app_id"];

    NSDictionary *resp = [[ASCClient shared] GET:@"/betaGroups" params:params error:error];
    if (!resp) return nil;

    NSArray *data = resp[@"data"];
    if (![data isKindOfClass:[NSArray class]] || !data.count) return @"No beta groups found.";

    NSMutableString *out = [NSMutableString stringWithFormat:@"Found %lu beta group(s):\n\n", (unsigned long)data.count];
    for (NSDictionary *g in data) {
        NSDictionary *attrs = g[@"attributes"] ?: @{};
        [out appendFormat:@"• %@ (ID: %@)\n  Public: %@ | Internal: %@\n\n",
         attrs[@"name"] ?: @"?", g[@"id"] ?: @"?",
         [attrs[@"publicLinkEnabled"] boolValue] ? @"Yes" : @"No",
         [attrs[@"isInternalGroup"] boolValue]   ? @"Yes" : @"No"];
    }
    return out;
}

+ (nullable NSString *)listGroupTesters:(NSDictionary *)args error:(NSError **)error {
    NSString *groupId = args[@"group_id"];
    if (!groupId.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCBetaTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"group_id is required"}];
        return nil;
    }

    NSString *path = [NSString stringWithFormat:@"/betaGroups/%@/betaTesters", groupId];
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (args[@"limit"]) params[@"limit"] = args[@"limit"];

    NSDictionary *resp = [[ASCClient shared] GET:path params:params error:error];
    if (!resp) return nil;

    NSArray *data = resp[@"data"];
    if (![data isKindOfClass:[NSArray class]] || !data.count) return @"No testers in this group.";

    NSMutableString *out = [NSMutableString stringWithFormat:@"Found %lu tester(s):\n\n", (unsigned long)data.count];
    for (NSDictionary *t in data) {
        NSDictionary *attrs = t[@"attributes"] ?: @{};
        [out appendFormat:@"• %@ %@ <%@> (ID: %@)\n",
         attrs[@"firstName"] ?: @"", attrs[@"lastName"] ?: @"",
         attrs[@"email"] ?: @"?", t[@"id"] ?: @"?"];
    }
    return out;
}

+ (nullable NSString *)addTesterToGroup:(NSDictionary *)args error:(NSError **)error {
    NSString *groupId = args[@"group_id"];
    NSString *email   = args[@"email"];
    if (!groupId.length || !email.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCBetaTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"group_id and email are required"}];
        return nil;
    }

    NSMutableDictionary *attrs = [@{@"email": email} mutableCopy];
    if (args[@"first_name"]) attrs[@"firstName"] = args[@"first_name"];
    if (args[@"last_name"])  attrs[@"lastName"]  = args[@"last_name"];

    NSDictionary *body = @{
        @"data": @{
            @"type": @"betaTesters",
            @"attributes": attrs,
            @"relationships": @{
                @"betaGroups": @{
                    @"data": @[@{@"id": groupId, @"type": @"betaGroups"}]
                }
            }
        }
    };

    NSDictionary *resp = [[ASCClient shared] POST:@"/betaTesters" body:body error:error];
    if (!resp) return nil;

    NSDictionary *data  = resp[@"data"];
    NSDictionary *rAttrs = data[@"attributes"] ?: @{};
    return [NSString stringWithFormat:@"✓ Added tester %@ <%@> (ID: %@) to group.",
            rAttrs[@"email"] ?: email, rAttrs[@"email"] ?: @"", data[@"id"] ?: @"?"];
}

+ (nullable NSString *)removeTesterFromGroup:(NSDictionary *)args error:(NSError **)error {
    NSString *groupId  = args[@"group_id"];
    NSString *testerId = args[@"tester_id"];
    if (!groupId.length || !testerId.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCBetaTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"group_id and tester_id are required"}];
        return nil;
    }

    NSString *path = [NSString stringWithFormat:@"/betaGroups/%@/relationships/betaTesters", groupId];
    NSDictionary *body = @{@"data": @[@{@"id": testerId, @"type": @"betaTesters"}]};

    BOOL ok = [[ASCClient shared] DELETE:path body:body error:error];
    if (!ok) return nil;
    return [NSString stringWithFormat:@"✓ Removed tester %@ from group %@.", testerId, groupId];
}

+ (nullable NSString *)listBetaFeedback:(NSDictionary *)args error:(NSError **)error {
    NSString *appId   = args[@"app_id"];
    NSString *buildId = args[@"build_id"];
    if (!appId.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCBetaTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"app_id is required"}];
        return nil;
    }

    NSString *path = [NSString stringWithFormat:@"/apps/%@/betaFeedbackScreenshotSubmissions", appId];
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (args[@"limit"])  params[@"limit"]           = args[@"limit"];
    if (buildId.length)  params[@"filter[build]"]   = buildId;

    NSDictionary *resp = [[ASCClient shared] GET:path params:params error:error];
    if (!resp) return nil;

    NSArray *data = resp[@"data"];
    if (![data isKindOfClass:[NSArray class]] || !data.count) return @"No beta feedback found.";

    NSMutableString *out = [NSMutableString stringWithFormat:@"Found %lu feedback submission(s):\n\n", (unsigned long)data.count];
    for (NSDictionary *f in data) {
        NSDictionary *attrs = f[@"attributes"] ?: @{};
        [out appendFormat:@"• ID: %@\n  Device: %@ %@ (iOS %@)\n  Date: %@\n\n",
         f[@"id"] ?: @"?",
         attrs[@"deviceModel"] ?: @"?",
         attrs[@"osVersion"]   ?: @"",
         attrs[@"architecture"]?: @"",
         attrs[@"timestamp"]   ?: @""];
    }
    return out;
}

+ (nullable NSString *)getBetaFeedback:(NSDictionary *)args error:(NSError **)error {
    NSString *feedbackId = args[@"feedback_id"];
    if (!feedbackId.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCBetaTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"feedback_id is required"}];
        return nil;
    }

    NSString *path = [NSString stringWithFormat:@"/betaFeedbackScreenshotSubmissions/%@", feedbackId];
    NSDictionary *resp = [[ASCClient shared] GET:path params:nil error:error];
    if (!resp) return nil;

    NSDictionary *data  = resp[@"data"];
    NSDictionary *attrs = data[@"attributes"] ?: @{};

    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"Feedback ID: %@\n", data[@"id"] ?: @"?"];
    [out appendFormat:@"Device: %@ %@\n", attrs[@"deviceModel"] ?: @"?", attrs[@"osVersion"] ?: @""];
    [out appendFormat:@"Date: %@\n", attrs[@"timestamp"] ?: @"?"];
    if (attrs[@"screenshotUrl"]) {
        [out appendFormat:@"Screenshot URL: %@\n", attrs[@"screenshotUrl"]];
    }
    if (attrs[@"comment"]) {
        [out appendFormat:@"Comment: %@\n", attrs[@"comment"]];
    }
    return out;
}

@end
