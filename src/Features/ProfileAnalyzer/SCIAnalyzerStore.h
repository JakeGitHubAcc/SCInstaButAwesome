#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Posted on the main queue whenever a store saves a scan
extern NSNotificationName const SCIAnalyzerStoreDidChangeNotification;

typedef NS_ENUM(NSInteger, SCIAnalyzerList) {
    SCIAnalyzerListMutuals,
    SCIAnalyzerListNotFollowingBack,   // You follow them, they don't follow you
    SCIAnalyzerListFans,               // They follow you, you don't follow them
    SCIAnalyzerListNewFollowers,
    SCIAnalyzerListLostFollowers,
    SCIAnalyzerListNewFollowing,
    SCIAnalyzerListUnfollowed,
};

///
/// Saved scans for one account, kept in Documents/SCInsta/ProfileAnalyzer/<pk>.
///
/// Users are dictionaries: pk, username, full_name, profile_pic_url, profile_pic_id, is_private, is_verified.
/// Events are dictionaries: date (NSNumber, unix time), type, pk, username, and optional old/new.
///
@interface SCIAnalyzerStore : NSObject

@property (nonatomic, readonly) NSString *userPK;
@property (nonatomic, readonly, nullable) NSDate *lastScanDate;
@property (nonatomic, readonly) NSUInteger followerCount;
@property (nonatomic, readonly) NSUInteger followingCount;
@property (nonatomic, readonly) NSArray<NSDictionary *> *events; // Newest first
@property (nonatomic, readonly) NSArray<NSDictionary *> *scans;  // Newest first

// One shared store per account, so the analyzer screen and background checks see the same data
+ (instancetype)storeForUserPK:(NSString *)pk;

// Set while a scan or background check is running for this account
@property (nonatomic) BOOL scanInProgress;

- (NSArray<NSDictionary *> *)usersForList:(SCIAnalyzerList)list;
+ (NSString *)titleForList:(SCIAnalyzerList)list;

- (BOOL)isFollower:(NSString *)pk;
- (BOOL)isFollowing:(NSString *)pk;

// Saves a fresh scan, recording what changed since the previous one, and returns the followers that were lost.
// Pass nil for `following` to keep the saved following list (used by background follower checks).
- (NSArray<NSDictionary *> *)saveScanWithFollowers:(NSArray<NSDictionary *> *)followers following:(nullable NSArray<NSDictionary *> *)following;

// Records that a lost follower's profile can no longer be loaded (blocked you or deactivated)
- (void)recordHiddenProfile:(NSDictionary *)user;

// Keeps the saved scan in sync after acting on a user from the analyzer
- (void)recordFollow:(NSDictionary *)user;
- (void)recordUnfollow:(NSDictionary *)user;
- (void)recordRemovedFollower:(NSDictionary *)user;

- (NSURL *)exportCSV;
- (void)clearAllData;

+ (NSString *)descriptionForEvent:(NSDictionary *)event;

@end

NS_ASSUME_NONNULL_END
