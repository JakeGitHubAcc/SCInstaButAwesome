#import "../../Utils.h"
#import "NotesThemeRuntime.h"

static char targetStaticRef[] = "target";

%group SCIRenamed_IGDirectNotesCreationView
%hook IGDirectNotesCreationView
- (id)initWithViewModel:(id)model
         featureSupport:(IGNotesCreationFeatureSupportModel *)support
  presentationAnimation:(id)animation
 composerUpdateListener:(id)listener
               delegate:(id)delegate
             layoutType:(long long)type
            userSession:(id)session
{
    if ([SCIUtils getBoolPref:@"enable_notes_customization"]) {

        // enableAnimatedEmojisInCreation
        @try {
            [support setValue:@(YES) forKey:@"enableAnimatedEmojisInCreation"];
        }
        @catch (NSException *exception) {
            NSLog(@"[SCInsta] WARNING: %@\n\nFull object: %@", exception.reason, support);
        }

        // enableBubbleCustomization
        @try {
            [support setValue:@(YES) forKey:@"enableBubbleCustomization"];
        }
        @catch (NSException *exception) {
            NSLog(@"[SCInsta] WARNING: %@\n\nFull object: %@", exception.reason, support);
        }

        // enableRandomThemeGenerator
        @try {
            [support setValue:@(YES) forKey:@"enableRandomThemeGenerator"];
        }
        @catch (NSException *exception) {
            NSLog(@"[SCInsta] WARNING: %@\n\nFull object: %@", exception.reason, support);
        }
        
    }

    // Seasonal and limited time options, available any day
    if ([SCIUtils getBoolPref:@"notes_unlock_all_themes"]) {
        NSArray *enabled = [SCINotesThemeRuntime enableAllFeatureFlagsOnModel:support];
        NSLog(@"[SCInsta] Notes: enabled feature flags: %@", enabled);
    }

    return %orig(model, support, animation, listener, delegate, type, session);
}
%end
%end

// Demangled name: IGNotesBubbleCreationSwift.IGDirectNotesBubbleEditorColorPaletteView (453+)
//                 IGDirectNotesUISwift.IGDirectNotesBubbleEditorColorPaletteView (418 and earlier)
// The class to hook is picked in %ctor. Logos types `self` as `id` for such hooks,
// so SELF casts it back to the palette view inside this group.
typedef _TtC20IGDirectNotesUISwift41IGDirectNotesBubbleEditorColorPaletteView SCINotesPaletteView;
#define SELF ((SCINotesPaletteView *)self)

static NSString * const kSCIUserCustomization = @"user_led_customization";
static NSString * const kSCIIconCellID = @"SCINoteThemeIconCell";
static NSUInteger const kSCIIconsPerPage = 6;
static char kSCIOriginalSectionsKey;

// The theme last picked through SCInsta. The bubble editor keeps its own copy of the theme and sends
// that on Apply, which would drop SCInsta's colors, so the receiving hooks below swap this one in.
// Cleared when one of Instagram's themes is picked, on Clear, and when the editor opens.
static IGNotesCustomThemeCreationModel *sciPendingThemeModel;

static id SCIFindSubviewOfClass(UIView *view, Class cls) {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:cls]) return subview;
        id found = SCIFindSubviewOfClass(subview, cls);
        if (found) return found;
    }
    return nil;
}

// Rounded icon matching Instagram's palette cells: a gradient (or solid) swatch with an emoji on top
@interface SCINoteThemeIconCell : UICollectionViewCell
@property (nonatomic, strong) CAGradientLayer *swatch;
@property (nonatomic, strong) UILabel *label;
- (void)configureWithIcon:(NSDictionary *)icon;
@end

@implementation SCINoteThemeIconCell

- (instancetype)initWithFrame:(CGRect)frame {
    self = [super initWithFrame:frame];

    if (self) {
        self.swatch = [CAGradientLayer layer];
        self.swatch.startPoint = CGPointMake(0, 0);
        self.swatch.endPoint = CGPointMake(1, 1);
        self.swatch.masksToBounds = YES;
        self.swatch.borderColor = [UIColor whiteColor].CGColor;
        [self.contentView.layer addSublayer:self.swatch];

        self.label = [UILabel new];
        self.label.textAlignment = NSTextAlignmentCenter;
        self.label.adjustsFontSizeToFitWidth = YES;
        [self.contentView addSubview:self.label];

        self.isAccessibilityElement = YES;
        self.accessibilityTraits = UIAccessibilityTraitButton;
    }

    return self;
}

- (void)layoutSubviews {
    [super layoutSubviews];

    CGRect bounds = self.contentView.bounds;
    self.swatch.frame = bounds;
    self.swatch.cornerRadius = MIN(bounds.size.width, bounds.size.height) * 0.25;
    self.label.frame = CGRectInset(bounds, bounds.size.width * 0.15, bounds.size.height * 0.15);
    self.label.font = [UIFont systemFontOfSize:bounds.size.height * 0.45 weight:UIFontWeightSemibold];
}

- (void)configureWithIcon:(NSDictionary *)icon {
    NSString *kind = icon[@"kind"];
    NSArray *colors;

    if ([kind isEqualToString:@"custom"]) {
        colors = @[(id)[UIColor systemPinkColor].CGColor, (id)[UIColor systemOrangeColor].CGColor, (id)[UIColor systemPurpleColor].CGColor];
        self.label.text = @"+";
        self.label.textColor = [UIColor whiteColor];
    }
    else if ([kind isEqualToString:@"swap"]) {
        colors = @[(id)[UIColor blackColor].CGColor, (id)[UIColor whiteColor].CGColor];
        self.label.text = @"⇄";
        self.label.textColor = [UIColor systemGrayColor];
    }
    else if (icon[@"activationType"]) {
        // Instagram's own seasonal designs
        colors = @[(id)[UIColor colorWithWhite:0.18 alpha:1].CGColor, (id)[UIColor colorWithWhite:0.06 alpha:1].CGColor];
        self.label.text = icon[@"emoji"];
    }
    else {
        UIColor *start = icon[@"background"];
        UIColor *end = icon[@"gradientEnd"] ?: start;
        colors = @[(id)start.CGColor, (id)end.CGColor];
        self.label.text = icon[@"emoji"];
    }

    self.swatch.colors = colors;
    self.accessibilityLabel = icon[@"name"];
    [self updateSelectionStyle];
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    [self updateSelectionStyle];
}

- (void)updateSelectionStyle {
    self.swatch.borderWidth = self.selected ? 2.5 : 0;
    self.transform = self.selected ? CGAffineTransformMakeScale(1.08, 1.08) : CGAffineTransformIdentity;
}

@end

%group NotesPalette
%hook _TtC20IGDirectNotesUISwift41IGDirectNotesBubbleEditorColorPaletteView
%property (nonatomic, copy) UIColor *backgroundColor;
%property (nonatomic, copy) UIColor *textColor;
%property (nonatomic, copy) NSString *emojiText;
%property (nonatomic, copy) UIColor *gradientStartColor;
%property (nonatomic, copy) UIColor *gradientEndColor;
%property (nonatomic, copy) NSString *activationType;

- (void)didMoveToWindow {
    %orig;

    if (![SCIUtils getBoolPref:@"custom_note_themes"]) return;
    
    // Inject buttons once in view lifecycle
    static char didInjectButtons;
    if (objc_getAssociatedObject(SELF, &didInjectButtons)) {
        return;
    }

    __weak SCINotesPaletteView *weakSelf = SELF;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!SELF || !SELF.window) {
            return;
        }

        UIView *container = SELF.superview ?: SELF.window;
        if (!container) {
            return;
        }

        // Button config
        UIButtonConfiguration *config = [UIButtonConfiguration tintedButtonConfiguration];
        config.background.cornerRadius = 12.0;
        config.cornerStyle = UIButtonConfigurationCornerStyleFixed;
        config.contentInsets = NSDirectionalEdgeInsetsMake(13.7, 10, 13.7, 10);


        // Left button
        UIButton *leftButton = [UIButton buttonWithType:UIButtonTypeSystem];
        leftButton.configuration = config;
        leftButton.translatesAutoresizingMaskIntoConstraints = NO;
        leftButton.tintColor = [SCIUtils SCIColor_Primary];

        NSMutableAttributedString *attrTitleLeft = [[NSMutableAttributedString alloc] initWithString:@"Background"];
        [attrTitleLeft addAttribute:NSFontAttributeName
                          value:[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold]
                          range:NSMakeRange(0, attrTitleLeft.length)
        ];
        [leftButton setAttributedTitle:attrTitleLeft forState:UIControlStateNormal];
        [leftButton sizeToFit];

        [leftButton addAction:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
            [SELF presentColorPicker:@"Background"];
        }] forControlEvents:UIControlEventTouchUpInside];

        // Middle button
        UIButton *middleButton = [UIButton buttonWithType:UIButtonTypeSystem];
        middleButton.configuration = config;
        middleButton.translatesAutoresizingMaskIntoConstraints = NO;
        middleButton.tintColor = [SCIUtils SCIColor_Primary];

        NSMutableAttributedString *attrTitleMiddle = [[NSMutableAttributedString alloc] initWithString:@"Text"];
        [attrTitleMiddle addAttribute:NSFontAttributeName
                          value:[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold]
                          range:NSMakeRange(0, attrTitleMiddle.length)
        ];
        [middleButton setAttributedTitle:attrTitleMiddle forState:UIControlStateNormal];
        [middleButton sizeToFit];

        [middleButton addAction:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
            [SELF presentColorPicker:@"Text"];
        }] forControlEvents:UIControlEventTouchUpInside];

        // Right button
        UIButton *rightButton = [UIButton buttonWithType:UIButtonTypeSystem];
        rightButton.configuration = config;
        rightButton.translatesAutoresizingMaskIntoConstraints = NO;
        rightButton.tintColor = [SCIUtils SCIColor_Primary];

        NSMutableAttributedString *attrTitleRight = [[NSMutableAttributedString alloc] initWithString:@"Emoji"];
        [attrTitleRight addAttribute:NSFontAttributeName
                          value:[UIFont systemFontOfSize:14 weight:UIFontWeightSemibold]
                          range:NSMakeRange(0, attrTitleRight.length)
        ];
        [rightButton setAttributedTitle:attrTitleRight forState:UIControlStateNormal];
        [rightButton sizeToFit];

        [rightButton addAction:[UIAction actionWithHandler:^(__kindof UIAction * _Nonnull action) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Enter Emoji Text"
                                                                           message:@"Click the Apply button after this to see the emoji"
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            
            [alert addTextFieldWithConfigurationHandler:^(UITextField *textField) {
                textField.placeholder = @"Type emoji...";
            }];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"OK"
                                                      style:UIAlertActionStyleDefault
                                                    handler:^(UIAlertAction *action) {
                SELF.emojiText = alert.textFields[0].text;
                [SELF applySCICustomTheme:@"Emoji"];
            }]];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                      style:UIAlertActionStyleCancel
                                                    handler:nil]];
            
            UIViewController *vc = [SCIUtils nearestViewControllerForView:SELF];
            [vc presentViewController:alert animated:YES completion:nil];
        }] forControlEvents:UIControlEventTouchUpInside];


        // Create stack view (gradients and presets live in the color palette, see below)
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[leftButton, middleButton, rightButton]];
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.spacing = 15.0;
        stack.alignment = UIStackViewAlignmentCenter;
        stack.distribution = UIStackViewDistributionFillEqually;

        // Find max height among arranged subviews
        CGFloat maxHeight = 0.0;
        for (UIView *subview in stack.arrangedSubviews) {
            maxHeight = MAX(maxHeight, subview.bounds.size.height);
        }

        // Manual frame with side padding
        CGFloat bottomMargin = 15.0;
        
        CGRect viewFrame = [SELF convertRect:SELF.bounds toView:container];
        CGFloat y = CGRectGetMinY(viewFrame) - maxHeight - bottomMargin;
        CGFloat width = container.bounds.size.width - stack.spacing * 2;

        stack.frame = CGRectMake(stack.spacing, y, width, maxHeight);

        [stack layoutIfNeeded];
        [container addSubview:stack];

        objc_setAssociatedObject(
            SELF,
            &didInjectButtons,
            @YES,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    });
}

%new - (void)presentColorPicker:(NSString *)target {
    UIColorPickerViewController *colorPickerController = [[UIColorPickerViewController alloc] init];

    colorPickerController.delegate = (id<UIColorPickerViewControllerDelegate>)SELF; // cast to suppress warnings
    colorPickerController.title = [NSString stringWithFormat:@"%@ color", target];
    colorPickerController.modalPresentationStyle = UIModalPresentationPopover;
    colorPickerController.supportsAlpha = NO;

    // Show last picked color for type
    if ([target isEqualToString:@"Background"] || [target isEqualToString:@"GradientStart"]) {
        if (SELF.backgroundColor) colorPickerController.selectedColor = SELF.backgroundColor;
    }
    else if ([target isEqualToString:@"Text"]) {
        colorPickerController.selectedColor = SELF.textColor;
    }

    if ([target isEqualToString:@"GradientStart"]) colorPickerController.title = @"Gradient start color";
    else if ([target isEqualToString:@"GradientEnd"]) colorPickerController.title = @"Gradient end color";
    
    UIViewController *presentingVC = [SCIUtils nearestViewControllerForView:SELF];
    
    if (presentingVC != nil) {
        [presentingVC presentViewController:colorPickerController animated:YES completion:nil];
    }

    // Save which color target to update 
    objc_setAssociatedObject(
        presentingVC,
        &targetStaticRef,
        target,
        OBJC_ASSOCIATION_RETAIN_NONATOMIC
    );
}

// UIColorPickerViewControllerDelegate Protocol
%new - (void)colorPickerViewController:(UIColorPickerViewController *)viewController
                        didSelectColor:(UIColor *)color
                          continuously:(BOOL)continuously
{
    _TtC20IGDirectNotesUISwift41IGDirectNotesBubbleEditorColorPaletteView *bubbleEditorVC = [SCIUtils nearestViewControllerForView:SELF];
    
    NSString *target = objc_getAssociatedObject(bubbleEditorVC, &targetStaticRef);
    if (!target) return;
    
    // Gradient colors are applied once both are picked
    if ([target isEqualToString:@"GradientStart"]) {
        SELF.gradientStartColor = color;
        return;
    }
    if ([target isEqualToString:@"GradientEnd"]) return;

    // Update saved color target
    if ([target isEqualToString:@"Background"]) {
        SELF.backgroundColor = color;
    }
    else if ([target isEqualToString:@"Text"]) {
        SELF.textColor = color;
    }

    [SELF applySCICustomTheme:target];
};

%new - (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    UIViewController *presentingVC = [SCIUtils nearestViewControllerForView:SELF];
    NSString *target = objc_getAssociatedObject(presentingVC, &targetStaticRef);

    if ([target isEqualToString:@"GradientStart"]) {
        if (!SELF.gradientStartColor) SELF.gradientStartColor = viewController.selectedColor;

        // Wait for this picker to finish dismissing before showing the next one
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [SELF presentColorPicker:@"GradientEnd"];
        });
    }
    else if ([target isEqualToString:@"GradientEnd"]) {
        objc_setAssociatedObject(presentingVC, &targetStaticRef, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        UIColor *start = SELF.gradientStartColor ?: SELF.backgroundColor ?: [UIColor blackColor];
        [SELF applySCIThemeWithBackground:start text:SELF.textColor emoji:SELF.emojiText gradientEnd:viewController.selectedColor];
    }
}

%new - (void)applySCIPreset:(NSDictionary *)preset {
    [SELF applySCIThemeWithBackground:preset[@"background"] text:preset[@"text"] emoji:preset[@"emoji"] gradientEnd:preset[@"gradientEnd"] activationType:kSCIUserCustomization];
}

%new - (void)applySCIThemeWithBackground:(UIColor *)background text:(UIColor *)text emoji:(NSString *)emoji gradientEnd:(UIColor *)gradientEnd {
    [SELF applySCIThemeWithBackground:background text:text emoji:emoji gradientEnd:gradientEnd activationType:kSCIUserCustomization];
}

%new - (void)applySCIThemeWithBackground:(UIColor *)background text:(UIColor *)text emoji:(NSString *)emoji gradientEnd:(UIColor *)gradientEnd activationType:(NSString *)activationType {
    if (background) SELF.backgroundColor = background;
    if (text) SELF.textColor = text;
    if (emoji) SELF.emojiText = emoji;
    SELF.gradientEndColor = gradientEnd;
    SELF.activationType = activationType;

    IGNotesCustomThemeCreationModel *current = [SELF sciCurrentThemeModel];
    if (!current) return;

    // Gradients and activation types can only be set through Instagram's initializer
    NSArray *gradient = gradientEnd ? @[SELF.backgroundColor ?: [UIColor blackColor], gradientEnd] : nil;
    IGNotesCustomThemeCreationModel *model = [SCINotesThemeRuntime themeModelWithBackground:SELF.backgroundColor ?: [UIColor blackColor]
                                                                             gradientColors:gradient
                                                                                  textColor:SELF.textColor ?: [UIColor whiteColor]
                                                                                      emoji:SELF.emojiText
                                                                             activationType:activationType
                                                                                    basedOn:current];

    if (!model) {
        // Older or newer Instagram without that initializer: solid colors only
        model = current;
        [model setValue:SELF.backgroundColor forKey:@"backgroundColor"];
        if (SELF.textColor) {
            [model setValue:SELF.textColor forKey:@"textColor"];
            [model setValue:SELF.textColor forKey:@"secondaryTextColor"];
        }
        [model setValue:SELF.emojiText forKey:@"customEmoji"];

        if ((gradientEnd || activationType) && ![[NSUserDefaults standardUserDefaults] boolForKey:@"notes_gradient_unsupported_shown"]) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"notes_gradient_unsupported_shown"];

            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Not available in this Instagram version"
                                                                           message:@"Gradients and Instagram's seasonal designs need Instagram's note theme initializer, which this version doesn't have, so only solid colors are used.\n\nTo help add support, go to SCInsta settings > Debug > Copy note theme fields and share the result."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [[SCIUtils nearestViewControllerForView:SELF] presentViewController:alert animated:YES completion:nil];
        }
    }

    [SELF sciCommitThemeModel:model];
}

%new - (IGNotesCustomThemeCreationModel *)sciCurrentThemeModel {
    // Get notes composer vc
    _TtC20IGDirectNotesUISwift39IGDirectNotesBubbleEditorViewController *parentVC = [SCIUtils nearestViewControllerForView:SELF];
    if (![parentVC respondsToSelector:@selector(delegate)]) return nil;

    IGDirectNotesComposerViewController *composerVC = parentVC.delegate;
    if (!composerVC) return nil;

    // Get current theme model
    // A property since 453; 418 has the same getter backed by an underscored ivar
    IGNotesCustomThemeCreationModel *model = nil;
    @try {
        model = [composerVC valueForKey:@"selectedCustomThemeCreationModel"];
    }
    @catch (NSException *exception) {
        NSLog(@"[SCInsta] Notes: couldn't read selected theme: %@", exception.reason);
    }
    if (!model) {
        // Create new note theme model
        model = [[%c(IGNotesCustomThemeCreationModel) alloc] init];
    }

    return model;
}

%new - (void)sciCommitThemeModel:(IGNotesCustomThemeCreationModel *)model {
    _TtC20IGDirectNotesUISwift39IGDirectNotesBubbleEditorViewController *parentVC = [SCIUtils nearestViewControllerForView:SELF];
    if (![parentVC respondsToSelector:@selector(delegate)]) return;

    IGDirectNotesComposerViewController *composerVC = parentVC.delegate;
    if (![composerVC respondsToSelector:@selector(notesBubbleEditorViewControllerDidUpdateWithCustomThemeCreationModel:)]) return;

    // Apply custom notes theme, and remember it for when the editor hands its theme over on Apply
    sciPendingThemeModel = model;
    [composerVC notesBubbleEditorViewControllerDidUpdateWithCustomThemeCreationModel:model];

    // Enable apply/cancel buttons
    UIView *parentVCView = [parentVC view];
    if (!parentVCView) return;

    NSArray<UIView *> *parentVCSubviews = [parentVCView subviews];
    if (!parentVCSubviews) return;

    [parentVCSubviews enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if ([obj isKindOfClass:%c(IGDSBottomButtonsView)]) {
            [obj setPrimaryButtonEnabled:YES];
            [obj setSecondaryButtonEnabled:YES];
        }
    }];
}

%new - (void)applySCICustomTheme:(NSString *)target {
    // A new background color replaces any gradient or seasonal design; text and emoji changes keep them
    BOOL keepDesign = ![target isEqualToString:@"Background"];

    [SELF applySCIThemeWithBackground:nil
                                 text:nil
                                emoji:nil
                          gradientEnd:keepDesign ? SELF.gradientEndColor : nil
                       activationType:keepDesign && SELF.activationType ? SELF.activationType : kSCIUserCustomization];
}

// MARK: - SCInsta pages in the color palette

%new - (NSInteger)sciOriginalSectionCount {
    return [objc_getAssociatedObject(SELF, &kSCIOriginalSectionsKey) integerValue];
}

%new - (NSArray<NSArray<NSDictionary *> *> *)sciIconPages {
    static NSArray *pages;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        // Instagram's seasonal and hidden designs first, then SCInsta's own
        NSMutableArray *items = [NSMutableArray array];
        for (NSDictionary *theme in [SCINotesThemeRuntime instagramSeasonalThemes]) [items addObject:theme];
        [items addObject:@{ @"kind": @"custom", @"name": @"Custom gradient" }];
        [items addObject:@{ @"kind": @"swap", @"name": @"Swap background and text" }];
        for (NSDictionary *preset in [SCINotesThemeRuntime gradientPresets]) [items addObject:preset];
        for (NSDictionary *preset in [SCINotesThemeRuntime seasonalPresets]) [items addObject:preset];

        // Same page size as Instagram's own palette pages
        NSMutableArray *chunks = [NSMutableArray array];
        for (NSUInteger i = 0; i < items.count; i += kSCIIconsPerPage) {
            [chunks addObject:[items subarrayWithRange:NSMakeRange(i, MIN(kSCIIconsPerPage, items.count - i))]];
        }
        pages = chunks;
    });
    return [SCIUtils getBoolPref:@"custom_note_themes"] ? pages : @[];
}

%new - (NSDictionary *)sciIconAtIndexPath:(NSIndexPath *)indexPath {
    NSInteger page = indexPath.section - [SELF sciOriginalSectionCount];
    NSArray *pages = [SELF sciIconPages];
    if (page < 0 || page >= (NSInteger)pages.count || indexPath.item >= (NSInteger)[pages[page] count]) return nil;
    return pages[page][indexPath.item];
}

- (long long)numberOfSectionsInCollectionView:(UICollectionView *)collectionView {
    long long original = %orig;
    objc_setAssociatedObject(SELF, &kSCIOriginalSectionsKey, @(original), OBJC_ASSOCIATION_RETAIN_NONATOMIC);

    return original + [SELF sciIconPages].count;
}

- (long long)collectionView:(UICollectionView *)collectionView numberOfItemsInSection:(long long)section {
    NSInteger page = section - [SELF sciOriginalSectionCount];
    if (page < 0) return %orig;

    NSArray *pages = [SELF sciIconPages];
    return page < (NSInteger)pages.count ? [pages[page] count] : 0;
}

- (UICollectionViewCell *)collectionView:(UICollectionView *)collectionView cellForItemAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *icon = [SELF sciIconAtIndexPath:indexPath];
    if (!icon) return %orig;

    [collectionView registerClass:[SCINoteThemeIconCell class] forCellWithReuseIdentifier:kSCIIconCellID];
    SCINoteThemeIconCell *cell = [collectionView dequeueReusableCellWithReuseIdentifier:kSCIIconCellID forIndexPath:indexPath];
    [cell configureWithIcon:icon];
    return cell;
}

- (CGSize)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout sizeForItemAtIndexPath:(NSIndexPath *)indexPath {
    if (![SELF sciIconAtIndexPath:indexPath]) return %orig;

    // Match Instagram's color cells
    NSInteger lastOriginal = [SELF sciOriginalSectionCount] - 1;
    if (lastOriginal < 0) return CGSizeMake(44, 44);
    return %orig(collectionView, layout, [NSIndexPath indexPathForItem:0 inSection:lastOriginal]);
}

- (UIEdgeInsets)collectionView:(UICollectionView *)collectionView layout:(UICollectionViewLayout *)layout insetForSectionAtIndex:(long long)section {
    NSInteger page = section - [SELF sciOriginalSectionCount];
    NSArray *pages = [SELF sciIconPages];
    if (page < 0 || page >= (NSInteger)pages.count) return %orig;

    NSInteger lastOriginal = [SELF sciOriginalSectionCount] - 1;
    UIEdgeInsets insets = lastOriginal >= 0 ? %orig(collectionView, layout, lastOriginal) : UIEdgeInsetsZero;

    // Center this page's icons so every page is exactly one screen wide
    CGSize itemSize = [SELF collectionView:collectionView layout:layout sizeForItemAtIndexPath:[NSIndexPath indexPathForItem:0 inSection:section]];
    CGFloat spacing = [layout isKindOfClass:[UICollectionViewFlowLayout class]] ? ((UICollectionViewFlowLayout *)layout).minimumLineSpacing : 12.0;
    NSInteger count = [pages[page] count];
    CGFloat contentWidth = count * itemSize.width + MAX(0, count - 1) * spacing;
    CGFloat side = MAX(0, (collectionView.bounds.size.width - contentWidth) / 2.0);

    insets.left = side;
    insets.right = side;
    return insets;
}

- (void)collectionView:(UICollectionView *)collectionView didSelectItemAtIndexPath:(NSIndexPath *)indexPath {
    NSDictionary *icon = [SELF sciIconAtIndexPath:indexPath];

    if (!icon) {
        // One of Instagram's own themes; it replaces anything picked through SCInsta
        sciPendingThemeModel = nil;
        %orig;
        return;
    }

    NSString *kind = icon[@"kind"];
    if ([kind isEqualToString:@"custom"]) {
        SELF.gradientStartColor = nil;
        [SELF presentColorPicker:@"GradientStart"];
    }
    else if ([kind isEqualToString:@"swap"]) {
        UIColor *background = SELF.backgroundColor;
        [SELF applySCIThemeWithBackground:SELF.textColor ?: [UIColor whiteColor]
                                     text:background ?: [UIColor blackColor]
                                    emoji:SELF.emojiText
                              gradientEnd:nil
                           activationType:kSCIUserCustomization];
    }
    else if (icon[@"activationType"]) {
        [SELF applySCIThemeWithBackground:nil text:nil emoji:icon[@"emoji"] gradientEnd:nil activationType:icon[@"activationType"]];
    }
    else {
        [SELF applySCIPreset:icon];
    }
}

- (void)layoutSubviews {
    %orig;

    // Add the SCInsta pages to the page dots
    NSInteger total = [SELF sciOriginalSectionCount] + [SELF sciIconPages].count;
    UIPageControl *pageControl = SCIFindSubviewOfClass(SELF, [UIPageControl class]);
    if (pageControl && total > pageControl.numberOfPages && [SELF sciOriginalSectionCount] > 0) {
        pageControl.numberOfPages = total;
    }
}
%end
%end

// Receives the theme from the bubble editor: IGDirectNotesThemeEditorController in 453+,
// the composer in 418 and earlier. The class is picked in %ctor.
%group NotesThemeReceiver
%hook IGDirectNotesComposerViewController
- (void)notesBubbleEditorViewControllerDidUpdateWithCustomThemeCreationModel:(id)model {
    %orig(sciPendingThemeModel ?: model);
}
%end
%end

// The bubble editor itself (Instagram 453+ and 418 module names, picked in %ctor)
%group NotesBubbleEditor
%hook _TtC20IGDirectNotesUISwift39IGDirectNotesBubbleEditorViewController
- (void)presentFrom:(id)arg1 noteContainerView:(id)arg2 thoughtBubbleView:(id)arg3 pogView:(id)arg4 initialCustomThemeCreationModel:(id)arg5 shouldPresentEmojiPicker:(BOOL)arg6 noteText:(id)arg7 {
    sciPendingThemeModel = nil;
    %orig;
}

- (void)didTapClearButton {
    sciPendingThemeModel = nil;
    %orig;
}
%end
%end

%ctor {
    // Classes Instagram renamed (mostly rewritten in Swift); the newest name is tried first
    {
        Class cls = objc_getClass("_TtC25IGDirectNotesCreationView25IGDirectNotesCreationView") ?: objc_getClass("IGDirectNotesCreationView");
        if (cls) %init(SCIRenamed_IGDirectNotesCreationView, IGDirectNotesCreationView = cls);
    }

    %init;

    Class paletteClass = objc_getClass("_TtC26IGNotesBubbleCreationSwift41IGDirectNotesBubbleEditorColorPaletteView")
                      ?: objc_getClass("_TtC20IGDirectNotesUISwift41IGDirectNotesBubbleEditorColorPaletteView");

    if (paletteClass) {
        %init(NotesPalette, _TtC20IGDirectNotesUISwift41IGDirectNotesBubbleEditorColorPaletteView = paletteClass);
    }
    else {
        NSLog(@"[SCInsta] Notes: color palette view not found, custom note themes are unavailable");
    }

    Class receiverClass = objc_getClass("_TtC36IGDirectNotesCreationComposerUISwift34IGDirectNotesThemeEditorController")
                       ?: objc_getClass("IGDirectNotesComposerViewController");
    if (receiverClass) {
        %init(NotesThemeReceiver, IGDirectNotesComposerViewController = receiverClass);
    }

    Class editorClass = objc_getClass("_TtC26IGNotesBubbleCreationSwift39IGDirectNotesBubbleEditorViewController")
                     ?: objc_getClass("_TtC20IGDirectNotesUISwift39IGDirectNotesBubbleEditorViewController");
    if (editorClass) {
        %init(NotesBubbleEditor, _TtC20IGDirectNotesUISwift39IGDirectNotesBubbleEditorViewController = editorClass);
    }
}
