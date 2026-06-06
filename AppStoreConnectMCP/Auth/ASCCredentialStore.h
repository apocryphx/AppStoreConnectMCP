//
//  ASCCredentialStore.h
//  AppStoreConnectMCP
//
//  Reads and writes App Store Connect API credentials to the macOS Keychain.
//  Items are stored as kSecClassGenericPassword under the service
//  "com.apocryphx.appstoreconnect-bridge".
//

#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface ASCCredentialStore : NSObject

+ (instancetype)shared;

/// YES if Key ID, Issuer ID, and p8 data are all present in Keychain.
@property (nonatomic, readonly) BOOL hasCredentials;

/// The 10-character API Key identifier.
@property (nonatomic, readonly, nullable) NSString *keyId;

/// The UUID issuer ID from App Store Connect.
@property (nonatomic, readonly, nullable) NSString *issuerId;

/// The raw contents of the .p8 private key file.
@property (nonatomic, readonly, nullable) NSData *p8Data;

/// Optional vendor number for sales/finance reports.
@property (nonatomic, readonly, nullable) NSString *vendorNumber;

/// Save all credentials to Keychain. Reads p8 from disk at p8Path.
/// Returns YES on success; NO with *error populated on failure.
- (BOOL)saveWithKeyId:(NSString *)keyId
             issuerId:(NSString *)issuerId
              p8Path:(NSString *)p8Path
        vendorNumber:(nullable NSString *)vendorNumber
               error:(NSError **)error;

/// Remove all stored credentials.
- (void)clearCredentials;

@end

NS_ASSUME_NONNULL_END
