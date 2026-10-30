#import "SCIAnalyzerStore.h"

static NSUInteger const kMaxEvents = 5000;
static NSUInteger const kMaxScans = 200;

@interface SCIAnalyzerStore ()
@property (nonatomic, strong) NSURL *directory;

@property (nonatomic, strong) NSMutableDictionary *latest;   // date, followers, following
@property (nonatomic, strong) NSDictionary *previous;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *mutableEvents;
@property (nonatomic, strong) NSMutableArray<NSDictionary *> *mutableScans;
@end

@implementation SCIAnalyzerStore

- (instancetype)initWithUserPK:(NSString *)pk {
    self = [super init];

    if (self) {
        _userPK = [pk copy];

        NSURL *documents = [[NSFileManager defaultManager] URLsForDirectory:NSDocumentDirectory inDomains:NSUserDomainMask].firstObject;
        self.directory = [documents URLByAppendingPathComponent:[NSString stringWithFormat:@"SCInsta/ProfileAnalyzer/%@", pk] isDirectory:YES];
        [[NSFileManager defaultManager] createDirectoryAtURL:self.directory withIntermediateDirectories:YES attributes:nil error:nil];

        [self load];
    }

    return self;
}

// MARK: - Persistence

- (id)readJSON:(NSString *)name {
    NSData *data = [NSData dataWithContentsOfURL:[self.directory URLByAppendingPathComponent:name]];
    if (!data) return nil;

    return [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil];
}

- (void)writeJSON:(id)object name:(NSString *)name {
    if (!object) {
        [[NSFileManager defaultManager] removeItemAtURL:[self.directory URLByAppendingPathComponent:name] error:nil];
        return;
    }

    NSData *data = [NSJSONSerialization dataWithJSONObject:object options:0 error:nil];
    [data writeToURL:[self.directory URLByAppendingPathComponent:name] atomically:YES];
}

- (void)load {
    NSDictionary *latest = [self readJSON:@"latest.json"];
    self.latest = [latest isKindOfClass:[NSDictionary class]] ? [latest mutableCopy] : nil;

    NSDictionary *previous = [self readJSON:@"previous.json"];
    self.previous = [previous isKindOfClass:[NSDictionary class]] ? previous : nil;

    NSArray *events = [self readJSON:@"events.json"];
    self.mutableEvents = [events isKindOfClass:[NSArray class]] ? [events mutableCopy] : [NSMutableArray array];

    NSArray *scans = [self readJSON:@"scans.json"];
    self.mutableScans = [scans isKindOfClass:[NSArray class]] ? [scans mutableCopy] : [NSMutableArray array];
}

- (void)saveLatest {
    [self writeJSON:self.latest name:@"latest.json"];
}

- (void)saveEvents {
    if (self.mutableEvents.count > kMaxEvents) {
        [self.mutableEvents removeObjectsInRange:NSMakeRange(kMaxEvents, self.mutableEvents.count - kMaxEvents)];
    }
    [self writeJSON:self.mutableEvents name:@"events.json"];
}

// MARK: - Accessors

- (NSDate *)lastScanDate {
    NSNumber *date = self.latest[@"date"];
    return date ? [NSDate dateWithTimeIntervalSince1970:date.doubleValue] : nil;
}

- (NSArray<NSDictionary *> *)followers { return self.latest[@"followers"] ?: @[]; }
- (NSArray<NSDictionary *> *)following { return self.latest[@"following"] ?: @[]; }

- (NSUInteger)followerCount { return [self followers].count; }
- (NSUInteger)followingCount { return [self following].count; }

- (NSArray<NSDictionary *> *)events { return [self.mutableEvents copy]; }
- (NSArray<NSDictionary *> *)scans { return [self.mutableScans copy]; }

+ (NSSet<NSString *> *)pksForUsers:(NSArray<NSDictionary *> *)users {
    NSMutableSet *pks = [NSMutableSet setWithCapacity:users.count];
    for (NSDictionary *user in users) {
        if (user[@"pk"]) [pks addObject:user[@"pk"]];
    }
    return pks;
}

+ (NSArray<NSDictionary *> *)users:(NSArray<NSDictionary *> *)users inSet:(NSSet *)pks matching:(BOOL)matching {
    NSMutableArray *result = [NSMutableArray array];
    for (NSDictionary *user in users) {
        if ([pks containsObject:user[@"pk"]] == matching) [result addObject:user];
    }
    return result;
}

- (BOOL)isFollower:(NSString *)pk {
    return [[SCIAnalyzerStore pksForUsers:[self followers]] containsObject:pk];
}

- (BOOL)isFollowing:(NSString *)pk {
    return [[SCIAnalyzerStore pksForUsers:[self following]] containsObject:pk];
}

- (NSArray<NSDictionary *> *)usersForList:(SCIAnalyzerList)list {
    NSArray *followers = [self followers];
    NSArray *following = [self following];
    NSArray *previousFollowers = self.previous[@"followers"];
    NSArray *previousFollowing = self.previous[@"following"];

    switch (list) {
        case SCIAnalyzerListMutuals:
            return [SCIAnalyzerStore users:following inSet:[SCIAnalyzerStore pksForUsers:followers] matching:YES];

        case SCIAnalyzerListNotFollowingBack:
            return [SCIAnalyzerStore users:following inSet:[SCIAnalyzerStore pksForUsers:followers] matching:NO];

        case SCIAnalyzerListFans:
            return [SCIAnalyzerStore users:followers inSet:[SCIAnalyzerStore pksForUsers:following] matching:NO];

        case SCIAnalyzerListNewFollowers:
            if (!previousFollowers) return @[];
            return [SCIAnalyzerStore users:followers inSet:[SCIAnalyzerStore pksForUsers:previousFollowers] matching:NO];

        case SCIAnalyzerListLostFollowers:
            if (!previousFollowers) return @[];
            return [SCIAnalyzerStore users:previousFollowers inSet:[SCIAnalyzerStore pksForUsers:followers] matching:NO];

        case SCIAnalyzerListNewFollowing:
            if (!previousFollowing) return @[];
            return [SCIAnalyzerStore users:following inSet:[SCIAnalyzerStore pksForUsers:previousFollowing] matching:NO];

        case SCIAnalyzerListUnfollowed:
            if (!previousFollowing) return @[];
            return [SCIAnalyzerStore users:previousFollowing inSet:[SCIAnalyzerStore pksForUsers:following] matching:NO];
    }

    return @[];
}

+ (NSString *)titleForList:(SCIAnalyzerList)list {
    switch (list) {
        case SCIAnalyzerListMutuals:          return @"Mutuals";
        case SCIAnalyzerListNotFollowingBack: return @"Not following you back";
        case SCIAnalyzerListFans:             return @"You don't follow back";
        case SCIAnalyzerListNewFollowers:     return @"New followers";
        case SCIAnalyzerListLostFollowers:    return @"Lost followers";
        case SCIAnalyzerListNewFollowing:     return @"New following";
        case SCIAnalyzerListUnfollowed:       return @"No longer following";
    }
    return @"";
}

// MARK: - Scans

- (NSDictionary *)eventOfType:(NSString *)type user:(NSDictionary *)user old:(nullable NSString *)oldValue new:(nullable NSString *)newValue date:(NSNumber *)date {
    NSMutableDictionary *event = [NSMutableDictionary dictionary];
    event[@"date"] = date;
    event[@"type"] = type;
    event[@"pk"] = user[@"pk"] ?: @"";
    event[@"username"] = user[@"username"] ?: @"";
    if (oldValue) event[@"old"] = oldValue;
    if (newValue) event[@"new"] = newValue;
    return event;
}

- (void)saveScanWithFollowers:(NSArray<NSDictionary *> *)followers following:(NSArray<NSDictionary *> *)following {
    NSNumber *now = @([[NSDate date] timeIntervalSince1970]);
    NSDictionary *old = self.latest;

    if (old) {
        NSMutableArray *newEvents = [NSMutableArray array];

        NSArray *oldFollowers = old[@"followers"] ?: @[];
        NSArray *oldFollowing = old[@"following"] ?: @[];

        NSSet *oldFollowerPKs = [SCIAnalyzerStore pksForUsers:oldFollowers];
        NSSet *newFollowerPKs = [SCIAnalyzerStore pksForUsers:followers];
        NSSet *oldFollowingPKs = [SCIAnalyzerStore pksForUsers:oldFollowing];
        NSSet *newFollowingPKs = [SCIAnalyzerStore pksForUsers:following];

        for (NSDictionary *user in [SCIAnalyzerStore users:followers inSet:oldFollowerPKs matching:NO])
            [newEvents addObject:[self eventOfType:@"new_follower" user:user old:nil new:nil date:now]];
        for (NSDictionary *user in [SCIAnalyzerStore users:oldFollowers inSet:newFollowerPKs matching:NO])
            [newEvents addObject:[self eventOfType:@"lost_follower" user:user old:nil new:nil date:now]];
        for (NSDictionary *user in [SCIAnalyzerStore users:following inSet:oldFollowingPKs matching:NO])
            [newEvents addObject:[self eventOfType:@"new_following" user:user old:nil new:nil date:now]];
        for (NSDictionary *user in [SCIAnalyzerStore users:oldFollowing inSet:newFollowingPKs matching:NO])
            [newEvents addObject:[self eventOfType:@"lost_following" user:user old:nil new:nil date:now]];

        // Profile changes for anyone seen in both scans
        NSMutableDictionary<NSString *, NSDictionary *> *oldUsers = [NSMutableDictionary dictionary];
        for (NSDictionary *user in [oldFollowers arrayByAddingObjectsFromArray:oldFollowing]) oldUsers[user[@"pk"]] = user;

        NSMutableSet *checked = [NSMutableSet set];
        for (NSDictionary *user in [followers arrayByAddingObjectsFromArray:following]) {
            NSString *pk = user[@"pk"];
            if ([checked containsObject:pk]) continue;
            [checked addObject:pk];

            NSDictionary *oldUser = oldUsers[pk];
            if (!oldUser) continue;

            if (![oldUser[@"username"] isEqualToString:user[@"username"]])
                [newEvents addObject:[self eventOfType:@"username" user:user old:oldUser[@"username"] new:user[@"username"] date:now]];
            if (![oldUser[@"full_name"] isEqualToString:user[@"full_name"]])
                [newEvents addObject:[self eventOfType:@"full_name" user:user old:oldUser[@"full_name"] new:user[@"full_name"] date:now]];
            if ([oldUser[@"profile_pic_id"] length] && [user[@"profile_pic_id"] length] && ![oldUser[@"profile_pic_id"] isEqualToString:user[@"profile_pic_id"]])
                [newEvents addObject:[self eventOfType:@"profile_pic" user:user old:nil new:nil date:now]];
        }

        [self.mutableEvents insertObjects:newEvents atIndexes:[NSIndexSet indexSetWithIndexesInRange:NSMakeRange(0, newEvents.count)]];
        [self saveEvents];

        self.previous = old;
        [self writeJSON:old name:@"previous.json"];
    }

    self.latest = [@{ @"date": now, @"followers": followers, @"following": following } mutableCopy];
    [self saveLatest];

    [self.mutableScans insertObject:@{ @"date": now, @"followers": @(followers.count), @"following": @(following.count) } atIndex:0];
    if (self.mutableScans.count > kMaxScans) [self.mutableScans removeLastObject];
    [self writeJSON:self.mutableScans name:@"scans.json"];
}

// MARK: - Actions

- (void)setUsers:(NSArray *)users forKey:(NSString *)key event:(NSString *)type user:(NSDictionary *)user {
    if (!self.latest) return;

    self.latest[key] = users;
    [self saveLatest];

    [self.mutableEvents insertObject:[self eventOfType:type user:user old:nil new:nil date:@([[NSDate date] timeIntervalSince1970])] atIndex:0];
    [self saveEvents];
}

- (void)recordFollow:(NSDictionary *)user {
    if ([self isFollowing:user[@"pk"]]) return;
    [self setUsers:[@[user] arrayByAddingObjectsFromArray:[self following]] forKey:@"following" event:@"you_followed" user:user];
}

- (void)recordUnfollow:(NSDictionary *)user {
    NSSet *pk = [NSSet setWithObject:user[@"pk"]];
    [self setUsers:[SCIAnalyzerStore users:[self following] inSet:pk matching:NO] forKey:@"following" event:@"you_unfollowed" user:user];
}

- (void)recordRemovedFollower:(NSDictionary *)user {
    NSSet *pk = [NSSet setWithObject:user[@"pk"]];
    [self setUsers:[SCIAnalyzerStore users:[self followers] inSet:pk matching:NO] forKey:@"followers" event:@"you_removed" user:user];
}

// MARK: - Export & clearing

+ (NSString *)csvField:(id)value {
    NSString *string = [NSString stringWithFormat:@"%@", value ?: @""];
    return [NSString stringWithFormat:@"\"%@\"", [string stringByReplacingOccurrencesOfString:@"\"" withString:@"\"\""]];
}

- (NSURL *)exportCSV {
    NSMutableString *csv = [NSMutableString stringWithString:@"username,full_name,pk,follows_you,you_follow,is_private,is_verified\n"];

    NSSet *followerPKs = [SCIAnalyzerStore pksForUsers:[self followers]];
    NSSet *followingPKs = [SCIAnalyzerStore pksForUsers:[self following]];

    NSMutableSet *written = [NSMutableSet set];
    for (NSDictionary *user in [[self followers] arrayByAddingObjectsFromArray:[self following]]) {
        if ([written containsObject:user[@"pk"]]) continue;
        [written addObject:user[@"pk"]];

        [csv appendFormat:@"%@,%@,%@,%@,%@,%@,%@\n",
            [SCIAnalyzerStore csvField:user[@"username"]],
            [SCIAnalyzerStore csvField:user[@"full_name"]],
            [SCIAnalyzerStore csvField:user[@"pk"]],
            [followerPKs containsObject:user[@"pk"]] ? @"yes" : @"no",
            [followingPKs containsObject:user[@"pk"]] ? @"yes" : @"no",
            [user[@"is_private"] boolValue] ? @"yes" : @"no",
            [user[@"is_verified"] boolValue] ? @"yes" : @"no"];
    }

    NSDateFormatter *formatter = [NSDateFormatter new];
    formatter.dateFormat = @"yyyy-MM-dd";

    NSString *name = [NSString stringWithFormat:@"profile-analyzer-%@.csv", [formatter stringFromDate:self.lastScanDate ?: [NSDate date]]];
    NSURL *url = [[NSURL fileURLWithPath:NSTemporaryDirectory()] URLByAppendingPathComponent:name];
    [csv writeToURL:url atomically:YES encoding:NSUTF8StringEncoding error:nil];

    return url;
}

- (void)clearAllData {
    [[NSFileManager defaultManager] removeItemAtURL:self.directory error:nil];
    [[NSFileManager defaultManager] createDirectoryAtURL:self.directory withIntermediateDirectories:YES attributes:nil error:nil];

    [self load];
}

// MARK: - Events

+ (NSString *)descriptionForEvent:(NSDictionary *)event {
    NSString *type = event[@"type"];
    NSString *username = [NSString stringWithFormat:@"@%@", event[@"username"]];

    if ([type isEqualToString:@"new_follower"])   return [NSString stringWithFormat:@"%@ started following you", username];
    if ([type isEqualToString:@"lost_follower"])  return [NSString stringWithFormat:@"%@ stopped following you", username];
    if ([type isEqualToString:@"new_following"])  return [NSString stringWithFormat:@"You started following %@", username];
    if ([type isEqualToString:@"lost_following"]) return [NSString stringWithFormat:@"You no longer follow %@", username];
    if ([type isEqualToString:@"you_followed"])   return [NSString stringWithFormat:@"You followed %@ from the analyzer", username];
    if ([type isEqualToString:@"you_unfollowed"]) return [NSString stringWithFormat:@"You unfollowed %@ from the analyzer", username];
    if ([type isEqualToString:@"you_removed"])    return [NSString stringWithFormat:@"You removed %@ as a follower", username];
    if ([type isEqualToString:@"username"])       return [NSString stringWithFormat:@"@%@ changed their username to @%@", event[@"old"], event[@"new"]];
    if ([type isEqualToString:@"full_name"])      return [NSString stringWithFormat:@"%@ changed their name from \"%@\" to \"%@\"", username, event[@"old"], event[@"new"]];
    if ([type isEqualToString:@"profile_pic"])    return [NSString stringWithFormat:@"%@ changed their profile picture", username];

    return username;
}

@end
