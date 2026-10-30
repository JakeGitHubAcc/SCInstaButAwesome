#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

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

- (instancetype)initWithUserPK:(NSString *)pk;

- (NSArray<NSDictionary *> *)usersForList:(SCIAnalyzerList)list;
+ (NSString *)titleForList:(SCIAnalyzerList)list;

- (BOOL)isFollower:(NSString *)pk;
- (BOOL)isFollowing:(NSString *)pk;

// Saves a fresh scan, recording what changed since the previous one
- (void)saveScanWithFollowers:(NSArray<NSDictionary *> *)followers following:(NSArray<NSDictionary *> *)following;

// Keeps the saved scan in sync after acting on a user from the analyzer
- (void)recordFollow:(NSDictionary *)user;
- (void)recordUnfollow:(NSDictionary *)user;
- (void)recordRemovedFollower:(NSDictionary *)user;

- (NSURL *)exportCSV;
- (void)clearAllData;

+ (NSString *)descriptionForEvent:(NSDictionary *)event;

@end

NS_ASSUME_NONNULL_END
