#import "../../Utils.h"
#import "NoteRequestLog.h"

// Records the bodies of note creation requests (Debug > Log note requests), so the
// request format for things like GIF notes with music can be worked out.
// Only the URL path and body are kept, never headers, and ids/tokens are redacted.

static NSUInteger const kSCIMaxLogLength = 60000;

@implementation SCINoteRequestLog

+ (NSURL *)logURL {
    NSURL *documents = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
    NSURL *folder = [documents URLByAppendingPathComponent:@"SCInsta" isDirectory:YES];
    [[NSFileManager defaultManager] createDirectoryAtURL:folder withIntermediateDirectories:YES attributes:nil error:nil];
    return [folder URLByAppendingPathComponent:@"note_requests.txt"];
}

+ (BOOL)shouldRedactKey:(NSString *)key {
    static NSRegularExpression *regex;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        regex = [NSRegularExpression regularExpressionWithPattern:@"token|uuid|device|guid|adid|session|phone|email|_uid|^uid$|user_?id|pk$|csrf|mid$" options:NSRegularExpressionCaseInsensitive error:nil];
    });
    return [regex numberOfMatchesInString:key options:0 range:NSMakeRange(0, key.length)] > 0;
}

+ (id)redact:(id)object {
    if ([object isKindOfClass:[NSDictionary class]]) {
        NSMutableDictionary *result = [NSMutableDictionary dictionary];
        [(NSDictionary *)object enumerateKeysAndObjectsUsingBlock:^(id key, id value, BOOL *stop) {
            result[key] = [key isKindOfClass:[NSString class]] && [self shouldRedactKey:key] ? @"<redacted>" : [self redact:value];
        }];
        return result;
    }
    if ([object isKindOfClass:[NSArray class]]) {
        NSMutableArray *result = [NSMutableArray array];
        for (id value in (NSArray *)object) [result addObject:[self redact:value]];
        return result;
    }
    if ([object isKindOfClass:[NSString class]]) {
        // Nested JSON strings are common in Instagram request bodies
        NSString *string = object;
        if ([string hasPrefix:@"{"] || [string hasPrefix:@"["]) {
            id json = [NSJSONSerialization JSONObjectWithData:[string dataUsingEncoding:NSUTF8StringEncoding] options:0 error:nil];
            if (json) return [self redact:json];
        }
    }
    return object;
}

+ (NSString *)describeBody:(NSData *)body {
    NSString *string = [[NSString alloc] initWithData:body encoding:NSUTF8StringEncoding];
    if (!string) return [NSString stringWithFormat:@"<%lu bytes of binary data>", (unsigned long)body.length];

    // JSON body
    id json = [NSJSONSerialization JSONObjectWithData:body options:0 error:nil];
    if (json) {
        NSData *pretty = [NSJSONSerialization dataWithJSONObject:[self redact:json] options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
        return [[NSString alloc] initWithData:pretty encoding:NSUTF8StringEncoding];
    }

    // Form body, possibly with signed_body=SIGNATURE.<json>
    NSMutableDictionary *form = [NSMutableDictionary dictionary];
    for (NSString *pair in [string componentsSeparatedByString:@"&"]) {
        NSRange equals = [pair rangeOfString:@"="];
        if (equals.location == NSNotFound) continue;

        NSString *key = [[pair substringToIndex:equals.location] stringByRemovingPercentEncoding] ?: @"";
        NSString *value = [[[pair substringFromIndex:equals.location + 1] stringByReplacingOccurrencesOfString:@"+" withString:@" "] stringByRemovingPercentEncoding] ?: @"";
        if ([key isEqualToString:@"signed_body"] && [value hasPrefix:@"SIGNATURE."]) value = [value substringFromIndex:10];

        form[key] = value;
    }
    if (!form.count) return @"<unrecognised body>";

    NSData *pretty = [NSJSONSerialization dataWithJSONObject:[self redact:form] options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil];
    return [[NSString alloc] initWithData:pretty encoding:NSUTF8StringEncoding];
}

+ (void)recordBody:(NSData *)body forURL:(NSURL *)url {
    if (!body.length || ![SCIUtils getBoolPref:@"notes_request_log"]) return;
    if (![url.host hasSuffix:@"instagram.com"] || ![url.path.lowercaseString containsString:@"note"]) return;

    NSString *entry = [NSString stringWithFormat:@"==== %@  %@\n%@\n\n", [NSDate date], url.path, [self describeBody:body]];

    @synchronized (self) {
        NSString *existing = [NSString stringWithContentsOfURL:[self logURL] encoding:NSUTF8StringEncoding error:nil] ?: @"";
        NSString *combined = [existing stringByAppendingString:entry];
        if (combined.length > kSCIMaxLogLength) combined = [combined substringFromIndex:combined.length - kSCIMaxLogLength];
        [combined writeToURL:[self logURL] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

+ (NSString *)contents {
    NSString *log = [NSString stringWithContentsOfURL:[self logURL] encoding:NSUTF8StringEncoding error:nil];
    return log.length ? log : @"No note requests recorded yet. Turn on Log note requests, post a note, then try again.";
}

+ (void)clear {
    [[NSFileManager defaultManager] removeItemAtURL:[self logURL] error:nil];
}

@end

%hook NSMutableURLRequest
- (void)setHTTPBody:(NSData *)body {
    %orig;

    [SCINoteRequestLog recordBody:body forURL:self.URL];
}
%end
