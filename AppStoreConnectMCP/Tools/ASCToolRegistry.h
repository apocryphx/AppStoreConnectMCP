//
//  ASCToolRegistry.h
//  AppStoreConnectMCP
//
//  Central tool registry. Returns the tool list for tools/list and dispatches
//  tools/call to domain handler classes.
//
//  When no credentials are stored, allTools returns a single
//  configure_app_store_connect tool. After credentials are saved, allTools
//  returns the full 35-tool surface.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ASCToolRegistry : NSObject

+ (instancetype)shared;

/// Returns the MCP tool schema array (for tools/list).
- (NSArray<NSDictionary *> *)allTools;

/// Invoke a tool by name. Returns result text or nil+error.
- (nullable NSString *)callTool:(NSString *)name
                      arguments:(NSDictionary *)arguments
                          error:(NSError **)error;

@end

NS_ASSUME_NONNULL_END
