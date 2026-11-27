#import "LauncherPreferences.h"
#import "PLProfiles.h"
#import "utils.h"

static PLProfiles* current;

@interface PLProfiles()
@end

@implementation PLProfiles

+ (id)defaultProfiles {
    return @{
        @"profiles": @{
            @"(Default)": @{
                @"name": @"(Default)",
                @"lastVersionId": @"latest-release"
            }
        },
        @"selectedProfile": @"(Default)"
    }.mutableCopy;
}

+ (PLProfiles *)current {
    if (!current) {
        [self updateCurrent];
    }
    return current;
}

+ (void)updateCurrent {
    current = [[PLProfiles alloc] initWithCurrentInstance];
}

+ (id)profile:(NSMutableDictionary *)profile resolveKey:(id)key {
    NSString *value = profile[key];
    if (value.length > 0) {
        //NSDebugLog(@"[PLProfiles] Applying %@: \"%@\"", key, value);
        return value;
    }

    NSDictionary *valueDefaults = @{
        @"javaVersion": @"0",
        @"gameDir": @"."
    };
    if (valueDefaults[key]) {
        return valueDefaults[key];
    }

    NSDictionary *prefDefaults = @{
        @"defaultTouchCtrl": @"control.default_ctrl",
        @"defaultGamepadCtrl": @"control.default_gamepad_ctrl",
        @"javaArgs": @"java.java_args",
        @"renderer": @"video.renderer"
    };
    return getPrefObject(prefDefaults[key]);
}

+ (id)resolveKeyForCurrentProfile:(id)key {
    return [self profile:self.current.selectedProfile resolveKey:key];
}

- (id)initWithCurrentInstance {
    self = [super init];
    self.profilePath = [@(getenv("GAME_DIR")) stringByAppendingPathComponent:@"launcher_profiles.json"];
    self.profileDict = parseJSONFromFile(self.profilePath);
    if (self.profileDict[@"NSErrorObject"]) {
        self.profileDict = PLProfiles.defaultProfiles;
        [self save];
    }

    return self;
}

- (id)profiles {
    return self.profileDict[@"profiles"];
}

- (id)selectedProfile {
    return self.profiles[self.selectedProfileName];
}

- (NSString *)selectedProfileName {
    return (id)self.profileDict[@"selectedProfile"];
}

- (void)setSelectedProfileName:(NSString *)name {
    self.profileDict[@"selectedProfile"] = (id)name;
    [self save];
}

- (void)save {
    saveJSONToFile(self.profileDict, self.profilePath);
}

// Keep the shared launcher metadata and downloaded libraries in GAME_DIR.
- (NSString *)instancePathForName:(NSString *)name {
    NSMutableCharacterSet *allowed = NSCharacterSet.alphanumericCharacterSet.mutableCopy;
    [allowed addCharactersInString:@" _-()"];
    NSString *component = [name stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    if (!component.length || [component lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 220) return nil;
    return [[@(getenv("AME_HOME")) stringByAppendingPathComponent:@"instances"] stringByAppendingPathComponent:component];
}

- (NSError *)directoryError:(NSString *)message {
    return [NSError errorWithDomain:@"AmethystInstanceDirectory" code:1
                           userInfo:@{NSLocalizedDescriptionKey: message}];
}

- (NSString *)gameDirectoryForProfile:(NSString *)key create:(BOOL)create error:(NSError **)error {
    NSDictionary *profile = self.profiles[key];
    if (!profile || getenv("DEMO_LOCK")) return @(getenv("GAME_DIR"));
    NSString *target = [self instancePathForName:key];
    NSFileManager *manager = NSFileManager.defaultManager;
    NSString *instancesRoot = target.stringByDeletingLastPathComponent;
    BOOL fresh = [profile[@"instanceLayout"] isEqualToString:@"new"];
    NSString *legacyRoot = [@(getenv("GAME_DIR")) stringByResolvingSymlinksInPath];
    NSString *subdir = [profile[@"gameDir"] length] ? profile[@"gameDir"] : @".";
    NSString *source = [[legacyRoot stringByAppendingPathComponent:subdir] stringByResolvingSymlinksInPath].stringByStandardizingPath;
    NSString *marker = [target stringByAppendingPathComponent:@".amethyst-instance"];
    if (target && [manager fileExistsAtPath:marker]) return target;
    // Existing folders can belong to the previous multi-directory layout.
    if (target && [manager fileExistsAtPath:target] && (![source isEqualToString:target] || [source isEqualToString:legacyRoot])) {
        target = [target stringByAppendingString:@"~profile"];
        marker = [target stringByAppendingPathComponent:@".amethyst-instance"];
        if ([manager fileExistsAtPath:marker]) return target;
    }
    if (!create) return target;
    if (!target || ([manager fileExistsAtPath:target] && ![source isEqualToString:target])) {
        if (error) *error = [self directoryError:@"インスタンスの保存先を確保できませんでした。"];
        return nil;
    }
    if ([source isEqualToString:target]) {
        if (![@"1" writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:error]) return nil;
        return target;
    }
    if (![manager createDirectoryAtPath:instancesRoot withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    NSString *staging = [instancesRoot stringByAppendingPathComponent:[@".migration-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    if (![manager createDirectoryAtPath:staging withIntermediateDirectories:NO attributes:nil error:error]) return nil;
    BOOL ok = YES;
    BOOL isLegacyPath = [source isEqualToString:legacyRoot] ||
        [source hasPrefix:[legacyRoot stringByAppendingString:@"/"]];
    if (!fresh && isLegacyPath && [manager fileExistsAtPath:source]) {
        NSArray *contents = [manager contentsOfDirectoryAtPath:source error:error];
        ok = contents != nil;
        NSSet *shared = [NSSet setWithArray:@[@"launcher_profiles.json", @"launcher_preferences.plist",
            @"versions", @"libraries", @"assets", @"custom_gamedir", @".amethyst-instance"]];
        for (NSString *entry in contents) {
            if ([shared containsObject:entry]) continue;
            ok = [manager copyItemAtPath:[source stringByAppendingPathComponent:entry]
                                 toPath:[staging stringByAppendingPathComponent:entry] error:error];
            if (!ok) break;
        }
    }
    if (ok) ok = [@"1" writeToFile:[staging stringByAppendingPathComponent:@".amethyst-instance"]
                           atomically:YES encoding:NSUTF8StringEncoding error:error];
    if (ok) ok = [manager moveItemAtPath:staging toPath:target error:error];
    if (!ok) [manager removeItemAtPath:staging error:nil];
    return ok ? target : nil;
}

- (BOOL)renameGameDirectoryForProfile:(NSString *)oldKey to:(NSString *)newKey error:(NSError **)error {
    NSString *target = [self instancePathForName:newKey];
    if (!target) {
        if (error) *error = [self directoryError:@"インスタンス名が長すぎます。"];
        return NO;
    }
    if (!oldKey.length || getenv("DEMO_LOCK")) return YES;
    NSString *source = [self gameDirectoryForProfile:oldKey create:NO error:nil];
    if (!source || ![NSFileManager.defaultManager fileExistsAtPath:[source stringByAppendingPathComponent:@".amethyst-instance"]]) return YES;
    if ([source isEqualToString:target]) return YES;
    return [NSFileManager.defaultManager moveItemAtPath:source toPath:target error:error];
}

@end
