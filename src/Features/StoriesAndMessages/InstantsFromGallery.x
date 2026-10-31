#import "../../Utils.h"
#import <PhotosUI/PhotosUI.h>

// Post a photo from the gallery as an instant (Instagram 453+)
//
// A gallery button is added to the instants camera. The picked photo replaces the camera shot
// when Instagram creates the instant (IGQuickSnapCreationModel), so sending, audience and the
// instants look all stay Instagram's own.

static UIImage *sciPendingInstantImage;
static char kSCIGalleryButtonKey;

static BOOL SCIInstantsFromGalleryEnabled(void) {
    return [SCIUtils getBoolPref:@"instants_from_gallery"];
}

static void SCIShowInstantMessage(NSString *message) {
    JGProgressHUD *hud = [[JGProgressHUD alloc] init];
    hud.textLabel.text = message;
    hud.indicatorView = [[JGProgressHUDSuccessIndicatorView alloc] init];
    hud.userInteractionEnabled = NO;
    [hud showInView:topMostController().view];
    [hud dismissAfterDelay:2.5];
}

// Instants are square, so the photo is center cropped (and kept to a sensible size)
static UIImage *SCISquareImage(UIImage *image) {
    CGFloat side = MIN(image.size.width, image.size.height);
    CGFloat output = MIN(side, 2048);

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    UIGraphicsImageRenderer *renderer = [[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(output, output) format:format];

    return [renderer imageWithActions:^(UIGraphicsImageRendererContext *context) {
        CGFloat scale = output / side;
        CGSize drawn = CGSizeMake(image.size.width * scale, image.size.height * scale);
        [image drawInRect:CGRectMake((output - drawn.width) / 2, (output - drawn.height) / 2, drawn.width, drawn.height)];
    }];
}

@interface SCIInstantsGalleryPicker : NSObject <PHPickerViewControllerDelegate>
@property (nonatomic, weak) UIButton *button;
+ (instancetype)sharedInstance;
- (void)presentFromView:(UIView *)view;
@end

@implementation SCIInstantsGalleryPicker

+ (instancetype)sharedInstance {
    static SCIInstantsGalleryPicker *instance;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ instance = [SCIInstantsGalleryPicker new]; });
    return instance;
}

- (void)presentFromView:(UIView *)view {
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.filter = [PHPickerFilter imagesFilter];
    configuration.selectionLimit = 1;

    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;

    UIViewController *presenter = [SCIUtils nearestViewControllerForView:view] ?: topMostController();
    [presenter presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    [picker dismissViewControllerAnimated:YES completion:nil];

    NSItemProvider *provider = results.firstObject.itemProvider;
    if (![provider canLoadObjectOfClass:[UIImage class]]) return;

    [provider loadObjectOfClass:[UIImage class] completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
        if (![(id)object isKindOfClass:[UIImage class]]) return;
        UIImage *image = SCISquareImage((UIImage *)object);

        dispatch_async(dispatch_get_main_queue(), ^{
            sciPendingInstantImage = image;
            self.button.tintColor = [SCIUtils SCIColor_Primary];
            SCIShowInstantMessage(@"Photo ready\nTap the shutter to post it as your instant");
        });
    }];
}

@end

// Demangled name: IGQuickSnapCreationCameraView.IGQuickSnapCameraView
%hook _TtC29IGQuickSnapCreationCameraView21IGQuickSnapCameraView
- (void)didMoveToWindow {
    %orig;

    UIView *view = (UIView *)self;
    if (!SCIInstantsFromGalleryEnabled() || !view.window || objc_getAssociatedObject(view, &kSCIGalleryButtonKey)) return;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:@"photo.on.rectangle" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
    button.tintColor = [UIColor whiteColor];
    button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    button.layer.cornerRadius = 20;
    button.frame = CGRectMake(12, 12, 40, 40);
    button.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
    button.accessibilityLabel = @"Choose a photo for your instant";

    SCIInstantsGalleryPicker *picker = [SCIInstantsGalleryPicker sharedInstance];
    picker.button = button;

    __weak UIView *weakView = view;
    [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        if (weakView) [picker presentFromView:weakView];
    }] forControlEvents:UIControlEventTouchUpInside];

    [view addSubview:button];
    objc_setAssociatedObject(view, &kSCIGalleryButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
%end

// Demangled name: IGQuickSnapModels.IGQuickSnapCreationModel
%hook _TtC17IGQuickSnapModels24IGQuickSnapCreationModel
- (id)initWithAudienceListId:(id)audienceListId mediaAudience:(long long)mediaAudience image:(UIImage *)image {
    if (SCIInstantsFromGalleryEnabled() && sciPendingInstantImage) {
        UIImage *galleryImage = sciPendingInstantImage;
        sciPendingInstantImage = nil;
        [SCIInstantsGalleryPicker sharedInstance].button.tintColor = [UIColor whiteColor];

        NSLog(@"[SCInsta] Instants: posting gallery photo instead of camera shot");
        return %orig(audienceListId, mediaAudience, galleryImage);
    }

    return %orig;
}
%end
