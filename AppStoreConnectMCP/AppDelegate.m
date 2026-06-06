//
//  AppDelegate.m
//  AppStoreConnectMCP
//

#import "AppDelegate.h"
#import "MCPServer.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    fprintf(stderr, "[asc-bridge] applicationDidFinishLaunching\n");
    [[MCPServer shared] start];
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)note {
    fprintf(stderr, "[asc-bridge] applicationWillTerminate\n");
}

@end
