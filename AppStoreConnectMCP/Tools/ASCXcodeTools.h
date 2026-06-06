//
//  ASCXcodeTools.h
//  AppStoreConnectMCP
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ASCXcodeTools : NSObject

/// list_schemes — runs `xcodebuild -list -json` in the current directory
+ (nullable NSString *)listSchemes:(NSDictionary *)args error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
