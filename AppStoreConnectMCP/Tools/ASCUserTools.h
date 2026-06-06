//
//  ASCUserTools.h
//  AppStoreConnectMCP
//

#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface ASCUserTools : NSObject
+ (nullable NSString *)listUsers:(NSDictionary *)args error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
