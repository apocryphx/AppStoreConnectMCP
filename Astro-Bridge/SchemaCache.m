//
//  SchemaCache.m
//  Astro-Bridge
//

#import "SchemaCache.h"
#import "Forwarder.h"
#import "MCPFraming.h"

static NSString *const kBundleIdentifier  = @"com.elarity.astro-bridge";
static NSString *const kCacheFileName      = @"tools.json";
static NSString *const kBootstrapResource  = @"tools-bootstrap";

@implementation SchemaCache

+ (instancetype)shared {
    static SchemaCache *instance = nil;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        instance = [[SchemaCache alloc] init];
    });
    return instance;
}

#pragma mark - Disk last-known-good

- (NSString *)_cacheDirectory {
    NSArray *paths = NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES);
    NSString *base = paths.firstObject ?: NSTemporaryDirectory();
    return [base stringByAppendingPathComponent:kBundleIdentifier];
}

- (NSString *)_cacheFilePath {
    return [[self _cacheDirectory] stringByAppendingPathComponent:kCacheFileName];
}

- (nullable NSArray *)_readDiskCache {
    NSData *data = [NSData dataWithContentsOfFile:[self _cacheFilePath]];
    if (!data) return nil;
    NSArray *arr = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [arr isKindOfClass:NSArray.class] ? arr : nil;
}

// Cold-start fallback: the tool list captured from a live server and shipped
// inside the .app bundle. Used only when there's no disk last-known-good yet
// (first launch while Astro is down). May be absent if the bundle wasn't
// built with it — that's fine, callers tolerate nil.
- (nullable NSArray *)_readBundledBootstrap {
    NSString *path = [[NSBundle mainBundle] pathForResource:kBootstrapResource
                                                     ofType:@"json"];
    if (!path) return nil;
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (!data) return nil;
    NSArray *arr = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
    return [arr isKindOfClass:NSArray.class] ? arr : nil;
}

- (void)_writeDiskCache:(NSArray *)tools {
    NSError *err = nil;
    NSData *data = [NSJSONSerialization dataWithJSONObject:tools
                                                   options:NSJSONWritingPrettyPrinted
                                                     error:&err];
    if (!data) {
        fprintf(stderr, "[astro-bridge] last-known-good encode failed: %s\n",
                err.localizedDescription.UTF8String);
        return;
    }
    NSString *dir = [self _cacheDirectory];
    [[NSFileManager defaultManager] createDirectoryAtPath:dir
                              withIntermediateDirectories:YES attributes:nil error:nil];
    NSString *tmp = [[self _cacheFilePath] stringByAppendingString:@".tmp"];
    if (![data writeToFile:tmp atomically:NO]) {
        fprintf(stderr, "[astro-bridge] last-known-good tmp write failed at %s\n",
                tmp.UTF8String);
        return;
    }
    if (rename(tmp.UTF8String, [self _cacheFilePath].UTF8String) != 0) {
        fprintf(stderr, "[astro-bridge] last-known-good rename failed: %s\n", strerror(errno));
    }
}

#pragma mark - Public API

- (NSArray<NSDictionary *> *)currentTools {
    // Fast path: if Forwarder already knows the host is unreachable
    // from a recent failed forward, skip the redundant 120s timeout
    // and go straight to the last-known-good disk file. Forwarder
    // flips reachability back to YES the moment any forward succeeds
    // (e.g. a subsequent tool call once the user starts the server),
    // so the next currentTools call will live-fetch again.
    if (![[Forwarder shared] hostReachable]) {
        return [self _serveLastKnownGood];
    }

    // Per-call id counter — purely for log readability. Concurrent
    // tools/list is rare and a collision here is harmless.
    static NSInteger toolsListId = 80000;
    toolsListId++;

    NSString *line = ESMBEncodeJSON(@{
        @"jsonrpc": @"2.0",
        @"id": @(toolsListId),
        @"method": @"tools/list",
        @"params": @{}
    });

    NSError *err = nil;
    NSString *response = [[Forwarder shared] forwardLine:line error:&err];

    NSArray *tools = nil;
    if (response) {
        NSData *data = [response dataUsingEncoding:NSUTF8StringEncoding];
        NSDictionary *parsed = [NSJSONSerialization JSONObjectWithData:data options:0 error:nil];
        if ([parsed isKindOfClass:NSDictionary.class]) {
            id result = parsed[@"result"];
            if ([result isKindOfClass:NSDictionary.class]) {
                id t = ((NSDictionary *)result)[@"tools"];
                if ([t isKindOfClass:NSArray.class]) tools = t;
            }
        }
    }

    if (tools) {
        // Live success — persist as last-known-good, then return.
        [self _writeDiskCache:tools];
        return tools;
    }

    // Live failed — Forwarder has flipped hostReachable to NO and logged
    // the transition. Serve last-known-good so Claude has a tool list
    // while the user starts the server; the next tool call will surface
    // the offline error via DegradedResponses.
    return [self _serveLastKnownGood];
}

// Live → disk last-known-good → bundled bootstrap → empty. The empty case
// only happens on a first-ever launch while Astro is down with no bootstrap
// shipped; a `tools/call` then surfaces the offline error via DegradedResponses.
- (NSArray<NSDictionary *> *)_serveLastKnownGood {
    NSArray *disk = [self _readDiskCache];
    if (disk.count) return disk;
    NSArray *bootstrap = [self _readBundledBootstrap];
    if (bootstrap.count) return bootstrap;
    return @[];
}

@end
