#import "LauncherInstanceImport.h"
#import "UnzipKit.h"
#import "installer/modpack/ModpackUtils.h"
#import "utils.h"
#import <CommonCrypto/CommonDigest.h>

static NSError *importError(NSString *message) {
    return [NSError errorWithDomain:@"AmethystInstanceImport" code:1
                          userInfo:@{NSLocalizedDescriptionKey: message}];
}

static BOOL safePath(NSString *path) {
    if (![path isKindOfClass:NSString.class] || !path.length || [path containsString:@"\\"] ||
        [path hasPrefix:@"/"] || [path containsString:@":"]) return NO;
    for (NSString *component in [path componentsSeparatedByString:@"/"]) {
        if ([component hasPrefix:@".amethyst-"] || !component.length || [component isEqualToString:@"."] || [component isEqualToString:@".."] ||
            [component rangeOfCharacterFromSet:NSCharacterSet.controlCharacterSet].location != NSNotFound) return NO;
    }
    return YES;
}

static BOOL safeVersion(id version) {
    return [version isKindOfClass:NSString.class] && [version length] > 0 && [version length] <= 120 &&
        [version rangeOfCharacterFromSet:
         [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789._+-"] invertedSet]].location == NSNotFound &&
        ![version isEqualToString:@"."] && ![version isEqualToString:@".."];
}

static NSDictionary *readArchiveJSON(UZKArchive *archive, NSString *file, NSError **error) {
    NSData *data = [archive extractDataFromFile:file error:error];
    if (!data) return nil;
    id decoded = [NSJSONSerialization JSONObjectWithData:data options:0 error:error];
    if ([decoded isKindOfClass:NSDictionary.class]) return decoded;
    if (error && !*error) *error = importError(@"インスタンスのメタデータを読めませんでした。");
    return nil;
}

static BOOL copyTree(UZKArchive *archive, NSArray<UZKFileInfo *> *entries, NSString *prefix,
                     NSString *target, NSError **error) {
    NSFileManager *files = NSFileManager.defaultManager;
    for (UZKFileInfo *entry in entries) {
        if (entry.isDirectory || ![entry.filename hasPrefix:prefix]) continue;
        NSString *relative = [entry.filename substringFromIndex:prefix.length];
        if (!safePath(relative) || [relative hasPrefix:@".amethyst-"] || entry.uncompressedSize > 128ULL * 1024 * 1024) {
            if (error) *error = importError(@"ZIP内に使用できないファイルがあります。");
            return NO;
        }
        NSString *path = [target stringByAppendingPathComponent:relative];
        if (![files createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error]) return NO;
        NSData *data = [archive extractData:entry error:error];
        if (!data || ![data writeToFile:path options:NSDataWritingAtomic error:error]) return NO;
    }
    return YES;
}

static BOOL downloadModrinthFiles(NSArray *records, NSString *folder, NSError **error) {
    if (![records isKindOfClass:NSArray.class] || records.count > 4000) {
        if (error) *error = importError(@"Modrinthのファイル一覧を読めませんでした。");
        return NO;
    }
    NSFileManager *files = NSFileManager.defaultManager;
    for (id item in records) {
        if (![item isKindOfClass:NSDictionary.class]) return NO;
        NSDictionary *record = item;
        NSDictionary *env = [record[@"env"] isKindOfClass:NSDictionary.class] ? record[@"env"] : nil;
        if ([env[@"client"] isEqual:@"unsupported"]) continue;
        NSString *relative = record[@"path"];
        NSArray *links = [record[@"downloads"] isKindOfClass:NSArray.class] ? record[@"downloads"] : @[];
        NSDictionary *hashes = [record[@"hashes"] isKindOfClass:NSDictionary.class] ? record[@"hashes"] : @{};
        NSString *hash = [hashes[@"sha512"] isKindOfClass:NSString.class] ? [hashes[@"sha512"] lowercaseString] : nil;
        unsigned long long size = [record[@"fileSize"] respondsToSelector:@selector(unsignedLongLongValue)] ? [record[@"fileSize"] unsignedLongLongValue] : 0;
        NSURL *url = nil;
        for (id link in links) {
            if (![link isKindOfClass:NSString.class]) continue;
            NSURL *candidate = [NSURL URLWithString:link];
            if ([candidate.scheme isEqual:@"https"] && [candidate.host.lowercaseString isEqual:@"cdn.modrinth.com"]) {
                url = candidate;
                break;
            }
        }
        if (!safePath(relative) || [relative hasPrefix:@".amethyst-"] || !url || hash.length != 128 ||
            size > 128ULL * 1024 * 1024) {
            if (error) *error = importError(@"Modrinth CDNのURLとSHA-512を確認できないファイルが含まれています。");
            return NO;
        }
        NSData *data = [NSData dataWithContentsOfURL:url options:0 error:error];
        if (!data) return NO;
        unsigned char digest[CC_SHA512_DIGEST_LENGTH];
        if (data.length != size || data.length > UINT32_MAX) {
            if (error) *error = importError(@"配布ファイルのサイズが一致しません。");
            return NO;
        }
        CC_SHA512(data.bytes, (CC_LONG)data.length, digest);
        NSMutableString *actual = [NSMutableString stringWithCapacity:128];
        for (NSUInteger index = 0; index < sizeof(digest); index++) [actual appendFormat:@"%02x", digest[index]];
        if (![actual isEqualToString:hash]) {
            if (error) *error = importError(@"配布ファイルのSHA-512が一致しません。");
            return NO;
        }
        NSString *path = [folder stringByAppendingPathComponent:relative];
        if (![files createDirectoryAtPath:path.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error] ||
            ![data writeToFile:path options:NSDataWritingAtomic error:error]) return NO;
    }
    return YES;
}

@implementation LauncherInstanceImport

+ (NSDictionary *)prepareArchive:(NSURL *)url error:(NSError **)error {
    BOOL scoped = [url startAccessingSecurityScopedResource];
    @try {
        return [self readArchive:url error:error];
    } @finally {
        if (scoped) [url stopAccessingSecurityScopedResource];
    }
}

+ (NSDictionary *)readArchive:(NSURL *)url error:(NSError **)error {
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:url.path error:error];
    NSArray<UZKFileInfo *> *entries = [archive listFileInfo:error];
    if (!entries) return nil;
    if (entries.count > 30000) {
        if (error) *error = importError(@"ZIP内のファイル数が上限を超えています。");
        return nil;
    }

    NSString *manifest = nil;
    BOOL modrinth = NO;
    unsigned long long unpacked = 0;
    for (UZKFileInfo *entry in entries) {
        if (entry.isDirectory) continue;
        if (!safePath(entry.filename) || entry.uncompressedSize > 8ULL * 1024 * 1024 * 1024 - unpacked) {
            if (error) *error = importError(@"ZIPのパスまたは展開サイズが上限を超えています。");
            return nil;
        }
        unpacked += entry.uncompressedSize;
        NSString *filename = entry.filename.lastPathComponent;
        if ([filename isEqualToString:@"mmc-pack.json"] || [filename isEqualToString:@"modrinth.index.json"]) {
            if (manifest || entry.uncompressedSize > 4 * 1024 * 1024) {
                if (error) *error = importError(@"インスタンスの定義ファイルを特定できません。");
                return nil;
            }
            manifest = entry.filename;
            modrinth = [filename isEqualToString:@"modrinth.index.json"];
        }
    }
    if (!manifest) {
        if (error) *error = importError(@"Prism Launcher／MultiMCのZIP、またはModrinthのmrpackを選んでください。");
        return nil;
    }
    NSDictionary *index = readArchiveJSON(archive, manifest, error);
    if (!index) return nil;
    NSString *prefix = manifest.stringByDeletingLastPathComponent;
    if (prefix.length) prefix = [prefix stringByAppendingString:@"/"];
    NSString *name = url.lastPathComponent.stringByDeletingPathExtension;
    NSMutableDictionary *dependencies = [NSMutableDictionary new];
    if (modrinth) {
        if ([index[@"name"] isKindOfClass:NSString.class] && [index[@"name"] length]) name = index[@"name"];
        if ([index[@"dependencies"] isKindOfClass:NSDictionary.class]) [dependencies addEntriesFromDictionary:index[@"dependencies"]];
    } else {
        NSDictionary *components = @{@"net.minecraft": @"minecraft", @"net.fabricmc.fabric-loader": @"fabric-loader",
            @"org.quiltmc.quilt-loader": @"quilt-loader", @"net.minecraftforge": @"forge", @"net.neoforged": @"neoforge"};
        NSArray *items = [index[@"components"] isKindOfClass:NSArray.class] ? index[@"components"] : @[];
        for (id item in items) {
            if (![item isKindOfClass:NSDictionary.class] || ![item[@"uid"] isKindOfClass:NSString.class]) continue;
            NSString *type = components[item[@"uid"]];
            if (type && safeVersion(item[@"version"])) dependencies[type] = item[@"version"];
        }
        NSString *configPath = [prefix stringByAppendingString:@"instance.cfg"];
        for (UZKFileInfo *entry in entries) {
            if (![entry.filename isEqualToString:configPath] || entry.uncompressedSize > 65536) continue;
            NSData *data = [archive extractData:entry error:nil];
            NSString *config = data ? [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] : nil;
            for (NSString *line in [config componentsSeparatedByCharactersInSet:NSCharacterSet.newlineCharacterSet]) {
                if ([line hasPrefix:@"name="] && line.length > 5) { name = [line substringFromIndex:5]; break; }
            }
            break;
        }
    }

    NSString *base = dependencies[@"minecraft"];
    if (!safeVersion(base)) {
        if (error) *error = importError(@"Minecraftのバージョンが確認できません。");
        return nil;
    }
    NSUInteger loaders = 0;
    for (NSString *key in @[@"fabric-loader", @"quilt-loader", @"forge", @"neoforge"]) {
        if (!dependencies[key]) continue;
        if (!safeVersion(dependencies[key])) {
            if (error) *error = importError(@"Modローダーのバージョンが不正です。");
            return nil;
        }
        loaders++;
    }
    if (loaders > 1) {
        if (error) *error = importError(@"複数のModローダーを含むインスタンスは読み込めません。");
        return nil;
    }
    NSDictionary *info = [ModpackUtils infoForDependencies:dependencies];
    NSString *version = info[@"id"] ?: base;
    NSString *versions = [@(getenv("GAME_DIR")) stringByAppendingPathComponent:@"versions"];
    if (dependencies[@"neoforge"]) version = [@"neoforge-" stringByAppendingString:dependencies[@"neoforge"]];
    NSString *jsonPath = [[versions stringByAppendingPathComponent:version]
        stringByAppendingPathComponent:[version stringByAppendingPathExtension:@"json"]];
    if ((dependencies[@"forge"] || dependencies[@"neoforge"]) && ![NSFileManager.defaultManager fileExistsAtPath:jsonPath]) {
        if (error) *error = importError([NSString stringWithFormat:@"先にAmethystで対応するForge／NeoForge（%@）を導入してください。", version]);
        return nil;
    }

    NSFileManager *files = NSFileManager.defaultManager;
    NSString *root = [@(getenv("AME_HOME")) stringByAppendingPathComponent:@"instances"];
    NSString *staging = [root stringByAppendingPathComponent:[@".import-" stringByAppendingString:NSUUID.UUID.UUIDString]];
    if (![files createDirectoryAtPath:staging withIntermediateDirectories:YES attributes:nil error:error]) return nil;
    BOOL ok;
    if (modrinth) {
        ok = downloadModrinthFiles(index[@"files"], staging, error) &&
            copyTree(archive, entries, [prefix stringByAppendingString:@"overrides/"], staging, error) &&
            copyTree(archive, entries, [prefix stringByAppendingString:@"client-overrides/"], staging, error);
    } else {
        ok = copyTree(archive, entries, [prefix stringByAppendingString:@".minecraft/"], staging, error) &&
            copyTree(archive, entries, [prefix stringByAppendingString:@"minecraft/"], staging, error);
    }
    if (ok && info[@"json"] && ![files fileExistsAtPath:jsonPath]) {
        NSData *data = [NSData dataWithContentsOfURL:[NSURL URLWithString:info[@"json"]] options:0 error:error];
        id loader = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:error] : nil;
        ok = [loader isKindOfClass:NSDictionary.class] && [loader[@"id"] isEqualToString:version] &&
            [files createDirectoryAtPath:jsonPath.stringByDeletingLastPathComponent withIntermediateDirectories:YES attributes:nil error:error] &&
            [data writeToFile:jsonPath options:NSDataWritingAtomic error:error];
    }
    if (ok) ok = [@"1" writeToFile:[staging stringByAppendingPathComponent:@".amethyst-instance"]
                       atomically:YES encoding:NSUTF8StringEncoding error:error];
    if (!ok) {
        [files removeItemAtPath:staging error:nil];
        if (error && !*error) *error = importError(@"インスタンスを読み込めませんでした。");
        return nil;
    }
    return @{@"name": name, @"version": version, @"staging": staging};
}

@end
