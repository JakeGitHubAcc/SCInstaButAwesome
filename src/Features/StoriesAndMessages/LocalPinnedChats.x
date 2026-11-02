#import "../../Utils.h"
#import "LocalPinnedChats.h"

static NSString * const kSCILocalPinsKey = @"local_pinned_threads"; // Thread ids, newest pin first
static char kSCIPinButtonKey;

@implementation SCILocalPinnedChats

+ (BOOL)isEnabled {
    return [SCIUtils getBoolPref:@"local_pinned_chats"];
}

+ (NSArray<NSString *> *)pinnedThreadIds {
    return [[NSUserDefaults standardUserDefaults] stringArrayForKey:kSCILocalPinsKey] ?: @[];
}

+ (BOOL)isPinned:(NSString *)threadId {
    return threadId.length && [[self pinnedThreadIds] containsObject:threadId];
}

+ (void)togglePinned:(NSString *)threadId {
    if (!threadId.length) return;

    NSMutableArray *pins = [[self pinnedThreadIds] mutableCopy];
    if ([pins containsObject:threadId]) [pins removeObject:threadId];
    else [pins insertObject:threadId atIndex:0];

    [[NSUserDefaults standardUserDefaults] setObject:pins forKey:kSCILocalPinsKey];
}

+ (NSString *)threadIdOf:(id)object {
    if (![object respondsToSelector:@selector(threadId)]) return nil;
    id threadId = [object valueForKey:@"threadId"];
    return threadId ? [NSString stringWithFormat:@"%@", threadId] : nil;
}

+ (NSArray *)reorderInboxObjects:(NSArray *)objects {
    NSArray *pins = [self pinnedThreadIds];
    if (![self isEnabled] || !pins.count) return objects;

    Class threadClass = NSClassFromString(@"IGDirectInboxThreadCellViewModel");
    NSMutableArray *result = [NSMutableArray arrayWithCapacity:objects.count];
    NSMutableDictionary<NSString *, id> *pinned = [NSMutableDictionary dictionary];

    for (id object in objects) {
        NSString *threadId = [object isKindOfClass:threadClass] ? [self threadIdOf:object] : nil;
        if (threadId && [pins containsObject:threadId] && ![[object valueForKey:@"isPinned"] boolValue]) {
            pinned[threadId] = object;
        }
        else {
            [result addObject:object];
        }
    }
    if (!pinned.count) return objects;

    // Right after Instagram's own pinned chats, or where the chat list starts
    NSUInteger insertIndex = NSNotFound;
    for (NSUInteger i = 0; i < result.count; i++) {
        if (![result[i] isKindOfClass:threadClass]) continue;
        if (insertIndex == NSNotFound) insertIndex = i;
        if ([[result[i] valueForKey:@"isPinned"] boolValue]) insertIndex = i + 1;
    }
    if (insertIndex == NSNotFound) insertIndex = result.count;

    for (NSString *threadId in [pins reverseObjectEnumerator]) {
        id object = pinned[threadId];
        if (!object) continue;

        // Show Instagram's own pin icon on the row
        @try { [object setValue:@YES forKey:@"isPinned"]; }
        @catch (NSException *exception) {}

        [result insertObject:object atIndex:insertIndex];
    }

    return [result copy];
}

@end

static void SCIUpdatePinButton(UIButton *button, BOOL pinned) {
    UIImageSymbolConfiguration *configuration = [UIImageSymbolConfiguration configurationWithPointSize:15 weight:UIImageSymbolWeightSemibold];
    [button setImage:[UIImage systemImageNamed:pinned ? @"pin.fill" : @"pin" withConfiguration:configuration] forState:UIControlStateNormal];
    button.tintColor = pinned ? [SCIUtils SCIColor_Primary] : [UIColor labelColor];
    button.accessibilityLabel = pinned ? @"Unpin chat (SCInsta)" : @"Pin chat (SCInsta)";
}

// A pin button under the chat's header
%hook IGDirectThreadViewController
- (void)viewDidLayoutSubviews {
    %orig;
    if (![SCILocalPinnedChats isEnabled]) return;

    UIViewController *controller = (UIViewController *)self;
    NSString *threadId = [SCILocalPinnedChats threadIdOf:controller];
    if (!threadId.length) return;

    UIButton *button = objc_getAssociatedObject(controller, &kSCIPinButtonKey);
    if (!button) {
        button = [UIButton buttonWithType:UIButtonTypeSystem];
        button.backgroundColor = [[UIColor secondarySystemBackgroundColor] colorWithAlphaComponent:0.9];
        button.layer.cornerRadius = 18;
        button.layer.shadowColor = [UIColor blackColor].CGColor;
        button.layer.shadowOpacity = 0.15;
        button.layer.shadowRadius = 4;
        button.layer.shadowOffset = CGSizeMake(0, 1);

        __weak UIViewController *weakController = controller;
        __weak UIButton *weakButton = button;
        [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
            NSString *currentId = [SCILocalPinnedChats threadIdOf:weakController];
            if (!currentId.length) return;

            [SCILocalPinnedChats togglePinned:currentId];
            BOOL pinned = [SCILocalPinnedChats isPinned:currentId];
            SCIUpdatePinButton(weakButton, pinned);

            JGProgressHUD *hud = [[JGProgressHUD alloc] init];
            hud.textLabel.text = pinned ? @"Pinned to the top of your inbox" : @"Unpinned";
            hud.indicatorView = [[JGProgressHUDSuccessIndicatorView alloc] init];
            hud.userInteractionEnabled = NO;
            [hud showInView:weakController.view];
            [hud dismissAfterDelay:1.2];
        }] forControlEvents:UIControlEventTouchUpInside];

        objc_setAssociatedObject(controller, &kSCIPinButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    if (button.superview != controller.view) [controller.view addSubview:button];
    else [controller.view bringSubviewToFront:button];

    SCIUpdatePinButton(button, [SCILocalPinnedChats isPinned:threadId]);

    // Just below the header, on the right
    CGFloat headerBottom = controller.view.safeAreaInsets.top;
    if ([controller respondsToSelector:NSSelectorFromString(@"customHeaderViewFrame")]) {
        CGRect header = ((CGRect (*)(id, SEL))objc_msgSend)(controller, NSSelectorFromString(@"customHeaderViewFrame"));
        if (CGRectGetMaxY(header) > 0) headerBottom = CGRectGetMaxY(header);
    }
    button.frame = CGRectMake(controller.view.bounds.size.width - 36 - 12, headerBottom + 8, 36, 36);
}
%end

%ctor {
    // On by default (registered so the settings switch shows it as on)
    [[NSUserDefaults standardUserDefaults] registerDefaults:@{ @"local_pinned_chats": @YES }];

    %init;
}
