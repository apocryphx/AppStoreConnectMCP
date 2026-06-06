//
//  ASCXcodeTools.m
//  AppStoreConnectMCP
//

#import "ASCXcodeTools.h"
#include <stdio.h>

@implementation ASCXcodeTools

+ (nullable NSString *)listSchemes:(NSDictionary *)args error:(NSError **)error {
    // Optional: caller can pass a "path" argument to CD into a project directory first.
    NSString *path = args[@"path"];
    NSString *cmd;
    if (path.length) {
        // Shell-escape the path
        NSString *escaped = [path stringByReplacingOccurrencesOfString:@"'" withString:@"'\\''"];
        cmd = [NSString stringWithFormat:@"cd '%@' && xcodebuild -list -json 2>&1", escaped];
    } else {
        cmd = @"xcodebuild -list -json 2>&1";
    }

    FILE *pipe = popen(cmd.UTF8String, "r");
    if (!pipe) {
        if (error) *error = [NSError errorWithDomain:@"ASCXcodeTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"Failed to run xcodebuild"}];
        return nil;
    }

    NSMutableData *outputData = [NSMutableData data];
    char buffer[4096];
    while (fgets(buffer, sizeof(buffer), pipe)) {
        [outputData appendBytes:buffer length:strlen(buffer)];
    }
    int status = pclose(pipe);

    NSString *rawOutput = [[NSString alloc] initWithData:outputData encoding:NSUTF8StringEncoding] ?: @"";

    // Try to parse the JSON output for a clean formatted result
    NSData *jsonData = [rawOutput dataUsingEncoding:NSUTF8StringEncoding];
    NSError *jsonError = nil;
    NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:jsonData options:0 error:&jsonError];

    if (parsed && !jsonError) {
        NSDictionary *project = parsed[@"project"];
        NSMutableString *out = [NSMutableString string];

        if (project[@"name"]) {
            [out appendFormat:@"Project: %@\n\n", project[@"name"]];
        }

        NSArray *targets = project[@"targets"];
        if ([targets isKindOfClass:[NSArray class]] && targets.count) {
            [out appendString:@"Targets:\n"];
            for (NSString *t in targets) [out appendFormat:@"  • %@\n", t];
            [out appendString:@"\n"];
        }

        NSArray *schemes = project[@"schemes"];
        if ([schemes isKindOfClass:[NSArray class]] && schemes.count) {
            [out appendString:@"Schemes:\n"];
            for (NSString *s in schemes) [out appendFormat:@"  • %@\n", s];
            [out appendString:@"\n"];
        }

        NSArray *configs = project[@"configurations"];
        if ([configs isKindOfClass:[NSArray class]] && configs.count) {
            [out appendString:@"Configurations:\n"];
            for (NSString *c in configs) [out appendFormat:@"  • %@\n", c];
        }

        return out.length ? out : @"No project info found.";
    }

    // JSON parse failed — return raw output (may include error message from xcodebuild)
    if (status != 0 || rawOutput.length == 0) {
        if (error) *error = [NSError errorWithDomain:@"ASCXcodeTools" code:2
                                           userInfo:@{NSLocalizedDescriptionKey:
                                                      rawOutput.length ? rawOutput : @"xcodebuild exited with error"}];
        return nil;
    }

    return rawOutput;
}

@end
