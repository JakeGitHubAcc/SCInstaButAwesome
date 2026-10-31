#import "NotesThemeRuntime.h"
#import <objc/runtime.h>
#import <objc/message.h>

NSString * const SCINotesUserCustomization = @"user_led_customization";

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

// MARK: - Colors

+ (NSString *)hexForColor:(UIColor *)color {
    if (!color) return nil;
    CGFloat r = 0, g = 0, b = 0, a = 0;
    if (![color getRed:&r green:&g blue:&b alpha:&a]) {
        CGFloat white = 0;
        [color getWhite:&white alpha:&a];
        r = g = b = white;
    }
    return [NSString stringWithFormat:@"%02lX%02lX%02lX", lround(r * 255), lround(g * 255), lround(b * 255)];
}

+ (UIColor *)colorFromHex:(NSString *)hex {
    if (!hex.length) return nil;
    unsigned int value = 0;
    [[NSScanner scannerWithString:[hex stringByReplacingOccurrencesOfString:@"#" withString:@""]] scanHexInt:&value];
    return [UIColor colorWithRed:((value >> 16) & 0xFF) / 255.0 green:((value >> 8) & 0xFF) / 255.0 blue:(value & 0xFF) / 255.0 alpha:1.0];
}

// Converts a color to whatever type the model already stores in its gradient array
+ (id)color:(UIColor *)color matchingExample:(id)example {
    if (!example || [example isKindOfClass:[UIColor class]]) return color;

    if ([example isKindOfClass:[NSString class]]) {
        NSString *hex = [self hexForColor:color];
        return [(NSString *)example hasPrefix:@"#"] ? [@"#" stringByAppendingString:hex] : hex;
    }

    if (CFGetTypeID((__bridge CFTypeRef)example) == CGColorGetTypeID()) {
        return (__bridge id)color.CGColor;
    }

    return color;
}

+ (id)valueOf:(id)object forKey:(NSString *)key {
    if (!object || ![object respondsToSelector:NSSelectorFromString(key)]) return nil;
    @try { return [object valueForKey:key]; }
    @catch (NSException *exception) { return nil; }
}

// MARK: - Theme models

+ (BOOL)isOfficialActivationType:(NSString *)activationType {
    return activationType.length && ![activationType isEqualToString:SCINotesUserCustomization] && ![activationType isEqualToString:@"unsupported"];
}

+ (id)themeModelForTheme:(NSDictionary *)theme {
    Class modelClass = NSClassFromString(@"IGNotesCustomThemeCreationModel");
    SEL initializer = NSSelectorFromString(@"initWithBackgroundColor:gradientBackgroundColors:textColor:secondaryTextColor:customEmoji:customizationId:usedGeneratedTheme:activationType:");
    if (!modelClass || ![modelClass instancesRespondToSelector:initializer]) return nil;

    UIColor *background = [self colorFromHex:theme[@"background"]] ?: [UIColor blackColor];
    UIColor *text = [self colorFromHex:theme[@"text"]] ?: [UIColor whiteColor];
    UIColor *secondaryText = [self colorFromHex:theme[@"secondaryText"]] ?: text;

    // Only official designs have gradients; Instagram can't share custom ones
    NSArray *gradient = nil;
    if ([theme[@"gradient"] count] > 1) {
        NSMutableArray *colors = [NSMutableArray array];
        for (NSString *hex in theme[@"gradient"]) [colors addObject:[self colorFromHex:hex]];
        gradient = colors;
    }

    typedef id (*InitFunction)(id, SEL, UIColor *, NSArray *, UIColor *, UIColor *, NSString *, NSString *, BOOL, NSString *);
    InitFunction init = (InitFunction)objc_msgSend;

    @try {
        return init([modelClass alloc], initializer, background, gradient, text, secondaryText, theme[@"emoji"], theme[@"customizationId"], NO, theme[@"activationType"]);
    }
    @catch (NSException *exception) {
        NSLog(@"[SCInsta] Notes: couldn't create theme model: %@", exception.reason);
        return nil;
    }
}

+ (NSDictionary *)themeFromModel:(id)model {
    if (!model) return nil;

    NSMutableDictionary *theme = [NSMutableDictionary dictionary];
    theme[@"background"] = [self hexForColor:[self valueOf:model forKey:@"backgroundColor"]];
    theme[@"text"] = [self hexForColor:[self valueOf:model forKey:@"textColor"]];
    theme[@"secondaryText"] = [self hexForColor:[self valueOf:model forKey:@"secondaryTextColor"]];
    theme[@"emoji"] = [self valueOf:model forKey:@"customEmoji"];
    theme[@"customizationId"] = [self valueOf:model forKey:@"customizationId"];
    theme[@"activationType"] = [self valueOf:model forKey:@"activationType"];

    NSMutableArray *gradient = [NSMutableArray array];
    for (id color in [self valueOf:model forKey:@"gradientBackgroundColors"]) {
        if ([color isKindOfClass:[UIColor class]]) [gradient addObject:[self hexForColor:color]];
        else if ([color isKindOfClass:[NSString class]]) [gradient addObject:color];
        else if (CFGetTypeID((__bridge CFTypeRef)color) == CGColorGetTypeID()) [gradient addObject:[self hexForColor:[UIColor colorWithCGColor:(__bridge CGColorRef)color]]];
    }
    if (gradient.count) theme[@"gradient"] = gradient;

    return theme;
}

// MARK: - Official designs

static NSString * const kSavedOfficialThemesKey = @"notes_saved_official_themes";

+ (NSArray<NSDictionary *> *)savedOfficialThemes {
    NSDictionary *saved = [[NSUserDefaults standardUserDefaults] dictionaryForKey:kSavedOfficialThemesKey];
    NSArray *order = [[self officialDesignNames] valueForKey:@"activationType"];

    return [saved.allValues sortedArrayUsingComparator:^NSComparisonResult(NSDictionary *a, NSDictionary *b) {
        NSUInteger ia = [order indexOfObject:a[@"activationType"]], ib = [order indexOfObject:b[@"activationType"]];
        if (ia != ib) return ia < ib ? NSOrderedAscending : NSOrderedDescending;
        return [a[@"activationType"] compare:b[@"activationType"]];
    }];
}

+ (void)saveOfficialThemeFromModel:(id)model {
    NSMutableDictionary *theme = [[self themeFromModel:model] mutableCopy];
    NSString *activationType = theme[@"activationType"];
    if (![self isOfficialActivationType:activationType]) return;

    for (NSDictionary *design in [self officialDesignNames]) {
        if ([design[@"activationType"] isEqualToString:activationType]) theme[@"name"] = design[@"name"];
    }
    if (!theme[@"name"]) theme[@"name"] = activationType;

    NSMutableDictionary *saved = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:kSavedOfficialThemesKey] mutableCopy] ?: [NSMutableDictionary dictionary];
    // Several designs can share an activation type, so keep them apart by customization id too
    NSString *key = [NSString stringWithFormat:@"%@|%@", activationType, theme[@"customizationId"] ?: @""];
    // Keep what was learned from posting it (the theme model doesn't have it)
    if (saved[key][@"expressiveEmoji"]) theme[@"expressiveEmoji"] = saved[key][@"expressiveEmoji"];
    if ([saved[key] isEqualToDictionary:theme]) return;

    saved[key] = theme;
    [[NSUserDefaults standardUserDefaults] setObject:saved forKey:kSavedOfficialThemesKey];
    NSLog(@"[SCInsta] Notes: saved official design %@", theme);
}

+ (void)clearSavedOfficialThemes {
    [[NSUserDefaults standardUserDefaults] removeObjectForKey:kSavedOfficialThemesKey];
}

// MARK: - Sharing

// Official designs can add an "expressive emoji" (like the stars in the corners), which isn't part
// of the theme model. Learn it when a saved design is posted through Instagram's own palette.
+ (void)learnFromOfficialNoteRequest:(id)request {
    @try {
        id input = [[request valueForKey:@"noteCreateParams"] valueForKey:@"noteCustomization"];
        NSString *activationType = [input valueForKey:@"activationType"];
        if (![self isOfficialActivationType:activationType]) return;

        NSString *key = [NSString stringWithFormat:@"%@|%@", activationType, [input valueForKey:@"customizationId"] ?: @""];
        NSMutableDictionary *saved = [[[NSUserDefaults standardUserDefaults] dictionaryForKey:kSavedOfficialThemesKey] mutableCopy];
        NSMutableDictionary *theme = [saved[key] mutableCopy];
        if (!theme) return;

        id expressiveEmoji = [input valueForKey:@"expressiveEmoji"];
        if ([expressiveEmoji isKindOfClass:[NSString class]]) theme[@"expressiveEmoji"] = expressiveEmoji;
        else [theme removeObjectForKey:@"expressiveEmoji"];

        saved[key] = theme;
        [[NSUserDefaults standardUserDefaults] setObject:saved forKey:kSavedOfficialThemesKey];
    }
    @catch (NSException *exception) {}
}

static NSDictionary *sciAppliedTheme;

+ (void)setAppliedTheme:(NSDictionary *)theme {
    sciAppliedTheme = [theme copy];
}

// Instagram builds the shared theme (IGXDTNoteCustomThemeInput) from the composer's theme model.
// That only carries solid colors, an emoji, and the official design's activation type and
// customization id. A custom theme must not carry an official design's id or activation type
// (the note then posts with the default grey), so those are cleared here at posting time.
+ (void)applyThemeToNoteRequest:(id)request {
    NSDictionary *theme = sciAppliedTheme;
    if (!theme) {
        [self learnFromOfficialNoteRequest:request];
        return;
    }

    @try {
        id params = [request valueForKey:@"noteCreateParams"];
        if (!params) return;

        id input = [params valueForKey:@"noteCustomization"];
        if (!input) {
            Class inputClass = NSClassFromString(@"IGXDTNoteCustomThemeInput");
            if (!inputClass) return;
            input = [inputClass new];
        }

        // Match the hex format Instagram already used, if any
        NSString *existingHex = [input valueForKey:@"backgroundColorHex"];
        NSString *prefix = (!existingHex || [existingHex hasPrefix:@"#"]) ? @"#" : @"";
        NSString *(^hex)(NSString *) = ^NSString *(NSString *value) {
            return value.length ? [prefix stringByAppendingString:value] : nil;
        };

        [input setValue:hex(theme[@"background"]) forKey:@"backgroundColorHex"];
        [input setValue:hex(theme[@"text"]) forKey:@"textColorHex"];
        [input setValue:hex(theme[@"secondaryText"] ?: theme[@"text"]) forKey:@"secondaryTextColorHex"];
        // Everything is set, including empty values, so nothing from an earlier design is left behind
        [input setValue:theme[@"emoji"] forKey:@"customEmoji"];

        BOOL official = [self isOfficialActivationType:theme[@"activationType"]];
        [input setValue:official ? theme[@"activationType"] : SCINotesUserCustomization forKey:@"activationType"];
        [input setValue:official ? theme[@"customizationId"] : nil forKey:@"customizationId"];
        [input setValue:official ? theme[@"expressiveEmoji"] : nil forKey:@"expressiveEmoji"];

        [params setValue:input forKey:@"noteCustomization"];
    }
    @catch (NSException *exception) {
        NSLog(@"[SCInsta] Notes: couldn't apply theme to note request: %@", exception.reason);
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

+ (NSDictionary *)presetNamed:(NSString *)name background:(NSString *)background text:(NSString *)text {
    return @{ @"name": name, @"background": background, @"text": text, @"activationType": SCINotesUserCustomization };
}

+ (NSArray<NSDictionary *> *)colorPresets {
    // Solid colors only: Instagram can't share custom gradients
    return @[
        [self presetNamed:@"Midnight"      background:@"111111" text:@"F5D76E"],
        [self presetNamed:@"Rose"          background:@"FF4D6D" text:@"FFFFFF"],
        [self presetNamed:@"Clover"        background:@"1E8449" text:@"FFFFFF"],
        [self presetNamed:@"Blossom"       background:@"F8C8DC" text:@"5B3256"],
        [self presetNamed:@"Sunset"        background:@"FF5F6D" text:@"FFFFFF"],
        [self presetNamed:@"Mango"         background:@"FFB347" text:@"1B4F72"],
        [self presetNamed:@"Lemon"         background:@"F4D03F" text:@"1C2833"],
        [self presetNamed:@"Maple"         background:@"A04000" text:@"FDEBD0"],
        [self presetNamed:@"Pumpkin"       background:@"FF7518" text:@"111111"],
        [self presetNamed:@"Cocoa"         background:@"784212" text:@"FAE5D3"],
        [self presetNamed:@"Frost"         background:@"D6EAF8" text:@"1B4F72"],
        [self presetNamed:@"Holly"         background:@"B03A2E" text:@"FFFFFF"],
        [self presetNamed:@"Ocean"         background:@"2193B0" text:@"FFFFFF"],
        [self presetNamed:@"Violet"        background:@"7F00FF" text:@"FFFFFF"],
        [self presetNamed:@"Peach"         background:@"FFB88C" text:@"4A2C2A"],
        [self presetNamed:@"Graphite"      background:@"414345" text:@"FFFFFF"],
    ];
}

+ (NSArray<NSDictionary *> *)officialDesignNames {
    // Names and order for saved official designs: every IGXDTNoteActivationTypeEnum value in
    // Instagram 453 (418 has the ones without "2026", "arirang" and "listening_now")
    return @[
        @{ @"name": @"Halloween skull 2026",       @"emoji": @"💀", @"activationType": @"halloween_note_skull_2026" },
        @{ @"name": @"Halloween bat 2026",         @"emoji": @"🦇", @"activationType": @"halloween_note_bat_2026" },
        @{ @"name": @"Halloween ghost 2026",       @"emoji": @"👻", @"activationType": @"halloween_note_ghost_2026" },
        @{ @"name": @"Halloween pumpkin",          @"emoji": @"🎃", @"activationType": @"halloween_note_pumpkin" },
        @{ @"name": @"Halloween bat",              @"emoji": @"🦇", @"activationType": @"halloween_note_bat" },
        @{ @"name": @"Halloween spider",           @"emoji": @"🕷️", @"activationType": @"halloween_note_spider" },
        @{ @"name": @"Halloween",                  @"emoji": @"🕸️", @"activationType": @"halloween_notes" },
        @{ @"name": @"Valentine's red",            @"emoji": @"❤️", @"activationType": @"valentines_red" },
        @{ @"name": @"Valentine's pink",           @"emoji": @"🩷", @"activationType": @"valentines_pink" },
        @{ @"name": @"Valentine's black",          @"emoji": @"🖤", @"activationType": @"valentines_black" },
        @{ @"name": @"New Year's Eve",             @"emoji": @"🎆", @"activationType": @"nye_2025" },
        @{ @"name": @"End of year",                @"emoji": @"✨", @"activationType": @"end_of_year_notes" },
        @{ @"name": @"Graduation",                 @"emoji": @"🎓", @"activationType": @"end_of_school_graduation_notes" },
        @{ @"name": @"March Madness",              @"emoji": @"🏀", @"activationType": @"march_madness_generic_notes" },
        @{ @"name": @"March Madness team 1",       @"emoji": @"🏆", @"activationType": @"march_madness_championship_team1_notes" },
        @{ @"name": @"March Madness team 2",       @"emoji": @"🥇", @"activationType": @"march_madness_championship_team2_notes" },
        @{ @"name": @"Arirang",                    @"emoji": @"💜", @"activationType": @"arirang" },
        @{ @"name": @"Listening now",              @"emoji": @"🎧", @"activationType": @"listening_now_launch_note" },
    ];
}

@end
