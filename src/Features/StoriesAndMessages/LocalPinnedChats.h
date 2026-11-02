#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

// Unlimited pinned chats, kept on this device. Instagram's servers cap real pins, so these are
// moved to the top of the inbox (after Instagram's own pins) by SCInsta instead.
@interface SCILocalPinnedChats : NSObject

+ (BOOL)isEnabled;
+ (BOOL)isPinned:(NSString *)threadId;
+ (void)togglePinned:(NSString *)threadId;

// Moves pinned chats in the inbox's list objects up, right after Instagram's own pinned chats
+ (NSArray *)reorderInboxObjects:(NSArray *)objects;

@end

NS_ASSUME_NONNULL_END
