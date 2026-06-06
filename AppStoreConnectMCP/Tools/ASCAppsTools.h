//
//  ASCAppsTools.h
//  AppStoreConnectMCP
//

#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface ASCAppsTools : NSObject
+ (nullable NSString *)listApps:(NSDictionary *)args error:(NSError **)error;
+ (nullable NSString *)getAppInfo:(NSDictionary *)args error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
