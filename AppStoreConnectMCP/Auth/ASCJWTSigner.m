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

/// Unwrap a PKCS#8 DER-encoded EC private key into X9.63 format (97 bytes).
///
/// Apple's .p8 is PKCS#8: SEQUENCE { INTEGER(0), AlgorithmIdentifier, OCTET_STRING { SEC1 } }
/// SecKeyCreateWithData expects X9.63: 04 ‖ Qx(32) ‖ Qy(32) ‖ d(32)
///
/// We parse the outer PKCS#8, extract the SEC1 ECPrivateKey from the OCTET STRING,
/// then pull out d and Q and assemble the 97-byte X9.63 form.
- (nullable NSData *)_x963KeyFromPKCS8:(NSData *)pkcs8 error:(NSError **)error {
    const uint8_t *b = pkcs8.bytes;
    NSUInteger     n = pkcs8.length;
    NSUInteger     p = 0;

    // Reads a DER length at b[p], advances p past it, returns the value.
    // Returns NSUIntegerMax on any parse error.
#define DER_LEN(dst) do { \
    if (p >= n) goto bad; \
    if (!(b[p] & 0x80)) { dst = b[p++]; } \
    else { \
        NSUInteger _nb = b[p++] & 0x7F; \
        if (!_nb || _nb > 4 || p + _nb > n) goto bad; \
        dst = 0; \
        for (NSUInteger _i = 0; _i < _nb; _i++) dst = (dst << 8) | b[p++]; \
    } \
} while(0)

    // ── Outer PKCS#8 SEQUENCE ──────────────────────────────────────────────
    if (p >= n || b[p++] != 0x30) goto bad;
    { NSUInteger _skip; DER_LEN(_skip); (void)_skip; }      // outer length (don't need it)

    // version INTEGER 0
    if (p + 3 > n || b[p] != 0x02 || b[p+1] != 0x01 || b[p+2] != 0x00) goto bad;
    p += 3;

    // AlgorithmIdentifier SEQUENCE — skip whole thing
    if (p >= n || b[p++] != 0x30) goto bad;
    { NSUInteger algLen; DER_LEN(algLen); if (p + algLen > n) goto bad; p += algLen; }

    // privateKey OCTET STRING — advance past tag+length; p now = start of SEC1
    if (p >= n || b[p++] != 0x04) goto bad;
    { NSUInteger _skip; DER_LEN(_skip); (void)_skip; }

    // ── SEC1 ECPrivateKey ──────────────────────────────────────────────────
    // SEQUENCE { INTEGER(1), OCTET_STRING(d,32), [1] { BIT_STRING(04‖Qx‖Qy,65) } }

    if (p >= n || b[p++] != 0x30) goto bad;
    { NSUInteger _skip; DER_LEN(_skip); (void)_skip; }      // SEC1 outer length

    // version INTEGER 1
    if (p + 3 > n || b[p] != 0x02 || b[p+1] != 0x01 || b[p+2] != 0x01) goto bad;
    p += 3;

    // d: OCTET STRING (32 bytes)
    if (p >= n || b[p++] != 0x04) goto bad;
    { NSUInteger dLen; DER_LEN(dLen); if (dLen != 32 || p + 32 > n) goto bad; }
    const uint8_t *dBytes = b + p;
    p += 32;

    // Skip optional [0] ECParameters (Apple's .p8 includes it; RFC 5915 makes it optional)
    if (p < n && b[p] == 0xA0) {
        p++;
        NSUInteger ctxLen; DER_LEN(ctxLen);
        if (p + ctxLen > n) goto bad;
        p += ctxLen;
    }

    // [1] context-specific tag containing the public key BIT STRING
    if (p >= n || b[p++] != 0xA1) goto bad;
    { NSUInteger _skip; DER_LEN(_skip); (void)_skip; }

    // BIT STRING  (tag 0x03, length 66, unused-bits 0x00, then 04‖Qx‖Qy)
    if (p >= n || b[p++] != 0x03) goto bad;
    { NSUInteger bsLen; DER_LEN(bsLen); if (bsLen != 66 || p + 66 > n) goto bad; }
    if (b[p++] != 0x00) goto bad;                           // unused-bits byte
    if (b[p] != 0x04) goto bad;                             // uncompressed-point marker
    const uint8_t *qBytes = b + p;                          // 65 bytes: 04‖Qx‖Qy

    {
        // Assemble X9.63: 04 ‖ Qx ‖ Qy ‖ d  (97 bytes)
        uint8_t x963[97];
        memcpy(x963,      qBytes, 65);
        memcpy(x963 + 65, dBytes, 32);
        return [NSData dataWithBytes:x963 length:97];
    }

#undef DER_LEN

bad:
    if (error) *error = [NSError errorWithDomain:@"ASCJWTSigner" code:2
                                       userInfo:@{NSLocalizedDescriptionKey:
                                                  @"Failed to parse PKCS#8 key — unexpected ASN.1 structure"}];
    return nil;
}

/// Create a SecKeyRef from DER-encoded PKCS#8 private key data.
- (nullable SecKeyRef)_privateKeyFromDER:(NSData *)der error:(NSError **)error {
    // SecKeyCreateWithData requires X9.63 (04‖Qx‖Qy‖d, 97 bytes), not PKCS#8.
    NSData *x963 = [self _x963KeyFromPKCS8:der error:error];
    if (!x963) return NULL;

    NSDictionary *attrs = @{
        (__bridge id)kSecAttrKeyType:  (__bridge id)kSecAttrKeyTypeEC,
        (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPrivate,
    };
    CFErrorRef cfError = NULL;
    SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)x963,
                                         (__bridge CFDictionaryRef)attrs,
                                         &cfError);
    if (!key) {
        if (error && cfError) *error = (__bridge_transfer NSError *)cfError;
        else if (error) *error = [NSError errorWithDomain:@"ASCJWTSigner" code:3
                                                userInfo:@{NSLocalizedDescriptionKey: @"EC private key creation from X9.63 data failed"}];
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
