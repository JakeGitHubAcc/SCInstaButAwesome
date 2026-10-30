#import "SCIAnalyzerAPI.h"
#import "../../Utils.h"
#import <sys/utsname.h>

static NSString * const kAPIBase = @"https://i.instagram.com/api/v1/";
static NSString * const kFallbackAppID = @"124024574287414"; // Instagram iOS app id

@interface SCIAnalyzerAPI ()
@property (nonatomic, strong) NSMutableDictionary<NSString *, NSString *> *capturedHeaders;
@property (nonatomic, strong) NSURLSession *session;
@property (nonatomic, copy) NSString *fallbackUserAgent; // Built on the main thread, since it reads UIScreen/UIDevice
@end

@implementation SCIAnalyzerAPI

+ (instancetype)sharedInstance {
    static SCIAnalyzerAPI *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        instance = [SCIAnalyzerAPI new];
    });
    return instance;
}

- (instancetype)init {
    self = [super init];

    if (self) {
        self.capturedHeaders = [NSMutableDictionary dictionary];

        NSURLSessionConfiguration *config = [NSURLSessionConfiguration defaultSessionConfiguration];
        config.HTTPCookieStorage = [NSHTTPCookieStorage sharedHTTPCookieStorage];
        config.timeoutIntervalForRequest = 30;
        self.session = [NSURLSession sessionWithConfiguration:config];
    }

    return self;
}

// MARK: - Header capture

- (void)captureHeaderValue:(NSString *)value forField:(NSString *)field url:(NSURL *)url {
    if (!value.length || !field.length) return;
    if (url && ![url.host hasSuffix:@"instagram.com"]) return;

    NSString *key = field.lowercaseString;

    static NSSet *wantedKeys;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        wantedKeys = [NSSet setWithArray:@[
            @"authorization", @"x-ig-app-id", @"user-agent", @"ig-u-ds-user-id",
            @"x-ig-www-claim", @"x-mid", @"x-ig-device-id", @"x-ig-family-device-id"
        ]];
    });
    if (![wantedKeys containsObject:key]) return;

    // Only keep real session tokens and app user agents
    if ([key isEqualToString:@"authorization"] && ![value hasPrefix:@"Bearer IGT"]) return;
    if ([key isEqualToString:@"user-agent"] && ![value hasPrefix:@"Instagram"]) return;

    @synchronized (self.capturedHeaders) {
        self.capturedHeaders[key] = value;
    }
}

- (NSDictionary<NSString *, NSString *> *)headersSnapshot {
    @synchronized (self.capturedHeaders) {
        return [self.capturedHeaders copy];
    }
}

- (nullable NSString *)cookieNamed:(NSString *)name {
    NSArray *cookies = [[NSHTTPCookieStorage sharedHTTPCookieStorage] cookiesForURL:[NSURL URLWithString:@"https://i.instagram.com/"]];
    for (NSHTTPCookie *cookie in cookies) {
        if ([cookie.name isEqualToString:name] && cookie.value.length) return cookie.value;
    }
    return nil;
}

// MARK: - Current user

- (nullable IGUser *)sessionUser {
    for (UIScene *scene in [UIApplication sharedApplication].connectedScenes) {
        if (![scene isKindOfClass:[UIWindowScene class]]) continue;

        for (UIWindow *window in ((UIWindowScene *)scene).windows) {
            if (![window respondsToSelector:@selector(userSession)]) continue;

            IGUserSession *session = [(IGWindow *)window userSession];
            if (session.user) return session.user;
        }
    }
    return nil;
}

- (nullable NSString *)currentUserPK {
    IGUser *user = [self sessionUser];

    if (user) {
        for (NSString *key in @[@"pk", @"instaID", @"userID"]) {
            @try {
                id value = [user valueForKey:key];
                if (value) return [NSString stringWithFormat:@"%@", value];
            }
            @catch (NSException *exception) {}
        }
    }

    return [self headersSnapshot][@"ig-u-ds-user-id"] ?: [self cookieNamed:@"ds_user_id"];
}

- (nullable NSString *)currentUsername {
    return [self sessionUser].username;
}

// MARK: - Requests

- (void)prepareFallbackUserAgent {
    if (self.fallbackUserAgent || ![NSThread isMainThread]) return;

    struct utsname systemInfo;
    uname(&systemInfo);

    UIScreen *screen = [UIScreen mainScreen];
    NSString *osVersion = [[UIDevice currentDevice].systemVersion stringByReplacingOccurrencesOfString:@"." withString:@"_"];
    NSString *locale = [NSLocale currentLocale].localeIdentifier;

    self.fallbackUserAgent = [NSString stringWithFormat:@"Instagram %@ (%s; iOS %@; %@; %@; scale=%.2f; %.0fx%.0f; 0) AppleWebKit/420+",
            [SCIUtils IGVersionString], systemInfo.machine, osVersion, locale,
            [NSLocale preferredLanguages].firstObject ?: @"en",
            screen.scale, screen.nativeBounds.size.width, screen.nativeBounds.size.height];
}

- (NSMutableURLRequest *)requestWithPath:(NSString *)path method:(NSString *)method body:(nullable NSDictionary *)body {
    NSMutableURLRequest *request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:[kAPIBase stringByAppendingString:path]]];
    request.HTTPMethod = method;

    NSDictionary *captured = [self headersSnapshot];
    [captured enumerateKeysAndObjectsUsingBlock:^(NSString *key, NSString *value, BOOL *stop) {
        [request setValue:value forHTTPHeaderField:key];
    }];

    if (!captured[@"x-ig-app-id"]) [request setValue:kFallbackAppID forHTTPHeaderField:@"X-IG-App-ID"];
    if (!captured[@"user-agent"] && self.fallbackUserAgent) [request setValue:self.fallbackUserAgent forHTTPHeaderField:@"User-Agent"];

    NSString *csrf = [self cookieNamed:@"csrftoken"];
    if (csrf) [request setValue:csrf forHTTPHeaderField:@"X-CSRFToken"];

    if (body) {
        NSData *json = [NSJSONSerialization dataWithJSONObject:body options:0 error:nil];
        NSString *jsonString = [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding];
        NSString *encoded = [jsonString stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]];

        request.HTTPBody = [[NSString stringWithFormat:@"signed_body=SIGNATURE.%@", encoded] dataUsingEncoding:NSUTF8StringEncoding];
        [request setValue:@"application/x-www-form-urlencoded; charset=UTF-8" forHTTPHeaderField:@"Content-Type"];
    }

    return request;
}

- (void)sendRequest:(NSURLRequest *)request completion:(void (^)(NSDictionary *json, NSError *error))completion {
    [[self.session dataTaskWithRequest:request completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
        if (error) {
            completion(nil, error);
            return;
        }

        NSInteger status = [(NSHTTPURLResponse *)response statusCode];
        NSDictionary *json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:nil] : nil;
        if (![json isKindOfClass:[NSDictionary class]]) json = nil;

        if (status == 200 && [json[@"status"] isEqualToString:@"ok"]) {
            completion(json, nil);
            return;
        }

        NSString *message = [json[@"message"] isKindOfClass:[NSString class]] ? json[@"message"] : nil;

        if (status == 401 || status == 403 || [message isEqualToString:@"login_required"]) {
            message = @"Instagram rejected the request as logged out. Scroll your feed or open a profile for a few seconds so SCInsta can pick up your session, then try again.";
        }
        else if (status == 429 || [message containsString:@"wait a few minutes"]) {
            message = @"Instagram is rate limiting requests. Wait a while before trying again.";
        }

        completion(nil, [SCIUtils errorWithDescription:message ?: [NSString stringWithFormat:@"Request failed (HTTP %ld)", (long)status] code:status]);
    }] resume];
}

// MARK: - Endpoints

+ (NSDictionary *)userFromJSON:(NSDictionary *)user {
    id pk = user[@"pk"] ?: user[@"pk_id"];
    if (!pk) return nil;

    NSMutableDictionary *result = [NSMutableDictionary dictionary];
    result[@"pk"] = [NSString stringWithFormat:@"%@", pk];
    result[@"username"] = user[@"username"] ?: @"";
    result[@"full_name"] = user[@"full_name"] ?: @"";
    result[@"is_private"] = @([user[@"is_private"] boolValue]);
    result[@"is_verified"] = @([user[@"is_verified"] boolValue]);

    NSString *picURL = user[@"profile_pic_url"];
    if ([picURL isKindOfClass:[NSString class]]) {
        result[@"profile_pic_url"] = picURL;

        // Picture urls are re-signed on every fetch, so keep a stable id for change tracking
        id picID = user[@"profile_pic_id"];
        result[@"profile_pic_id"] = picID ? [NSString stringWithFormat:@"%@", picID] : ([NSURL URLWithString:picURL].lastPathComponent ?: @"");
    }

    return result;
}

- (void)fetchUserListOfKind:(NSString *)kind
                     userPK:(NSString *)pk
                   progress:(void (^)(NSUInteger))progress
                isCancelled:(BOOL (^)(void))isCancelled
                 completion:(void (^)(NSArray<NSDictionary *> *, NSError *))completion
{
    [self prepareFallbackUserAgent];

    void (^finish)(NSArray *, NSError *) = ^(NSArray *result, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(result, error); });
    };

    [self fetchPageOfKind:kind userPK:pk maxID:nil users:[NSMutableArray array] seen:[NSMutableSet set] progress:progress isCancelled:isCancelled finish:finish];
}

- (void)fetchPageOfKind:(NSString *)kind
                 userPK:(NSString *)pk
                  maxID:(nullable NSString *)maxID
                  users:(NSMutableArray *)users
                   seen:(NSMutableSet *)seen
               progress:(void (^)(NSUInteger))progress
            isCancelled:(BOOL (^)(void))isCancelled
                 finish:(void (^)(NSArray *, NSError *))finish
{
    if (isCancelled && isCancelled()) {
        finish(nil, [SCIUtils errorWithDescription:@"Scan cancelled" code:-999]);
        return;
    }

    NSMutableString *path = [NSMutableString stringWithFormat:@"friendships/%@/%@/?count=200", pk, kind];
    if ([kind isEqualToString:@"followers"]) [path appendString:@"&search_surface=follow_list_page"];
    if (maxID.length) [path appendFormat:@"&max_id=%@", [maxID stringByAddingPercentEncodingWithAllowedCharacters:[NSCharacterSet alphanumericCharacterSet]]];

    [self sendRequest:[self requestWithPath:path method:@"GET" body:nil] completion:^(NSDictionary *json, NSError *error) {
        if (error) {
            finish(nil, error);
            return;
        }

        for (NSDictionary *rawUser in json[@"users"]) {
            if (![rawUser isKindOfClass:[NSDictionary class]]) continue;

            NSDictionary *user = [SCIAnalyzerAPI userFromJSON:rawUser];
            if (!user || [seen containsObject:user[@"pk"]]) continue;

            [seen addObject:user[@"pk"]];
            [users addObject:user];
        }

        if (progress) {
            NSUInteger count = users.count;
            dispatch_async(dispatch_get_main_queue(), ^{ progress(count); });
        }

        id nextMaxID = json[@"next_max_id"];
        NSString *nextMaxIDString = (nextMaxID && nextMaxID != [NSNull null]) ? [NSString stringWithFormat:@"%@", nextMaxID] : nil;
        if (!nextMaxIDString.length) {
            finish([users copy], nil);
            return;
        }

        // Space out pages so the scan looks like normal scrolling
        double delay = 1.0 + (arc4random_uniform(1500) / 1000.0);
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(delay * NSEC_PER_SEC)), dispatch_get_global_queue(QOS_CLASS_UTILITY, 0), ^{
            [self fetchPageOfKind:kind userPK:pk maxID:nextMaxIDString users:users seen:seen progress:progress isCancelled:isCancelled finish:finish];
        });
    }];
}

- (void)performAction:(SCIAnalyzerFriendshipAction)action userPK:(NSString *)pk completion:(void (^)(NSError *))completion {
    [self prepareFallbackUserAgent];

    NSString *endpoint;
    switch (action) {
        case SCIAnalyzerFriendshipActionFollow:         endpoint = @"create"; break;
        case SCIAnalyzerFriendshipActionUnfollow:       endpoint = @"destroy"; break;
        case SCIAnalyzerFriendshipActionRemoveFollower: endpoint = @"remove_follower"; break;
    }

    NSString *myPK = [self currentUserPK] ?: @"";
    NSString *deviceID = [self headersSnapshot][@"x-ig-device-id"] ?: [UIDevice currentDevice].identifierForVendor.UUIDString;

    NSDictionary *body = @{
        @"user_id": pk,
        @"_uid": myPK,
        @"_uuid": deviceID ?: @"",
        @"radio_type": @"wifi-none",
        @"container_module": @"profile"
    };

    NSString *path = [NSString stringWithFormat:@"friendships/%@/%@/", endpoint, pk];
    [self sendRequest:[self requestWithPath:path method:@"POST" body:body] completion:^(NSDictionary *json, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{ completion(error); });
    }];
}

@end
