//
//  MCPServer.m
//  Astro-Bridge
//

#import "MCPServer.h"
#import "MCPFraming.h"
#import "DegradedResponses.h"
#import "Forwarder.h"
#import "SchemaCache.h"
#import <AppKit/AppKit.h>

@interface MCPServer ()
@property (strong) dispatch_queue_t readQueue;
@property (strong) dispatch_queue_t writeQueue;
@property (strong) dispatch_queue_t workQueue;
@property (strong) NSFileHandle    *stdinHandle;
@property (strong) NSFileHandle    *stdoutHandle;
@property (strong) NSMutableData   *inputBuffer;
@end

@implementation MCPServer

+ (instancetype)shared {
    static MCPServer *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[MCPServer alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    _readQueue   = dispatch_queue_create("astro.mcp.read",  DISPATCH_QUEUE_SERIAL);
    _writeQueue  = dispatch_queue_create("astro.mcp.write", DISPATCH_QUEUE_SERIAL);
    // Serial: each line forwards synchronously and one at a time. MCP over
    // stdio is request/response (the client waits), and Astro's HTTP server is
    // session-based and order-sensitive — it expects `initialize` to establish
    // the session before any tool call. Forwarding concurrently lets a call
    // race ahead of initialize and get rejected with a non-200, which the
    // Forwarder would then silently drop. Serializing eliminates that race.
    _workQueue   = dispatch_queue_create("astro.mcp.work",  DISPATCH_QUEUE_SERIAL);
    _stdinHandle  = [NSFileHandle fileHandleWithStandardInput];
    _stdoutHandle = [NSFileHandle fileHandleWithStandardOutput];
    _inputBuffer  = [NSMutableData data];
    return self;
}

- (void)start {
    fprintf(stderr, "[astro-bridge] MCP server starting (pid=%d)\n", getpid());

    __weak typeof(self) weak = self;
    self.stdinHandle.readabilityHandler = ^(NSFileHandle *h) {
        __strong typeof(weak) s = weak;
        if (!s) return;

        NSData *chunk = nil;
        @try { chunk = [h availableData]; }
        @catch (NSException *e) {
            fprintf(stderr, "[astro-bridge] stdin read exception: %s\n",
                    e.reason.UTF8String ?: "?");
        }

        if (!chunk.length) {
            h.readabilityHandler = nil;
            fprintf(stderr, "[astro-bridge] stdin EOF — draining and terminating\n");
            // Drain three queues in order before terminating:
            //   1. readQueue   (serial) — process any pending input chunks
            //   2. workQueue   (serial) — finish handleLine for every
            //                             line drained in step 1
            //   3. writeQueue  (serial) — flush every -write: that
            //                             handleLine dispatched
            // Then hop to the main thread for NSApp.terminate. Without
            // step 1, the barrier on workQueue can fire before late
            // chunks have even been pushed onto workQueue, and a tool
            // response gets lost in the shutdown race.
            dispatch_async(s.readQueue, ^{
                dispatch_barrier_async(s.workQueue, ^{
                    dispatch_async(s.writeQueue, ^{
                        dispatch_async(dispatch_get_main_queue(), ^{ [NSApp terminate:nil]; });
                    });
                });
            });
            return;
        }

        dispatch_async(s.readQueue, ^{
            [s.inputBuffer appendData:chunk];
            [s drainLines];
        });
    };
}

- (void)drainLines {
    static const uint8_t nl = '\n';
    while (YES) {
        NSRange r = [self.inputBuffer rangeOfData:[NSData dataWithBytes:&nl length:1]
                                          options:0
                                            range:NSMakeRange(0, self.inputBuffer.length)];
        if (r.location == NSNotFound) break;

        NSData *lineData = [self.inputBuffer subdataWithRange:NSMakeRange(0, r.location)];
        [self.inputBuffer replaceBytesInRange:NSMakeRange(0, r.location + 1)
                                    withBytes:NULL length:0];
        if (!lineData.length) continue;

        NSString *line = [[NSString alloc] initWithData:lineData encoding:NSUTF8StringEncoding];
        line = [line stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceCharacterSet];
        if (line.length) dispatch_async(self.workQueue, ^{ [self handleLine:line]; });
    }
}

- (void)write:(NSString *_Nullable)line {
    if (!line) return;
    dispatch_async(self.writeQueue, ^{
        NSData *out = [[line stringByAppendingString:@"\n"] dataUsingEncoding:NSUTF8StringEncoding];
        @try { [self.stdoutHandle writeData:out]; }
        @catch (NSException *e) {
            fprintf(stderr, "[astro-bridge] stdout write failed: %s\n",
                    e.reason.UTF8String ?: "?");
        }
    });
}

#pragma mark - Line dispatch

- (void)handleLine:(NSString *)line {
    NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *msg = [NSJSONSerialization JSONObjectWithData:lineData options:0 error:nil];

    NSString *output = nil;

    if ([msg isKindOfClass:[NSDictionary class]]) {
        NSString *method = msg[@"method"];
        id rpcId = msg[@"id"];

        if ([method isEqualToString:@"tools/list"]) {
            // Serve from SchemaCache (live proxy + last-known-good disk cache
            // + bundled bootstrap fallback). The bridge owns the tool surface
            // so a list is always available even when Astro is down — we never
            // forward tools/list.
            output = ESMBJSONRPCResult(rpcId, @{ @"tools": [[SchemaCache shared] currentTools] });
        }
        // Everything else (initialize, tools/call, notifications, …) falls
        // through to the generic forward below.
    }

    // Fall through to forwarding for anything we didn't handle.
    if (!output) {
        // Synchronous forward on the serial work queue — one request in
        // flight at a time, in arrival order (see -init for why Astro needs
        // this).
        //
        // We deliberately don't use forwardLineAsync: here: stdin EOF
        // triggers [NSApp terminate] immediately, which would lose any
        // pending async responses. Sync ensures handleLine completes
        // (and writes its response) before EOF can race it.
        NSError *error = nil;
        NSString *response = ForwardRequest(line, &error);
        if (response) {
            output = response;
        } else if (error && [msg isKindOfClass:[NSDictionary class]]) {
            output = ESMBDegradedResponseForRequest(msg, [[SchemaCache shared] currentTools]);
        }
        // response nil + no error → 202 ack from host, no output.
        // Reachability transitions are logged inside Forwarder.
    }

    if (output) [self write:output];
}

@end
