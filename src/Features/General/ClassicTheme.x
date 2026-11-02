#import "../../Utils.h"

// Classic iOS theme: Instagram's top bars and tab bar in the style of iOS 6 (glossy gradients,
// embossed titles, a glowing selected tab). Instagram's own content keeps its look.

static BOOL SCIClassicTheme(void) {
    return [SCIUtils getBoolPref:@"classic_ios_theme"];
}

static UIColor *SCIHex(unsigned int value) {
    return [UIColor colorWithRed:((value >> 16) & 0xFF) / 255.0 green:((value >> 8) & 0xFF) / 255.0 blue:(value & 0xFF) / 255.0 alpha:1];
}

// A view drawing a vertical gradient, with an optional glossy top half and edge lines
@interface SCIClassicBarBackground : UIView
@property (nonatomic, strong) CAGradientLayer *gradient;
@property (nonatomic, strong) CAGradientLayer *gloss;
@property (nonatomic, strong) CALayer *topLine;
@property (nonatomic, strong) CALayer *topHighlight;
@property (nonatomic, strong) CALayer *bottomLine;
@end

@implementation SCIClassicBarBackground

- (instancetype)initWithColors:(NSArray<UIColor *> *)colors gloss:(BOOL)gloss topLine:(UIColor *)topLine topHighlight:(UIColor *)topHighlight bottomLine:(UIColor *)bottomLine {
    self = [super initWithFrame:CGRectZero];

    if (self) {
        self.userInteractionEnabled = NO;

        self.gradient = [CAGradientLayer layer];
        // CGColor isn't key-value coding compliant, so the array is built by hand
        NSMutableArray *cgColors = [NSMutableArray arrayWithCapacity:colors.count];
        for (UIColor *color in colors) [cgColors addObject:(__bridge id)color.CGColor];
        self.gradient.colors = cgColors;
        [self.layer addSublayer:self.gradient];

        if (gloss) {
            self.gloss = [CAGradientLayer layer];
            self.gloss.colors = @[(id)[UIColor colorWithWhite:1 alpha:0.14].CGColor, (id)[UIColor colorWithWhite:1 alpha:0.04].CGColor];
            [self.layer addSublayer:self.gloss];
        }

        CALayer *(^line)(UIColor *) = ^CALayer *(UIColor *color) {
            if (!color) return nil;
            CALayer *layer = [CALayer layer];
            layer.backgroundColor = color.CGColor;
            [self.layer addSublayer:layer];
            return layer;
        };
        self.topLine = line(topLine);
        self.topHighlight = line(topHighlight);
        self.bottomLine = line(bottomLine);
    }

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGRect bounds = self.bounds;
    CGFloat pixel = 1.0 / UIScreen.mainScreen.scale;

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    self.gradient.frame = bounds;
    self.gloss.frame = CGRectMake(0, 0, bounds.size.width, bounds.size.height / 2);
    self.topLine.frame = CGRectMake(0, 0, bounds.size.width, pixel);
    self.topHighlight.frame = CGRectMake(0, pixel, bounds.size.width, pixel);
    self.bottomLine.frame = CGRectMake(0, bounds.size.height - pixel, bounds.size.width, pixel);
    [CATransaction commit];
}

@end

static char kSCIClassicBackgroundKey;
static char kSCIClassicGlowKey;
static char kSCIClassicSelectedKey;
static char kSCIClassicLayingOutKey;

// Instagram re-lays out its bars when their colors change, so colors are only set when they differ
// and each bar's styling skips nested layout passes; otherwise the two loop until the app is killed
static void SCISetTint(UIView *view, UIColor *color) {
    if (![view.tintColor isEqual:color]) view.tintColor = color;
}

static BOOL SCIBeginClassicLayout(UIView *view) {
    if (objc_getAssociatedObject(view, &kSCIClassicLayingOutKey)) return NO;
    objc_setAssociatedObject(view, &kSCIClassicLayingOutKey, @YES, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    return YES;
}

static void SCIEndClassicLayout(UIView *view) {
    objc_setAssociatedObject(view, &kSCIClassicLayingOutKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

// White embossed titles and white icons, like iOS 6 bars
static void SCIClassicStyleBarContents(UIView *view, UIView *skip) {
    for (UIView *subview in view.subviews) {
        if (subview == skip) continue;

        if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)subview;
            if (![label.textColor isEqual:[UIColor whiteColor]]) label.textColor = [UIColor whiteColor];
            if (!label.shadowColor) {
                label.shadowColor = [UIColor colorWithWhite:0 alpha:0.45];
                label.shadowOffset = CGSizeMake(0, -1);
            }
        }
        else if ([subview isKindOfClass:[UIButton class]] || [subview isKindOfClass:[UIImageView class]]) {
            SCISetTint(subview, [UIColor whiteColor]);
        }

        SCIClassicStyleBarContents(subview, skip);
    }
}

// Top bars: the iOS 6 blue-grey gradient
%hook IGNavigationBar
- (void)layoutSubviews {
    %orig;

    UIView *bar = (UIView *)self;
    if (!SCIClassicTheme() || !SCIBeginClassicLayout(bar)) return;
    SCIClassicBarBackground *background = objc_getAssociatedObject(bar, &kSCIClassicBackgroundKey);
    if (!background) {
        background = [[SCIClassicBarBackground alloc] initWithColors:@[SCIHex(0xB4C1D2), SCIHex(0x8496B0), SCIHex(0x6D83A1)]
                                                               gloss:NO
                                                             topLine:nil
                                                        topHighlight:[UIColor colorWithWhite:1 alpha:0.35]
                                                          bottomLine:SCIHex(0x2D3642)];
        objc_setAssociatedObject(bar, &kSCIClassicBackgroundKey, background, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    // Only reorder when needed, so this doesn't trigger another layout pass
    if (background.superview != bar) [bar insertSubview:background atIndex:0];
    else if (bar.subviews.firstObject != background) [bar sendSubviewToBack:background];

    // Reach up behind the status bar too
    CGFloat top = bar.window ? [bar convertPoint:CGPointZero toView:nil].y : 0;
    background.frame = CGRectMake(0, -MAX(0, top), bar.bounds.size.width, bar.bounds.size.height + MAX(0, top));

    SCIClassicStyleBarContents(bar, background);
    SCIEndClassicLayout(bar);
}
%end

// Tab bar: glossy black
%hook IGTabBar
- (void)layoutSubviews {
    %orig;

    UIView *bar = (UIView *)self;
    if (!SCIClassicTheme() || !SCIBeginClassicLayout(bar)) return;
    SCIClassicBarBackground *background = objc_getAssociatedObject(bar, &kSCIClassicBackgroundKey);
    if (!background) {
        background = [[SCIClassicBarBackground alloc] initWithColors:@[SCIHex(0x3A3A3A), SCIHex(0x1C1C1C), SCIHex(0x0A0A0A)]
                                                               gloss:YES
                                                             topLine:[UIColor blackColor]
                                                        topHighlight:SCIHex(0x4D4D4D)
                                                          bottomLine:nil];
        objc_setAssociatedObject(bar, &kSCIClassicBackgroundKey, background, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    // Above Instagram's own background, below the views holding the tab buttons
    // (positions counted without the background itself; only reorder when needed)
    Class buttonClass = NSClassFromString(@"IGTabBarButton");
    NSMutableArray<UIView *> *others = [bar.subviews mutableCopy];
    [others removeObject:background];

    NSUInteger insertIndex = 0;
    for (NSUInteger i = 0; i < others.count; i++) {
        UIView *subview = others[i];
        BOOL holdsButtons = [subview isKindOfClass:buttonClass];
        for (UIView *child in subview.subviews) {
            if ([child isKindOfClass:buttonClass]) holdsButtons = YES;
        }
        if (holdsButtons) break;
        insertIndex = i + 1;
    }

    if (background.superview != bar || [bar.subviews indexOfObject:background] != insertIndex) {
        [background removeFromSuperview];
        [bar insertSubview:background atIndex:insertIndex];
    }

    // Down over the home indicator area
    CGFloat bottom = bar.window ? bar.window.bounds.size.height - [bar convertPoint:CGPointMake(0, bar.bounds.size.height) toView:nil].y : 0;
    CGRect frame = CGRectMake(0, 0, bar.bounds.size.width, bar.bounds.size.height + MAX(0, bottom));
    if (!CGRectEqualToRect(background.frame, frame)) background.frame = frame;
    SCIEndClassicLayout(bar);
}
%end

// Tab buttons: the selected one sits in a soft glowing square
static void SCIClassicUpdateTabButton(UIView *button, BOOL selected) {
    CAGradientLayer *glow = objc_getAssociatedObject(button, &kSCIClassicGlowKey);
    if (!glow) {
        glow = [CAGradientLayer layer];
        glow.colors = @[(id)[UIColor colorWithWhite:1 alpha:0.24].CGColor, (id)[UIColor colorWithWhite:1 alpha:0.07].CGColor];
        glow.cornerRadius = 5;
        glow.borderWidth = 1.0 / UIScreen.mainScreen.scale;
        glow.borderColor = [UIColor colorWithWhite:1 alpha:0.12].CGColor;
        objc_setAssociatedObject(button, &kSCIClassicGlowKey, glow, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        [button.layer insertSublayer:glow atIndex:0];
    }

    [CATransaction begin];
    [CATransaction setDisableActions:YES];
    CGRect bounds = button.bounds;
    CGFloat height = MIN(bounds.size.height - 6, 46);
    CGFloat width = MIN(bounds.size.width - 8, height * 1.25);
    glow.frame = CGRectMake(CGRectGetMidX(bounds) - width / 2, CGRectGetMidY(bounds) - height / 2, width, height);
    glow.hidden = !selected;
    [CATransaction commit];

    SCISetTint(button, selected ? [UIColor whiteColor] : SCIHex(0x9A9A9A));
}

// The selected state is remembered from setSelected:, as the button may not be a UIControl
%hook IGTabBarButton
- (void)setSelected:(BOOL)selected {
    %orig;

    UIView *button = (UIView *)self;
    objc_setAssociatedObject(button, &kSCIClassicSelectedKey, @(selected), OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    if (SCIClassicTheme() && SCIBeginClassicLayout(button)) {
        SCIClassicUpdateTabButton(button, selected);
        SCIEndClassicLayout(button);
    }
}

- (void)layoutSubviews {
    %orig;

    UIView *button = (UIView *)self;
    if (SCIClassicTheme() && SCIBeginClassicLayout(button)) {
        SCIClassicUpdateTabButton(button, [objc_getAssociatedObject(button, &kSCIClassicSelectedKey) boolValue]);
        SCIEndClassicLayout(button);
    }
}
%end

%ctor {
    %init;

    // Safety net: if the last launch with the theme on didn't survive its first seconds, turn the theme
    // off so Instagram can open (and say why once it has)
    NSUserDefaults *defaults = [NSUserDefaults standardUserDefaults];
    if (SCIClassicTheme() && [defaults boolForKey:@"classic_ios_theme_launching"]) {
        [defaults setBool:NO forKey:@"classic_ios_theme"];
        [defaults setBool:NO forKey:@"classic_ios_theme_launching"];

        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Classic iOS theme turned off"
                                                                           message:@"Instagram closed while starting with the theme on, so SCInsta turned it off."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [topMostController() presentViewController:alert animated:YES completion:nil];
        });
    }

    if (SCIClassicTheme()) {
        [defaults setBool:YES forKey:@"classic_ios_theme_launching"];
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(15 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [[NSUserDefaults standardUserDefaults] setBool:NO forKey:@"classic_ios_theme_launching"];
        });
    }

    if (SCIClassicTheme()) {
        // iOS 6 blue switches, once the app has started
        dispatch_async(dispatch_get_main_queue(), ^{
            [[UISwitch appearance] setOnTintColor:SCIHex(0x2E7FE8)];
        });
    }
}
