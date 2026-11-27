#import <UIKit/UIKit.h>

#define sidebarNavController ((UINavigationController *)self.splitViewController.viewControllers[0])
#define sidebarViewController ((LauncherMenuViewController *)sidebarNavController.viewControllers[0])

@interface LauncherMenuCustomItem : NSObject
@property(nonatomic) NSString *title, *imageName;
@property(nonatomic, copy) void (^action)(void);
@property(nonatomic) NSArray<UIViewController *> *vcArray;
@end

@interface LauncherMenuViewController : UITableViewController

@property NSString* listPath;
@property(nonatomic) UIButton *accountButton;
@property(nonatomic) UIBarButtonItem *accountBtnItem;
@property(nonatomic) BOOL isInitialVc;

- (void)restoreHighlightedSelection;
- (void)selectAccount:(UIButton *)sender;
- (void)selectAccountFrom:(UIViewController *)presenter anchor:(UIView *)anchor completion:(void (^)(void))completion;
- (void)selectAccountFrom:(UIViewController *)presenter anchor:(UIView *)anchor sourceRect:(CGRect)rect
              completion:(void (^)(void))completion;
- (void)updateAccountInfo;
- (UIBarButtonItem *)drawAccountButton;

@end
