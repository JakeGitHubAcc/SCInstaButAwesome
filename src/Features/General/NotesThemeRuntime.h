#import <Foundation/Foundation.h>
#import <UIKit/UIKit.h>

NS_ASSUME_NONNULL_BEGIN

// Activation type of themes made from custom colors
extern NSString * const SCINotesUserCustomization;

///
/// Runtime helpers for the note editor.
///
/// Instagram's note theme classes change between versions and aren't documented,
/// so these look properties up by name at runtime instead of hardcoding them.
///
/// A theme is a dictionary: background, text, secondaryText (hex strings without "#"),
/// emoji, activationType, customizationId, gradient (hex strings, official designs only), name,
/// and decoration (an official design's activation type, carried by a custom theme).
///
@interface SCINotesThemeRuntime : NSObject

// Turns on every "enable…" flag of the note creation feature model.
// Returns the names of the flags that were switched on.
+ (NSArray<NSString *> *)enableAllFeatureFlagsOnModel:(id)supportModel;

+ (nullable NSString *)hexForColor:(nullable UIColor *)color;
+ (nullable UIColor *)colorFromHex:(nullable NSString *)hex;

// Builds a theme model through Instagram's own initializer, the only way to set its gradient,
// activation type and customization id. Returns nil if this Instagram version lacks it.
+ (nullable id)themeModelForTheme:(NSDictionary *)theme;
+ (nullable NSDictionary *)themeFromModel:(nullable id)model;
+ (BOOL)isOfficialActivationType:(nullable NSString *)activationType;
+ (BOOL)isOfficialTheme:(nullable NSDictionary *)theme;
+ (nullable NSString *)decorationOfTheme:(nullable NSDictionary *)theme;
+ (nullable NSString *)emojiForActivationType:(nullable NSString *)activationType;

// Saved official designs' types, to add on top of custom colors
+ (NSArray<NSDictionary *> *)decorations;

// Official designs are only sent to the app during their event, so each one picked in
// Instagram's palette is saved for good, to be reused later
+ (NSArray<NSDictionary *> *)savedOfficialThemes;
+ (void)saveOfficialThemeFromModel:(id)model;

// The theme picked through SCInsta for the note being written, or nil when Instagram's own
// theme is used. Fixed up in the note request when posting.
+ (void)setAppliedTheme:(nullable NSDictionary *)theme;

// The note's IGXDTNoteCreateParams inside a note request
// (IGXDTCreateInboxTrayItemRequest -> additionalParams -> noteCreateParams)
+ (nullable id)noteCreateParamsOfRequest:(nullable id)request;
+ (void)applyThemeToNoteRequest:(id)request;

// Property names and types of the note theme classes, for adding support for new Instagram versions
+ (NSString *)themeClassDump;

// Solid color presets
+ (NSArray<NSDictionary *> *)colorPresets;

@end

NS_ASSUME_NONNULL_END
