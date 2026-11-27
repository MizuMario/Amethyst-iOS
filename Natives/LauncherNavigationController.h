#import <UIKit/UIKit.h>

NSMutableArray<NSDictionary *> *localVersionList, *remoteVersionList;

@interface LauncherNavigationController : UINavigationController

@property(nonatomic) UIProgressView *progressViewMain, *progressViewSub;
@property(nonatomic) UILabel* progressText;

- (NSDictionary *)launcherDownloadSnapshot;
- (void)requestLauncherJIT;
- (void)enterCustomControls;
- (void)enterModInstaller;
- (void)enterModInstallerWithPath:(NSString *)path hitEnterAfterWindowShown:(BOOL)hitEnter;
- (void)fetchLocalVersionList;
- (void)reloadProfileList;
- (void)selectProfile:(NSString *)key launch:(BOOL)launch;
- (void)setInteractionEnabled:(BOOL)enable forDownloading:(BOOL)downloading;

@end
