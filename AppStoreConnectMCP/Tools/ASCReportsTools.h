//
//  ASCReportsTools.h
//  AppStoreConnectMCP
//

#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface ASCReportsTools : NSObject
+ (nullable NSString *)createReportRequest:(NSDictionary *)args error:(NSError **)error;
+ (nullable NSString *)listReports:(NSDictionary *)args error:(NSError **)error;
+ (nullable NSString *)listSegments:(NSDictionary *)args error:(NSError **)error;
+ (nullable NSString *)downloadSegment:(NSDictionary *)args error:(NSError **)error;
+ (nullable NSString *)downloadSalesReport:(NSDictionary *)args error:(NSError **)error;
+ (nullable NSString *)downloadFinanceReport:(NSDictionary *)args error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
