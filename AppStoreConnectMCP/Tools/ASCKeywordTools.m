//
//  ASCKeywordTools.m
//  AppStoreConnectMCP
//
//  Uses the public iTunes Search API (no auth required):
//  https://itunes.apple.com/search?term=…&entity=software&limit=…&country=…
//
//  Results are returned in relevance/rank order, so array index = rank.
//

#import "ASCKeywordTools.h"

// ─── iTunes Search helper ─────────────────────────────────────────────────────

/// Synchronous iTunes Search API call. Returns parsed JSON or nil on error.
static NSArray *itunesSearch(NSString *term, NSString *country, NSInteger limit) {
    NSString *encoded = [term stringByAddingPercentEncodingWithAllowedCharacters:
                         [NSCharacterSet URLQueryAllowedCharacterSet]];
    NSString *urlStr = [NSString stringWithFormat:
        @"https://itunes.apple.com/search?term=%@&entity=software&limit=%ld&country=%@&lang=en_us",
        encoded, (long)limit, country ?: @"us"];

    NSMutableURLRequest *req = [NSMutableURLRequest
        requestWithURL:[NSURL URLWithString:urlStr]
           cachePolicy:NSURLRequestUseProtocolCachePolicy
       timeoutInterval:15];
    [req setValue:@"application/json" forHTTPHeaderField:@"Accept"];

    dispatch_semaphore_t sem = dispatch_semaphore_create(0);
    __block NSArray *results = nil;

    [[[NSURLSession sharedSession]
      dataTaskWithRequest:req
      completionHandler:^(NSData *d, NSURLResponse *r, NSError *e) {
          if (d && !e) {
              NSDictionary *json = [NSJSONSerialization JSONObjectWithData:d options:0 error:nil];
              results = json[@"results"];
          }
          dispatch_semaphore_signal(sem);
      }] resume];

    dispatch_semaphore_wait(sem, dispatch_time(DISPATCH_TIME_NOW, 15 * NSEC_PER_SEC));
    return results ?: @[];
}

/// Throttle between bulk requests to stay well inside iTunes Search rate limits.
static void throttle(void) {
    [NSThread sleepForTimeInterval:0.25];
}

/// Format a star rating as "★4.7" or "★—" if missing.
static NSString *stars(NSDictionary *app) {
    NSNumber *r = app[@"averageUserRating"];
    if (!r) return @"★—";
    return [NSString stringWithFormat:@"★%.1f", r.doubleValue];
}

/// Compact app label: "Name (★4.7, 12K ratings)"
static NSString *appLabel(NSDictionary *app) {
    NSString *name = app[@"trackName"] ?: @"?";
    NSNumber *ratingCount = app[@"userRatingCount"];
    NSString *count = @"";
    if (ratingCount) {
        long n = ratingCount.longValue;
        if (n >= 1000000)      count = [NSString stringWithFormat:@", %.1fM ratings", n / 1000000.0];
        else if (n >= 1000)    count = [NSString stringWithFormat:@", %ldK ratings", n / 1000];
        else if (n > 0)        count = [NSString stringWithFormat:@", %ld ratings", n];
    }
    return [NSString stringWithFormat:@"%@ (%@%@)", name, stars(app), count];
}

// ─── Tools ───────────────────────────────────────────────────────────────────

@implementation ASCKeywordTools

+ (nullable NSString *)checkKeywordRankings:(NSDictionary *)args error:(NSError **)error {
    NSString *keywordsRaw = args[@"keywords"];
    NSString *bundleId    = args[@"bundle_id"];
    NSString *country     = args[@"country"] ?: @"us";
    NSInteger limit       = [args[@"limit"] integerValue] ?: 100;
    if (limit < 1 || limit > 200) limit = 100;

    if (!keywordsRaw.length || !bundleId.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCKeywordTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey:
                                                      @"keywords and bundle_id are required"}];
        return nil;
    }

    NSArray *keywords = [[keywordsRaw componentsSeparatedByString:@","]
                         filteredArrayUsingPredicate:
                         [NSPredicate predicateWithBlock:^BOOL(NSString *s, id _) {
                             return s.length > 0;
                         }]];
    keywords = [keywords valueForKeyPath:@"@unionOfObjects.self"]; // keep order

    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"Keyword rankings for %@ (%@, top %ld)\n\n",
     bundleId, country.uppercaseString, (long)limit];
    [out appendFormat:@"%-35s  %s\n", "Keyword", "Rank"];
    [out appendString:@"────────────────────────────────────────────\n"];

    NSInteger found = 0, notFound = 0;

    for (NSString *rawKw in keywords) {
        NSString *kw = [rawKw stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceCharacterSet]];
        if (!kw.length) continue;

        NSArray *results = itunesSearch(kw, country, limit);
        NSInteger rank = NSNotFound;
        for (NSUInteger i = 0; i < results.count; i++) {
            if ([results[i][@"bundleId"] isEqualToString:bundleId]) {
                rank = (NSInteger)i + 1;
                break;
            }
        }

        if (rank != NSNotFound) {
            [out appendFormat:@"%-35s  #%ld\n",
             [kw UTF8String], (long)rank];
            found++;
        } else {
            [out appendFormat:@"%-35s  not in top %ld\n",
             [kw UTF8String], (long)MIN((NSInteger)results.count, limit)];
            notFound++;
        }

        if (keywords.lastObject != rawKw) throttle();
    }

    [out appendFormat:@"\n%ld keyword(s) ranking, %ld not in top %ld.",
     (long)found, (long)notFound, (long)limit];
    return out;
}

+ (nullable NSString *)searchKeywordCompetition:(NSDictionary *)args error:(NSError **)error {
    NSString *keyword = [args[@"keyword"]
                         stringByTrimmingCharactersInSet:[NSCharacterSet whitespaceCharacterSet]];
    NSString *country = args[@"country"] ?: @"us";
    NSInteger limit   = [args[@"limit"] integerValue] ?: 10;
    if (limit < 1 || limit > 50) limit = 10;

    if (!keyword.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCKeywordTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"keyword is required"}];
        return nil;
    }

    NSArray *results = itunesSearch(keyword, country, limit);
    if (!results.count) return [NSString stringWithFormat:@"No results for \"%@\".", keyword];

    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"Top %lu result(s) for \"%@\" (%@)\n\n",
     (unsigned long)results.count, keyword, country.uppercaseString];

    for (NSUInteger i = 0; i < results.count; i++) {
        NSDictionary *app = results[i];
        NSString *name      = app[@"trackName"]    ?: @"?";
        NSString *developer = app[@"artistName"]   ?: @"?";
        NSString *bundleId  = app[@"bundleId"]     ?: @"?";
        NSString *genre     = app[@"primaryGenreName"] ?: @"?";
        NSNumber *price     = app[@"price"];
        NSString *priceStr  = (price && price.doubleValue > 0)
                              ? [NSString stringWithFormat:@"$%.2f", price.doubleValue]
                              : @"Free";

        [out appendFormat:@"#%lu  %@\n", (unsigned long)(i + 1), name];
        [out appendFormat:@"    Developer: %@\n", developer];
        [out appendFormat:@"    Bundle:    %@\n", bundleId];
        [out appendFormat:@"    Rating:    %@\n", stars(app)];
        [out appendFormat:@"    Genre:     %@  |  %@\n\n", genre, priceStr];
    }
    return out;
}

+ (nullable NSString *)bulkKeywordScan:(NSDictionary *)args error:(NSError **)error {
    NSString *keywordsRaw = args[@"keywords"];
    NSString *bundleId    = args[@"bundle_id"];  // optional
    NSString *country     = args[@"country"] ?: @"us";
    NSInteger limit       = [args[@"limit"] integerValue] ?: 100;
    if (limit < 1 || limit > 200) limit = 100;

    if (!keywordsRaw.length) {
        if (error) *error = [NSError errorWithDomain:@"ASCKeywordTools" code:1
                                           userInfo:@{NSLocalizedDescriptionKey: @"keywords is required"}];
        return nil;
    }

    NSArray *keywords = [[keywordsRaw componentsSeparatedByString:@","]
                         filteredArrayUsingPredicate:
                         [NSPredicate predicateWithBlock:^BOOL(NSString *s, id _) {
                             return [[s stringByTrimmingCharactersInSet:
                                      [NSCharacterSet whitespaceCharacterSet]] length] > 0;
                         }]];

    NSMutableString *out = [NSMutableString string];
    [out appendFormat:@"Keyword Scan — %@ — top %ld per keyword\n\n",
     country.uppercaseString, (long)limit];

    if (bundleId.length) {
        [out appendFormat:@"Tracking: %@\n\n", bundleId];
        [out appendString:@"Keyword                              Rank    #1 App                              #2 App\n"];
        [out appendString:@"──────────────────────────────────────────────────────────────────────────────────────────────\n"];
    } else {
        [out appendString:@"Keyword                              #1 App                              #2 App                              #3 App\n"];
        [out appendString:@"──────────────────────────────────────────────────────────────────────────────────────────────────────────────\n"];
    }

    for (NSString *rawKw in keywords) {
        NSString *kw = [rawKw stringByTrimmingCharactersInSet:
                        [NSCharacterSet whitespaceCharacterSet]];
        if (!kw.length) continue;

        NSArray *results = itunesSearch(kw, country, limit);

        // Find bundle rank if requested
        NSString *rankStr = @"";
        if (bundleId.length) {
            NSInteger rank = NSNotFound;
            for (NSUInteger i = 0; i < results.count; i++) {
                if ([results[i][@"bundleId"] isEqualToString:bundleId]) {
                    rank = (NSInteger)i + 1;
                    break;
                }
            }
            rankStr = (rank != NSNotFound)
                ? [NSString stringWithFormat:@"#%-5ld", (long)rank]
                : [NSString stringWithFormat:@"—(%ld)", (long)results.count];
        }

        // Top competitors (skip own app if tracking)
        NSMutableArray *competitors = [NSMutableArray array];
        for (NSDictionary *app in results) {
            if (bundleId.length && [app[@"bundleId"] isEqualToString:bundleId]) continue;
            [competitors addObject:appLabel(app)];
            if (competitors.count >= (bundleId.length ? 2 : 3)) break;
        }
        while (competitors.count < (bundleId.length ? 2 : 3)) [competitors addObject:@"—"];

        if (bundleId.length) {
            [out appendFormat:@"%-36s %-7s %-35s %@\n",
             [kw UTF8String],
             [rankStr UTF8String],
             [[competitors[0] substringToIndex:MIN(35u, (unsigned)[competitors[0] length])] UTF8String],
             [competitors[1] substringToIndex:MIN(35u, (unsigned)[competitors[1] length])]];
        } else {
            [out appendFormat:@"%-36s %-35s %-35s %@\n",
             [kw UTF8String],
             [[competitors[0] substringToIndex:MIN(35u, (unsigned)[competitors[0] length])] UTF8String],
             [[competitors[1] substringToIndex:MIN(35u, (unsigned)[competitors[1] length])] UTF8String],
             [competitors[2] substringToIndex:MIN(35u, (unsigned)[competitors[2] length])]];
        }

        if (rawKw != keywords.lastObject) throttle();
    }

    [out appendFormat:@"\n%lu keyword(s) scanned.", (unsigned long)keywords.count];
    return out;
}

@end
