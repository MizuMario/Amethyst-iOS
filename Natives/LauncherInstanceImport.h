#import <Foundation/Foundation.h>

@interface LauncherInstanceImport : NSObject
+ (NSDictionary *)prepareArchive:(NSURL *)url error:(NSError **)error;
@end
