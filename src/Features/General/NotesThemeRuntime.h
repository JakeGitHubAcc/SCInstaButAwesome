#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

///
/// Runtime helpers for the note editor.
///
/// Instagram's note theme classes change between versions and aren't documented,
/// so these look properties up by name at runtime instead of hardcoding them.
///
@interface SCINotesThemeRuntime : NSObject

// Turns on every "enable…" flag of the note creation feature model, which includes
// the seasonal and limited time options Instagram only offers on certain dates.
// Returns the names of the flags that were switched on.
+ (NSArray<NSString *> *)enableAllFeatureFlagsOnModel:(id)supportModel;

// Sets a two color gradient on a custom theme model, if this Instagram version has a gradient field.
// Returns NO when no gradient field exists.
+ (BOOL)applyGradientFrom:(UIColor *)startColor to:(UIColor *)endColor onThemeModel:(id)themeModel;

// Property names and types of the note theme classes, for adding support for new Instagram versions
+ (NSString *)themeClassDump;

// Built in color presets: name, background, text, emoji and an optional gradient end color
+ (NSArray<NSDictionary *> *)seasonalPresets;
+ (NSArray<NSDictionary *> *)gradientPresets;

@end

NS_ASSUME_NONNULL_END
