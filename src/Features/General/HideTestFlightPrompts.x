#import "../../Utils.h"

// Instagram Beta (TestFlight) builds show a full screen "It's time to update Instagram Beta" gate
// once the build is old, plus update nudges. Instagram decides it's a TestFlight build from the
// App Store receipt being named "sandboxReceipt", which sideloaded apps also have, so the receipt
// is reported with the App Store name instead.

static BOOL SCIHideTestFlightPrompts(void) {
    return [[NSUserDefaults standardUserDefaults] boolForKey:@"hide_testflight_prompts"];
}

%hook NSBundle
- (NSURL *)appStoreReceiptURL {
    NSURL *url = %orig;
    if (!SCIHideTestFlightPrompts() || self != [NSBundle mainBundle]) return url;

    if ([url.lastPathComponent isEqualToString:@"sandboxReceipt"]) {
        return [[url URLByDeletingLastPathComponent] URLByAppendingPathComponent:@"receipt"];
    }
    return url;
}
%end

// Backup for the "TestFlight Update Available" nudge
// Demangled name: IGCoreRootTestFlightNagPlugin.TestFlightUpdateNudgeViewController
%hook _TtC29IGCoreRootTestFlightNagPlugin35TestFlightUpdateNudgeViewController
- (void)viewDidAppear:(BOOL)animated {
    %orig;

    if (SCIHideTestFlightPrompts()) {
        [(UIViewController *)self dismissViewControllerAnimated:NO completion:nil];
    }
}
%end

%ctor {
    // On by default (registered so the settings switch shows it as on)
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{ @"hide_testflight_prompts": @YES }];

    %init;
}
