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

// Builds a new custom theme model through Instagram's own initializer, which is the only way
// to set its gradient and activation type (they have no setters). Keeps the customization id
// and other values of `existing`. Returns nil if this Instagram version lacks the initializer.
+ (nullable id)themeModelWithBackground:(UIColor *)background
                         gradientColors:(nullable NSArray<UIColor *> *)gradientColors
                              textColor:(UIColor *)textColor
                                  emoji:(nullable NSString *)emoji
                         activationType:(nullable NSString *)activationType
                                basedOn:(nullable id)existing;

// Property names and types of the note theme classes, for adding support for new Instagram versions
+ (NSString *)themeClassDump;

// Built in color presets: name, background, text, emoji and an optional gradient end color
+ (NSArray<NSDictionary *> *)seasonalPresets;
+ (NSArray<NSDictionary *> *)gradientPresets;

// Instagram's own seasonal note designs: name, emoji and activationType
+ (NSArray<NSDictionary *> *)instagramSeasonalThemes;

@end

NS_ASSUME_NONNULL_END
