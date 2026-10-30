#import "SCIAnalyzerMonitor.h"
#import "SCIAnalyzerAPI.h"
#import "SCIAnalyzerStore.h"
#import "../../Utils.h"
#import <UserNotifications/UserNotifications.h>

static NSUInteger const kMaxFollowersForAutoCheck = 20000;
static NSUInteger const kMaxBlockChecks = 10;

@implementation SCIAnalyzerMonitor

+ (double)intervalHours {
    double hours = [SCIUtils getDoublePref:@"analyzer_check_hours"];
    return hours >= 1 ? hours : 6;
}

+ (void)checkIfDue {
    if (![SCIUtils getBoolPref:@"analyzer_unfollow_alerts"]) return;

    NSString *pk = [[SCIAnalyzerAPI sharedInstance] currentUserPK];
    if (!pk) return;

    SCIAnalyzerStore *store = [SCIAnalyzerStore storeForUserPK:pk];
    if (store.scanInProgress || !store.lastScanDate) return;
    if (store.followerCount > kMaxFollowersForAutoCheck) return;
    if (-[store.lastScanDate timeIntervalSinceNow] < [self intervalHours] * 3600) return;

    store.scanInProgress = YES;
    NSLog(@"[SCInsta] Profile analyzer: checking followers for %@", pk);

    // Lets the check finish if Instagram is closed partway through
    __block UIBackgroundTaskIdentifier backgroundTask = [[UIApplication sharedApplication] beginBackgroundTaskWithName:@"SCInsta follower check" expirationHandler:^{
        [[UIApplication sharedApplication] endBackgroundTask:backgroundTask];
        backgroundTask = UIBackgroundTaskInvalid;
    }];

    void (^finish)(void) = ^{
        store.scanInProgress = NO;
        if (backgroundTask != UIBackgroundTaskInvalid) {
            [[UIApplication sharedApplication] endBackgroundTask:backgroundTask];
            backgroundTask = UIBackgroundTaskInvalid;
        }
    };

    [[SCIAnalyzerAPI sharedInstance] fetchUserListOfKind:@"followers" userPK:pk progress:nil isCancelled:nil completion:^(NSArray<NSDictionary *> *followers, NSError *error) {
        if (error) {
            NSLog(@"[SCInsta] Profile analyzer: follower check failed: %@", error.localizedDescription);
            finish();
            return;
        }

        NSArray *lost = [store saveScanWithFollowers:followers following:nil];
        if (!lost.count) {
            finish();
            return;
        }

        if (![SCIUtils getBoolPref:@"analyzer_block_check"]) {
            [self notifyLostFollowers:lost hidden:@[]];
            finish();
            return;
        }

        NSArray *toCheck = lost.count > kMaxBlockChecks ? [lost subarrayWithRange:NSMakeRange(0, kMaxBlockChecks)] : lost;
        [self checkVisibilityOfUsers:toCheck index:0 hidden:[NSMutableArray array] store:store completion:^(NSArray *hidden) {
            [self notifyLostFollowers:lost hidden:hidden];
            finish();
        }];
    }];
}

+ (void)checkVisibilityOfUsers:(NSArray<NSDictionary *> *)users
                         index:(NSUInteger)index
                        hidden:(NSMutableArray<NSDictionary *> *)hidden
                         store:(SCIAnalyzerStore *)store
                    completion:(void (^)(NSArray<NSDictionary *> *hidden))completion
{
    if (index >= users.count) {
        completion(hidden);
        return;
    }

    NSDictionary *user = users[index];
    [[SCIAnalyzerAPI sharedInstance] checkProfileVisible:user[@"pk"] completion:^(BOOL visible) {
        if (!visible) {
            [hidden addObject:user];
            [store recordHiddenProfile:user];
        }

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(1.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self checkVisibilityOfUsers:users index:index + 1 hidden:hidden store:store completion:completion];
        });
    }];
}

// MARK: - Notifications

+ (void)requestNotificationPermission {
    [[UNUserNotificationCenter currentNotificationCenter] requestAuthorizationWithOptions:(UNAuthorizationOptionAlert | UNAuthorizationOptionSound)
                                                                        completionHandler:^(BOOL granted, NSError *error) {}];
}

+ (void)notifyLostFollowers:(NSArray<NSDictionary *> *)lost hidden:(NSArray<NSDictionary *> *)hidden {
    NSMutableSet *hiddenPKs = [NSMutableSet set];
    for (NSDictionary *user in hidden) [hiddenPKs addObject:user[@"pk"]];

    NSString *title;
    NSMutableArray<NSString *> *lines = [NSMutableArray array];

    if (lost.count == 1) {
        NSDictionary *user = lost.firstObject;
        BOOL isHidden = [hiddenPKs containsObject:user[@"pk"]];

        title = isHidden
            ? [NSString stringWithFormat:@"@%@ may have blocked you", user[@"username"]]
            : [NSString stringWithFormat:@"@%@ unfollowed you", user[@"username"]];
        if (isHidden) [lines addObject:@"They stopped following you and their profile is no longer visible. They may also have deactivated."];
    }
    else {
        title = [NSString stringWithFormat:@"%lu people unfollowed you", (unsigned long)lost.count];

        NSMutableArray *names = [NSMutableArray array];
        for (NSDictionary *user in [lost subarrayWithRange:NSMakeRange(0, MIN(lost.count, 5))]) {
            [names addObject:[NSString stringWithFormat:@"@%@", user[@"username"]]];
        }
        [lines addObject:[names componentsJoinedByString:@", "]];
        if (lost.count > 5) [lines addObject:[NSString stringWithFormat:@"and %lu more", (unsigned long)lost.count - 5]];

        if (hidden.count) {
            NSMutableArray *hiddenNames = [NSMutableArray array];
            for (NSDictionary *user in hidden) [hiddenNames addObject:[NSString stringWithFormat:@"@%@", user[@"username"]]];
            [lines addObject:[NSString stringWithFormat:@"May have blocked you: %@", [hiddenNames componentsJoinedByString:@", "]]];
        }
    }

    NSString *body = [lines componentsJoinedByString:@"\n"];

    UNMutableNotificationContent *content = [UNMutableNotificationContent new];
    content.title = title;
    content.body = body;
    content.sound = [UNNotificationSound defaultSound];

    UNNotificationRequest *request = [UNNotificationRequest requestWithIdentifier:[NSUUID UUID].UUIDString content:content trigger:nil];
    [[UNUserNotificationCenter currentNotificationCenter] addNotificationRequest:request withCompletionHandler:nil];

    // Instagram may not show banners while it's open, so show a toast as well
    dispatch_async(dispatch_get_main_queue(), ^{
        if ([UIApplication sharedApplication].applicationState == UIApplicationStateActive) {
            [SCIUtils showToastForDuration:4.0 title:title subtitle:lost.count == 1 ? nil : body];
        }
    });
}

@end
