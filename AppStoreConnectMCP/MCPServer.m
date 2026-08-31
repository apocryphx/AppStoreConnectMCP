//
//  MCPServer.m
//  AppStoreConnectMCP
//

#import "MCPServer.h"
#import "MCPFraming.h"
#import "ASCToolRegistry.h"
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
    _readQueue   = dispatch_queue_create("asc.mcp.read",  DISPATCH_QUEUE_SERIAL);
    _writeQueue  = dispatch_queue_create("asc.mcp.write", DISPATCH_QUEUE_SERIAL);
    // Serial work queue: MCP over stdio is request/response (the client
    // waits), and App Store Connect API calls are synchronous. Serializing
    // keeps ordering correct and avoids race conditions on shared state.
    _workQueue   = dispatch_queue_create("asc.mcp.work",  DISPATCH_QUEUE_SERIAL);
    _stdinHandle  = [NSFileHandle fileHandleWithStandardInput];
    _stdoutHandle = [NSFileHandle fileHandleWithStandardOutput];
    _inputBuffer  = [NSMutableData data];
    return self;
}

- (void)start {
    fprintf(stderr, "[asc-bridge] MCP server starting (pid=%d)\n", getpid());

    __weak typeof(self) weak = self;
    self.stdinHandle.readabilityHandler = ^(NSFileHandle *h) {
        __strong typeof(weak) s = weak;
        if (!s) return;

        NSData *chunk = nil;
        @try { chunk = [h availableData]; }
        @catch (NSException *e) {
            fprintf(stderr, "[asc-bridge] stdin read exception: %s\n",
                    e.reason.UTF8String ?: "?");
        }

        if (!chunk.length) {
            h.readabilityHandler = nil;
            fprintf(stderr, "[asc-bridge] stdin EOF — draining and terminating\n");
            // Drain three queues in order before terminating:
            //   1. readQueue  — process any pending input chunks
            //   2. workQueue  — finish handleLine for every line drained in step 1
            //   3. writeQueue — flush every -write: dispatched by handleLine
            // Then hop to the main thread for NSApp.terminate.
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
            fprintf(stderr, "[asc-bridge] stdout write failed: %s\n",
                    e.reason.UTF8String ?: "?");
        }
    });
}

#pragma mark - Line dispatch

- (void)handleLine:(NSString *)line {
    NSData *lineData = [line dataUsingEncoding:NSUTF8StringEncoding];
    NSDictionary *msg = [NSJSONSerialization JSONObjectWithData:lineData options:0 error:nil];

    if (![msg isKindOfClass:[NSDictionary class]]) return;

    NSString *method = msg[@"method"];
    id rpcId = msg[@"id"];
    NSDictionary *params = msg[@"params"];

    NSString *output = nil;

    if ([method isEqualToString:@"initialize"]) {
        // Respond locally — no upstream server to forward to.
        output = ESMBJSONRPCResult(rpcId, @{
            @"protocolVersion": @"2024-11-05",
            @"capabilities": @{@"tools": @{}},
            @"serverInfo": @{@"name": @"AppStoreConnect Bridge", @"version": @"1.0.0"}
        });

    } else if ([method isEqualToString:@"tools/list"]) {
        // ASCToolRegistry returns configure_app_store_connect when no
        // credentials are stored, or the full 35-tool set otherwise.
        output = ESMBJSONRPCResult(rpcId, @{@"tools": [[ASCToolRegistry shared] allTools]});

    } else if ([method isEqualToString:@"tools/call"]) {
        NSString *toolName = params[@"name"];
        NSDictionary *arguments = params[@"arguments"] ?: @{};
        NSError *error = nil;
        NSString *text = nil;
        // callTool:arguments:error: blocks synchronously on the work queue.
        // That's intentional: one request completes before the next starts,
        // which keeps responses matched to their request IDs.
        // An ObjC exception here must fail this one call, not kill the server.
        @try {
            text = [[ASCToolRegistry shared] callTool:toolName
                                            arguments:arguments
                                                error:&error];
        } @catch (NSException *ex) {
            text = nil;
            error = [NSError errorWithDomain:@"MCPServer" code:-1
                                    userInfo:@{NSLocalizedDescriptionKey:
                [NSString stringWithFormat:@"Internal error in tool '%@': %@",
                 toolName ?: @"?", ex.reason ?: ex.name]}];
        }
        output = ESMBJSONRPCResult(rpcId, @{
            @"content": @[@{
                @"type": @"text",
                @"text": text ?: (error.localizedDescription ?: @"Unknown error")
            }],
            @"isError": text ? @NO : @YES
        });

    } else if ([method hasPrefix:@"notifications/"]) {
        // Fire-and-forget — no response expected or sent.

    } else if (rpcId) {
        // Unknown method with an id — return MethodNotFound.
        output = ESMBJSONRPCError(rpcId, -32601, @"Method not found");
    }

    if (output) [self write:output];
}

@end
