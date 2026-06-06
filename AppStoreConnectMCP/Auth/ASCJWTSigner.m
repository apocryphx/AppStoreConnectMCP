//
//  ASCJWTSigner.m
//  AppStoreConnectMCP
//
//  ES256 JWT signing for App Store Connect API.
//
//  Apple's .p8 file is a PKCS#8 PEM-encoded EC (P-256) private key.
//  Signing steps:
//    1. Strip PEM armor, base64-decode → DER PKCS#8 bytes
//    2. SecKeyCreateWithData → SecKeyRef (EC private key)
//    3. Build JWT header + payload, base64url-encode each
//    4. SecKeyCreateSignature with kSecKeyAlgorithmECDSASignatureMessageX962SHA256
//       → DER-encoded ECDSA signature
//    5. Convert DER signature to raw R‖S (32 + 32 bytes) for JWT format
//    6. Assemble: header_b64.payload_b64.signature_b64url
//

#import "ASCJWTSigner.h"
#import "ASCCredentialStore.h"
#import <Security/Security.h>

@implementation ASCJWTSigner

+ (instancetype)shared {
    static ASCJWTSigner *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[ASCJWTSigner alloc] init]; });
    return s;
}

- (nullable NSString *)bearerTokenError:(NSError **)error {
    ASCCredentialStore *store = [ASCCredentialStore shared];
    NSString *keyId    = store.keyId;
    NSString *issuerId = store.issuerId;
    NSData   *p8Data   = store.p8Data;

    if (!keyId || !issuerId || !p8Data) {
        if (error) *error = [NSError errorWithDomain:@"ASCJWTSigner" code:1
                                           userInfo:@{NSLocalizedDescriptionKey:
                                                      @"Credentials not configured. Call configure_app_store_connect first."}];
        return nil;
    }

    // 1. Parse PEM → DER
    NSData *derData = [self _derFromPEM:p8Data error:error];
    if (!derData) return nil;

    // 2. Create SecKey from DER PKCS#8
    SecKeyRef privateKey = [self _privateKeyFromDER:derData error:error];
    if (!privateKey) return nil;

    // 3. Build header and payload
    NSString *header  = [self _base64url:[self _jsonBytes:@{@"alg": @"ES256",
                                                             @"kid": keyId,
                                                             @"typ": @"JWT"}]];
    NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
    NSString *payload = [self _base64url:[self _jsonBytes:@{
        @"iss": issuerId,
        @"iat": @((NSInteger)now),
        @"exp": @((NSInteger)(now + 1200)),   // 20-minute token
        @"aud": @"appstoreconnect-v1"
    }]];

    NSString *signingInput = [NSString stringWithFormat:@"%@.%@", header, payload];
    NSData *signingInputData = [signingInput dataUsingEncoding:NSUTF8StringEncoding];

    // 4. Sign with ECDSA (Security.framework hashes internally for MessageX962SHA256)
    CFErrorRef cfError = NULL;
    NSData *derSig = (__bridge_transfer NSData *)
        SecKeyCreateSignature(privateKey,
                              kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                              (__bridge CFDataRef)signingInputData,
                              &cfError);
    CFRelease(privateKey);

    if (!derSig) {
        if (error && cfError) *error = (__bridge_transfer NSError *)cfError;
        else if (error) *error = [NSError errorWithDomain:@"ASCJWTSigner" code:3
                                                userInfo:@{NSLocalizedDescriptionKey: @"Signing failed"}];
        return nil;
    }

    // 5. Convert DER ECDSA signature → raw R‖S (64 bytes)
    NSData *rawSig = [self _rawSignatureFromDER:derSig error:error];
    if (!rawSig) return nil;

    // 6. Assemble JWT
    NSString *sigB64 = [self _base64url:rawSig];
    return [NSString stringWithFormat:@"%@.%@.%@", header, payload, sigB64];
}

#pragma mark - Private helpers

/// Strip PEM header/footer and base64-decode to DER.
- (nullable NSData *)_derFromPEM:(NSData *)pemData error:(NSError **)error {
    NSString *pem = [[NSString alloc] initWithData:pemData encoding:NSUTF8StringEncoding];
    // Remove header, footer, and all whitespace/newlines
    NSMutableString *b64 = [pem mutableCopy];
    NSArray *strips = @[@"-----BEGIN PRIVATE KEY-----",
                        @"-----END PRIVATE KEY-----",
                        @"-----BEGIN EC PRIVATE KEY-----",
                        @"-----END EC PRIVATE KEY-----"];
    for (NSString *s in strips) [b64 replaceOccurrencesOfString:s
                                                     withString:@""
                                                        options:0
                                                          range:NSMakeRange(0, b64.length)];
    // Remove all whitespace
    NSString *clean = [[b64 componentsSeparatedByCharactersInSet:
                        [NSCharacterSet whitespaceAndNewlineCharacterSet]]
                       componentsJoinedByString:@""];
    NSData *der = [[NSData alloc] initWithBase64EncodedString:clean options:0];
    if (!der) {
        if (error) *error = [NSError errorWithDomain:@"ASCJWTSigner" code:2
                                           userInfo:@{NSLocalizedDescriptionKey: @"Failed to decode PEM key"}];
        return nil;
    }
    return der;
}

/// Create a SecKeyRef from DER-encoded PKCS#8 private key data.
- (nullable SecKeyRef)_privateKeyFromDER:(NSData *)der error:(NSError **)error {
    NSDictionary *attrs = @{
        (__bridge id)kSecAttrKeyType:  (__bridge id)kSecAttrKeyTypeEC,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPrivate,
    };
    CFErrorRef cfError = NULL;
    SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)der,
                                         (__bridge CFDictionaryRef)attrs,
                                         &cfError);
    if (!key) {
        if (error && cfError) *error = (__bridge_transfer NSError *)cfError;
        else if (error) *error = [NSError errorWithDomain:@"ASCJWTSigner" code:3
                                                userInfo:@{NSLocalizedDescriptionKey: @"Invalid .p8 key data"}];
        return NULL;
    }
    return key;
}

/// Convert DER-encoded ECDSA signature to raw R||S format (64 bytes).
/// DER format: 30 LEN 02 RLEN R-BYTES 02 SLEN S-BYTES
- (nullable NSData *)_rawSignatureFromDER:(NSData *)der error:(NSError **)error {
    const uint8_t *bytes = der.bytes;
    NSUInteger len = der.length;

    if (len < 2 || bytes[0] != 0x30) goto fail;
    NSUInteger pos = 2;                          // skip 30 <seqlen>
    if (bytes[1] & 0x80) pos += (bytes[1] & 0x7F);  // long-form length

    // Parse R
    if (pos + 2 > len || bytes[pos] != 0x02) goto fail;
    pos++;
    NSUInteger rLen = bytes[pos++];
    if (pos + rLen > len) goto fail;
    const uint8_t *rBytes = bytes + pos;
    pos += rLen;

    // Parse S
    if (pos + 2 > len || bytes[pos] != 0x02) goto fail;
    pos++;
    NSUInteger sLen = bytes[pos++];
    if (pos + sLen > len) goto fail;
    const uint8_t *sBytes = bytes + pos;

    {
        // Zero-pad R and S to 32 bytes each
        uint8_t raw[64] = {0};
        // R: skip leading zeros if rLen > 32, or right-align if rLen < 32
        NSUInteger rStart = (rLen > 32) ? (rLen - 32) : 0;
        NSUInteger rCount = MIN(rLen, 32U);
        memcpy(raw + (32 - rCount), rBytes + rStart, rCount);

        NSUInteger sStart = (sLen > 32) ? (sLen - 32) : 0;
        NSUInteger sCount = MIN(sLen, 32U);
        memcpy(raw + 32 + (32 - sCount), sBytes + sStart, sCount);

        return [NSData dataWithBytes:raw length:64];
    }

fail:
    if (error) *error = [NSError errorWithDomain:@"ASCJWTSigner" code:4
                                       userInfo:@{NSLocalizedDescriptionKey: @"Failed to parse DER signature"}];
    return nil;
}

/// Serialize an NSDictionary to compact JSON bytes.
- (NSData *)_jsonBytes:(NSDictionary *)obj {
    return [NSJSONSerialization dataWithJSONObject:obj options:0 error:nil] ?: [NSData data];
}

/// Base64url-encode data (RFC 4648 §5: no padding, + → -, / → _).
- (NSString *)_base64url:(NSData *)data {
    NSString *b64 = [data base64EncodedStringWithOptions:0];
    b64 = [b64 stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    b64 = [b64 stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    b64 = [b64 stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return b64;
}

@end
