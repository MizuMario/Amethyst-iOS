#import "LauncherMenuViewController.h"
#import "LauncherNavigationController.h"
#import "LauncherPreferences.h"
#import "LauncherPreferencesViewController.h"
#import "LauncherPrefGameDirViewController.h"
#import "LauncherPrefManageJREViewController.h"
#import "LauncherProfileEditorViewController.h"
#import "LauncherProfilesViewController.h"
//#import "NSFileManager+NRFileManager.h"
#import "PLProfiles.h"
#pragma clang diagnostic push
#pragma clang diagnostic ignored "-Wunguarded-availability-new"
#import "UIKit+AFNetworking.h"
#pragma clang diagnostic pop
#import "UIKit+hook.h"
#import "installer/FabricInstallViewController.h"
#import "installer/ForgeInstallViewController.h"
#import "installer/ModpackInstallViewController.h"
#import "ios_uikit_bridge.h"
#import "utils.h"
#import "UnzipKit.h"
#import "LauncherInstanceImport.h"
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>

#if AMETHYST_SWIFT_PROFILE_UI
@interface AMProfileBrowser : NSObject
+ (UIViewController *)makeWithRows:(NSArray<NSDictionary *> *)rows selected:(NSString *)selected
    isolated:(BOOL)isolated allowsInstanceSettings:(BOOL)allowsInstanceSettings settings:(UIViewController *(^)(NSString *))settings
    jitStatus:(BOOL (^)(void))jitStatus accountImage:(UIImage *(^)(void))accountImage
    downloadSnapshot:(NSDictionary *(^)(void))downloadSnapshot prepareDirectory:(NSString *(^)(NSString *))prepareDirectory
    blockTexture:(UIImage *(^)(NSString *, NSString *))blockTexture
    blockTextures:(NSArray *(^)(NSString *))blockTextures
    saveJava:(BOOL (^)(NSString *, NSDictionary *))saveJava action:(void (^)(NSString *, NSString *))action;
+ (void)updateController:(UIViewController *)controller rows:(NSArray<NSDictionary *> *)rows selected:(NSString *)selected;
@end
#endif

typedef NS_ENUM(NSUInteger, LauncherProfilesTableSection) {
    kInstances,
    kProfiles
};

@interface LauncherProfilesViewController () <UIDocumentPickerDelegate>

@property(nonatomic) UIBarButtonItem *createButtonItem;
#if AMETHYST_SWIFT_PROFILE_UI
@property(nonatomic) UIViewController *profileBrowser;
#endif
@end

@implementation LauncherProfilesViewController

- (id)init {
    self = [super init];
    self.title = localize(@"Profiles", nil);
    return self;
}

- (NSString *)imageName {
    return @"MenuProfiles";
}

- (void)viewDidLoad
{
    [super viewDidLoad];

    [NSNotificationCenter.defaultCenter addObserver:self selector:@selector(profileEditorDidSave:)
        name:LauncherProfilesDidSaveNotification object:nil];

    UIMenu *createMenu = [UIMenu menuWithTitle:localize(@"profile.title.create", nil) image:nil identifier:nil
    options:UIMenuOptionsDisplayInline
    children:@[
        [UIAction
            actionWithTitle:@"Vanilla" image:nil
            identifier:@"vanilla" handler:^(UIAction *action) {
                [self actionEditProfile:@{
                    @"name": @"",
                    @"lastVersionId": @"latest-release"}];
            }],
#if 0 // TODO
        [UIAction
            actionWithTitle:@"OptiFine" image:nil
            identifier:@"optifine" handler:createHandler],
#endif
        [UIAction
            actionWithTitle:@"Fabric/Quilt" image:nil
            identifier:@"fabric_or_quilt" handler:^(UIAction *action) {
                [self actionCreateFabricProfile];
            }],
        [UIAction
            actionWithTitle:@"Forge" image:nil
            identifier:@"forge" handler:^(UIAction *action) {
                [self actionCreateForgeProfile];
            }],
        [UIAction
            actionWithTitle:@"Modpack" image:nil
            identifier:@"modpack" handler:^(UIAction *action) {
                [self actionCreateModpackProfile];
            }]
    ]];
    self.createButtonItem = [[UIBarButtonItem alloc] initWithBarButtonSystemItem:UIBarButtonSystemItemAdd menu:createMenu];
    if(@available(iOS 19.0, *)) {
        self.createButtonItem.sharesBackground = NO;
    }

    #if !AMETHYST_SWIFT_PROFILE_UI
    self.tableView = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleInsetGrouped];
    self.tableView.keyboardDismissMode = UIScrollViewKeyboardDismissModeInteractive;
    #endif
}

- (void)viewWillAppear:(BOOL)animated {
    [super viewWillAppear:animated];

    // Put navigation buttons back in place
    self.navigationItem.rightBarButtonItems = @[[sidebarViewController drawAccountButton], self.createButtonItem];

#if AMETHYST_SWIFT_PROFILE_UI
    if (@available(iOS 17.0, *)) {
        [self.navigationController setNavigationBarHidden:YES animated:NO];
        [self.navigationController setToolbarHidden:YES animated:NO];
        self.navigationItem.leftBarButtonItem = nil;
        self.navigationItem.hidesBackButton = YES;
        self.navigationItem.rightBarButtonItems = @[];
    }
#endif

    // Pickup changes made in the profile editor and switching instance
    [PLProfiles updateCurrent];
#if AMETHYST_SWIFT_PROFILE_UI
    [self refreshProfileBrowser];
#else
    [self.tableView reloadData];
#endif
    [self.navigationController performSelector:@selector(reloadProfileList)];
}

- (void)profileEditorDidSave:(NSNotification *)notification {
    if (!self.isViewLoaded || self.navigationController.topViewController != self) return;
    [(LauncherNavigationController *)self.navigationController reloadProfileList];
#if AMETHYST_SWIFT_PROFILE_UI
    [self refreshProfileBrowser];
#else
    [self.tableView reloadData];
#endif
}

- (void)viewWillDisappear:(BOOL)animated {
    [super viewWillDisappear:animated];
#if AMETHYST_SWIFT_PROFILE_UI
    if (@available(iOS 17.0, *)) {
        if (self.navigationController.topViewController != self) {
            [self.navigationController setNavigationBarHidden:NO animated:animated];
        }
    }
#endif
}

- (void)actionTogglePrefIsolation:(UISwitch *)sender {
    if (!sender.isOn) {
        setPrefBool(@"internal.isolated", NO);
    }
    toggleIsolatedPref(sender.isOn);
}

- (void)actionCreateFabricProfile {
    FabricInstallViewController *vc = [FabricInstallViewController new];
    [self presentNavigatedViewController:vc];
}

- (void)actionCreateForgeProfile {
    ForgeInstallViewController *vc = [ForgeInstallViewController new];
    [self presentNavigatedViewController:vc];
}

- (void)actionCreateModpackProfile {
    ModpackInstallViewController *vc = [ModpackInstallViewController new];
    [self presentNavigatedViewController:vc];
}

- (void)actionEditProfile:(NSDictionary *)profile {
    LauncherProfileEditorViewController *vc = [LauncherProfileEditorViewController new];
    vc.profile = profile.mutableCopy;
    [self presentNavigatedViewController:vc];
}

- (void)presentNavigatedViewController:(UIViewController *)vc {
    UINavigationController *nav = [[UINavigationController alloc] initWithRootViewController:vc];
    //nav.navigationBar.prefersLargeTitles = YES;
#if AMETHYST_SWIFT_PROFILE_UI
    nav.modalPresentationStyle = UIModalPresentationFullScreen;
#endif
    [self presentViewController:nav animated:YES completion:nil];
}

#if AMETHYST_SWIFT_PROFILE_UI
- (NSString *)clientArchiveForVersion:(NSString *)version {
    if (!version.length || ![version isEqualToString:version.lastPathComponent] ||
        [version isEqualToString:@"."] || [version isEqualToString:@".."]) return nil;
    NSString *versions = [@(getenv("GAME_DIR")) stringByAppendingPathComponent:@"versions"];
    NSString *folder = [versions stringByAppendingPathComponent:version];
    NSString *metadataPath = [folder stringByAppendingPathComponent:[version stringByAppendingPathExtension:@"json"]];
    if ([NSFileManager.defaultManager fileExistsAtPath:metadataPath]) {
        NSString *parent = parseJSONFromFile(metadataPath)[@"inheritsFrom"];
        if (parent.length && [parent isEqualToString:parent.lastPathComponent] &&
            ![parent isEqualToString:@"."] && ![parent isEqualToString:@".."]) {
            version = parent;
            folder = [versions stringByAppendingPathComponent:parent];
        }
    }
    NSString *jar = [folder stringByAppendingPathComponent:[version stringByAppendingPathExtension:@"jar"]];
    return [NSFileManager.defaultManager fileExistsAtPath:jar] ? jar : nil;
}

- (NSArray<NSString *> *)blockTexturesForVersion:(NSString *)version {
    NSString *jar = [self clientArchiveForVersion:version];
    if (!jar) return @[];
    UZKArchive *archive = [[UZKArchive alloc] initWithPath:jar error:nil];
    NSMutableSet *names = [NSMutableSet new];
    for (NSString *path in [archive listFilenames:nil]) {
        NSString *directory = path.stringByDeletingLastPathComponent;
        if (([directory isEqualToString:@"assets/minecraft/textures/block"] ||
             [directory isEqualToString:@"assets/minecraft/textures/blocks"]) &&
            [path.pathExtension isEqualToString:@"png"]) {
            [names addObject:path.lastPathComponent.stringByDeletingPathExtension];
        }
    }
    return [[names allObjects] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
}

- (UIImage *)blockTexture:(NSString *)texture forVersion:(NSString *)version {
    static NSCache<NSString *, UIImage *> *cache;
    static dispatch_once_t once;
    dispatch_once(&once, ^{
        cache = [NSCache new];
        cache.countLimit = 64;
    });
    if (!texture.length || [texture rangeOfCharacterFromSet:
            [[NSCharacterSet characterSetWithCharactersInString:@"abcdefghijklmnopqrstuvwxyz0123456789_"] invertedSet]].location != NSNotFound) return nil;
    NSString *jar = [self clientArchiveForVersion:version];
    if (!jar) return nil;
    NSString *key = [jar stringByAppendingFormat:@"/%@", texture];
    UIImage *image = [cache objectForKey:key];
    if (image) return image;

    UZKArchive *archive = [[UZKArchive alloc] initWithPath:jar error:nil];
    for (NSString *subfolder in @[@"block", @"blocks"]) {
        NSString *path = [NSString stringWithFormat:@"assets/minecraft/textures/%@/%@.png", subfolder, texture];
        NSData *data = [archive extractDataFromFile:path error:nil];
        image = data ? [UIImage imageWithData:data] : nil;
        if (image) {
            [cache setObject:image forKey:key];
            return image;
        }
    }
    return nil;
}

- (void)refreshProfileBrowser {
    NSDictionary *profiles = PLProfiles.current.profiles;
    NSMutableArray *rows = [NSMutableArray new];
    NSMutableArray<NSString *> *javaVersions = [NSMutableArray new];
    for (NSString *key in [[getPrefObject(@"java.java_homes") allKeys] sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
        if (key.intValue > 0 && getJavaHomeForVersion(key)) [javaVersions addObject:key];
    }
    NSInteger maxMemory = MAX(250, (NSInteger)((NSProcessInfo.processInfo.physicalMemory / 1048576) * 0.85));
    for (NSString *key in [profiles.allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
        NSDictionary *profile = profiles[key];
        NSString *directory = [PLProfiles.current gameDirectoryForProfile:key create:NO error:nil];
        NSString *log = [directory stringByAppendingPathComponent:@"logs/latest.log"];
        if (log.length == 0 || ![NSFileManager.defaultManager fileExistsAtPath:log]) {
            NSString *legacy = [profile[@"gameDir"] length] ? profile[@"gameDir"] : @".";
            log = [[@(getenv("GAME_DIR")) stringByAppendingPathComponent:legacy]
                stringByAppendingPathComponent:@"logs/latest.log"];
        }
        [rows addObject:@{@"id": key, @"name": profile[@"name"] ?: key,
                          @"version": profile[@"lastVersionId"] ?: @"",
                          @"iconTexture": profile[@"iconTexture"] ?: @"",
                          @"log": log, @"java": profile[@"javaVersion"] ?: @"0",
                          @"javaVersions": [javaVersions componentsJoinedByString:@","],
                          @"javaArgs": profile[@"javaArgs"] ?: @"",
                          @"javaArgsOverride": profile[@"javaArgsOverride"] ?: @"",
                          @"memoryMode": profile[@"memoryMode"] ?: @"inherit",
                          @"memoryMB": profile[@"memoryMB"] ?: @(getPrefInt(@"java.allocated_memory")).stringValue,
                          @"maxMemory": @(maxMemory).stringValue,
                          @"canDelete": profiles.count > 1 ? @"1" : @"0"}];
    }

    if (self.profileBrowser) {
        [AMProfileBrowser updateController:self.profileBrowser rows:rows selected:PLProfiles.current.selectedProfileName];
        return;
    }

    __weak typeof(self) weakSelf = self;
    self.profileBrowser = [AMProfileBrowser makeWithRows:rows selected:PLProfiles.current.selectedProfileName
        isolated:getPrefBool(@"internal.isolated") allowsInstanceSettings:!getenv("DEMO_LOCK")
        settings:^UIViewController *(NSString *section) {
            LauncherPreferencesViewController *controller = [LauncherPreferencesViewController new];
            controller.launcherSection = section;
            return controller;
        }
        jitStatus:^BOOL { return isJITEnabled(false); }
        accountImage:^UIImage *{
            LauncherProfilesViewController *owner = weakSelf;
            if (!owner) return [UIImage imageNamed:@"DefaultAccount"];
            UINavigationController *menuNavigation = (id)owner.splitViewController.viewControllers.firstObject;
            LauncherMenuViewController *menu = (id)menuNavigation.viewControllers.firstObject;
            return menu.accountButton.currentImage ?: [UIImage imageNamed:@"DefaultAccount"];
        }
        downloadSnapshot:^NSDictionary *{
            LauncherNavigationController *navigation = (id)weakSelf.navigationController;
            return [navigation launcherDownloadSnapshot] ?: @{};
        }
        prepareDirectory:^NSString *(NSString *key) {
            NSError *error;
            NSString *path = [PLProfiles.current gameDirectoryForProfile:key create:YES error:&error];
            if (!path) NSLog(@"[Launcher] Cannot prepare instance directory: %@", error);
            return path;
        }
        blockTexture:^UIImage *(NSString *version, NSString *texture) {
            return [weakSelf blockTexture:texture forVersion:version];
        }
        blockTextures:^NSArray *(NSString *version) {
            return [weakSelf blockTexturesForVersion:version] ?: @[];
        }
        saveJava:^BOOL(NSString *key, NSDictionary *values) {
            if (!weakSelf || getenv("DEMO_LOCK")) return NO;
            PLProfiles *store = PLProfiles.current;
            NSDictionary *current = store.profiles[key];
            if (!current) return NO;
            int memory = [values[@"memoryMB"] intValue];
            if ([values[@"memoryMode"] isEqualToString:@"manual"] && (memory < 250 || memory > maxMemory)) return NO;
            NSMutableDictionary *updated = current.mutableCopy;
            for (NSString *field in @[@"javaVersion", @"javaArgs", @"javaArgsOverride", @"memoryMode", @"memoryMB", @"iconTexture"]) {
                if ([values[field] isKindOfClass:NSString.class]) updated[field] = values[field];
            }
            store.profiles[key] = updated;
            NSError *error = saveJSONToFile(store.profileDict, store.profilePath);
            if (error) {
                store.profiles[key] = current.mutableCopy;
                NSLog(@"[Launcher] Cannot save Java configuration: %@", error);
                return NO;
            }
            return YES;
        }
        action:^(NSString *action, NSString *key) {
        [weakSelf handleProfileAction:action key:key];
    }];
    UIViewController *browser = self.profileBrowser;
    [self addChildViewController:browser];
    browser.view.frame = self.view.bounds;
    browser.view.autoresizingMask = UIViewAutoresizingFlexibleWidth | UIViewAutoresizingFlexibleHeight;
    [self.view addSubview:browser.view];
    [browser didMoveToParentViewController:self];
}

- (void)showImportPicker API_AVAILABLE(ios(14.0)) {
    if (getenv("DEMO_LOCK")) return;
    UTType *modrinth = [UTType typeWithFilenameExtension:@"mrpack"] ?: UTTypeData;
    UIDocumentPickerViewController *picker = [[UIDocumentPickerViewController alloc]
        initForOpeningContentTypes:@[UTTypeZIP, modrinth] asCopy:YES];
    picker.delegate = self;
    picker.allowsMultipleSelection = NO;
    [self presentViewController:picker animated:YES completion:nil];
}

- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *url = urls.firstObject;
    if (!url) return;
    PLProfiles *store = PLProfiles.current;
    dispatch_async(dispatch_get_main_queue(), ^{
        UIAlertController *progress = [UIAlertController alertControllerWithTitle:@"インスタンスを読み込み中"
            message:@"読み込みが完了するまでお待ちください。" preferredStyle:UIAlertControllerStyleAlert];
        [self presentViewController:progress animated:YES completion:^{
            dispatch_async(dispatch_get_global_queue(QOS_CLASS_USER_INITIATED, 0), ^{
                NSError *error;
                NSDictionary *item = [LauncherInstanceImport prepareArchive:url error:&error];
                dispatch_async(dispatch_get_main_queue(), ^{
                    [progress dismissViewControllerAnimated:YES completion:^{
                        if (!item) {
                            showDialog(localize(@"Error", nil), error.localizedDescription ?: @"読み込みに失敗しました。");
                            return;
                        }
                        [self installImportedInstance:item intoStore:store];
                    }];
                });
            });
        }];
    });
}

- (void)installImportedInstance:(NSDictionary *)item intoStore:(PLProfiles *)store {
    NSFileManager *files = NSFileManager.defaultManager;
    NSString *staging = item[@"staging"];
    NSString *base = [item[@"name"] stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
    if (!base.length) base = @"Imported Instance";
    while (base.length && ![store instancePathForName:base]) {
        NSRange last = [base rangeOfComposedCharacterSequenceAtIndex:base.length - 1];
        base = [base substringToIndex:last.location];
    }
    if (!base.length) base = @"Imported Instance";
    NSString *name = base;
    NSString *target = [store instancePathForName:name];
    if (!target || [target lengthOfBytesUsingEncoding:NSUTF8StringEncoding] > 900) {
        [files removeItemAtPath:staging error:nil];
        showDialog(localize(@"Error", nil), @"保存先を作成できませんでした。");
        return;
    }

    for (NSUInteger suffix = 2; store.profiles[name] || [files fileExistsAtPath:target]; suffix++) {
        NSString *ending = [NSString stringWithFormat:@" %lu", (unsigned long)suffix];
        NSString *shortName = base;
        while (shortName.length && ![store instancePathForName:[shortName stringByAppendingString:ending]]) {
            NSRange last = [shortName rangeOfComposedCharacterSequenceAtIndex:shortName.length - 1];
            shortName = [shortName substringToIndex:last.location];
        }
        name = [shortName stringByAppendingString:ending];
        target = [store instancePathForName:name];
    }

    NSError *error = nil;
    if (![PLProfiles.current.profilePath isEqualToString:store.profilePath]) {
        error = [NSError errorWithDomain:@"AmethystInstanceImport" code:2
            userInfo:@{NSLocalizedDescriptionKey: @"読み込み中にアカウントが切り替わりました。"}];
    } else if ([files moveItemAtPath:staging toPath:target error:&error]) {
        PLProfiles *current = PLProfiles.current;
        // Use the live store so an import never overwrites unrelated profile edits.
        current.profiles[name] = [@{@"name": name, @"lastVersionId": item[@"version"], @"instanceLayout": @"new"} mutableCopy];
        error = saveJSONToFile(current.profileDict, current.profilePath);
        if (!error) {
            [(LauncherNavigationController *)self.navigationController reloadProfileList];
            [self refreshProfileBrowser];
            showDialog(@"読み込み完了", name);
            return;
        }
        [current.profiles removeObjectForKey:name];
        [files removeItemAtPath:target error:nil];
    }
    [files removeItemAtPath:staging error:nil];
    showDialog(localize(@"Error", nil), error.localizedDescription ?: @"保存できませんでした。");
}

- (void)handleProfileAction:(NSString *)action key:(NSString *)key {
    LauncherNavigationController *navigation = (id)self.navigationController;
    PLProfiles *store = PLProfiles.current;
    if ([action isEqualToString:@"account"]) {
        UIView *anchor = self.profileBrowser.view;
        CGRect area = anchor.safeAreaLayoutGuide.layoutFrame;
        CGRect rect = CGRectMake(CGRectGetMaxX(area) - 46, CGRectGetMinY(area) + 12, 32, 32);
        [sidebarViewController selectAccountFrom:navigation anchor:anchor sourceRect:rect completion:nil];
    } else if ([action isEqualToString:@"importInstance"]) {
        [self showImportPicker];
    } else if ([action isEqualToString:@"createVanilla"]) {
        [self actionEditProfile:@{@"name": @"", @"lastVersionId": @"latest-release"}];
    } else if ([action isEqualToString:@"createFabric"]) {
        [self actionCreateFabricProfile];
    } else if ([action isEqualToString:@"createForge"]) {
        [self actionCreateForgeProfile];
    } else if ([action isEqualToString:@"createModpack"]) {
        [self actionCreateModpackProfile];
    } else if ([action isEqualToString:@"jit"]) {
        [navigation requestLauncherJIT];
    } else if ([action isEqualToString:@"directory"]) {
        if (!getenv("DEMO_LOCK")) [navigation pushViewController:[LauncherPrefGameDirViewController new] animated:YES];
    } else if ([action isEqualToString:@"isolation"]) {
        if (getenv("DEMO_LOCK")) return;
        BOOL enabled = [key isEqualToString:@"1"];
        if (!enabled) setPrefBool(@"internal.isolated", NO);
        toggleIsolatedPref(enabled);
    } else if (store.profiles[key]) {
        if ([action isEqualToString:@"select"] || [action isEqualToString:@"play"]) {
            [navigation selectProfile:key launch:[action isEqualToString:@"play"]];
        } else if ([action isEqualToString:@"edit"]) {
            [self actionEditProfile:store.profiles[key]];
        } else if ([action isEqualToString:@"duplicate"]) {
            NSMutableDictionary *copy = [store.profiles[key] mutableCopy];
            NSString *name = [NSString stringWithFormat:@"%@ のコピー", copy[@"name"] ?: key];
            NSString *uniqueName = name;
            for (NSUInteger index = 2; store.profiles[uniqueName]; index++) {
                uniqueName = [NSString stringWithFormat:@"%@ %lu", name, (unsigned long)index];
            }
            copy[@"name"] = uniqueName;
            copy[@"instanceLayout"] = @"new";
            [copy removeObjectForKey:@"gameDir"];
            store.profiles[uniqueName] = copy;
            store.selectedProfileName = uniqueName;
            [navigation reloadProfileList];
            [self refreshProfileBrowser];
        } else if ([action isEqualToString:@"delete"] && store.profiles.count > 1) {
            UIAlertController *alert = [UIAlertController alertControllerWithTitle:localize(@"preference.title.confirm", nil)
                message:store.profiles[key][@"name"] ?: key preferredStyle:UIAlertControllerStyleAlert];
            [alert addAction:[UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil]];
            __weak typeof(self) weakSelf = self;
            [alert addAction:[UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleDestructive
                handler:^(UIAlertAction *unused) {
                    if (PLProfiles.current != store || store.profiles.count <= 1 || !store.profiles[key]) return;
                    [store.profiles removeObjectForKey:key];
                    if ([store.selectedProfileName isEqualToString:key]) {
                        store.selectedProfileName = [store.profiles.allKeys sortedArrayUsingSelector:@selector(localizedStandardCompare:)].firstObject;
                    } else {
                        [store save];
                    }
                    [navigation reloadProfileList];
                    [weakSelf refreshProfileBrowser];
                }]];
            [self presentViewController:alert animated:YES completion:nil];
        }
    }
}
#else
#pragma mark Table view

- (NSInteger)numberOfSectionsInTableView:(UITableView *)tableView {
    return 2;
}

- (NSString *)tableView:(UITableView *)tableView titleForHeaderInSection:(NSInteger)section {
    switch (section) {
        case 0: return localize(@"profile.section.instance", nil);
        case 1: return localize(@"profile.section.profiles", nil);
    }
    return nil;
}

- (NSInteger)tableView:(UITableView *)tableView numberOfRowsInSection:(NSInteger)section {
    switch (section) {
        case 0: return 2;
        case 1: return [PLProfiles.current.profiles count];
    }
    return 0;
}

- (void)setupInstanceCell:(UITableViewCell *) cell atRow:(NSInteger)row {
    cell.userInteractionEnabled = !getenv("DEMO_LOCK");
    if (row == 0) {
        cell.imageView.image = [UIImage systemImageNamed:@"folder"];
        cell.textLabel.text = localize(@"preference.title.game_directory", nil);
        cell.detailTextLabel.text = getenv("DEMO_LOCK") ? @".demo" : getPrefObject(@"general.game_directory");
    } else {
        NSString *imageName;
        if (@available(iOS 15.0, *)) {
            imageName = @"folder.badge.gearshape";
        } else {
            imageName = @"folder.badge.gear";
        }
        cell.imageView.image = [UIImage systemImageNamed:imageName];
        cell.textLabel.text = localize(@"profile.title.separate_preference", nil);
        cell.detailTextLabel.text = localize(@"profile.detail.separate_preference", nil);
        UISwitch *view = [UISwitch new];
        [view setOn:getPrefBool(@"internal.isolated") animated:NO];
        [view addTarget:self action:@selector(actionTogglePrefIsolation:) forControlEvents:UIControlEventValueChanged];
        cell.accessoryView = view;
    }
}

- (void)setupProfileCell:(UITableViewCell *) cell atRow:(NSInteger)row {
    NSMutableDictionary *profile = PLProfiles.current.profiles.allValues[row];

    cell.textLabel.text = profile[@"name"];
    cell.detailTextLabel.text = profile[@"lastVersionId"];
    cell.imageView.layer.magnificationFilter = kCAFilterNearest;

    UIImage *fallbackImage = [[UIImage imageNamed:@"DefaultProfile"] _imageWithSize:CGSizeMake(40, 40)];
    [cell.imageView setImageWithURL:[NSURL URLWithString:profile[@"icon"]] placeholderImage:fallbackImage];
}

- (UITableViewCell *)tableView:(nonnull UITableView *)tableView cellForRowAtIndexPath:(NSIndexPath *)indexPath
{
    NSString *cellID = indexPath.section == kInstances ? @"InstanceCell" : @"ProfileCell";
    UITableViewCell *cell = [tableView dequeueReusableCellWithIdentifier:cellID];
    if (cell == nil) {
        cell = [[UITableViewCell alloc] initWithStyle:UITableViewCellStyleSubtitle reuseIdentifier:cellID];
        cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
        cell.detailTextLabel.numberOfLines = 0;
        cell.detailTextLabel.lineBreakMode = NSLineBreakByWordWrapping;
        if (indexPath.section == kProfiles) {
            cell.imageView.frame = CGRectMake(0, 0, 40, 40);
            cell.imageView.isSizeFixed = YES;
        }
    } else {
        cell.imageView.image = nil;
        cell.userInteractionEnabled = YES;
        cell.accessoryView = nil;
    }

    if (indexPath.section == kInstances) {
        [self setupInstanceCell:cell atRow:indexPath.row];
    } else {
        [self setupProfileCell:cell atRow:indexPath.row];
    }

    cell.textLabel.enabled = cell.detailTextLabel.enabled = cell.userInteractionEnabled;
    return cell;
}

- (void)tableView:(UITableView *)tableView didSelectRowAtIndexPath:(NSIndexPath *)indexPath {
    [tableView deselectRowAtIndexPath:indexPath animated:NO];

    if (indexPath.section == kInstances) {
        if (indexPath.row == 0) {
            [self.navigationController pushViewController:[LauncherPrefGameDirViewController new] animated:YES];
        }
        return;
    }

    [self actionEditProfile:PLProfiles.current.profiles.allValues[indexPath.row]];
}

#pragma mark Context Menu configuration

- (void)tableView:(UITableView *)tableView commitEditingStyle:(UITableViewCellEditingStyle)editingStyle forRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (editingStyle != UITableViewCellEditingStyleDelete) return;

    UITableViewCell *cell = [self.tableView cellForRowAtIndexPath:indexPath];
    NSString *title = localize(@"preference.title.confirm", nil);
    // reusing the delete runtime message
    NSString *message = [NSString stringWithFormat:localize(@"preference.title.confirm.delete_runtime", nil), cell.textLabel.text];
    UIAlertController *confirmAlert = [UIAlertController alertControllerWithTitle:title message:message preferredStyle:UIAlertControllerStyleActionSheet];
    confirmAlert.popoverPresentationController.sourceView = cell;
    confirmAlert.popoverPresentationController.sourceRect = cell.bounds;
    UIAlertAction *ok = [UIAlertAction actionWithTitle:localize(@"OK", nil) style:UIAlertActionStyleDestructive handler:^(UIAlertAction * _Nonnull action) {
        [PLProfiles.current.profiles removeObjectForKey:cell.textLabel.text];
        if ([PLProfiles.current.selectedProfileName isEqualToString:cell.textLabel.text]) {
            // The one being deleted is the selected one, switch to the random one now
            PLProfiles.current.selectedProfileName = PLProfiles.current.profiles.allKeys[0];
            [self.navigationController performSelector:@selector(reloadProfileList)];
        } else {
            [PLProfiles.current save];
        }
        [tableView deleteRowsAtIndexPaths:@[indexPath] withRowAnimation:UITableViewRowAnimationAutomatic];
    }];
    UIAlertAction *cancel = [UIAlertAction actionWithTitle:localize(@"Cancel", nil) style:UIAlertActionStyleCancel handler:nil];
    [confirmAlert addAction:cancel];
    [confirmAlert addAction:ok];
    [self presentViewController:confirmAlert animated:YES completion:nil];
}

- (UITableViewCellEditingStyle)tableView:(UITableView *)tableView editingStyleForRowAtIndexPath:(NSIndexPath *)indexPath
{
    if (indexPath.section == kInstances || PLProfiles.current.profiles.count==1) {
        return UITableViewCellEditingStyleNone;
    }
    return UITableViewCellEditingStyleDelete;
}

#endif

@end
