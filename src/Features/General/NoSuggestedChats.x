#import "../../Utils.h"
#import "../../InstagramHeaders.h"

// Channels dms tab (header)
%group SCIRenamed_IGDirectInboxHeaderSectionController
%hook IGDirectInboxHeaderSectionController
- (id)viewModel {
    if ([[%orig title] isEqualToString:@"Suggested"]) {

        if ([SCIUtils getBoolPref:@"no_suggested_chats"]) {
            NSLog(@"[SCInsta] Hiding suggested chats (header: channels tab)");

            return nil;
        }

    }

    return %orig;
}
%end
%end

%ctor {
    // Classes Instagram renamed (mostly rewritten in Swift); the newest name is tried first
    {
        Class cls = objc_getClass("_TtC32IGDirectInboxViewControllerSwift36IGDirectInboxHeaderSectionController") ?: objc_getClass("IGDirectInboxHeaderSectionController");
        if (cls) %init(SCIRenamed_IGDirectInboxHeaderSectionController, IGDirectInboxHeaderSectionController = cls);
    }
}
