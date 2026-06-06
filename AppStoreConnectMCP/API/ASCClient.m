//
//  ASCClient.m
//  AppStoreConnectMCP
//

#import "ASCClient.h"
#import "ASCJWTSigner.h"

static NSString *const kBaseURL = @"https://api.appstoreconnect.apple.com/v1";
static const NSTimeInterval kTimeout = 60.0;

@interface ASCClient ()
@property (strong) NSURLSession *session;
@end

@implementation ASCClient

+ (instancetype)shared {
    static ASCClient *s;
    static dispatch_once_t once;
    dispatch_once(&once, ^{ s = [[ASCClient alloc] init]; });
    return s;
}

- (instancetype)init {
    self = [super init];
    if (!self) return nil;
    NSURLSessionConfiguration *cfg = [NSURLSessionConfiguration defaultSessionConfiguration];
    cfg.timeoutIntervalForRequest  = kTimeout;
    cfg.timeoutIntervalForResource = kTimeout;
    _session = [NSURLSession sessionWithConfiguration:cfg];
    return self;
}

#pragma mark - Public API

- (nullable NSDictionary *)GET:(NSString *)path
                        params:(nullable NSDictionary *)params
                         error:(NSError **)error {
    NSURL *url = [self _urlForPath:path params:params];
    NSMutableURLRequest *req = [self _requestWithURL:url method:@"GET" body:nil error:error];
    if (!req) return nil;
    return [self _send:req error:error];
}

- (nullable NSDictionary *)POST:(NSString *)path
                           body:(NSDictionary *)body
                          error:(NSError **)error {
    NSURL *url = [self _urlForPath:path params:nil];
    NSMutableURLRequest *req = [self _requestWithURL:url method:@"POST" body:body error:error];
    if (!req) return nil;
    return [self _send:req error:error];
}

- (nullable NSDictionary *)PATCH:(NSString *)path
                            body:(NSDictionary *)body
                           error:(NSError **)error {
    NSURL *url = [self _urlForPath:path params:nil];
    NSMutableURLRequest *req = [self _requestWithURL:url method:@"PATCH" body:body error:error];
    if (!req) return nil;
    return [self _send:req error:error];
}

- (BOOL)DELETE:(NSString *)path
          body:(nullable NSDictionary *)body
         error:(NSError **)error {
    NSURL *url = [self _urlForPath:path params:nil];
    NSMutableURLRequest *req = [self _requestWithURL:url method:@"DELETE" body:body error:error];
    if (!req) return NO;
    NSDictionary *result = [self _send:req error:error];
    // 204 No Content returns nil result with no error — that's success.
    return (result != nil || (error && *error == nil));
}

- (nullable NSString *)downloadText:(NSString *)absoluteURL error:(NSError **)error {
    NSError *jwtError = nil;
    NSString *token = [[ASCJWTSigner shared] bearerTokenError:&jwtError];
    if (!token) { if (error) *error = jwtError; return nil; }

    NSURL *url = [NSURL URLWithString:absoluteURL];
    if (!url) {
        if (error) *error = [NSError errorWithDomain:@"ASCClient" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"Invalid download URL"}];
        return nil;
    }
    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    [req setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    req.timeoutInterval = kTimeout;

    __block NSData *responseData = nil;
    __block NSError *responseError = nil;
    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[self.session dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        responseData = d;
        responseError = e;
        dispatch_semaphore_signal(sem);
    }] resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kTimeout * NSEC_PER_SEC)));

    if (responseError) { if (error) *error = responseError; return nil; }
    return responseData ? [[NSString alloc] initWithData:responseData encoding:NSUTF8StringEncoding] : nil;
}

#pragma mark - Private helpers

- (NSURL *)_urlForPath:(NSString *)path params:(nullable NSDictionary *)params {
    NSString *urlString = [kBaseURL stringByAppendingString:path];
    if (!params.count) return [NSURL URLWithString:urlString];

    NSURLComponents *comps = [NSURLComponents componentsWithString:urlString];
    NSMutableArray *items = [NSMutableArray array];
    [params enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
        if ([value isKindOfClass:[NSArray class]]) {
            for (id v in (NSArray *)value) {
                [items addObject:[NSURLQueryItem queryItemWithName:key value:[v description]]];
            }
        } else {
            [items addObject:[NSURLQueryItem queryItemWithName:key value:[value description]]];
        }
    }];
    comps.queryItems = items;
    return comps.URL ?: [NSURL URLWithString:urlString];
}

- (nullable NSMutableURLRequest *)_requestWithURL:(NSURL *)url
                                           method:(NSString *)method
                                             body:(nullable NSDictionary *)body
                                            error:(NSError **)error {
    NSError *jwtError = nil;
    NSString *token = [[ASCJWTSigner shared] bearerTokenError:&jwtError];
    if (!token) { if (error) *error = jwtError; return nil; }

    NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
    req.HTTPMethod = method;
    req.timeoutInterval = kTimeout;
    [req setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    if (body) {
        NSError *jsonError = nil;
        NSData *bodyData = [NSJSONSerialization dataWithJSONObject:body options:0 error:&jsonError];
        if (!bodyData) { if (error) *error = jsonError; return nil; }
        req.HTTPBody = bodyData;
        [req setValue:@"application/json" forHTTPHeaderField:@"Content-Type"];
    }
    return req;
}

- (nullable NSDictionary *)_send:(NSURLRequest *)req error:(NSError **)error {
    __block NSData *responseData = nil;
    __block NSHTTPURLResponse *httpResponse = nil;
    __block NSError *responseError = nil;

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    [[self.session dataTaskWithRequest:req completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
        responseData = d;
        httpResponse = (NSHTTPURLResponse *)r;
        responseError = e;
        dispatch_semaphore_signal(sem);
    }] resume];
    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, (int64_t)(kTimeout * NSEC_PER_SEC)));

    if (responseError) { if (error) *error = responseError; return nil; }

    NSInteger statusCode = httpResponse.statusCode;

    // 204 No Content — success with no body
    if (statusCode == 204) return @{};

    // Parse JSON body
    NSDictionary *json = nil;
    if (responseData.length) {
        json = [NSJSONSerialization JSONObjectWithData:responseData options:0 error:nil];
    }

    // Handle API errors (4xx, 5xx)
    if (statusCode < 200 || statusCode >= 300) {
        NSString *message = [self _errorMessageFromJSON:json statusCode:statusCode];
        if (error) *error = [NSError errorWithDomain:@"ASCClient"
                                                code:statusCode
                                            userInfo:@{NSLocalizedDescriptionKey: message}];
        return nil;
    }

    return [json isKindOfClass:[NSDictionary class]] ? json : @{};
}

- (NSString *)_errorMessageFromJSON:(nullable NSDictionary *)json statusCode:(NSInteger)code {
    NSArray *errors = json[@"errors"];
    if ([errors isKindOfClass:[NSArray class]] && errors.count) {
        NSDictionary *first = errors[0];
        NSString *title  = first[@"title"]  ?: @"";
        NSString *detail = first[@"detail"] ?: @"";
        if (detail.length) return [NSString stringWithFormat:@"[%ld] %@: %@", (long)code, title, detail];
        if (title.length)  return [NSString stringWithFormat:@"[%ld] %@", (long)code, title];
    }
    return [NSString stringWithFormat:@"HTTP %ld", (long)code];
}

@end
