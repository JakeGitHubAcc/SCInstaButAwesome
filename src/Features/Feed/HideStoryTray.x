#import "../../Utils.h"
#import "../../InstagramHeaders.h"

// Disable story data source
%group SCIRenamed_IGMainStoryTrayDataSource
%hook IGMainStoryTrayDataSource
- (id)initWithUserSession:(id)arg1 {
    if ([SCIUtils getBoolPref:@"hide_stories_tray"]) {
        NSLog(@"[SCInsta] Hiding story tray");

        return nil;
    }
    
    return %orig;
}
%end
%end

%ctor {
    // Classes Instagram renamed (mostly rewritten in Swift); the newest name is tried first
    {
        Class cls = objc_getClass("_TtC25IGMainStoryTrayDataSource25IGMainStoryTrayDataSource") ?: objc_getClass("IGMainStoryTrayDataSource");
        if (cls) %init(SCIRenamed_IGMainStoryTrayDataSource, IGMainStoryTrayDataSource = cls);
    }
}
