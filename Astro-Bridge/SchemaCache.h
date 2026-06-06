//
//  SchemaCache.h
//  Astro-Bridge
//
//  Live proxy for the server's tools/list, with last-known-good disk and
//  bundled-bootstrap fallbacks for when the server isn't running.
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface SchemaCache : NSObject

+ (instancetype)shared;

/// Synchronous fetch. Blocks for one server round-trip (typical <50ms;
/// Forwarder timeout 120s). Returns:
///   - live server response (and persists it to disk) when reachable
///   - last-known-good from disk, then bundled bootstrap, when the server
///     is down

- (NSArray<NSDictionary *> *)currentTools;

@end

NS_ASSUME_NONNULL_END
