//
//  ASCKeywordTools.h
//  AppStoreConnectMCP
//

#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface ASCKeywordTools : NSObject
+ (nullable NSString *)checkKeywordRankings:(NSDictionary *)args error:(NSError **)error;
+ (nullable NSString *)searchKeywordCompetition:(NSDictionary *)args error:(NSError **)error;
+ (nullable NSString *)bulkKeywordScan:(NSDictionary *)args error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
