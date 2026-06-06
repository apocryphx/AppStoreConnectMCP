//
//  ASCLocalizationTools.h
//  AppStoreConnectMCP
//

#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface ASCLocalizationTools : NSObject
+ (nullable NSString *)createVersion:(NSDictionary *)args error:(NSError **)error;
+ (nullable NSString *)listVersions:(NSDictionary *)args error:(NSError **)error;
+ (nullable NSString *)listLocalizations:(NSDictionary *)args error:(NSError **)error;
+ (nullable NSString *)getLocalization:(NSDictionary *)args error:(NSError **)error;
+ (nullable NSString *)updateLocalization:(NSDictionary *)args error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
