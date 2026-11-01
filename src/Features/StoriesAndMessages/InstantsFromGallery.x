#import "../../Utils.h"
#import <PhotosUI/PhotosUI.h>
#import <AVFoundation/AVFoundation.h>
#import <CoreImage/CoreImage.h>
#import <ImageIO/ImageIO.h>

// Post a photo from the gallery as an instant (Instagram 453+)
//
// A gallery button is added to the instants camera. The picked photo is cropped in the instants
// shape and shown in place of the camera preview. When the shutter is pressed, the camera's photo
// (AVCapturePhoto) hands back the cropped photo instead of what the camera saw, so everything
// Instagram does with the shot (processing, sending, audience) uses it.

static UIImage *sciPendingInstantImage;
static __weak UIView *sciInstantsCameraView;
static char kSCIGalleryButtonKey;
static char kSCIPreviewOverlayKey;

static BOOL SCIInstantsFromGalleryEnabled(void) {
    return [SCIUtils getBoolPref:@"instants_from_gallery"];
}

// The instants rounded square, from Instagram's own IGQuickSnapSquircleProvider when available
static UIBezierPath *SCIInstantsShapePath(CGFloat side) {
    Class provider = objc_getClass("_TtC27IGQuickSnapSquircleProvider27IGQuickSnapSquircleProvider");
    SEL selector = NSSelectorFromString(@"squareImageMaskPathForSize:");

    if ([provider respondsToSelector:selector]) {
        id path = ((id (*)(id, SEL, double))objc_msgSend)(provider, selector, side);
        if ([path isKindOfClass:[UIBezierPath class]]) return path;
    }
    return [UIBezierPath bezierPathWithRoundedRect:CGRectMake(0, 0, side, side) cornerRadius:side * 0.22];
}

// MARK: - Camera preview

// Shows the chosen photo over the camera's rounded square, or removes it
static void SCIUpdateInstantsPreview(UIView *cameraView) {
    if (!cameraView) return;

    UIImageView *overlay = objc_getAssociatedObject(cameraView, &kSCIPreviewOverlayKey);
    if (!sciPendingInstantImage || !SCIInstantsFromGalleryEnabled()) {
        [overlay removeFromSuperview];
        objc_setAssociatedObject(cameraView, &kSCIPreviewOverlayKey, nil, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        return;
    }

    // Lazily created Swift views; nil until Instagram has built them
    UIView *squircleGuide = [SCIUtils getIvarForObj:cameraView name:"$__lazy_storage_$_squircleLayoutGuideView"];
    UIView *preview = [SCIUtils getIvarForObj:cameraView name:"$__lazy_storage_$_cameraPreviewView"];
    if (![squircleGuide isKindOfClass:[UIView class]]) squircleGuide = nil;
    if (![preview isKindOfClass:[UIView class]]) preview = nil;

    UIView *shapeSource = squircleGuide.superview ? squircleGuide : (preview.superview ? preview : cameraView);
    CGRect frame = [shapeSource convertRect:shapeSource.bounds toView:cameraView];
    CGFloat side = MIN(frame.size.width, frame.size.height);
    frame = CGRectMake(CGRectGetMidX(frame) - side / 2, CGRectGetMidY(frame) - side / 2, side, side);

    if (!overlay) {
        overlay = [[UIImageView alloc] init];
        overlay.contentMode = UIViewContentModeScaleAspectFill;
        overlay.clipsToBounds = YES;
        overlay.userInteractionEnabled = NO;

        // Above the camera preview, below Instagram's controls
        UIView *above = preview;
        while (above && above.superview != cameraView) above = above.superview;
        if (above) [cameraView insertSubview:overlay aboveSubview:above];
        else [cameraView addSubview:overlay];

        objc_setAssociatedObject(cameraView, &kSCIPreviewOverlayKey, overlay, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    }

    overlay.image = sciPendingInstantImage;
    if (!CGRectEqualToRect(overlay.frame, frame)) {
        overlay.frame = frame;

        CAShapeLayer *mask = [CAShapeLayer layer];
        mask.path = SCIInstantsShapePath(side).CGPath;
        overlay.layer.mask = mask;
    }
}

static void SCISetPendingInstantImage(UIImage *image) {
    sciPendingInstantImage = image;

    UIButton *button = objc_getAssociatedObject(sciInstantsCameraView, &kSCIGalleryButtonKey);
    button.tintColor = image ? [SCIUtils SCIColor_Primary] : [UIColor whiteColor];

    SCIUpdateInstantsPreview(sciInstantsCameraView);
}

// MARK: - Cropping

@interface SCIInstantCropViewController : UIViewController <UIScrollViewDelegate>
@property (nonatomic, strong) UIImage *image;
@property (nonatomic, copy) void (^completion)(UIImage *croppedImage);
@property (nonatomic, strong) UIScrollView *scrollView;
@property (nonatomic, strong) UIImageView *imageView;
@property (nonatomic, strong) CAShapeLayer *dimLayer;
@property (nonatomic) CGRect cropRect;
@property (nonatomic) BOOL didSetInitialZoom;
@end

@implementation SCIInstantCropViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    self.view.backgroundColor = [UIColor blackColor];

    self.scrollView = [[UIScrollView alloc] initWithFrame:self.view.bounds];
    self.scrollView.delegate = self;
    self.scrollView.showsHorizontalScrollIndicator = NO;
    self.scrollView.showsVerticalScrollIndicator = NO;
    self.scrollView.alwaysBounceVertical = YES;
    self.scrollView.alwaysBounceHorizontal = YES;
    self.scrollView.contentInsetAdjustmentBehavior = UIScrollViewContentInsetAdjustmentNever;
    [self.view addSubview:self.scrollView];

    self.imageView = [[UIImageView alloc] initWithImage:self.image];
    self.imageView.frame = CGRectMake(0, 0, self.image.size.width, self.image.size.height);
    [self.scrollView addSubview:self.imageView];
    self.scrollView.contentSize = self.image.size;

    // Dims everything outside the instants shape
    UIView *dimView = [[UIView alloc] initWithFrame:self.view.bounds];
    dimView.userInteractionEnabled = NO;
    dimView.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    self.dimLayer = [CAShapeLayer layer];
    self.dimLayer.fillRule = kCAFillRuleEvenOdd;
    self.dimLayer.fillColor = [UIColor colorWithWhite:0 alpha:0.6].CGColor;
    self.dimLayer.strokeColor = [UIColor colorWithWhite:1 alpha:0.9].CGColor;
    self.dimLayer.lineWidth = 1.5;
    [dimView.layer addSublayer:self.dimLayer];
    [self.view addSubview:dimView];

    UILabel *title = [[UILabel alloc] init];
    title.text = @"Move and scale";
    title.textColor = [UIColor whiteColor];
    title.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    title.translatesAutoresizingMaskIntoConstraints = NO;
    [self.view addSubview:title];

    UIButton *cancel = [UIButton buttonWithType:UIButtonTypeSystem];
    [cancel setTitle:@"Cancel" forState:UIControlStateNormal];
    cancel.tintColor = [UIColor whiteColor];
    cancel.titleLabel.font = [UIFont systemFontOfSize:17];
    cancel.translatesAutoresizingMaskIntoConstraints = NO;
    [cancel addTarget:self action:@selector(cancel) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:cancel];

    UIButton *use = [UIButton buttonWithType:UIButtonTypeSystem];
    [use setTitle:@"Use photo" forState:UIControlStateNormal];
    use.tintColor = [SCIUtils SCIColor_Primary];
    use.titleLabel.font = [UIFont systemFontOfSize:17 weight:UIFontWeightSemibold];
    use.translatesAutoresizingMaskIntoConstraints = NO;
    [use addTarget:self action:@selector(usePhoto) forControlEvents:UIControlEventTouchUpInside];
    [self.view addSubview:use];

    UILayoutGuide *safe = self.view.safeAreaLayoutGuide;
    [NSLayoutConstraint activateConstraints:@[
        [title.topAnchor constraintEqualToAnchor:safe.topAnchor constant:16],
        [title.centerXAnchor constraintEqualToAnchor:self.view.centerXAnchor],
        [cancel.leadingAnchor constraintEqualToAnchor:safe.leadingAnchor constant:20],
        [cancel.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16],
        [use.trailingAnchor constraintEqualToAnchor:safe.trailingAnchor constant:-20],
        [use.bottomAnchor constraintEqualToAnchor:safe.bottomAnchor constant:-16],
    ]];
}

- (void)viewDidLayoutSubviews {
    [super viewDidLayoutSubviews];

    CGRect bounds = self.view.bounds;
    CGFloat side = MIN(bounds.size.width - 32, bounds.size.height * 0.6);
    self.cropRect = CGRectMake((bounds.size.width - side) / 2, (bounds.size.height - side) / 2, side, side);

    // The scroll view fills the screen; insets keep the photo able to reach every edge of the crop
    self.scrollView.frame = bounds;
    self.scrollView.contentInset = UIEdgeInsetsMake(CGRectGetMinY(self.cropRect), CGRectGetMinX(self.cropRect),
                                                    bounds.size.height - CGRectGetMaxY(self.cropRect), bounds.size.width - CGRectGetMaxX(self.cropRect));

    UIBezierPath *dim = [UIBezierPath bezierPathWithRect:bounds];
    UIBezierPath *shape = SCIInstantsShapePath(side);
    [shape applyTransform:CGAffineTransformMakeTranslation(CGRectGetMinX(self.cropRect), CGRectGetMinY(self.cropRect))];
    [dim appendPath:shape];
    self.dimLayer.path = dim.CGPath;

    if (!self.didSetInitialZoom && self.image.size.width > 0 && self.image.size.height > 0) {
        self.didSetInitialZoom = YES;

        // Fill the shape, centered
        CGFloat minimum = MAX(side / self.image.size.width, side / self.image.size.height);
        self.scrollView.minimumZoomScale = minimum;
        self.scrollView.maximumZoomScale = minimum * 6;
        self.scrollView.zoomScale = minimum;

        CGSize content = self.scrollView.contentSize;
        self.scrollView.contentOffset = CGPointMake((content.width - side) / 2 - CGRectGetMinX(self.cropRect),
                                                    (content.height - side) / 2 - CGRectGetMinY(self.cropRect));
    }
}

- (UIView *)viewForZoomingInScrollView:(UIScrollView *)scrollView {
    return self.imageView;
}

- (void)cancel {
    [self dismissViewControllerAnimated:YES completion:nil];
}

- (void)usePhoto {
    CGFloat zoom = self.scrollView.zoomScale;
    CGPoint offset = self.scrollView.contentOffset;
    CGFloat side = self.cropRect.size.width;

    // The crop in the photo's own coordinates
    CGRect crop = CGRectMake((offset.x + CGRectGetMinX(self.cropRect)) / zoom,
                             (offset.y + CGRectGetMinY(self.cropRect)) / zoom,
                             side / zoom, side / zoom);

    CGFloat output = MIN(1440, MAX(1, crop.size.width * self.image.scale));
    CGFloat factor = output / crop.size.width;

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    format.opaque = YES;
    UIImage *cropped = [[[UIGraphicsImageRenderer alloc] initWithSize:CGSizeMake(output, output) format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor blackColor] setFill];
        UIRectFill(CGRectMake(0, 0, output, output));
        [self.image drawInRect:CGRectMake(-crop.origin.x * factor, -crop.origin.y * factor, self.image.size.width * factor, self.image.size.height * factor)];
    }];

    void (^completion)(UIImage *) = self.completion;
    [self dismissViewControllerAnimated:YES completion:^{
        if (completion) completion(cropped);
    }];
}

@end

// MARK: - Picking

@interface SCIInstantsGalleryPicker : NSObject <PHPickerViewControllerDelegate>
@property (nonatomic, weak) UIViewController *presenter;
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
    self.presenter = [SCIUtils nearestViewControllerForView:view] ?: topMostController();

    // With a photo already chosen, offer to change it or go back to the camera
    if (sciPendingInstantImage) {
        UIAlertController *sheet = [UIAlertController alertControllerWithTitle:nil message:nil preferredStyle:UIAlertControllerStyleActionSheet];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Choose another photo" style:UIAlertActionStyleDefault handler:^(UIAlertAction *action) {
            [self presentPicker];
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Use the camera instead" style:UIAlertActionStyleDestructive handler:^(UIAlertAction *action) {
            SCISetPendingInstantImage(nil);
        }]];
        [sheet addAction:[UIAlertAction actionWithTitle:@"Cancel" style:UIAlertActionStyleCancel handler:nil]];
        sheet.popoverPresentationController.sourceView = view;
        [self.presenter presentViewController:sheet animated:YES completion:nil];
        return;
    }

    [self presentPicker];
}

- (void)presentPicker {
    PHPickerConfiguration *configuration = [[PHPickerConfiguration alloc] init];
    configuration.filter = [PHPickerFilter imagesFilter];
    configuration.selectionLimit = 1;

    PHPickerViewController *picker = [[PHPickerViewController alloc] initWithConfiguration:configuration];
    picker.delegate = self;
    [self.presenter presentViewController:picker animated:YES completion:nil];
}

- (void)picker:(PHPickerViewController *)picker didFinishPicking:(NSArray<PHPickerResult *> *)results {
    NSItemProvider *provider = results.firstObject.itemProvider;
    if (![provider canLoadObjectOfClass:[UIImage class]]) {
        [picker dismissViewControllerAnimated:YES completion:nil];
        return;
    }

    [provider loadObjectOfClass:[UIImage class] completionHandler:^(id<NSItemProviderReading> object, NSError *error) {
        dispatch_async(dispatch_get_main_queue(), ^{
            [picker dismissViewControllerAnimated:YES completion:^{
                if (![(id)object isKindOfClass:[UIImage class]]) return;

                SCIInstantCropViewController *cropper = [SCIInstantCropViewController new];
                cropper.image = (UIImage *)object;
                cropper.modalPresentationStyle = UIModalPresentationFullScreen;
                cropper.completion = ^(UIImage *croppedImage) {
                    SCISetPendingInstantImage(croppedImage);
                };
                [self.presenter presentViewController:cropper animated:YES completion:nil];
            }];
        });
    }];
}

@end

// MARK: - Hooks

// Demangled name: IGQuickSnapCreationCameraView.IGQuickSnapCameraView
%hook _TtC29IGQuickSnapCreationCameraView21IGQuickSnapCameraView
- (void)didMoveToWindow {
    %orig;

    UIView *view = (UIView *)self;
    if (!SCIInstantsFromGalleryEnabled() || !view.window) return;

    sciInstantsCameraView = view;
    if (objc_getAssociatedObject(view, &kSCIGalleryButtonKey)) return;

    UIButton *button = [UIButton buttonWithType:UIButtonTypeSystem];
    [button setImage:[UIImage systemImageNamed:@"photo.on.rectangle" withConfiguration:[UIImageSymbolConfiguration configurationWithPointSize:18 weight:UIImageSymbolWeightSemibold]] forState:UIControlStateNormal];
    button.tintColor = sciPendingInstantImage ? [SCIUtils SCIColor_Primary] : [UIColor whiteColor];
    button.backgroundColor = [UIColor colorWithWhite:0 alpha:0.45];
    button.layer.cornerRadius = 20;
    button.frame = CGRectMake(12, 12, 40, 40);
    button.autoresizingMask = UIViewAutoresizingFlexibleRightMargin | UIViewAutoresizingFlexibleBottomMargin;
    button.accessibilityLabel = @"Choose a photo for your instant";

    __weak UIView *weakView = view;
    [button addAction:[UIAction actionWithHandler:^(__kindof UIAction *action) {
        if (weakView) [[SCIInstantsGalleryPicker sharedInstance] presentFromView:weakView];
    }] forControlEvents:UIControlEventTouchUpInside];

    [view addSubview:button];
    objc_setAssociatedObject(view, &kSCIGalleryButtonKey, button, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (void)layoutSubviews {
    %orig;

    UIView *view = (UIView *)self;
    SCIUpdateInstantsPreview(view);

    UIButton *button = objc_getAssociatedObject(view, &kSCIGalleryButtonKey);
    if (button) [view bringSubviewToFront:button];
}
%end

// MARK: - Replacing the camera shot

static char kSCIReplacementKey;

static BOOL SCIShouldReplaceCapture(void) {
    return SCIInstantsFromGalleryEnabled() && sciPendingInstantImage && sciInstantsCameraView.window;
}

static CIContext *SCISharedCIContext(void) {
    static CIContext *context;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{ context = [CIContext contextWithOptions:nil]; });
    return context;
}

static CGImagePropertyOrientation SCIOrientationOfPhoto(AVCapturePhoto *photo) {
    NSNumber *orientation = photo.metadata[(NSString *)kCGImagePropertyOrientation];
    return orientation ? (CGImagePropertyOrientation)orientation.unsignedIntValue : kCGImagePropertyOrientationUp;
}

// The gallery photo laid out like a camera frame of width x height pixels, stored the way the sensor
// stores it: once `orientation` is applied it shows upright, as a centered square of the shorter side
static CIImage *SCISensorImage(UIImage *image, size_t width, size_t height, CGImagePropertyOrientation orientation) {
    BOOL rotated = orientation >= kCGImagePropertyOrientationLeftMirrored; // 5-8 swap width and height
    CGSize displayed = rotated ? CGSizeMake(height, width) : CGSizeMake(width, height);
    CGFloat side = MIN(displayed.width, displayed.height);

    UIGraphicsImageRendererFormat *format = [UIGraphicsImageRendererFormat defaultFormat];
    format.scale = 1;
    format.opaque = YES;
    UIImage *upright = [[[UIGraphicsImageRenderer alloc] initWithSize:displayed format:format] imageWithActions:^(UIGraphicsImageRendererContext *context) {
        [[UIColor blackColor] setFill];
        UIRectFill(CGRectMake(0, 0, displayed.width, displayed.height));
        [image drawInRect:CGRectMake((displayed.width - side) / 2, (displayed.height - side) / 2, side, side)];
    }];

    // Undo the orientation Instagram will apply (only 6 and 8 aren't their own inverse)
    CGImagePropertyOrientation inverse = orientation;
    if (orientation == kCGImagePropertyOrientationRight) inverse = kCGImagePropertyOrientationLeft;
    else if (orientation == kCGImagePropertyOrientationLeft) inverse = kCGImagePropertyOrientationRight;

    CIImage *sensor = [[CIImage imageWithCGImage:upright.CGImage] imageByApplyingCGOrientation:inverse];
    return [sensor imageByApplyingTransform:CGAffineTransformMakeTranslation(-sensor.extent.origin.x, -sensor.extent.origin.y)];
}

// Replacement data for one photo, made once and kept alive with it
static NSMutableDictionary *SCIReplacementsForPhoto(AVCapturePhoto *photo) {
    NSMutableDictionary *replacements = objc_getAssociatedObject(photo, &kSCIReplacementKey);
    if (!replacements) {
        replacements = [NSMutableDictionary dictionary];
        objc_setAssociatedObject(photo, &kSCIReplacementKey, replacements, OBJC_ASSOCIATION_RETAIN_NONATOMIC);
        NSLog(@"[SCInsta] Instants: replacing camera shot with gallery photo");
    }
    return replacements;
}

static CVPixelBufferRef SCIReplacementPixelBuffer(AVCapturePhoto *photo, CVPixelBufferRef original, NSString *key) {
    if (!original) return original;

    NSMutableDictionary *replacements = SCIReplacementsForPhoto(photo);
    if (replacements[key]) return (__bridge CVPixelBufferRef)replacements[key];

    size_t width = CVPixelBufferGetWidth(original), height = CVPixelBufferGetHeight(original);
    NSDictionary *attributes = @{ (NSString *)kCVPixelBufferIOSurfacePropertiesKey: @{} };

    CVPixelBufferRef buffer = NULL;
    if (CVPixelBufferCreate(kCFAllocatorDefault, width, height, CVPixelBufferGetPixelFormatType(original), (__bridge CFDictionaryRef)attributes, &buffer) != kCVReturnSuccess || !buffer) {
        return original;
    }

    CIImage *sensor = SCISensorImage(sciPendingInstantImage, width, height, SCIOrientationOfPhoto(photo));
    [SCISharedCIContext() render:sensor toCVPixelBuffer:buffer];

    replacements[key] = (__bridge_transfer id)buffer;
    return buffer;
}

static CGImageRef SCIReplacementCGImage(AVCapturePhoto *photo, CGImageRef original, NSString *key) {
    if (!original) return original;

    NSMutableDictionary *replacements = SCIReplacementsForPhoto(photo);
    if (replacements[key]) return (__bridge CGImageRef)replacements[key];

    CIImage *sensor = SCISensorImage(sciPendingInstantImage, CGImageGetWidth(original), CGImageGetHeight(original), SCIOrientationOfPhoto(photo));
    CGImageRef image = [SCISharedCIContext() createCGImage:sensor fromRect:sensor.extent];
    if (!image) return original;

    replacements[key] = (__bridge_transfer id)image;
    return image;
}

%hook AVCapturePhoto
- (CVPixelBufferRef)pixelBuffer {
    CVPixelBufferRef original = %orig;
    return SCIShouldReplaceCapture() ? SCIReplacementPixelBuffer(self, original, @"pixelBuffer") : original;
}

- (CVPixelBufferRef)previewPixelBuffer {
    CVPixelBufferRef original = %orig;
    return SCIShouldReplaceCapture() ? SCIReplacementPixelBuffer(self, original, @"previewPixelBuffer") : original;
}

- (CGImageRef)CGImageRepresentation {
    CGImageRef original = %orig;
    return SCIShouldReplaceCapture() ? SCIReplacementCGImage(self, original, @"CGImageRepresentation") : original;
}

- (CGImageRef)previewCGImageRepresentation {
    CGImageRef original = %orig;
    return SCIShouldReplaceCapture() ? SCIReplacementCGImage(self, original, @"previewCGImageRepresentation") : original;
}

- (NSData *)fileDataRepresentation {
    NSData *original = %orig;
    if (!SCIShouldReplaceCapture() || !original) return original;

    NSMutableDictionary *replacements = SCIReplacementsForPhoto(self);
    if (replacements[@"fileData"]) return replacements[@"fileData"];

    // Same size and orientation tag as the camera's file
    CGImageSourceRef source = CGImageSourceCreateWithData((__bridge CFDataRef)original, NULL);
    NSDictionary *properties = source ? (__bridge_transfer NSDictionary *)CGImageSourceCopyPropertiesAtIndex(source, 0, NULL) : nil;
    if (source) CFRelease(source);

    size_t width = [properties[(NSString *)kCGImagePropertyPixelWidth] unsignedLongValue];
    size_t height = [properties[(NSString *)kCGImagePropertyPixelHeight] unsignedLongValue];
    if (!width || !height) return original;

    CGImagePropertyOrientation orientation = properties[(NSString *)kCGImagePropertyOrientation] ? (CGImagePropertyOrientation)[properties[(NSString *)kCGImagePropertyOrientation] unsignedIntValue] : SCIOrientationOfPhoto(self);
    CIImage *sensor = SCISensorImage(sciPendingInstantImage, width, height, orientation);
    CGImageRef image = [SCISharedCIContext() createCGImage:sensor fromRect:sensor.extent];
    if (!image) return original;

    NSMutableData *data = [NSMutableData data];
    CGImageDestinationRef destination = CGImageDestinationCreateWithData((__bridge CFMutableDataRef)data, CFSTR("public.jpeg"), 1, NULL);
    if (destination) {
        NSDictionary *options = @{ (NSString *)kCGImagePropertyOrientation: @(orientation), (NSString *)kCGImageDestinationLossyCompressionQuality: @0.92 };
        CGImageDestinationAddImage(destination, image, (__bridge CFDictionaryRef)options);
        CGImageDestinationFinalize(destination);
        CFRelease(destination);
    }
    CGImageRelease(image);

    if (!data.length) return original;
    replacements[@"fileData"] = data;
    return data;
}
%end

// Demangled name: IGQuickSnapModels.IGQuickSnapCreationModel
%hook _TtC17IGQuickSnapModels24IGQuickSnapCreationModel
- (id)initWithAudienceListId:(id)audienceListId mediaAudience:(long long)mediaAudience image:(UIImage *)image {
    if (SCIInstantsFromGalleryEnabled() && sciPendingInstantImage) {
        UIImage *galleryImage = sciPendingInstantImage;
        NSLog(@"[SCInsta] Instants: posting gallery photo instead of camera shot");
        return %orig(audienceListId, mediaAudience, galleryImage);
    }

    return %orig;
}
%end

// One photo per instant: once it starts uploading, the camera preview comes back
// Demangled name: IGQuickSnapCreationSendController.IGQuickSnapCreationSendController
%hook _TtC33IGQuickSnapCreationSendController33IGQuickSnapCreationSendController
- (void)quickSnapUploadDidBeginUpload:(id)upload audience:(long long)audience {
    %orig;

    dispatch_async(dispatch_get_main_queue(), ^{
        if (sciPendingInstantImage) SCISetPendingInstantImage(nil);
    });
}
%end
