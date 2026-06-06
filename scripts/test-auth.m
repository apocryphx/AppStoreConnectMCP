//
//  test-auth.m  —  App Store Connect Bridge authentication smoke test
//
//  Reads credentials from the Keychain, signs an ES256 JWT, and calls
//  GET /v1/apps to verify the full auth chain end-to-end.
//
//  Compile & run (no Xcode needed):
//
//    clang -framework Foundation -framework Security \
//          scripts/test-auth.m -o /tmp/asc-test-auth && /tmp/asc-test-auth
//
//  Or use the companion shell script:
//
//    bash scripts/test-auth.sh
//

#import <Foundation/Foundation.h>
#import <Security/Security.h>

// ─── Keychain ────────────────────────────────────────────────────────────────

static NSData *keychainItem(NSString *account) {
    NSDictionary *q = @{
        (__bridge id)kSecClass:       (__bridge id)kSecClassGenericPassword,
        (__bridge id)kSecAttrService: @"com.apocryphx.appstoreconnect-bridge",
        (__bridge id)kSecAttrAccount: account,
        (__bridge id)kSecReturnData:  @YES,
        (__bridge id)kSecMatchLimit:  (__bridge id)kSecMatchLimitOne,
    };
    CFTypeRef result = NULL;
    OSStatus status = SecItemCopyMatching((__bridge CFDictionaryRef)q, &result);
    if (status != errSecSuccess) return nil;
    return (__bridge_transfer NSData *)result;
}

static NSString *keychainString(NSString *account) {
    NSData *d = keychainItem(account);
    return d ? [[NSString alloc] initWithData:d encoding:NSUTF8StringEncoding] : nil;
}

// ─── PKCS#8 → X9.63 unwrapper ────────────────────────────────────────────────

#define DER_LEN(dst) do { \
    if (p >= n) { fprintf(stderr, "  DER_LEN: out of bounds at p=%zu n=%zu\n", p, n); goto bad; } \
    if (!(b[p] & 0x80)) { dst = b[p++]; } \
    else { \
        size_t _nb = b[p++] & 0x7F; \
        if (!_nb || _nb > 4 || p + _nb > n) goto bad; \
        dst = 0; \
        for (size_t _i = 0; _i < _nb; _i++) dst = (dst << 8) | b[p++]; \
    } \
} while(0)

static NSData *x963FromPKCS8(NSData *pkcs8) {
    const uint8_t *b = pkcs8.bytes;
    size_t n = pkcs8.length, p = 0;

    printf("  PKCS#8 length: %zu bytes\n", n);

    // Outer SEQUENCE
    if (p >= n || b[p++] != 0x30) { fprintf(stderr, "  Expected SEQUENCE at pos 0\n"); goto bad; }
    { size_t _s; DER_LEN(_s); printf("  Outer SEQUENCE length: %zu\n", _s); }

    // version INTEGER 0
    if (p + 3 > n || b[p] != 0x02 || b[p+1] != 0x01 || b[p+2] != 0x00)
        { fprintf(stderr, "  Expected version INTEGER 0 at pos %zu (got %02X %02X %02X)\n", p, b[p], b[p+1], b[p+2]); goto bad; }
    p += 3;
    printf("  Version: 0 ✓\n");

    // AlgorithmIdentifier SEQUENCE — skip
    if (p >= n || b[p++] != 0x30) { fprintf(stderr, "  Expected AlgId SEQUENCE\n"); goto bad; }
    { size_t algLen; DER_LEN(algLen); printf("  AlgId length: %zu\n", algLen); if (p + algLen > n) goto bad; p += algLen; }

    // OCTET STRING
    if (p >= n || b[p++] != 0x04) { fprintf(stderr, "  Expected OCTET STRING at pos %zu\n", p-1); goto bad; }
    { size_t _s; DER_LEN(_s); printf("  OCTET STRING (SEC1) length: %zu\n", _s); }

    // SEC1 outer SEQUENCE
    if (p >= n || b[p++] != 0x30) { fprintf(stderr, "  Expected SEC1 SEQUENCE at pos %zu\n", p-1); goto bad; }
    { size_t _s; DER_LEN(_s); printf("  SEC1 SEQUENCE length: %zu\n", _s); }

    // SEC1 version INTEGER 1
    if (p + 3 > n || b[p] != 0x02 || b[p+1] != 0x01 || b[p+2] != 0x01)
        { fprintf(stderr, "  Expected SEC1 version 1 at pos %zu (got %02X %02X %02X)\n", p, b[p], b[p+1], b[p+2]); goto bad; }
    p += 3;
    printf("  SEC1 version: 1 ✓\n");

    // d OCTET STRING (32 bytes)
    if (p >= n || b[p++] != 0x04) { fprintf(stderr, "  Expected d OCTET STRING\n"); goto bad; }
    { size_t dLen; DER_LEN(dLen);
      printf("  d length: %zu%s\n", dLen, dLen == 32 ? " ✓" : " ✗ (expected 32)");
      if (dLen != 32 || p + 32 > n) goto bad; }
    const uint8_t *dBytes = b + p;
    p += 32;

    // Optional [0] ECParameters — skip if present
    if (p < n && b[p] == 0xA0) {
        p++;
        size_t ctxLen; DER_LEN(ctxLen);
        printf("  [0] ECParameters: %zu bytes (skipped) ✓\n", ctxLen);
        if (p + ctxLen > n) goto bad;
        p += ctxLen;
    }

    // [1] publicKey
    if (p >= n || b[p++] != 0xA1)
        { fprintf(stderr, "  Expected [1] tag at pos %zu (got %02X)\n", p-1, p > 0 ? b[p-1] : 0xFF); goto bad; }
    { size_t _s; DER_LEN(_s); printf("  [1] context length: %zu\n", _s); }

    // BIT STRING
    if (p >= n || b[p++] != 0x03) { fprintf(stderr, "  Expected BIT STRING\n"); goto bad; }
    { size_t bsLen; DER_LEN(bsLen);
      printf("  BIT STRING length: %zu%s\n", bsLen, bsLen == 66 ? " ✓" : " ✗ (expected 66)");
      if (bsLen != 66 || p + 66 > n) goto bad; }
    if (b[p++] != 0x00) { fprintf(stderr, "  Expected unused-bits=0\n"); goto bad; }
    if (b[p] != 0x04)   { fprintf(stderr, "  Expected uncompressed point marker 0x04\n"); goto bad; }
    const uint8_t *qBytes = b + p;  // 04‖Qx‖Qy (65 bytes)

    {
        uint8_t x963[97];
        memcpy(x963,      qBytes, 65);
        memcpy(x963 + 65, dBytes, 32);
        printf("  X9.63 assembled: 97 bytes ✓\n");
        return [NSData dataWithBytes:x963 length:97];
    }

bad:
    return nil;
}

// ─── JWT ──────────────────────────────────────────────────────────────────────

static NSString *base64url(NSData *d) {
    NSString *s = [d base64EncodedStringWithOptions:0];
    s = [s stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
    s = [s stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
    s = [s stringByReplacingOccurrencesOfString:@"=" withString:@""];
    return s;
}

static NSData *jsonBytes(NSDictionary *d) {
    return [NSJSONSerialization dataWithJSONObject:d options:NSJSONWritingSortedKeys error:nil];
}

static NSData *derSigToRaw(NSData *der) {
    const uint8_t *b = der.bytes;
    NSUInteger len = der.length, pos = 2;
    if (len < 2 || b[0] != 0x30) return nil;
    if (b[1] & 0x80) pos += (b[1] & 0x7F);

    if (pos + 2 > len || b[pos] != 0x02) return nil;
    pos++;
    NSUInteger rLen = b[pos++];
    if (pos + rLen > len) return nil;
    const uint8_t *rBytes = b + pos; pos += rLen;

    if (pos + 2 > len || b[pos] != 0x02) return nil;
    pos++;
    NSUInteger sLen = b[pos++];
    if (pos + sLen > len) return nil;
    const uint8_t *sBytes = b + pos;

    uint8_t raw[64] = {0};
    NSUInteger rStart = rLen > 32 ? rLen - 32 : 0, rCount = MIN(rLen, 32U);
    memcpy(raw + (32 - rCount), rBytes + rStart, rCount);
    NSUInteger sStart = sLen > 32 ? sLen - 32 : 0, sCount = MIN(sLen, 32U);
    memcpy(raw + 32 + (32 - sCount), sBytes + sStart, sCount);
    return [NSData dataWithBytes:raw length:64];
}

// ─── Main ─────────────────────────────────────────────────────────────────────

int main(void) {
    @autoreleasepool {
        printf("\n╔═══════════════════════════════════════════╗\n");
        printf("║  App Store Connect Bridge — Auth Test     ║\n");
        printf("╚═══════════════════════════════════════════╝\n\n");

        // 1. Load credentials
        printf("── 1. Keychain ─────────────────────────────\n");
        NSString *keyId    = keychainString(@"keyId");
        NSString *issuerId = keychainString(@"issuerId");
        NSData   *p8Data   = keychainItem(@"p8Data");

        if (!keyId || !issuerId || !p8Data) {
            fprintf(stderr, "✗ Credentials not found in Keychain.\n");
            fprintf(stderr, "  Run configure_app_store_connect in Claude Desktop first.\n");
            return 1;
        }
        printf("  Key ID:    %s ✓\n", keyId.UTF8String);
        printf("  Issuer ID: %s ✓\n", issuerId.UTF8String);
        printf("  p8Data:    %lu bytes ✓\n\n", (unsigned long)p8Data.length);

        // 2. Parse PEM → DER
        printf("── 2. PEM → DER ────────────────────────────\n");
        NSString *pem = [[NSString alloc] initWithData:p8Data encoding:NSUTF8StringEncoding];
        NSMutableString *b64 = [pem mutableCopy];
        for (NSString *s in @[@"-----BEGIN PRIVATE KEY-----", @"-----END PRIVATE KEY-----",
                               @"-----BEGIN EC PRIVATE KEY-----", @"-----END EC PRIVATE KEY-----"])
            [b64 replaceOccurrencesOfString:s withString:@"" options:0
                                      range:NSMakeRange(0, b64.length)];
        NSString *clean = [[b64 componentsSeparatedByCharactersInSet:
                            [NSCharacterSet whitespaceAndNewlineCharacterSet]]
                           componentsJoinedByString:@""];
        NSData *der = [[NSData alloc] initWithBase64EncodedString:clean options:0];
        if (!der) { fprintf(stderr, "✗ PEM decode failed\n"); return 1; }
        printf("  DER: %lu bytes ✓\n\n", (unsigned long)der.length);

        // 3. Unwrap PKCS#8 → X9.63
        printf("── 3. PKCS#8 → X9.63 ──────────────────────\n");
        NSData *x963 = x963FromPKCS8(der);
        if (!x963) { fprintf(stderr, "\n✗ PKCS#8 parse failed — see output above\n"); return 1; }
        printf("\n");

        // 4. Create SecKey
        printf("── 4. SecKeyCreateWithData ─────────────────\n");
        NSDictionary *attrs = @{
            (__bridge id)kSecAttrKeyType:  (__bridge id)kSecAttrKeyTypeEC,
            (__bridge id)kSecAttrKeyClass: (__bridge id)kSecAttrKeyClassPrivate,
        };
        CFErrorRef cfErr = NULL;
        SecKeyRef key = SecKeyCreateWithData((__bridge CFDataRef)x963,
                                             (__bridge CFDictionaryRef)attrs, &cfErr);
        if (!key) {
            NSError *err = (__bridge_transfer NSError *)cfErr;
            fprintf(stderr, "✗ SecKeyCreateWithData failed: %s\n", err.localizedDescription.UTF8String);
            return 1;
        }
        printf("  SecKeyRef: created ✓\n\n");

        // 5. Build and sign JWT
        printf("── 5. JWT ──────────────────────────────────\n");
        NSString *header  = base64url(jsonBytes(@{@"alg":@"ES256", @"kid":keyId, @"typ":@"JWT"}));
        NSTimeInterval now = [[NSDate date] timeIntervalSince1970];
        NSString *payload = base64url(jsonBytes(@{
            @"iss": issuerId,
            @"iat": @((NSInteger)now),
            @"exp": @((NSInteger)(now + 1200)),
            @"aud": @"appstoreconnect-v1",
        }));
        NSString *sigInput = [NSString stringWithFormat:@"%@.%@", header, payload];
        NSData *sigInputData = [sigInput dataUsingEncoding:NSUTF8StringEncoding];

        CFErrorRef sigErr = NULL;
        NSData *derSig = (__bridge_transfer NSData *)
            SecKeyCreateSignature(key,
                                  kSecKeyAlgorithmECDSASignatureMessageX962SHA256,
                                  (__bridge CFDataRef)sigInputData, &sigErr);
        CFRelease(key);
        if (!derSig) {
            NSError *err = (__bridge_transfer NSError *)sigErr;
            fprintf(stderr, "✗ Signing failed: %s\n", err.localizedDescription.UTF8String);
            return 1;
        }

        NSData *rawSig = derSigToRaw(derSig);
        if (!rawSig) { fprintf(stderr, "✗ DER→R‖S conversion failed\n"); return 1; }

        NSString *jwt = [NSString stringWithFormat:@"%@.%@.%@", header, payload, base64url(rawSig)];
        printf("  Header:  %s\n", header.UTF8String);
        printf("  Payload: %s\n", payload.UTF8String);
        printf("  JWT length: %lu chars ✓\n\n", (unsigned long)jwt.length);

        // 6. API call: GET /v1/apps
        printf("── 6. GET /v1/apps ─────────────────────────\n");
        NSURL *url = [NSURL URLWithString:@"https://api.appstoreconnect.apple.com/v1/apps?limit=5"];
        NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url
                                                           cachePolicy:NSURLRequestUseProtocolCachePolicy
                                                       timeoutInterval:30];
        [req setValue:[@"Bearer " stringByAppendingString:jwt] forHTTPHeaderField:@"Authorization"];
        [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];

        dispatch_semaphore_t sem = dispatch_semaphore_create(0);
        __block NSData *respData = nil;
        __block NSHTTPURLResponse *httpResp = nil;
        __block NSError *netErr = nil;

        [[[NSURLSession sharedSession]
          dataTaskWithRequest:req
          completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
              respData = d;
              httpResp = (NSHTTPURLResponse *)r;
              netErr = e;
              dispatch_semaphore_signal(sem);
          }] resume];
        dispatch_semaphore_wait(sem, DISPATCH_TIME_FOREVER);

        if (netErr) {
            fprintf(stderr, "✗ Network error: %s\n", netErr.localizedDescription.UTF8String);
            return 1;
        }

        printf("  HTTP %ld\n", (long)httpResp.statusCode);

        NSDictionary *json = [NSJSONSerialization JSONObjectWithData:respData options:0 error:nil];

        if (httpResp.statusCode == 200) {
            NSArray *data = json[@"data"];
            printf("\n✅ Auth successful! Found %lu app(s):\n", (unsigned long)data.count);
            for (NSDictionary *app in data) {
                NSDictionary *attrs = app[@"attributes"];
                printf("   • %s  (%s)\n",
                       [attrs[@"name"] UTF8String] ?: "?",
                       [attrs[@"bundleId"] UTF8String] ?: "?");
            }
        } else {
            NSArray *errors = json[@"errors"];
            fprintf(stderr, "\n✗ API error:\n");
            for (NSDictionary *e in errors) {
                fprintf(stderr, "  [%s] %s — %s\n",
                        [e[@"status"] UTF8String] ?: "?",
                        [e[@"title"]  UTF8String] ?: "?",
                        [e[@"detail"] UTF8String] ?: "?");
            }
            // Print raw body for debugging
            NSString *raw = [[NSString alloc] initWithData:respData encoding:NSUTF8StringEncoding];
            fprintf(stderr, "\n  Raw response: %s\n", raw.UTF8String ?: "(binary)");
            return 1;
        }

        printf("\n");
        return 0;
    }
}
