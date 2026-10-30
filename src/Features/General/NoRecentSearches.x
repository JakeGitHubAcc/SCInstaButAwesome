#import "../../Utils.h"
#import "../../InstagramHeaders.h"

// Disable logging of searches at server-side
%group SCIRenamed_IGSearchEntityRouter
%hook IGSearchEntityRouter
- (id)initWithUserSession:(id)arg1 analyticsModule:(id)arg2 shouldAddToRecents:(BOOL)shouldAddToRecents {
    if ([SCIUtils getBoolPref:@"no_recent_searches"]) {
        NSLog(@"[SCInsta] Disabling recent searches");

        shouldAddToRecents = false;
    }
    
    return %orig(arg1, arg2, shouldAddToRecents);
}
%end
%end

// Most in-app search bars
%group SCIRenamed_IGRecentSearchStore
%hook IGRecentSearchStore
- (id)initWithDiskManager:(id)arg1 recentSearchStoreConfiguration:(id)arg2 {
    if ([SCIUtils getBoolPref:@"no_recent_searches"]) {
        NSLog(@"[SCInsta] Disabling recent searches");

        return nil;
    }

    return %orig;
}
- (BOOL)addItem:(id)arg1 {
    if ([SCIUtils getBoolPref:@"no_recent_searches"]) {
        NSLog(@"[SCInsta] Disabling recent searches");

        return nil;
    }

    return %orig;
}
%end
%end

// Recent dm message recipients search bar
%hook IGDirectRecipientRecentSearchStorage
- (id)initWithDiskManager:(id)arg1 directCache:(id)arg2 userStore:(id)arg3 currentUser:(id)arg4 featureSets:(id)arg5 {
    if ([SCIUtils getBoolPref:@"no_recent_searches"]) {
        NSLog(@"[SCInsta] Disabling recent searches");

        return nil;
    }

    return %orig;
}
%end

%ctor {
    %init;

    // Classes Instagram renamed (mostly rewritten in Swift); the newest name is tried first
    {
        Class cls = objc_getClass("_TtC19IGRecentSearchStore19IGRecentSearchStore") ?: objc_getClass("IGRecentSearchStore");
        if (cls) %init(SCIRenamed_IGRecentSearchStore, IGRecentSearchStore = cls);
    }
    {
        Class cls = objc_getClass("_TtC20IGSearchEntityRouter20IGSearchEntityRouter") ?: objc_getClass("IGSearchEntityRouter");
        if (cls) %init(SCIRenamed_IGSearchEntityRouter, IGSearchEntityRouter = cls);
    }
}
