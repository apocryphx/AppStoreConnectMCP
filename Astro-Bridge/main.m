//
//  main.m
//  Astro-Bridge
//
//  Stdio↔HTTP bridge for the Astro MCP server.
//
//  Claude Desktop launches this app (packaged inside an .mcpb bundle) as a
//  subprocess. It reads JSON-RPC messages from stdin, forwards each to the
//  Astro app's locally-running HTTP server, and writes the response
//  back to stdout.
//
//  The app runs as an NSApplication accessory (LSUIElement=true) so a
//  future preferences window or status bar item can attach without
//  re-architecting.
//
//  Bypasses NSApplicationMain so the stock MainMenu.xib window is never
//  loaded. NSApp.delegate is held in a static to survive ARC scope exit.
//

#import <Cocoa/Cocoa.h>
#import "AppDelegate.h"
#include <signal.h>
#include <stdio.h>

static AppDelegate *gAppDelegate = nil;

int main(int argc, const char *argv[]) {
    setvbuf(stdout, NULL, _IONBF, 0);   // JSON-RPC channel — never buffer (§10.1)
    setvbuf(stderr, NULL, _IONBF, 0);   // diagnostics — never buffer
    signal(SIGPIPE, SIG_IGN);
    fprintf(stderr, "[astro-bridge] main() pid=%d\n", getpid());

    @autoreleasepool {
        NSApplication *app = [NSApplication sharedApplication];
        [app setActivationPolicy:NSApplicationActivationPolicyAccessory];

        gAppDelegate = [[AppDelegate alloc] init];
        app.delegate = gAppDelegate;

        [app run];
    }
    return 0;
}
