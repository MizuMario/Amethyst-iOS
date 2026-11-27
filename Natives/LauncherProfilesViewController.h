#import <UIKit/UIKit.h>

#if AMETHYST_SWIFT_PROFILE_UI
@interface LauncherProfilesViewController : UIViewController
#else
@interface LauncherProfilesViewController : UITableViewController
#endif

@end

