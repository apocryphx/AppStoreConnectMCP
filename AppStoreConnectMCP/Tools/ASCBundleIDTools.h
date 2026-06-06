//
//  ASCBundleIDTools.h
//  AppStoreConnectMCP
//

#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface ASCBundleIDTools : NSObject
+ (nullable NSString *)createBundleId:(NSDictionary *)args error:(NSError **)error;
+ (nullable NSString *)listBundleIds:(NSDictionary *)args error:(NSError **)error;
+ (nullable NSString *)getBundleIdInfo:(NSDictionary *)args error:(NSError **)error;
+ (nullable NSString *)enableCapability:(NSDictionary *)args error:(NSError **)error;
+ (nullable NSString *)disableCapability:(NSDictionary *)args error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
