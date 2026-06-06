//
//  ASCJWTSigner.h
//  AppStoreConnectMCP
//
//  Generates ES256-signed JWTs for the App Store Connect API using the
//  credentials stored in ASCCredentialStore. Uses Security.framework only —
//  no third-party dependencies.
//
//  Tokens have a 20-minute expiry per Apple's requirement. A new token is
//  generated on each call (~1ms); no caching is necessary.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ASCJWTSigner : NSObject

+ (instancetype)shared;

/// Generate and return a signed JWT Bearer token, or nil on error.
- (nullable NSString *)bearerTokenError:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
