#import "../../Utils.h"
#import "NotesThemeRuntime.h"

static char targetStaticRef[] = "target";

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

// Demangled name: IGNotesBubbleCreationSwift.IGDirectNotesBubbleEditorColorPaletteView (453+)
//                 IGDirectNotesUISwift.IGDirectNotesBubbleEditorColorPaletteView (418 and earlier)
// The class to hook is picked in %ctor
%group NotesPalette
%hook _TtC20IGDirectNotesUISwift41IGDirectNotesBubbleEditorColorPaletteView
%property (nonatomic, copy) UIColor *backgroundColor;
%property (nonatomic, copy) UIColor *textColor;
%property (nonatomic, copy) NSString *emojiText;
%property (nonatomic, copy) UIColor *gradientStartColor;

- (void)didMoveToWindow {
    %orig;

    if (![SCIUtils getBoolPref:@"custom_note_themes"]) return;
    
    // Inject buttons once in view lifecycle
    static char didInjectButtons;
    if (objc_getAssociatedObject(self, &didInjectButtons)) {
        return;
    }

    __weak typeof(self) weakSelf = self;
    dispatch_async(dispatch_get_main_queue(), ^{
        __strong typeof(weakSelf) self = weakSelf;
        if (!self || !self.window) {
            return;
        }

        UIView *container = self.superview ?: self.window;
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
            [self presentColorPicker:@"Background"];
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
            [self presentColorPicker:@"Text"];
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
                self.emojiText = alert.textFields[0].text;
                [self applySCICustomTheme:@"Emoji"];
            }]];
            
            [alert addAction:[UIAlertAction actionWithTitle:@"Cancel"
                                                      style:UIAlertActionStyleCancel
                                                    handler:nil]];
            
            UIViewController *vc = [SCIUtils nearestViewControllerForView:self];
            [vc presentViewController:alert animated:YES completion:nil];
        }] forControlEvents:UIControlEventTouchUpInside];


        // More button (gradients and presets)
        UIButton *moreButton = [UIButton buttonWithType:UIButtonTypeSystem];
        moreButton.configuration = config;
        moreButton.translatesAutoresizingMaskIntoConstraints = NO;
        moreButton.tintColor = [SCIUtils SCIColor_Primary];
        [moreButton setImage:[UIImage systemImageNamed:@"ellipsis"] forState:UIControlStateNormal];
        moreButton.menu = [self sciMoreMenu];
        moreButton.showsMenuAsPrimaryAction = YES;
        [moreButton sizeToFit];

        // Create stack view
        UIStackView *stack = [[UIStackView alloc] initWithArrangedSubviews:@[leftButton, middleButton, rightButton, moreButton]];
        stack.axis = UILayoutConstraintAxisHorizontal;
        stack.spacing = 15.0;
        stack.alignment = UIStackViewAlignmentCenter;
        stack.distribution = UIStackViewDistributionFill;

        // Text buttons share the width, the more button stays square
        [middleButton.widthAnchor constraintEqualToAnchor:leftButton.widthAnchor].active = YES;
        [rightButton.widthAnchor constraintEqualToAnchor:leftButton.widthAnchor].active = YES;
        [moreButton.widthAnchor constraintEqualToConstant:44.0].active = YES;

        // Find max height among arranged subviews
        CGFloat maxHeight = 0.0;
        for (UIView *subview in stack.arrangedSubviews) {
            maxHeight = MAX(maxHeight, subview.bounds.size.height);
        }

        // Manual frame with side padding
        CGFloat bottomMargin = 15.0;
        
        CGRect viewFrame = [self convertRect:self.bounds toView:container];
        CGFloat y = CGRectGetMinY(viewFrame) - maxHeight - bottomMargin;
        CGFloat width = container.bounds.size.width - stack.spacing * 2;

        stack.frame = CGRectMake(stack.spacing, y, width, maxHeight);

        [stack layoutIfNeeded];
        [container addSubview:stack];

        objc_setAssociatedObject(
            self,
            &didInjectButtons,
            @YES,
            OBJC_ASSOCIATION_RETAIN_NONATOMIC
        );
    });
}

%new - (void)presentColorPicker:(NSString *)target {
    UIColorPickerViewController *colorPickerController = [[UIColorPickerViewController alloc] init];

    colorPickerController.delegate = (id<UIColorPickerViewControllerDelegate>)self; // cast to suppress warnings
    colorPickerController.title = [NSString stringWithFormat:@"%@ color", target];
    colorPickerController.modalPresentationStyle = UIModalPresentationPopover;
    colorPickerController.supportsAlpha = NO;

    // Show last picked color for type
    if ([target isEqualToString:@"Background"] || [target isEqualToString:@"GradientStart"]) {
        if (self.backgroundColor) colorPickerController.selectedColor = self.backgroundColor;
    }
    else if ([target isEqualToString:@"Text"]) {
        colorPickerController.selectedColor = self.textColor;
    }

    if ([target isEqualToString:@"GradientStart"]) colorPickerController.title = @"Gradient start color";
    else if ([target isEqualToString:@"GradientEnd"]) colorPickerController.title = @"Gradient end color";
    
    UIViewController *presentingVC = [SCIUtils nearestViewControllerForView:self];
    
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
    _TtC20IGDirectNotesUISwift41IGDirectNotesBubbleEditorColorPaletteView *bubbleEditorVC = [SCIUtils nearestViewControllerForView:self];
    
    NSString *target = objc_getAssociatedObject(bubbleEditorVC, &targetStaticRef);
    if (!target) return;
    
    // Gradient colors are applied once both are picked
    if ([target isEqualToString:@"GradientStart"]) {
        self.gradientStartColor = color;
        return;
    }
    if ([target isEqualToString:@"GradientEnd"]) return;

    // Update saved color target
    if ([target isEqualToString:@"Background"]) {
        self.backgroundColor = color;
    }
    else if ([target isEqualToString:@"Text"]) {
        self.textColor = color;
    }

    [self applySCICustomTheme:target];
};

%new - (void)colorPickerViewControllerDidFinish:(UIColorPickerViewController *)viewController {
    UIViewController *presentingVC = [SCIUtils nearestViewControllerForView:self];
    NSString *target = objc_getAssociatedObject(presentingVC, &targetStaticRef);

    if ([target isEqualToString:@"GradientStart"]) {
        if (!self.gradientStartColor) self.gradientStartColor = viewController.selectedColor;

        // Wait for this picker to finish dismissing before showing the next one
        dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.5 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{
            [self presentColorPicker:@"GradientEnd"];
        });
    }
    else if ([target isEqualToString:@"GradientEnd"]) {
        objc_setAssociatedObject(presentingVC, &targetStaticRef, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);

        UIColor *start = self.gradientStartColor ?: self.backgroundColor ?: [UIColor blackColor];
        [self applySCIThemeWithBackground:start text:self.textColor emoji:self.emojiText gradientEnd:viewController.selectedColor];
    }
}

%new - (UIMenu *)sciMoreMenu {
    __weak typeof(self) weakSelf = self;

    UIAction *customGradient = [UIAction actionWithTitle:@"Custom gradient…" image:[UIImage systemImageNamed:@"paintpalette"] identifier:nil handler:^(UIAction *action) {
        weakSelf.gradientStartColor = nil;
        [weakSelf presentColorPicker:@"GradientStart"];
    }];

    NSMutableArray *gradientActions = [NSMutableArray arrayWithObject:customGradient];
    for (NSDictionary *preset in [SCINotesThemeRuntime gradientPresets]) {
        [gradientActions addObject:[UIAction actionWithTitle:[NSString stringWithFormat:@"%@ %@", preset[@"emoji"], preset[@"name"]] image:nil identifier:nil handler:^(UIAction *action) {
            [weakSelf applySCIPreset:preset];
        }]];
    }

    NSMutableArray *seasonalActions = [NSMutableArray array];
    for (NSDictionary *preset in [SCINotesThemeRuntime seasonalPresets]) {
        [seasonalActions addObject:[UIAction actionWithTitle:[NSString stringWithFormat:@"%@ %@", preset[@"emoji"], preset[@"name"]] image:nil identifier:nil handler:^(UIAction *action) {
            [weakSelf applySCIPreset:preset];
        }]];
    }

    NSMutableArray *instagramActions = [NSMutableArray array];
    for (NSDictionary *theme in [SCINotesThemeRuntime instagramSeasonalThemes]) {
        [instagramActions addObject:[UIAction actionWithTitle:[NSString stringWithFormat:@"%@ %@", theme[@"emoji"], theme[@"name"]] image:nil identifier:nil handler:^(UIAction *action) {
            [weakSelf applySCIThemeWithBackground:nil text:nil emoji:nil gradientEnd:nil activationType:theme[@"activationType"]];
        }]];
    }
    [seasonalActions insertObject:[UIMenu menuWithTitle:@"Instagram's seasonal designs" image:[UIImage systemImageNamed:@"sparkles"] identifier:nil options:0 children:instagramActions] atIndex:0];

    UIAction *swap = [UIAction actionWithTitle:@"Swap background and text" image:[UIImage systemImageNamed:@"arrow.left.arrow.right"] identifier:nil handler:^(UIAction *action) {
        UIColor *background = weakSelf.backgroundColor;
        [weakSelf applySCIThemeWithBackground:weakSelf.textColor ?: [UIColor whiteColor] text:background ?: [UIColor blackColor] emoji:weakSelf.emojiText gradientEnd:nil];
    }];

    return [UIMenu menuWithChildren:@[
        [UIMenu menuWithTitle:@"Gradient" image:[UIImage systemImageNamed:@"circle.lefthalf.filled"] identifier:nil options:0 children:gradientActions],
        [UIMenu menuWithTitle:@"Seasonal" image:[UIImage systemImageNamed:@"leaf"] identifier:nil options:0 children:seasonalActions],
        swap
    ]];
}

%new - (void)applySCIPreset:(NSDictionary *)preset {
    [self applySCIThemeWithBackground:preset[@"background"] text:preset[@"text"] emoji:preset[@"emoji"] gradientEnd:preset[@"gradientEnd"]];
}

%new - (void)applySCIThemeWithBackground:(UIColor *)background text:(UIColor *)text emoji:(NSString *)emoji gradientEnd:(UIColor *)gradientEnd {
    [self applySCIThemeWithBackground:background text:text emoji:emoji gradientEnd:gradientEnd activationType:nil];
}

%new - (void)applySCIThemeWithBackground:(UIColor *)background text:(UIColor *)text emoji:(NSString *)emoji gradientEnd:(UIColor *)gradientEnd activationType:(NSString *)activationType {
    if (background) self.backgroundColor = background;
    if (text) self.textColor = text;
    if (emoji) self.emojiText = emoji;

    IGNotesCustomThemeCreationModel *current = [self sciCurrentThemeModel];
    if (!current) return;

    // Gradients and activation types can only be set through Instagram's initializer
    NSArray *gradient = gradientEnd ? @[self.backgroundColor ?: [UIColor blackColor], gradientEnd] : nil;
    IGNotesCustomThemeCreationModel *model = [SCINotesThemeRuntime themeModelWithBackground:self.backgroundColor ?: [UIColor blackColor]
                                                                             gradientColors:gradient
                                                                                  textColor:self.textColor ?: [UIColor whiteColor]
                                                                                      emoji:self.emojiText
                                                                             activationType:activationType
                                                                                    basedOn:current];

    if (!model) {
        // Older or newer Instagram without that initializer: solid colors only
        model = current;
        [model setValue:self.backgroundColor forKey:@"backgroundColor"];
        if (self.textColor) {
            [model setValue:self.textColor forKey:@"textColor"];
            [model setValue:self.textColor forKey:@"secondaryTextColor"];
        }
        [model setValue:self.emojiText forKey:@"customEmoji"];

        if ((gradientEnd || activationType) && ![[NSUserDefaults standardUserDefaults] boolForKey:@"notes_gradient_unsupported_shown"]) {
            [[NSUserDefaults standardUserDefaults] setBool:YES forKey:@"notes_gradient_unsupported_shown"];

            UIAlertController *alert = [UIAlertController alertControllerWithTitle:@"Not available in this Instagram version"
                                                                           message:@"Gradients and Instagram's seasonal designs need Instagram's note theme initializer, which this version doesn't have, so only solid colors are used.\n\nTo help add support, go to SCInsta settings > Debug > Copy note theme fields and share the result."
                                                                    preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
            [[SCIUtils nearestViewControllerForView:self] presentViewController:alert animated:YES completion:nil];
        }
    }

    [self sciCommitThemeModel:model];
}

%new - (IGNotesCustomThemeCreationModel *)sciCurrentThemeModel {
    // Get notes composer vc
    _TtC20IGDirectNotesUISwift39IGDirectNotesBubbleEditorViewController *parentVC = [SCIUtils nearestViewControllerForView:self];
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
    _TtC20IGDirectNotesUISwift39IGDirectNotesBubbleEditorViewController *parentVC = [SCIUtils nearestViewControllerForView:self];
    if (![parentVC respondsToSelector:@selector(delegate)]) return;

    IGDirectNotesComposerViewController *composerVC = parentVC.delegate;
    if (![composerVC respondsToSelector:@selector(notesBubbleEditorViewControllerDidUpdateWithCustomThemeCreationModel:)]) return;

    // Apply custom notes theme
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
    IGNotesCustomThemeCreationModel *model = [self sciCurrentThemeModel];
    if (!model) return;

    // Update saved color target
    if ([target isEqualToString:@"Background"]) {
        [model setValue:self.backgroundColor forKey:@"backgroundColor"];
    }
    else if ([target isEqualToString:@"Text"]) {
        [model setValue:self.textColor forKey:@"textColor"];
        [model setValue:self.textColor forKey:@"secondaryTextColor"];  
    }

    // Always set emoji to prevent it being overwritten
    [model setValue:self.emojiText forKey:@"customEmoji"];  

    [self sciCommitThemeModel:model];
}
%end
%end

%ctor {
    %init;

    Class paletteClass = objc_getClass("_TtC26IGNotesBubbleCreationSwift41IGDirectNotesBubbleEditorColorPaletteView")
                      ?: objc_getClass("_TtC20IGDirectNotesUISwift41IGDirectNotesBubbleEditorColorPaletteView");

    if (paletteClass) {
        %init(NotesPalette, _TtC20IGDirectNotesUISwift41IGDirectNotesBubbleEditorColorPaletteView = paletteClass);
    }
    else {
        NSLog(@"[SCInsta] Notes: color palette view not found, custom note themes are unavailable");
    }
}
