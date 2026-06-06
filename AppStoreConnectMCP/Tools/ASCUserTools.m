//
//  ASCUserTools.m
//  AppStoreConnectMCP
//

#import "ASCUserTools.h"
#import "ASCClient.h"

@implementation ASCUserTools

+ (nullable NSString *)listUsers:(NSDictionary *)args error:(NSError **)error {
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (args[@"limit"])       params[@"limit"]          = args[@"limit"];
    if (args[@"sort"])        params[@"sort"]            = args[@"sort"];
    if (args[@"filter_role"]) params[@"filter[roles]"]  = args[@"filter_role"];

    NSDictionary *resp = [[ASCClient shared] GET:@"/users" params:params error:error];
    if (!resp) return nil;

    NSArray *data = resp[@"data"];
    if (![data isKindOfClass:[NSArray class]] || !data.count) return @"No users found.";

    NSMutableString *out = [NSMutableString stringWithFormat:@"Found %lu user(s):\n\n", (unsigned long)data.count];
    for (NSDictionary *u in data) {
        NSDictionary *attrs = u[@"attributes"] ?: @{};
        NSArray *roles = attrs[@"roles"] ?: @[];
        [out appendFormat:@"• %@ %@ <%@>\n  Roles: %@\n\n",
         attrs[@"firstName"] ?: @"",
         attrs[@"lastName"]  ?: @"",
         attrs[@"username"]  ?: @"?",
         [roles componentsJoinedByString:@", "] ?: @"?"];
    }
    return out;
}

@end
