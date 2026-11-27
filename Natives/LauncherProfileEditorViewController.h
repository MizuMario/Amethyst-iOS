#import <UIKit/UIKit.h>
#import "PLPrefTableViewController.h"

extern NSString * const LauncherProfilesDidSaveNotification;

@interface LauncherProfileEditorViewController : PLPrefTableViewController
@property(nonatomic) NSMutableDictionary* profile;
@end
