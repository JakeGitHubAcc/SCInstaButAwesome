#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

///
/// Re-checks your followers when Instagram is opened, at most once per chosen interval,
/// and sends a notification when someone unfollows you or their profile disappears.
///
/// Needs at least one manual scan from the profile analyzer as a starting point.
///
@interface SCIAnalyzerMonitor : NSObject

+ (void)checkIfDue;

+ (void)requestNotificationPermission;

@end

NS_ASSUME_NONNULL_END
