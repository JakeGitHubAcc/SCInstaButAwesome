#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, SCIAnalyzerFriendshipAction) {
    SCIAnalyzerFriendshipActionFollow,
    SCIAnalyzerFriendshipActionUnfollow,
    SCIAnalyzerFriendshipActionRemoveFollower,
};

///
/// Minimal client for Instagram's private API, used by the profile analyzer.
///
/// Auth headers are captured from the app's own requests (see AuthCapture.x),
/// with the shared cookie store as a fallback.
///
@interface SCIAnalyzerAPI : NSObject

+ (instancetype)sharedInstance;

- (void)captureHeaderValue:(nullable NSString *)value forField:(NSString *)field url:(nullable NSURL *)url;

// Logged in account (main thread only)
- (nullable NSString *)currentUserPK;
- (nullable NSString *)currentUsername;

// `kind` is either "followers" or "following"
- (void)fetchUserListOfKind:(NSString *)kind
                     userPK:(NSString *)pk
                   progress:(nullable void (^)(NSUInteger fetched))progress
                isCancelled:(nullable BOOL (^)(void))isCancelled
                 completion:(void (^)(NSArray<NSDictionary *> * _Nullable users, NSError * _Nullable error))completion;

// Whether the profile can still be loaded. Blocked and deactivated accounts both come back as not found;
// `visible` is YES when the result is unclear, so a network error is never reported as a block.
- (void)checkProfileVisible:(NSString *)pk completion:(void (^)(BOOL visible))completion;

- (void)performAction:(SCIAnalyzerFriendshipAction)action
               userPK:(NSString *)pk
           completion:(void (^)(NSError * _Nullable error))completion;

@end

NS_ASSUME_NONNULL_END
