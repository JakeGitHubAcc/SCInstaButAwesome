#import "../../Utils.h"
#import "SCIAnalyzerAPI.h"

// Picks up the session headers Instagram attaches to its own API requests,
// so the profile analyzer can make requests as the logged in account.

%hook NSMutableURLRequest
- (void)setValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    %orig;

    [[SCIAnalyzerAPI sharedInstance] captureHeaderValue:value forField:field url:self.URL];
}

- (void)addValue:(NSString *)value forHTTPHeaderField:(NSString *)field {
    %orig;

    [[SCIAnalyzerAPI sharedInstance] captureHeaderValue:value forField:field url:self.URL];
}

- (void)setAllHTTPHeaderFields:(NSDictionary<NSString *, NSString *> *)headerFields {
    %orig;

    for (NSString *field in headerFields) {
        [[SCIAnalyzerAPI sharedInstance] captureHeaderValue:headerFields[field] forField:field url:self.URL];
    }
}
%end
