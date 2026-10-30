#import "../../Utils.h"

///////////////////////////////////////////////////////////

// Confirmation handlers

#define CONFIRMPOSTLIKE(orig)                             \
    if ([SCIUtils getBoolPref:@"like_confirm"]) {           \
        NSLog(@"[SCInsta] Confirm post like triggered");  \
                                                          \
        [SCIUtils showConfirmation:^(void) { orig; }];    \
    }                                                     \
    else {                                                \
        return orig;                                      \
    }                                                     \

#define CONFIRMREELSLIKE(orig)                            \
    if ([SCIUtils getBoolPref:@"like_confirm_reels"]) {     \
        NSLog(@"[SCInsta] Confirm reels like triggered"); \
                                                          \
        [SCIUtils showConfirmation:^(void) { orig; }];    \
    }                                                     \
    else {                                                \
        return orig;                                      \
    }                                                     \

///////////////////////////////////////////////////////////

// Liking posts
%hook IGUFIButtonBarView
- (void)_onLikeButtonPressed:(id)arg1 {
    CONFIRMPOSTLIKE(%orig);
}

// Instagram 453+
- (void)_onLikeButtonPressed {
    CONFIRMPOSTLIKE(%orig);
}
%end
%hook IGFeedPhotoView
- (void)_onDoubleTap:(id)arg1 {
    CONFIRMPOSTLIKE(%orig);
}
%end
%group SCIRenamed_IGVideoPlayerOverlayContainerView
%hook IGVideoPlayerOverlayContainerView
- (void)_handleDoubleTapGesture:(id)arg1 {
    CONFIRMPOSTLIKE(%orig);
}

// Instagram 453+
- (void)handleDoubleTapGesture:(id)arg1 {
    CONFIRMPOSTLIKE(%orig);
}
%end
%end

// Liking reels
%hook IGSundialViewerVideoCell
- (void)controlsOverlayControllerDidTapLikeButton:(id)arg1 {
    CONFIRMREELSLIKE(%orig);
}
- (void)controlsOverlayControllerDidLongPressLikeButton:(id)arg1 gestureRecognizer:(id)arg2 {
    CONFIRMREELSLIKE(%orig);
}
- (void)gestureController:(id)arg1 didObserveDoubleTap:(id)arg2 {
    CONFIRMREELSLIKE(%orig);
}
%end
%hook IGSundialViewerPhotoCell
- (void)controlsOverlayControllerDidTapLikeButton:(id)arg1 {
    CONFIRMREELSLIKE(%orig);
}
- (void)gestureController:(id)arg1 didObserveDoubleTap:(id)arg2 {
    CONFIRMREELSLIKE(%orig);
}
%end
%hook IGSundialViewerCarouselCell
- (void)controlsOverlayControllerDidTapLikeButton:(id)arg1 {
    CONFIRMREELSLIKE(%orig);
}
- (void)gestureController:(id)arg1 didObserveDoubleTap:(id)arg2 {
    CONFIRMREELSLIKE(%orig);
}
%end

// Liking comments
%hook IGCommentCellController
- (void)commentCell:(id)arg1 didTapLikeButton:(id)arg2 {
    CONFIRMPOSTLIKE(%orig);
}
- (void)commentCell:(id)arg1 didTapLikedByButtonForUser:(id)arg2 {
    CONFIRMPOSTLIKE(%orig);
}
- (void)commentCellDidLongPressOnLikeButton:(id)arg1 {
    CONFIRMPOSTLIKE(%orig);
}
- (void)commentCellDidEndLongPressOnLikeButton:(id)arg1 {
    CONFIRMPOSTLIKE(%orig);
}
- (void)commentCellDidDoubleTap:(id)arg1 {
    CONFIRMPOSTLIKE(%orig);
}
%end
%hook IGFeedItemPreviewCommentCell
- (void)_didTapLikeButton {
    CONFIRMPOSTLIKE(%orig);
}
%end

// Liking stories
%group SCIRenamed_IGStoryFullscreenDefaultFooterView
%hook IGStoryFullscreenDefaultFooterView
- (void)_handleLikeTapped {
    CONFIRMPOSTLIKE(%orig);
}
- (void)_likeTapped {
    CONFIRMPOSTLIKE(%orig);
}
- (void)inputView:(id)arg1 didTapLikeButton:(id)arg2 {
    CONFIRMPOSTLIKE(%orig);
}

// For some stupid reason they removed the "liketapped" methods on newer Instagram versions
// Now we have to do a shitty workaround instead :(
// Works 99% of the time, but sometimes clicks get through directly to the like button (somehow)
- (void)layoutSubviews {
    %orig;

    if (![SCIUtils getBoolPref:@"like_confirm"]) return;

    // The Swift footer in 453+ may not expose likeButton to KVC
    UIButton *likeButton = nil;
    @try {
        likeButton = [self valueForKey:@"likeButton"];
    }
    @catch (NSException *exception) {
        return;
    }
    if (![likeButton isKindOfClass:[UIButton class]]) return;

    // 129115 = L(12) I(9) K(11) E(5)
    static NSInteger kOverlayTag = 129115;
    if ([likeButton viewWithTag:kOverlayTag]) return;

    UIButton *overlay = [UIButton buttonWithType:UIButtonTypeCustom];
    overlay.tag = kOverlayTag;
    overlay.frame = likeButton.bounds;
    overlay.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [overlay addTarget:self action:@selector(overlayTapped:) forControlEvents:UIControlEventTouchUpInside];
    [likeButton addSubview:overlay];
}

%new - (void)overlayTapped:(UIButton *)overlay {
    UIButton *likeButton = (UIButton *)overlay.superview;

    [SCIUtils showConfirmation:^{
        dispatch_async(dispatch_get_main_queue(), ^{
            [likeButton sendActionsForControlEvents:UIControlEventTouchUpInside];
        });
    }];
}
%end
%end

// DM like button (seems to be hidden)
%hook IGDirectThreadViewController
- (void)_didTapLikeButton {
    CONFIRMPOSTLIKE(%orig);
}
%end

%ctor {
    %init;

    // Classes Instagram renamed (mostly rewritten in Swift); the newest name is tried first
    {
        Class cls = objc_getClass("_TtC25IGModernFeedVideoOverlays33IGVideoPlayerOverlayContainerView") ?: objc_getClass("IGVideoPlayerOverlayContainerView");
        if (cls) %init(SCIRenamed_IGVideoPlayerOverlayContainerView, IGVideoPlayerOverlayContainerView = cls);
    }
    {
        Class cls = objc_getClass("_TtC20IGStoryDefaultFooter34IGStoryFullscreenDefaultFooterView") ?: objc_getClass("IGStoryFullscreenDefaultFooterView");
        if (cls) %init(SCIRenamed_IGStoryFullscreenDefaultFooterView, IGStoryFullscreenDefaultFooterView = cls);
    }
}
