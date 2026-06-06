//
//  ASCReportsTools.m
//  AppStoreConnectMCP
//

#import "ASCReportsTools.h"
#import "ASCClient.h"
#import "ASCCredentialStore.h"

@implementation ASCReportsTools

+ (nullable NSString *)createReportRequest:(NSDictionary *)args error:(NSError **)error {
    NSString *appId      = args[@"app_id"];
    NSString *accessType = args[@"access_type"];
    if (!appId.length || !accessType.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCReportsTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"app_id and access_type are required"}];
        return nil;
    }

    NSDictionary *body = @{
        @"data": @{
            @"type": @"analyticsReportRequests",
            @"attributes": @{@"accessType": accessType},
            @"relationships": @{
                @"app": @{@"data": @{@"id": appId, @"type": @"apps"}}
            }
        }
    };

    NSDictionary *resp = [[ASCClient shared] POST:@"/analyticsReportRequests" body:body error:error];
    if (!resp) return nil;

    NSDictionary *data = resp[@"data"];
    return [NSString stringWithFormat:@"✓ Created analytics report request (ID: %@). Use list_analytics_reports to see available reports.",
            data[@"id"] ?: @"?"];
}

+ (nullable NSString *)listReports:(NSDictionary *)args error:(NSError **)error {
    NSString *requestId = args[@"report_request_id"];
    if (!requestId.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCReportsTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"report_request_id is required"}];
        return nil;
    }

    NSString *path = [NSString stringWithFormat:@"/analyticsReportRequests/%@/reports", requestId];
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (args[@"limit"]) params[@"limit"] = args[@"limit"];

    NSDictionary *resp = [[ASCClient shared] GET:path params:params error:error];
    if (!resp) return nil;

    NSArray *data = resp[@"data"];
    if (![data isKindOfClass:[NSArray class]] || !data.count) return @"No reports found for this request.";

    NSMutableString *out = [NSMutableString stringWithFormat:@"Found %lu report(s):\n\n", (unsigned long)data.count];
    for (NSDictionary *r in data) {
        NSDictionary *attrs = r[@"attributes"] ?: @{};
        [out appendFormat:@"• %@ — %@ (ID: %@)\n",
         attrs[@"name"] ?: @"?", attrs[@"category"] ?: @"?", r[@"id"] ?: @"?"];
    }
    return out;
}

+ (nullable NSString *)listSegments:(NSDictionary *)args error:(NSError **)error {
    NSString *reportId = args[@"report_id"];
    if (!reportId.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCReportsTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"report_id is required"}];
        return nil;
    }

    NSString *path = [NSString stringWithFormat:@"/analyticsReports/%@/segments", reportId];
    NSMutableDictionary *params = [NSMutableDictionary dictionary];
    if (args[@"limit"]) params[@"limit"] = args[@"limit"];

    NSDictionary *resp = [[ASCClient shared] GET:path params:params error:error];
    if (!resp) return nil;

    NSArray *data = resp[@"data"];
    if (![data isKindOfClass:[NSArray class]] || !data.count) return @"No segments found for this report.";

    NSMutableString *out = [NSMutableString stringWithFormat:@"Found %lu segment(s):\n\n", (unsigned long)data.count];
    for (NSDictionary *s in data) {
        NSDictionary *attrs = s[@"attributes"] ?: @{};
        [out appendFormat:@"• Segment %@ — %@ bytes\n  URL: %@\n\n",
         attrs[@"sizeInBytes"] ? [NSString stringWithFormat:@"(%@ bytes)", attrs[@"sizeInBytes"]] : @"",
         attrs[@"checksum"] ?: @"",
         attrs[@"url"] ?: @"?"];
    }
    return out;
}

+ (nullable NSString *)downloadSegment:(NSDictionary *)args error:(NSError **)error {
    NSString *url = args[@"url"];
    if (!url.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCReportsTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"url is required"}];
        return nil;
    }

    NSString *content = [[ASCClient shared] downloadText:url error:error];
    if (!content) return nil;

    // Truncate very large CSV files for readability
    NSUInteger maxLen = 8000;
    if (content.length > maxLen) {
        content = [[content substringToIndex:maxLen] stringByAppendingString:
                   @"\n\n[... truncated — download the full URL separately for complete data ...]"];
    }
    return content;
}

+ (nullable NSString *)downloadSalesReport:(NSDictionary *)args error:(NSError **)error {
    NSString *frequency    = args[@"frequency"];
    NSString *reportDate   = args[@"report_date"];
    NSString *reportType   = args[@"report_type"];
    NSString *reportSubType = args[@"report_sub_type"];

    if (!frequency.length || !reportDate.length || !reportType.length || !reportSubType.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCReportsTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey:
                                                      @"frequency, report_date, report_type, and report_sub_type are required"}];
        return nil;
    }

    NSString *vendorNumber = [[ASCCredentialStore shared] vendorNumber];
    if (!vendorNumber.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCReportsTools" code:2
                                           userInfo:@{NSLocalizedDescriptionKey:
                                                      @"vendor_number is required for sales reports. Re-run configure_app_store_connect and include vendor_number."}];
        return nil;
    }

    NSDictionary *params = @{
        @"filter[frequency]":     frequency,
        @"filter[reportDate]":    reportDate,
        @"filter[reportType]":    reportType,
        @"filter[reportSubType]": reportSubType,
        @"filter[vendorNumber]":  vendorNumber,
        @"filter[version]":       @"1_0",
    };

    // Sales reports return gzipped TSV — use the raw download path
    NSString *content = [[ASCClient shared] downloadText:@"https://api.appstoreconnect.apple.com/v1/salesReports" error:error];
    if (!content) {
        // Fallback: use GET (client will handle it)
        NSDictionary *resp = [[ASCClient shared] GET:@"/salesReports" params:params error:error];
        if (!resp) return nil;
        return [NSString stringWithFormat:@"Sales report response: %@", resp];
    }
    return content;
}

+ (nullable NSString *)downloadFinanceReport:(NSDictionary *)args error:(NSError **)error {
    NSString *reportDate = args[@"report_date"];
    NSString *regionCode = args[@"region_code"];

    if (!reportDate.length || !regionCode.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCReportsTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"report_date and region_code are required"}];
        return nil;
    }

    NSString *vendorNumber = [[ASCCredentialStore shared] vendorNumber];
    if (!vendorNumber.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCReportsTools" code:2
                                           userInfo:@{NSLocalizedDescriptionKey:
                                                      @"vendor_number is required for finance reports. Re-run configure_app_store_connect and include vendor_number."}];
        return nil;
    }

    NSDictionary *params = @{
        @"filter[reportDate]":   reportDate,
        @"filter[regionCode]":   regionCode,
        @"filter[vendorNumber]": vendorNumber,
    };

    NSDictionary *resp = [[ASCClient shared] GET:@"/financeReports" params:params error:error];
    if (!resp) return nil;
    return [NSString stringWithFormat:@"Finance report data: %@", resp];
}

@end
