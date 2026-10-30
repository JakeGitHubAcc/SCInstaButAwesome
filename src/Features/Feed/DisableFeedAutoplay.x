#import "../../Utils.h"

// Demangled name: IGFeedPlayback.IGFeedPlaybackStrategy
%hook _TtC14IGFeedPlayback22IGFeedPlaybackStrategy
- (id)initWithShouldDisableAutoplay:(_Bool)autoplay {
    if ([SCIUtils getBoolPref:@"disable_feed_autoplay"]) return %orig(true);

    return %orig(autoplay);
}

// Instagram 453+
- (id)initWithShouldDisableAutoplay:(_Bool)autoplay shouldClearStaleReservation:(_Bool)arg2 {
    return %orig([SCIUtils getBoolPref:@"disable_feed_autoplay"] ? true : autoplay, arg2);
}

- (id)initWithShouldDisableAutoplay:(_Bool)autoplay shouldClearStaleReservation:(_Bool)arg2 shouldBypassDisabledAutoplayForVoiceover:(_Bool)arg3 {
    return %orig([SCIUtils getBoolPref:@"disable_feed_autoplay"] ? true : autoplay, arg2, arg3);
}

- (id)initWithShouldDisableAutoplay:(_Bool)autoplay shouldClearStaleReservation:(_Bool)arg2 shouldBypassDisabledAutoplayForVoiceover:(_Bool)arg3 shouldOverrideDefaultThresholds:(_Bool)arg4 mobileConfig:(id)arg5 {
    return %orig([SCIUtils getBoolPref:@"disable_feed_autoplay"] ? true : autoplay, arg2, arg3, arg4, arg5);
}
%end