#import "NotesThemeRuntime.h"
#import <objc/runtime.h>
#import <objc/message.h>

@implementation SCINotesThemeRuntime

// MARK: - Introspection

// Name -> type encoding for every property of the class and its superclasses (below NSObject)
+ (NSDictionary<NSString *, NSString *> *)propertiesOfClass:(Class)cls {
    NSMutableDictionary *result = [NSMutableDictionary dictionary];

    for (Class current = cls; current && current != [NSObject class]; current = class_getSuperclass(current)) {
        unsigned int count = 0;
        objc_property_t *properties = class_copyPropertyList(current, &count);

        for (unsigned int i = 0; i < count; i++) {
            NSString *name = @(property_getName(properties[i]));
            if (result[name]) continue;

            char *type = property_copyAttributeValue(properties[i], "T");
            result[name] = type ? @(type) : @"?";
            free(type);
        }

        free(properties);
    }

    return result;
}

+ (BOOL)isBoolType:(NSString *)type {
    return [type isEqualToString:@"c"] || [type isEqualToString:@"B"];
}

// MARK: - Feature flags

+ (NSArray<NSString *> *)enableAllFeatureFlagsOnModel:(id)supportModel {
    if (!supportModel) return @[];

    NSMutableArray *enabled = [NSMutableArray array];
    NSDictionary *properties = [self propertiesOfClass:[supportModel class]];

    for (NSString *name in properties) {
        NSString *lowercase = name.lowercaseString;

        if (![self isBoolType:properties[name]]) continue;
        if (![lowercase containsString:@"enable"]) continue;

        // Never flip flags that turn things off
        if ([lowercase containsString:@"disable"] || [lowercase containsString:@"kill"] || [lowercase containsString:@"holdout"]) continue;

        @try {
            [supportModel setValue:@YES forKey:name];
            [enabled addObject:name];
        }
        @catch (NSException *exception) {
            NSLog(@"[SCInsta] Notes: couldn't enable %@: %@", name, exception.reason);
        }
    }

    return enabled;
}

// MARK: - Gradients

+ (NSString *)hexForColor:(UIColor *)color {
    CGFloat r = 0, g = 0, b = 0, a = 0;
    [color getRed:&r green:&g blue:&b alpha:&a];
    return [NSString stringWithFormat:@"%02lX%02lX%02lX", lround(r * 255), lround(g * 255), lround(b * 255)];
}

// Converts a color to whatever type the model already stores in its gradient array
+ (id)color:(UIColor *)color matchingExample:(id)example {
    if (!example || [example isKindOfClass:[UIColor class]]) return color;

    if ([example isKindOfClass:[NSString class]]) {
        NSString *hex = [self hexForColor:color];
        return [(NSString *)example hasPrefix:@"#"] ? [@"#" stringByAppendingString:hex] : hex;
    }

    if ([example isKindOfClass:[NSNumber class]]) {
        CGFloat r = 0, g = 0, b = 0, a = 0;
        [color getRed:&r green:&g blue:&b alpha:&a];
        uint32_t argb = ((uint32_t)lround(a * 255) << 24) | ((uint32_t)lround(r * 255) << 16) | ((uint32_t)lround(g * 255) << 8) | (uint32_t)lround(b * 255);
        return @(argb);
    }

    if (CFGetTypeID((__bridge CFTypeRef)example) == CGColorGetTypeID()) {
        return (__bridge id)color.CGColor;
    }

    return color;
}

+ (id)themeModelWithBackground:(UIColor *)background
                gradientColors:(NSArray<UIColor *> *)gradientColors
                     textColor:(UIColor *)textColor
                         emoji:(NSString *)emoji
                activationType:(NSString *)activationType
                       basedOn:(id)existing
{
    Class modelClass = NSClassFromString(@"IGNotesCustomThemeCreationModel");
    SEL initializer = NSSelectorFromString(@"initWithBackgroundColor:gradientBackgroundColors:textColor:secondaryTextColor:customEmoji:customizationId:usedGeneratedTheme:activationType:");
    if (!modelClass || ![modelClass instancesRespondToSelector:initializer]) return nil;

    // Values to carry over from the current theme
    id (^existingValue)(NSString *) = ^id (NSString *key) {
        if (!existing || ![existing respondsToSelector:NSSelectorFromString(key)]) return nil;
        @try { return [existing valueForKey:key]; }
        @catch (NSException *exception) { return nil; }
    };

    NSString *customizationId = existingValue(@"customizationId");
    BOOL usedGeneratedTheme = [existingValue(@"usedGeneratedTheme") boolValue];
    if (!activationType) activationType = existingValue(@"activationType");

    // Match the element type Instagram already uses for gradients, if there is one
    NSArray *gradient = nil;
    if (gradientColors.count) {
        NSArray *existingGradient = existingValue(@"gradientBackgroundColors");
        id example = [existingGradient isKindOfClass:[NSArray class]] ? existingGradient.firstObject : nil;

        NSMutableArray *converted = [NSMutableArray array];
        for (UIColor *color in gradientColors) [converted addObject:[self color:color matchingExample:example]];
        gradient = converted;
    }

    typedef id (*InitFunction)(id, SEL, UIColor *, NSArray *, UIColor *, UIColor *, NSString *, NSString *, BOOL, NSString *);
    InitFunction init = (InitFunction)objc_msgSend;

    @try {
        return init([modelClass alloc], initializer, background, gradient, textColor, textColor, emoji, customizationId, usedGeneratedTheme, activationType);
    }
    @catch (NSException *exception) {
        NSLog(@"[SCInsta] Notes: couldn't create theme model: %@", exception.reason);
        return nil;
    }
}

// MARK: - Debug

+ (NSString *)themeClassDump {
    NSMutableString *dump = [NSMutableString string];
    NSArray *keywords = @[@"notestheme", @"notetheme", @"notescreation", @"notesbubble", @"notescustom", @"seasonal"];

    unsigned int classCount = 0;
    Class *classes = objc_copyClassList(&classCount);
    NSMutableArray<NSString *> *matches = [NSMutableArray array];

    for (unsigned int i = 0; i < classCount; i++) {
        NSString *name = @(class_getName(classes[i]));
        NSString *lowercase = name.lowercaseString;

        for (NSString *keyword in keywords) {
            if ([lowercase containsString:keyword]) {
                [matches addObject:name];
                break;
            }
        }
    }
    free(classes);

    [matches sortUsingSelector:@selector(compare:)];

    for (NSString *name in matches) {
        Class cls = NSClassFromString(name);
        [dump appendFormat:@"== %@ : %@\n", name, NSStringFromClass(class_getSuperclass(cls))];

        NSDictionary *properties = [self propertiesOfClass:cls];
        for (NSString *property in [properties.allKeys sortedArrayUsingSelector:@selector(compare:)]) {
            [dump appendFormat:@"  @property %@ (%@)\n", property, properties[property]];
        }

        unsigned int ivarCount = 0;
        Ivar *ivars = class_copyIvarList(cls, &ivarCount);
        for (unsigned int i = 0; i < ivarCount; i++) {
            const char *type = ivar_getTypeEncoding(ivars[i]);
            [dump appendFormat:@"  ivar %s (%s)\n", ivar_getName(ivars[i]), type ? type : "?"];
        }
        free(ivars);
    }

    return dump.length ? dump : @"No note theme classes found";
}

// MARK: - Presets

+ (UIColor *)colorFromHex:(NSString *)hex {
    unsigned int value = 0;
    [[NSScanner scannerWithString:hex] scanHexInt:&value];
    return [UIColor colorWithRed:((value >> 16) & 0xFF) / 255.0 green:((value >> 8) & 0xFF) / 255.0 blue:(value & 0xFF) / 255.0 alpha:1.0];
}

+ (NSDictionary *)presetNamed:(NSString *)name background:(NSString *)background text:(NSString *)text emoji:(NSString *)emoji gradientEnd:(nullable NSString *)gradientEnd {
    NSMutableDictionary *preset = [NSMutableDictionary dictionary];
    preset[@"name"] = name;
    preset[@"background"] = [self colorFromHex:background];
    preset[@"text"] = [self colorFromHex:text];
    preset[@"emoji"] = emoji;
    if (gradientEnd) preset[@"gradientEnd"] = [self colorFromHex:gradientEnd];
    return preset;
}

+ (NSArray<NSDictionary *> *)seasonalPresets {
    return @[
        [self presetNamed:@"New Year"         background:@"111111" text:@"F5D76E" emoji:@"🎆" gradientEnd:@"3A2E5C"],
        [self presetNamed:@"Valentine's Day"  background:@"FF4D6D" text:@"FFFFFF" emoji:@"💘" gradientEnd:@"FF8FA3"],
        [self presetNamed:@"St. Patrick's Day" background:@"1E8449" text:@"FFFFFF" emoji:@"☘️" gradientEnd:@"58D68D"],
        [self presetNamed:@"Spring"           background:@"F8C8DC" text:@"5B3256" emoji:@"🌸" gradientEnd:@"C8F0D8"],
        [self presetNamed:@"Pride"            background:@"E40303" text:@"FFFFFF" emoji:@"🏳️‍🌈" gradientEnd:@"732982"],
        [self presetNamed:@"Summer"           background:@"FFB347" text:@"1B4F72" emoji:@"🌴" gradientEnd:@"FFE29A"],
        [self presetNamed:@"Back to school"   background:@"F4D03F" text:@"1C2833" emoji:@"✏️" gradientEnd:nil],
        [self presetNamed:@"Autumn"           background:@"A04000" text:@"FDEBD0" emoji:@"🍂" gradientEnd:@"D68910"],
        [self presetNamed:@"Halloween"        background:@"FF7518" text:@"111111" emoji:@"🎃" gradientEnd:@"6C3483"],
        [self presetNamed:@"Thanksgiving"     background:@"784212" text:@"FAE5D3" emoji:@"🦃" gradientEnd:@"CA6F1E"],
        [self presetNamed:@"Winter"           background:@"D6EAF8" text:@"1B4F72" emoji:@"❄️" gradientEnd:@"FFFFFF"],
        [self presetNamed:@"Christmas"        background:@"B03A2E" text:@"FFFFFF" emoji:@"🎄" gradientEnd:@"1E8449"],
    ];
}

+ (NSArray<NSDictionary *> *)instagramSeasonalThemes {
    // Values of the IGXDTNoteActivationTypeEnum constants in Instagram 418.2.0
    return @[
        @{ @"name": @"Halloween pumpkin",  @"emoji": @"🎃", @"activationType": @"halloween_note_pumpkin" },
        @{ @"name": @"Halloween bat",      @"emoji": @"🦇", @"activationType": @"halloween_note_bat" },
        @{ @"name": @"Halloween spider",   @"emoji": @"🕷️", @"activationType": @"halloween_note_spider" },
        @{ @"name": @"Valentine's red",    @"emoji": @"❤️", @"activationType": @"valentines_red" },
        @{ @"name": @"Valentine's pink",   @"emoji": @"🩷", @"activationType": @"valentines_pink" },
        @{ @"name": @"Valentine's black",  @"emoji": @"🖤", @"activationType": @"valentines_black" },
        @{ @"name": @"New Year's Eve",     @"emoji": @"🎆", @"activationType": @"nye_2025" },
        @{ @"name": @"End of year",        @"emoji": @"✨", @"activationType": @"end_of_year_notes" },
        @{ @"name": @"Graduation",         @"emoji": @"🎓", @"activationType": @"end_of_school_graduation_notes" },
        @{ @"name": @"March Madness",      @"emoji": @"🏀", @"activationType": @"march_madness_generic_notes" },
    ];
}

+ (NSArray<NSDictionary *> *)gradientPresets {
    return @[
        [self presetNamed:@"Sunset"     background:@"FF5F6D" text:@"FFFFFF" emoji:@"🌅" gradientEnd:@"FFC371"],
        [self presetNamed:@"Ocean"      background:@"2193B0" text:@"FFFFFF" emoji:@"🌊" gradientEnd:@"6DD5ED"],
        [self presetNamed:@"Aurora"     background:@"00C9FF" text:@"0B2545" emoji:@"🌌" gradientEnd:@"92FE9D"],
        [self presetNamed:@"Purple haze" background:@"7F00FF" text:@"FFFFFF" emoji:@"🔮" gradientEnd:@"E100FF"],
        [self presetNamed:@"Peach"      background:@"FFB88C" text:@"4A2C2A" emoji:@"🍑" gradientEnd:@"DE6262"],
        [self presetNamed:@"Midnight"   background:@"232526" text:@"FFFFFF" emoji:@"🌙" gradientEnd:@"414345"],
    ];
}

@end
