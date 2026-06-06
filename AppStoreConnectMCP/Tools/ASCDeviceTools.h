//
//  ASCDeviceTools.h
//  AppStoreConnectMCP
//

#import <Foundation/Foundation.h>
NS_ASSUME_NONNULL_BEGIN
@interface ASCDeviceTools : NSObject
+ (nullable NSString *)listDevices:(NSDictionary *)args error:(NSError **)error;
@end
NS_ASSUME_NONNULL_END
