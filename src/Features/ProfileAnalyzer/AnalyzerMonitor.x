#import "../../Utils.h"
#import "SCIAnalyzerMonitor.h"

%ctor {
    // Wait a bit after Instagram becomes active, so it has made a few requests and the session headers are captured
    [[NSNotificationCenter defaultCenter] addObserverForName:UIApplicationDidBecomeActiveNotification
                                                      object:nil
                                                       queue:[NSOperationQueue mainQueue]
                                                  usingBlock:^(NSNotification *notification) {
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [SCIAnalyzerMonitor checkIfDue];
        });
    }];
}
