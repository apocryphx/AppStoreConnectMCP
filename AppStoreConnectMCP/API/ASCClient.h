//
//  ASCClient.h
//  AppStoreConnectMCP
//
//  NSURLSession-based HTTPS client for the App Store Connect API v1.
//  All methods are synchronous (dispatch_semaphore) and intended to be
//  called from the MCPServer work queue.
//
//  Base URL: https://api.appstoreconnect.apple.com/v1
//  Auth: Bearer JWT injected automatically on every request.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ASCClient : NSObject

+ (instancetype)shared;

/// GET /v1/<path>?<params>. Returns parsed JSON body or nil+error.
- (nullable NSDictionary *)GET:(NSString *)path
                        params:(nullable NSDictionary *)params
                         error:(NSError **)error;

/// POST /v1/<path> with JSON body. Returns parsed response or nil+error.
- (nullable NSDictionary *)POST:(NSString *)path
                           body:(NSDictionary *)body
                          error:(NSError **)error;

/// PATCH /v1/<path> with JSON body. Returns parsed response or nil+error.
- (nullable NSDictionary *)PATCH:(NSString *)path
                            body:(NSDictionary *)body
                           error:(NSError **)error;

/// DELETE /v1/<path>. Returns YES on success (204), NO+error otherwise.
- (BOOL)DELETE:(NSString *)path
          body:(nullable NSDictionary *)body
         error:(NSError **)error;

/// Download text content from an absolute URL (e.g. report segment S3 URL).
- (nullable NSString *)downloadText:(NSString *)absoluteURL error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
