#import "../../Utils.h"
#import "NoteRequestLog.h"
#import <objc/runtime.h>

// Records note creation requests (Debug > Log note requests), so the request format for
// things like GIF notes with music can be worked out. Instagram 453 sends notes through its
// own networking as GraphQL input objects, so those objects are recorded field by field;
// plain NSURLRequest bodies are recorded too. Headers are never kept, and ids/tokens are redacted.

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

    [self appendEntry:[NSString stringWithFormat:@"==== %@  %@\n%@\n\n", [NSDate date], url.path, [self describeBody:body]]];
}

+ (void)appendEntry:(NSString *)entry {
    @synchronized (self) {
        NSString *existing = [NSString stringWithContentsOfURL:[self logURL] encoding:NSUTF8StringEncoding error:nil] ?: @"";
        NSString *combined = [existing stringByAppendingString:entry];
        if (combined.length > kSCIMaxLogLength) combined = [combined substringFromIndex:combined.length - kSCIMaxLogLength];
        [combined writeToURL:[self logURL] atomically:YES encoding:NSUTF8StringEncoding error:nil];
    }
}

// Describes a GraphQL input object through its declared properties (their getters are
// generated at runtime, so they're read with KVC)
+ (id)describeObject:(id)object depth:(NSInteger)depth {
    if (!object || object == [NSNull null]) return @"null";
    if ([object isKindOfClass:[NSString class]] || [object isKindOfClass:[NSNumber class]]) return object;
    if ([object isKindOfClass:[NSArray class]]) {
        NSMutableArray *items = [NSMutableArray array];
        for (id item in (NSArray *)object) [items addObject:[self describeObject:item depth:depth]];
        return items;
    }
    if ([object isKindOfClass:[NSDictionary class]]) return [self redact:object];
    if (depth <= 0) return [NSString stringWithFormat:@"<%@>", NSStringFromClass([object class])];

    NSMutableDictionary *fields = [NSMutableDictionary dictionary];
    fields[@"_class"] = NSStringFromClass([object class]);

    for (Class cls = [object class]; cls && cls != [NSObject class]; cls = class_getSuperclass(cls)) {
        unsigned int count = 0;
        objc_property_t *properties = class_copyPropertyList(cls, &count);
        for (unsigned int i = 0; i < count; i++) {
            NSString *name = @(property_getName(properties[i]));
            if (fields[name] || [@[@"hash", @"superclass", @"description", @"debugDescription"] containsObject:name]) continue;

            if ([self shouldRedactKey:name]) {
                fields[name] = @"<redacted>";
                continue;
            }

            id value = nil;
            @try { value = [object valueForKey:name]; }
            @catch (NSException *exception) { continue; }
            if (value) fields[name] = [self describeObject:value depth:depth - 1];
        }
        free(properties);
    }
    return fields;
}

+ (void)recordObject:(id)object title:(NSString *)title {
    if (![SCIUtils getBoolPref:@"notes_request_log"]) return;

    id description = [self describeObject:object depth:5];
    NSString *text = [description isKindOfClass:[NSString class]] ? description : nil;
    if (!text) {
        NSData *json = [NSJSONSerialization isValidJSONObject:description] ? [NSJSONSerialization dataWithJSONObject:description options:NSJSONWritingPrettyPrinted | NSJSONWritingSortedKeys error:nil] : nil;
        text = json ? [[NSString alloc] initWithData:json encoding:NSUTF8StringEncoding] : [description description];
    }

    [self appendEntry:[NSString stringWithFormat:@"==== %@  %@\n%@\n\n", [NSDate date], title, text]];
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

// Instagram 453+: the parts of a note as Instagram builds them
%hook IGXDTMusicNoteCreateInfo
- (id)initWithAudioClusterId:(id)clusterId {
    id result = %orig;
    [SCINoteRequestLog recordObject:result title:@"IGXDTMusicNoteCreateInfo (as created)"];
    return result;
}
%end

%hook IGXDTGifNoteCreateInfo
- (id)initWithGifParams:(id)params {
    id result = %orig;
    [SCINoteRequestLog recordObject:result title:@"IGXDTGifNoteCreateInfo (as created)"];
    return result;
}
%end
