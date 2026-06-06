//
//  ASCCredentialStore.m
//  AppStoreConnectMCP
//

#import "ASCCredentialStore.h"
#import <Security/Security.h>

static NSString *const kService   = @"com.apocryphx.appstoreconnect-bridge";
static NSString *const kKeyId     = @"keyId";
static NSString *const kIssuerId  = @"issuerId";
static NSString *const kP8Data    = @"p8Data";
static NSString *const kVendorNum = @"vendorNumber";

@implementation ASCCredentialStore

+ (instancetype)shared {
    static ASCCredentialStore *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[ASCCredentialStore alloc] init]; });
    return s;
}

- (BOOL)hasCredentials {
    return self.keyId != nil && self.issuerId != nil && self.p8Data != nil;
}

- (nullable NSString *)keyId     { return [self _stringForAccount:kKeyId]; }
- (nullable NSString *)issuerId  { return [self _stringForAccount:kIssuerId]; }
- (nullable NSData *)p8Data      { return [self _dataForAccount:kP8Data]; }
- (nullable NSString *)vendorNumber { return [self _stringForAccount:kVendorNum]; }

- (BOOL)saveWithKeyId:(NSString *)keyId
             issuerId:(NSString *)issuerId
              p8Path:(NSString *)p8Path
        vendorNumber:(nullable NSString *)vendorNumber
               error:(NSError **)error {

    // Expand ~ and resolve symlinks
    NSString *expandedPath = [p8Path stringByExpandingTildeInPath];

    // Read and validate the .p8 file
    NSError *readError = nil;
    NSData *p8Data = [NSData dataWithContentsOfFile:expandedPath
                                            options:0
                                              error:&readError];
    if (!p8Data) {
        if (error) *error = readError ?: [NSError errorWithDomain:@"ASCCredentialStore"
                                                             code:1
                                                         userInfo:@{NSLocalizedDescriptionKey:
                                                                     [NSString stringWithFormat:@"Cannot read file at %@", expandedPath]}];
        return NO;
    }

    // Validate: confirm it looks like a PEM EC private key
    NSString *pem = [[NSString alloc] initWithData:p8Data encoding:NSUTF8StringEncoding];
    if (!pem || [pem rangeOfString:@"PRIVATE KEY"].location == NSNotFound) {
        if (error) *error = [NSError errorWithDomain:@"ASCCredentialStore"
                                                code:2
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                       @"File does not appear to be a PEM private key (.p8)"}];
        return NO;
    }

    // Store each item
    BOOL ok = YES;
    ok = ok && [self _saveString:keyId forAccount:kKeyId error:error];
    ok = ok && [self _saveString:issuerId forAccount:kIssuerId error:error];
    ok = ok && [self _saveData:p8Data forAccount:kP8Data error:error];
    if (vendorNumber.length) {
        ok = ok && [self _saveString:vendorNumber forAccount:kVendorNum error:error];
    }
    return ok;
}

- (void)clearCredentials {
    for (NSString *account in @[kKeyId, kIssuerId, kP8Data, kVendorNum]) {
        NSDictionary *query = @{
            (__bridge id)kSecClass:       (__bridge id)kSecClassGenericPassword,
            (__bridge id)kSecAttrService: kService,
            (__bridge id)kSecAttrAccount: account,
        };
        SecItemDelete((__bridge CFDictionaryRef)query);
    }
}

#pragma mark - Private helpers

- (nullable NSString *)_stringForAccount:(NSString *)account {
    NSData *data = [self _dataForAccount:account];
    if (!data) return nil;
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
}

- (nullable NSData *)_dataForAccount:(NSString *)account {
    NSDictionary *query = @{
        (__bridge id)kSecClass:            (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService:      kService,
        (__bridge id)kSecAttrAccount:      account,
        (__bridge id)kSecReturnData:       @YES,
        (__bridge id)kSecMatchLimit:       (__bridge id)kSecMatchLimitOne,
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)query, &result);
    if (status != errSecSuccess || !result) return nil;
    return (__bridge_transfer NSData *)result;
}

- (BOOL)_saveData:(NSData *)data forAccount:(NSString *)account error:(NSError **)error {
    // Try update first, then add
    NSDictionary *query = @{
        (__bridge id)kSecClass:       (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: kService,
        (__bridge id)kSecAttrAccount: account,
    };
    NSDictionary *update = @{(__bridge id)kSecValueData: data};
    OSStatus status = SecItemUpdate((__bridge CFDictionaryRef)query,
                                    (__bridge CFDictionaryRef)update);
    if (status == errSecItemNotFound) {
        NSMutableDictionary *add = [query mutableCopy];
        add[(__bridge id)kSecValueData] = data;
        status = SecItemAdd((__bridge CFDictionaryRef)add, NULL);
    }
    if (status != errSecSuccess) {
        if (error) *error = [NSError errorWithDomain:NSOSStatusErrorDomain
                                                code:status
                                            userInfo:@{NSLocalizedDescriptionKey:
                                                       [NSString stringWithFormat:@"Keychain error %d saving %@", (int)status, account]}];
        return NO;
    }
    return YES;
}

- (BOOL)_saveString:(NSString *)string forAccount:(NSString *)account error:(NSError **)error {
    NSData *data = [string dataUsingEncoding:NSUTF8StringEncoding];
    return [self _saveData:data forAccount:account error:error];
}

@end
