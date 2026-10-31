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

static NSString * const kSCIIconCellID = @"SCINoteThemeIconCell";
static NSUInteger const kSCIIconsPerPage = 6;
static char kSCIOriginalSectionsKey;
static char kSCIIconPagesKey;

// The theme last picked through SCInsta. The bubble editor keeps its own copy of the theme and sends
// that on Apply, which would drop SCInsta's colors, so the receiving hooks below swap this one in.
// Cleared when one of Instagram's themes is picked, on Clear, and when the editor opens.
static IGNotesCustomThemeCreationModel *sciPendingThemeModel;
static NSDictionary *sciPendingTheme; // The same theme as a dictionary, for fixing up the note request

static id SCIFindSubviewOfClass(UIView *view, Class cls) {
    for (UIView *subview in view.subviews) {
        if ([subview isKindOfClass:cls]) return subview;
        id found = SCIFindSubviewOfClass(subview, cls);
        if (found) return found;
    }
    return nil;
}

// Square icon matching Instagram's palette: a rounded swatch with a white outline
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
        self.swatch.startPoint = CGPointMake(0.5, 0);
        self.swatch.endPoint = CGPointMake(0.5, 1);
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

    // Square, centered, with room between neighbouring icons
    CGRect bounds = self.contentView.bounds;
    CGFloat side = MIN(bounds.size.width, bounds.size.height) * 0.82;
    CGRect square = CGRectMake(CGRectGetMidX(bounds) - side / 2, CGRectGetMidY(bounds) - side / 2, side, side);

    self.swatch.frame = square;
    self.swatch.cornerRadius = side * 0.24;
    self.label.frame = CGRectInset(square, side * 0.14, side * 0.14);
    self.label.font = [UIFont systemFontOfSize:side * 0.42 weight:UIFontWeightBold];
}

- (void)configureWithIcon:(NSDictionary *)icon {
    if ([icon[@"kind"] isEqualToString:@"swap"]) {
        self.swatch.colors = @[(id)[UIColor whiteColor].CGColor, (id)[UIColor blackColor].CGColor];
        self.swatch.locations = @[@0.5, @0.5];
        self.label.text = @"⇄";
        self.label.textColor = [UIColor systemGrayColor];
    }
    else {
        UIColor *background = [SCINotesThemeRuntime colorFromHex:icon[@"background"]] ?: [UIColor darkGrayColor];
        NSMutableArray *colors = [NSMutableArray array];
        for (NSString *hex in icon[@"gradient"]) [colors addObject:(id)[SCINotesThemeRuntime colorFromHex:hex].CGColor];
        if (colors.count < 2) colors = [@[(id)background.CGColor, (id)background.CGColor] mutableCopy];

        self.swatch.colors = colors;
        self.swatch.locations = nil;

        // Official designs show their emoji; color presets show their text color
        BOOL official = [SCINotesThemeRuntime isOfficialActivationType:icon[@"activationType"]];
        self.label.text = official ? (icon[@"emoji"] ?: @"") : @"Aa";
        self.label.textColor = [SCINotesThemeRuntime colorFromHex:icon[@"text"]] ?: [UIColor whiteColor];
    }

    self.accessibilityLabel = icon[@"name"];
    [self updateSelectionStyle];
}

- (void)setSelected:(BOOL)selected {
    [super setSelected:selected];
    [self updateSelectionStyle];
}

- (void)updateSelectionStyle {
    self.swatch.borderWidth = self.selected ? 3.5 : 2.0;
    self.transform = self.selected ? CGAffineTransformMakeScale(1.06, 1.06) : CGAffineTransformIdentity;
}

@end

%group NotesPalette
%hook _TtC20IGDirectNotesUISwift41IGDirectNotesBubbleEditorColorPaletteView
%property (nonatomic, copy) UIColor *backgroundColor;
%property (nonatomic, copy) UIColor *textColor;
%property (nonatomic, copy) NSString *emojiText;
%property (nonatomic, copy) NSDictionary *sciTheme;
%property (nonatomic, copy) NSString *sciUserEmoji; // Set with the Emoji button; official designs' emoji don't carry over

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
                SELF.sciUserEmoji = SELF.emojiText.length ? SELF.emojiText : nil;
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
    if ([target isEqualToString:@"Background"]) {
        if (SELF.backgroundColor) colorPickerController.selectedColor = SELF.backgroundColor;
    }
    else if ([target isEqualToString:@"Text"]) {
        if (SELF.textColor) colorPickerController.selectedColor = SELF.textColor;
    }
    
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
    
    // Update saved color target
    if ([target isEqualToString:@"Background"]) {
        SELF.backgroundColor = color;
    }
    else if ([target isEqualToString:@"Text"]) {
        SELF.textColor = color;
    }

    [SELF applySCICustomTheme:target];
};

// Applies a theme picked through SCInsta (see SCINotesThemeRuntime for the format)
%new - (void)applySCITheme:(NSDictionary *)theme {
    // Instagram's editor keeps state for its own official designs (like the Halloween 2026 bubble),
    // which would linger under SCInsta's theme, so reset it with Instagram's own Clear first
    if (!SELF.sciTheme) {
        NSDictionary *current = [SCINotesThemeRuntime themeFromModel:[SELF sciCurrentThemeModel]];
        UIViewController *editor = [SCIUtils nearestViewControllerForView:SELF];

        if ([SCINotesThemeRuntime isOfficialActivationType:current[@"activationType"]] && [editor respondsToSelector:@selector(didTapClearButton)]) {
            [editor performSelector:@selector(didTapClearButton)];
        }
    }

    SELF.sciTheme = theme;
    SELF.backgroundColor = [SCINotesThemeRuntime colorFromHex:theme[@"background"]];
    SELF.textColor = [SCINotesThemeRuntime colorFromHex:theme[@"text"]];
    SELF.emojiText = theme[@"emoji"];

    // Gradients, activation types and customization ids can only be set through Instagram's initializer
    IGNotesCustomThemeCreationModel *model = [SCINotesThemeRuntime themeModelForTheme:theme];

    if (!model) {
        // Instagram without that initializer: set the solid colors on the current model
        model = [SELF sciCurrentThemeModel];
        if (!model) return;

        @try {
            [model setValue:SELF.backgroundColor forKey:@"backgroundColor"];
            [model setValue:SELF.textColor forKey:@"textColor"];
            [model setValue:SELF.textColor forKey:@"secondaryTextColor"];
            [model setValue:SELF.emojiText forKey:@"customEmoji"];
        }
        @catch (NSException *exception) {
            NSLog(@"[SCInsta] Notes: couldn't update theme model: %@", exception.reason);
        }
    }

    sciPendingTheme = theme;
    [SELF sciCommitThemeModel:model];
}

// The theme being edited: the last one picked through SCInsta, else the editor's current one
%new - (NSDictionary *)sciBaseTheme {
    if (SELF.sciTheme) return SELF.sciTheme;
    return [SCINotesThemeRuntime themeFromModel:[SELF sciCurrentThemeModel]] ?: @{};
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
    NSMutableDictionary *theme = [[SELF sciBaseTheme] mutableCopy];

    if ([target isEqualToString:@"Emoji"]) {
        // An emoji change keeps the current design
        theme[@"emoji"] = SELF.sciUserEmoji;
    }
    else {
        // A new color turns any official design into a custom theme, which has no gradient or design id
        if ([target isEqualToString:@"Background"]) {
            theme[@"background"] = [SCINotesThemeRuntime hexForColor:SELF.backgroundColor];
        }
        else {
            theme[@"text"] = [SCINotesThemeRuntime hexForColor:SELF.textColor];
            theme[@"secondaryText"] = theme[@"text"];
        }

        // An official design's emoji belongs to the design
        if ([SCINotesThemeRuntime isOfficialActivationType:theme[@"activationType"]]) theme[@"emoji"] = SELF.sciUserEmoji;

        theme[@"activationType"] = SCINotesUserCustomization;
        [theme removeObjectsForKeys:@[@"customizationId", @"gradient", @"expressiveEmoji", @"name"]];
    }

    [SELF applySCITheme:theme];
}

// MARK: - SCInsta pages in the color palette

%new - (NSInteger)sciOriginalSectionCount {
    return [objc_getAssociatedObject(SELF, &kSCIOriginalSectionsKey) integerValue];
}

%new - (NSArray<NSArray<NSDictionary *> *> *)sciBuildIconPages {
    if (![SCIUtils getBoolPref:@"custom_note_themes"]) return @[];

    // Official designs saved from Instagram's palette first, then SCInsta's own
    NSMutableArray *items = [NSMutableArray array];
    [items addObjectsFromArray:[SCINotesThemeRuntime savedOfficialThemes]];
    [items addObject:@{ @"kind": @"swap", @"name": @"Swap background and text" }];
    [items addObjectsFromArray:[SCINotesThemeRuntime colorPresets]];

    // Same page size as Instagram's own palette pages
    NSMutableArray *pages = [NSMutableArray array];
    for (NSUInteger i = 0; i < items.count; i += kSCIIconsPerPage) {
        [pages addObject:[items subarrayWithRange:NSMakeRange(i, MIN(kSCIIconsPerPage, items.count - i))]];
    }
    return pages;
}

%new - (NSArray<NSArray<NSDictionary *> *> *)sciIconPages {
    NSArray *pages = objc_getAssociatedObject(SELF, &kSCIIconPagesKey);
    if (!pages) {
        pages = [SELF sciBuildIconPages];
        objc_setAssociatedObject(SELF, &kSCIIconPagesKey, pages, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }
    return pages;
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

    // Pick up official designs saved since the palette last loaded
    objc_setAssociatedObject(SELF, &kSCIIconPagesKey, [SELF sciBuildIconPages], OBJC_ASSOCIATION_RETAIN_NONATOMIC);

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

    // Square cells as tall as Instagram's (the icon inside leaves room between neighbours)
    NSInteger lastOriginal = [SELF sciOriginalSectionCount] - 1;
    if (lastOriginal < 0) return CGSizeMake(56, 56);
    CGSize original = %orig(collectionView, layout, [NSIndexPath indexPathForItem:0 inSection:lastOriginal]);
    CGFloat side = MIN(original.width, original.height);
    return CGSizeMake(side, side);
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
        sciPendingTheme = nil;
        SELF.sciTheme = nil;
        %orig;
        return;
    }

    if ([icon[@"kind"] isEqualToString:@"swap"]) {
        NSMutableDictionary *theme = [[SELF sciBaseTheme] mutableCopy];
        NSString *background = theme[@"background"] ?: @"000000";
        theme[@"background"] = theme[@"text"] ?: @"FFFFFF";
        theme[@"text"] = background;
        theme[@"secondaryText"] = background;
        if ([SCINotesThemeRuntime isOfficialActivationType:theme[@"activationType"]]) theme[@"emoji"] = SELF.sciUserEmoji;
        theme[@"activationType"] = SCINotesUserCustomization;
        [theme removeObjectsForKeys:@[@"customizationId", @"gradient", @"expressiveEmoji", @"name"]];
        [SELF applySCITheme:theme];
        return;
    }

    NSMutableDictionary *theme = [icon mutableCopy];
    [theme removeObjectForKey:@"name"];

    // Color presets keep an emoji you set yourself; official designs bring their own
    if (![SCINotesThemeRuntime isOfficialActivationType:theme[@"activationType"]] && SELF.sciUserEmoji) {
        theme[@"emoji"] = SELF.sciUserEmoji;
    }

    [SELF applySCITheme:theme];
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
    if (sciPendingThemeModel) {
        [SCINotesThemeRuntime setAppliedTheme:sciPendingTheme];
        %orig(sciPendingThemeModel);
        return;
    }

    // Instagram's own theme: remember official designs so they can be used after their event
    [SCINotesThemeRuntime setAppliedTheme:nil];
    if (model) [SCINotesThemeRuntime saveOfficialThemeFromModel:model];
    %orig;
}
%end
%end

// The bubble editor itself (Instagram 453+ and 418 module names, picked in %ctor)
%group NotesBubbleEditor
%hook _TtC20IGDirectNotesUISwift39IGDirectNotesBubbleEditorViewController
- (void)presentFrom:(id)arg1 noteContainerView:(id)arg2 thoughtBubbleView:(id)arg3 pogView:(id)arg4 initialCustomThemeCreationModel:(id)arg5 shouldPresentEmojiPicker:(BOOL)arg6 noteText:(id)arg7 {
    sciPendingThemeModel = nil;
    sciPendingTheme = nil;
    %orig;
}

- (void)didTapClearButton {
    sciPendingThemeModel = nil;
    sciPendingTheme = nil;
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
