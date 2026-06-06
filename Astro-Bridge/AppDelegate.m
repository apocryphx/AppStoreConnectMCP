//
//  AppDelegate.m
//  Astro-Bridge
//

#import "AppDelegate.h"
#import "Forwarder.h"
#import "MCPServer.h"

@implementation AppDelegate

- (void)applicationDidFinishLaunching:(NSNotification *)note {
    fprintf(stderr, "[astro-bridge] applicationDidFinishLaunching\n");

    // Touch the shared Forwarder once so its init log line lands before
    // the first inbound line — keeps the log ordering stable.
    (void)[Forwarder shared];

    // Note: SchemaCache no longer needs startup priming. Every tools/list
    // call now fetches live from the server via SchemaCache.currentTools.

    [[MCPServer shared] start];
}

- (BOOL)applicationSupportsSecureRestorableState:(NSApplication *)app {
    return YES;
}

- (void)applicationWillTerminate:(NSNotification *)note {
    fprintf(stderr, "[astro-bridge] applicationWillTerminate\n");
}

@end
