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
        self.gradient.colors = [colors valueForKey:@"CGColor"];
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

// White embossed titles and white icons, like iOS 6 bars
static void SCIClassicStyleBarContents(UIView *view, UIView *skip) {
    for (UIView *subview in view.subviews) {
        if (subview == skip) continue;

        if ([subview isKindOfClass:[UILabel class]]) {
            UILabel *label = (UILabel *)subview;
            label.textColor = [UIColor whiteColor];
            label.shadowColor = [UIColor colorWithWhite:0 alpha:0.45];
            label.shadowOffset = CGSizeMake(0, -1);
        }
        else if ([subview isKindOfClass:[UIButton class]] || [subview isKindOfClass:[UIImageView class]]) {
            subview.tintColor = [UIColor whiteColor];
        }

        SCIClassicStyleBarContents(subview, skip);
    }
}

// Top bars: the iOS 6 blue-grey gradient
%hook IGNavigationBar
- (void)layoutSubviews {
    %orig;
    if (!SCIClassicTheme()) return;

    UIView *bar = (UIView *)self;
    SCIClassicBarBackground *background = objc_getAssociatedObject(bar, &kSCIClassicBackgroundKey);
    if (!background) {
        background = [[SCIClassicBarBackground alloc] initWithColors:@[SCIHex(0xB4C1D2), SCIHex(0x8496B0), SCIHex(0x6D83A1)]
                                                               gloss:NO
                                                             topLine:nil
                                                        topHighlight:[UIColor colorWithWhite:1 alpha:0.35]
                                                          bottomLine:SCIHex(0x2D3642)];
        objc_setAssociatedObject(bar, &kSCIClassicBackgroundKey, background, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    if (background.superview != bar) [bar insertSubview:background atIndex:0];
    else [bar sendSubviewToBack:background];

    // Reach up behind the status bar too
    CGFloat top = bar.window ? [bar convertPoint:CGPointZero toView:nil].y : 0;
    background.frame = CGRectMake(0, -MAX(0, top), bar.bounds.size.width, bar.bounds.size.height + MAX(0, top));

    SCIClassicStyleBarContents(bar, background);
}
%end

// Tab bar: glossy black
%hook IGTabBar
- (void)layoutSubviews {
    %orig;
    if (!SCIClassicTheme()) return;

    UIView *bar = (UIView *)self;
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
    Class buttonClass = NSClassFromString(@"IGTabBarButton");
    NSUInteger insertIndex = 0;
    for (NSUInteger i = 0; i < bar.subviews.count; i++) {
        UIView *subview = bar.subviews[i];
        if (subview == background) continue;

        BOOL holdsButtons = [subview isKindOfClass:buttonClass];
        for (UIView *child in subview.subviews) {
            if ([child isKindOfClass:buttonClass]) holdsButtons = YES;
        }
        if (holdsButtons) break;
        insertIndex = i + 1;
    }
    if (background.superview != bar || [bar.subviews indexOfObject:background] != MIN(insertIndex, bar.subviews.count - 1)) {
        [background removeFromSuperview];
        [bar insertSubview:background atIndex:MIN(insertIndex, bar.subviews.count)];
    }

    // Down over the home indicator area
    CGFloat bottom = bar.window ? bar.window.bounds.size.height - [bar convertPoint:CGPointMake(0, bar.bounds.size.height) toView:nil].y : 0;
    background.frame = CGRectMake(0, 0, bar.bounds.size.width, bar.bounds.size.height + MAX(0, bottom));
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

    button.tintColor = selected ? [UIColor whiteColor] : SCIHex(0x9A9A9A);
}

%hook IGTabBarButton
- (void)setSelected:(BOOL)selected {
    %orig;
    if (SCIClassicTheme()) SCIClassicUpdateTabButton((UIView *)self, selected);
}

- (void)layoutSubviews {
    %orig;
    if (SCIClassicTheme()) SCIClassicUpdateTabButton((UIView *)self, ((UIButton *)self).isSelected);
}
%end

%ctor {
    %init;

    if (SCIClassicTheme()) {
        // iOS 6 blue switches
        [[UISwitch appearance] setOnTintColor:SCIHex(0x2E7FE8)];
    }
}
