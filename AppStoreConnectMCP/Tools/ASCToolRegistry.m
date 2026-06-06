//
//  ASCToolRegistry.m
//  AppStoreConnectMCP
//

#import "ASCToolRegistry.h"
#import "ASCCredentialStore.h"
#import "ASCAppsTools.h"
#import "ASCBetaTools.h"
#import "ASCLocalizationTools.h"
#import "ASCBundleIDTools.h"
#import "ASCDeviceTools.h"
#import "ASCUserTools.h"
#import "ASCReportsTools.h"
#import "ASCXcodeTools.h"

@implementation ASCToolRegistry

+ (instancetype)shared {
    static ASCToolRegistry *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[ASCToolRegistry alloc] init]; });
    return s;
}

#pragma mark - Tool list

- (NSArray<NSDictionary *> *)allTools {
    if (![[ASCCredentialStore shared] hasCredentials]) {
        return @[[self _setupTool]];
    }
    return [self _allASCTools];
}

#pragma mark - Dispatch

- (nullable NSString *)callTool:(NSString *)name
                      arguments:(NSDictionary *)arguments
                          error:(NSError **)error {

    // Setup tool — always available (even before credentials)
    if ([name isEqualToString:@"configure_app_store_connect"]) {
        return [self _configure:arguments error:error];
    }

    // All other tools require credentials
    if (![[ASCCredentialStore shared] hasCredentials]) {
        if (error) *error = [NSError errorWithDomain:@"ASCToolRegistry" code:1
                                           userInfo:@{NSLocalizedDescriptionKey:
                                                      @"Not configured. Use configure_app_store_connect first."}];
        return nil;
    }

    // Apps
    if ([name isEqualToString:@"list_apps"])    return [ASCAppsTools listApps:arguments error:error];
    if ([name isEqualToString:@"get_app_info"]) return [ASCAppsTools getAppInfo:arguments error:error];

    // Beta
    if ([name isEqualToString:@"list_beta_groups"])              return [ASCBetaTools listBetaGroups:arguments error:error];
    if ([name isEqualToString:@"list_group_testers"])            return [ASCBetaTools listGroupTesters:arguments error:error];
    if ([name isEqualToString:@"add_tester_to_group"])           return [ASCBetaTools addTesterToGroup:arguments error:error];
    if ([name isEqualToString:@"remove_tester_from_group"])      return [ASCBetaTools removeTesterFromGroup:arguments error:error];
    if ([name isEqualToString:@"list_beta_feedback_screenshots"])return [ASCBetaTools listBetaFeedback:arguments error:error];
    if ([name isEqualToString:@"get_beta_feedback_screenshot"])  return [ASCBetaTools getBetaFeedback:arguments error:error];

    // Localizations
    if ([name isEqualToString:@"create_app_store_version"])                return [ASCLocalizationTools createVersion:arguments error:error];
    if ([name isEqualToString:@"list_app_store_versions"])                 return [ASCLocalizationTools listVersions:arguments error:error];
    if ([name isEqualToString:@"list_app_store_version_localizations"])    return [ASCLocalizationTools listLocalizations:arguments error:error];
    if ([name isEqualToString:@"get_app_store_version_localization"])      return [ASCLocalizationTools getLocalization:arguments error:error];
    if ([name isEqualToString:@"update_app_store_version_localization"])   return [ASCLocalizationTools updateLocalization:arguments error:error];

    // Bundle IDs
    if ([name isEqualToString:@"create_bundle_id"])        return [ASCBundleIDTools createBundleId:arguments error:error];
    if ([name isEqualToString:@"list_bundle_ids"])         return [ASCBundleIDTools listBundleIds:arguments error:error];
    if ([name isEqualToString:@"get_bundle_id_info"])      return [ASCBundleIDTools getBundleIdInfo:arguments error:error];
    if ([name isEqualToString:@"enable_bundle_capability"])  return [ASCBundleIDTools enableCapability:arguments error:error];
    if ([name isEqualToString:@"disable_bundle_capability"]) return [ASCBundleIDTools disableCapability:arguments error:error];

    // Devices
    if ([name isEqualToString:@"list_devices"]) return [ASCDeviceTools listDevices:arguments error:error];

    // Users
    if ([name isEqualToString:@"list_users"]) return [ASCUserTools listUsers:arguments error:error];

    // Reports
    if ([name isEqualToString:@"create_analytics_report_request"])  return [ASCReportsTools createReportRequest:arguments error:error];
    if ([name isEqualToString:@"list_analytics_reports"])           return [ASCReportsTools listReports:arguments error:error];
    if ([name isEqualToString:@"list_analytics_report_segments"])   return [ASCReportsTools listSegments:arguments error:error];
    if ([name isEqualToString:@"download_analytics_report_segment"])return [ASCReportsTools downloadSegment:arguments error:error];
    if ([name isEqualToString:@"download_sales_report"])            return [ASCReportsTools downloadSalesReport:arguments error:error];
    if ([name isEqualToString:@"download_finance_report"])          return [ASCReportsTools downloadFinanceReport:arguments error:error];

    // Xcode (local)
    if ([name isEqualToString:@"list_schemes"]) return [ASCXcodeTools listSchemes:arguments error:error];

    if (error) *error = [NSError errorWithDomain:@"ASCToolRegistry" code:404
                                       userInfo:@{NSLocalizedDescriptionKey:
                                                  [NSString stringWithFormat:@"Unknown tool: %@", name]}];
    return nil;
}

#pragma mark - Configure tool

- (nullable NSString *)_configure:(NSDictionary *)args error:(NSError **)error {
    NSString *keyId    = args[@"key_id"];
    NSString *issuerId = args[@"issuer_id"];
    NSString *p8Path   = args[@"p8_path"];
    NSString *vendor   = args[@"vendor_number"]; // optional

    if (!keyId.length || !issuerId.length || !p8Path.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCToolRegistry" code:1
                                           userInfo:@{NSLocalizedDescriptionKey:
                                                      @"key_id, issuer_id, and p8_path are all required."}];
        return nil;
    }

    NSError *saveError = nil;
    BOOL ok = [[ASCCredentialStore shared] saveWithKeyId:keyId
                                               issuerId:issuerId
                                                p8Path:p8Path
                                          vendorNumber:vendor
                                                 error:&saveError];
    if (!ok) { if (error) *error = saveError; return nil; }

    // Delete the .p8 file from disk now that it's safely stored in Keychain.
    NSError *removeError = nil;
    BOOL deleted = [[NSFileManager defaultManager] removeItemAtPath:p8Path error:&removeError];
    NSString *deletedNote = deleted
        ? [NSString stringWithFormat:@"\n🗑 Deleted %@ from disk — the key is now stored only in your Keychain.", p8Path]
        : [NSString stringWithFormat:@"\n⚠️ Could not delete %@ from disk (%@). Please remove it manually.",
           p8Path, removeError.localizedDescription ?: @"unknown error"];

    return [@"✓ Credentials saved to Keychain." stringByAppendingString:deletedNote];
}

#pragma mark - Setup tool schema

- (NSDictionary *)_setupTool {
    return @{
        @"name": @"configure_app_store_connect",
        @"description": @"Set up App Store Connect API credentials. Required before using any other tools.\n\nHow to get credentials:\n1. Go to App Store Connect → Users and Access → Integrations → App Store Connect API\n2. Generate an API Key (Team key or Individual key)\n3. Download the .p8 file (you can only download it once)\n4. Note the Key ID and Issuer ID shown on the page\n\nAfter saving, the .p8 file is automatically deleted from disk — the private key is stored only in your macOS Keychain.",
        @"inputSchema": @{
            @"type": @"object",
            @"properties": @{
                @"key_id": @{
                    @"type": @"string",
                    @"description": @"10-character API Key ID (e.g. ABC1234567)"
                },
                @"issuer_id": @{
                    @"type": @"string",
                    @"description": @"UUID Issuer ID from the App Store Connect API keys page"
                },
                @"p8_path": @{
                    @"type": @"string",
                    @"description": @"Absolute path to the downloaded .p8 private key file (e.g. /Users/you/Downloads/AuthKey_ABC1234567.p8). The file will be deleted from disk automatically after its contents are stored in the Keychain."
                },
                @"vendor_number": @{
                    @"type": @"string",
                    @"description": @"Optional vendor number — only needed for sales and finance reports. Find it in App Store Connect under Payments and Financial Reports."
                }
            },
            @"required": @[@"key_id", @"issuer_id", @"p8_path"]
        }
    };
}

#pragma mark - Full tool list

- (NSArray<NSDictionary *> *)_allASCTools {
    // Helper block for simple string/integer properties
    NSDictionary *(^strProp)(NSString *) = ^(NSString *desc) {
        return @{@"type": @"string", @"description": desc};
    };
    NSDictionary *(^intProp)(NSString *, NSInteger, NSInteger) = ^(NSString *desc, NSInteger mn, NSInteger mx) {
        return @{@"type": @"integer", @"description": desc, @"minimum": @(mn), @"maximum": @(mx)};
    };

    return @[
        // ── Apps ─────────────────────────────────────────────────────────
        @{
            @"name": @"list_apps",
            @"description": @"List all apps in App Store Connect, optionally filtered by bundle ID.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"limit": intProp(@"Maximum results (default 100, max 200)", 1, 200),
                    @"bundle_id": strProp(@"Filter by bundle identifier (e.g. com.example.app)")
                },
                @"required": @[]
            }
        },
        @{
            @"name": @"get_app_info",
            @"description": @"Get detailed information about a specific app.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"app_id": strProp(@"The numeric App Store Connect app ID")
                },
                @"required": @[@"app_id"]
            }
        },

        // ── Beta ─────────────────────────────────────────────────────────
        @{
            @"name": @"list_beta_groups",
            @"description": @"List all beta testing groups (internal and external).",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"limit": intProp(@"Maximum results (default 100, max 200)", 1, 200),
                    @"app_id": strProp(@"Filter by app ID")
                },
                @"required": @[]
            }
        },
        @{
            @"name": @"list_group_testers",
            @"description": @"List testers in a specific beta group.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"group_id": strProp(@"The beta group ID"),
                    @"limit": intProp(@"Maximum results (default 100, max 200)", 1, 200)
                },
                @"required": @[@"group_id"]
            }
        },
        @{
            @"name": @"add_tester_to_group",
            @"description": @"Add a new tester to a beta group.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"group_id":   strProp(@"The beta group ID"),
                    @"email":      strProp(@"Tester email address"),
                    @"first_name": strProp(@"Tester first name"),
                    @"last_name":  strProp(@"Tester last name")
                },
                @"required": @[@"group_id", @"email"]
            }
        },
        @{
            @"name": @"remove_tester_from_group",
            @"description": @"Remove a tester from a beta group.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"group_id":  strProp(@"The beta group ID"),
                    @"tester_id": strProp(@"The tester ID to remove")
                },
                @"required": @[@"group_id", @"tester_id"]
            }
        },
        @{
            @"name": @"list_beta_feedback_screenshots",
            @"description": @"List beta feedback screenshot submissions for an app or build.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"app_id":   strProp(@"Filter by app ID"),
                    @"build_id": strProp(@"Filter by build ID"),
                    @"limit": intProp(@"Maximum results (default 50, max 200)", 1, 200)
                },
                @"required": @[]
            }
        },
        @{
            @"name": @"get_beta_feedback_screenshot",
            @"description": @"Get details about a specific beta feedback screenshot submission.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"feedback_id": strProp(@"The feedback submission ID")
                },
                @"required": @[@"feedback_id"]
            }
        },

        // ── Localizations ─────────────────────────────────────────────────
        @{
            @"name": @"create_app_store_version",
            @"description": @"Create a new App Store version for an app.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"app_id":         strProp(@"The app ID"),
                    @"platform":       strProp(@"Platform: IOS, MAC_OS, TV_OS, or VISION_OS"),
                    @"version_string": strProp(@"Version string e.g. '2.0.0'"),
                    @"release_type":   strProp(@"MANUAL, AFTER_APPROVAL, or SCHEDULED"),
                    @"copyright":      strProp(@"Copyright text"),
                    @"build_id":       strProp(@"Associate with this build ID")
                },
                @"required": @[@"app_id", @"platform", @"version_string"]
            }
        },
        @{
            @"name": @"list_app_store_versions",
            @"description": @"List all App Store versions for an app.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"app_id": strProp(@"The app ID"),
                    @"limit":  intProp(@"Maximum results (default 100, max 200)", 1, 200),
                    @"platform": strProp(@"Filter by platform: IOS, MAC_OS, TV_OS"),
                    @"state":    strProp(@"Filter by state e.g. READY_FOR_SALE, PREPARE_FOR_SUBMISSION")
                },
                @"required": @[@"app_id"]
            }
        },
        @{
            @"name": @"list_app_store_version_localizations",
            @"description": @"List all localizations for a specific App Store version.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"version_id": strProp(@"The App Store version ID"),
                    @"limit": intProp(@"Maximum results (default 100, max 200)", 1, 200)
                },
                @"required": @[@"version_id"]
            }
        },
        @{
            @"name": @"get_app_store_version_localization",
            @"description": @"Get details of a specific localization.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"localization_id": strProp(@"The localization ID")
                },
                @"required": @[@"localization_id"]
            }
        },
        @{
            @"name": @"update_app_store_version_localization",
            @"description": @"Update a field in an App Store version localization (description, keywords, whatsNew, etc.).",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"localization_id": strProp(@"The localization ID"),
                    @"field": strProp(@"Field to update: description, keywords, marketingUrl, promotionalText, supportUrl, or whatsNew"),
                    @"value": strProp(@"New value for the field")
                },
                @"required": @[@"localization_id", @"field", @"value"]
            }
        },

        // ── Bundle IDs ───────────────────────────────────────────────────
        @{
            @"name": @"create_bundle_id",
            @"description": @"Register a new bundle ID.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"identifier": strProp(@"Bundle ID string e.g. com.example.app"),
                    @"name":       strProp(@"Display name for this bundle ID"),
                    @"platform":   strProp(@"IOS, MAC_OS, or UNIVERSAL")
                },
                @"required": @[@"identifier", @"name", @"platform"]
            }
        },
        @{
            @"name": @"list_bundle_ids",
            @"description": @"List bundle IDs registered to your team.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"limit": intProp(@"Maximum results (default 100, max 200)", 1, 200),
                    @"sort":  strProp(@"Sort order: name, -name, identifier, -identifier, platform, -platform"),
                    @"filter_identifier": strProp(@"Filter by bundle ID string"),
                    @"filter_name":       strProp(@"Filter by name")
                },
                @"required": @[]
            }
        },
        @{
            @"name": @"get_bundle_id_info",
            @"description": @"Get details for a specific bundle ID.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"bundle_id_id": strProp(@"The bundle ID resource ID (not the identifier string)")
                },
                @"required": @[@"bundle_id_id"]
            }
        },
        @{
            @"name": @"enable_bundle_capability",
            @"description": @"Enable a capability for a bundle ID (e.g. PUSH_NOTIFICATIONS, ICLOUD, GAME_CENTER).",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"bundle_id_id":    strProp(@"The bundle ID resource ID"),
                    @"capability_type": strProp(@"Capability type e.g. PUSH_NOTIFICATIONS, ICLOUD, GAME_CENTER, HEALTHKIT, SIRIKIT, NFC_TAG_READING, ASSOCIATED_DOMAINS")
                },
                @"required": @[@"bundle_id_id", @"capability_type"]
            }
        },
        @{
            @"name": @"disable_bundle_capability",
            @"description": @"Disable a capability from a bundle ID.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"capability_id": strProp(@"The capability resource ID to disable")
                },
                @"required": @[@"capability_id"]
            }
        },

        // ── Devices ───────────────────────────────────────────────────────
        @{
            @"name": @"list_devices",
            @"description": @"List all devices registered to your team.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"limit":    intProp(@"Maximum results (default 100, max 200)", 1, 200),
                    @"sort":     strProp(@"Sort order: name, platform, status, udid, deviceClass, addedDate (prefix with - for descending)"),
                    @"platform": strProp(@"Filter by platform: IOS or MAC_OS"),
                    @"status":   strProp(@"Filter by status: ENABLED or DISABLED")
                },
                @"required": @[]
            }
        },

        // ── Users ─────────────────────────────────────────────────────────
        @{
            @"name": @"list_users",
            @"description": @"List team members in App Store Connect.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"limit":       intProp(@"Maximum results (default 100, max 200)", 1, 200),
                    @"sort":        strProp(@"Sort: username, firstName, lastName, roles (prefix - for descending)"),
                    @"filter_role": strProp(@"Filter by role e.g. ADMIN, DEVELOPER, FINANCE, READ_ONLY")
                },
                @"required": @[]
            }
        },

        // ── Analytics & Reports ──────────────────────────────────────────
        @{
            @"name": @"create_analytics_report_request",
            @"description": @"Create an analytics report request for an app.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"app_id":      strProp(@"The app ID"),
                    @"access_type": strProp(@"ONGOING or ONE_TIME_SNAPSHOT")
                },
                @"required": @[@"app_id", @"access_type"]
            }
        },
        @{
            @"name": @"list_analytics_reports",
            @"description": @"List available analytics reports from a report request.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"report_request_id": strProp(@"The analytics report request ID"),
                    @"limit": intProp(@"Maximum results (default 100)", 1, 200)
                },
                @"required": @[@"report_request_id"]
            }
        },
        @{
            @"name": @"list_analytics_report_segments",
            @"description": @"List downloadable segments for a specific analytics report.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"report_id": strProp(@"The analytics report ID"),
                    @"limit": intProp(@"Maximum results (default 100)", 1, 200)
                },
                @"required": @[@"report_id"]
            }
        },
        @{
            @"name": @"download_analytics_report_segment",
            @"description": @"Download data from an analytics report segment URL.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"url": strProp(@"The segment download URL from list_analytics_report_segments")
                },
                @"required": @[@"url"]
            }
        },
        @{
            @"name": @"download_sales_report",
            @"description": @"Download a sales and trends report. Requires vendor_number in credentials.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"frequency":     strProp(@"DAILY, WEEKLY, MONTHLY, or YEARLY"),
                    @"report_date":   strProp(@"Date: YYYY-MM-DD for daily, YYYY-MM for monthly/yearly"),
                    @"report_type":   strProp(@"SALES, SUBSCRIPTION, SUBSCRIPTION_EVENT, SUBSCRIBER, NEWSSTAND, or PREORDER"),
                    @"report_sub_type": strProp(@"SUMMARY or DETAILED")
                },
                @"required": @[@"frequency", @"report_date", @"report_type", @"report_sub_type"]
            }
        },
        @{
            @"name": @"download_finance_report",
            @"description": @"Download a finance report by region. Requires vendor_number in credentials.",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"report_date":  strProp(@"Report month: YYYY-MM"),
                    @"region_code":  strProp(@"Region code: Z1 (worldwide), WW (Europe), US, etc.")
                },
                @"required": @[@"report_date", @"region_code"]
            }
        },

        // ── Xcode (local) ─────────────────────────────────────────────────
        @{
            @"name": @"list_schemes",
            @"description": @"List all Xcode schemes in a project or workspace (runs locally via xcodebuild).",
            @"inputSchema": @{
                @"type": @"object",
                @"properties": @{
                    @"project_path": strProp(@"Absolute path to .xcodeproj or .xcworkspace file")
                },
                @"required": @[@"project_path"]
            }
        },
    ];
}

@end
