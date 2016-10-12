#import <Foundation/Foundation.h>

#import "OnDemandManager.h"
#import "LZMAExtractor.h"
#import <AVFoundation/AVFoundation.h>
#import <AVKit/AVKit.h>

// TODO: calculate size from the archive.
static const unsigned long long _requiredFreeSpaceToUnpack = 640LL * 1024 * 1024;
#if TARGET_OS_IOS
// Can be disabled for debug purposes.
static const BOOL _enableUnpackedResourcesCheck = YES;
#endif

@interface OnDemandViewController: UIViewController

@property (nonatomic, strong) UIImageView* backgroundImageView;
@property (nonatomic, strong) UIActivityIndicatorView* spinner;
@property (nonatomic, strong) UILabel* label;
@property (nonatomic, strong) UIButton* button;
@property (nonatomic, strong) void (^buttonHandler)();

@end

@implementation OnDemandViewController

- (void)viewDidLoad
{
    [super viewDidLoad];
#if TARGET_OS_IOS
    UIImage* backgroundImage = [[UIImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"LaunchScreen-iPad" ofType:@".png"]];
#elif TARGET_OS_TV
    UIImage* backgroundImage = [[UIImage alloc] initWithContentsOfFile:[[NSBundle mainBundle] pathForResource:@"Default" ofType:@".png"]];
#endif
    self.view.backgroundColor = [UIColor colorWithRed:0.6f green:0.6f blue:0.6f alpha:1.0f];
    self.backgroundImageView = [[UIImageView alloc] initWithImage:backgroundImage highlightedImage:nil];
    self.backgroundImageView.frame = self.view.frame;
    self.backgroundImageView.contentMode = UIViewContentModeScaleAspectFill;
    [self.view addSubview:self.backgroundImageView];
    
    self.spinner = [[UIActivityIndicatorView alloc] initWithFrame:self.view.frame];
    self.spinner.color = [UIColor colorWithRed:0.3f green:0.3f blue:0.3f alpha:1.0f];
    self.spinner.transform = CGAffineTransformMakeScale(2.0f, 2.0f);
    [self.spinner startAnimating];
    [self.view addSubview:self.spinner];
    
    CGRect labelFrame = self.view.frame;
    labelFrame.origin.y += labelFrame.size.height/4;
    labelFrame.size.height -= 100.0f;//?
    
    self.label = [[UILabel alloc] initWithFrame:labelFrame];
    self.label.text = NSLocalizedString(@"wait", nil);
    self.label.textAlignment = NSTextAlignmentCenter;
    self.label.textColor = [UIColor colorWithRed:0.6f green:0.6f blue:0.6f alpha:1.0f];
    self.label.font = [self.label.font fontWithSize:28.0f];
    [self.view addSubview:self.label];
    
}

- (void)showButtonWithText:(NSString*)text handler:(void (^)())handler
{
    if (!self.button)
    {
        self.button = [UIButton buttonWithType:UIButtonTypeRoundedRect];
        [self.button setBackgroundColor:[UIColor colorWithRed:0.6f green:0.6f blue:0.6f alpha:1.0f]];
        self.button.layer.cornerRadius = 10.0f;
        self.button.clipsToBounds = YES;
        [self.button addTarget:self action:@selector(onButtonPressed) forControlEvents:UIControlEventTouchUpInside];
        self.button.titleLabel.font = [self.button.titleLabel.font fontWithSize:32.0f];
        self.button.titleLabel.textColor = [UIColor colorWithRed:1.0f green:1.0f blue:1.0f alpha:1.0f];
        [self.button setTitle:text forState:UIControlStateNormal];
        [self.button sizeToFit];
        self.button.center = CGPointMake(self.view.frame.size.width * 0.5f, self.view.frame.size.height * 0.5f);
        [self.view addSubview:self.button];
    }
    else
    {
        [self.button setTitle:text forState:UIControlStateNormal];
    }
    
    self.buttonHandler = handler;
}

- (void)hideButton
{
    if (self.button)
    {
        self.buttonHandler = nil;
        [self.button removeFromSuperview];
        [self.button removeTarget:self action:@selector(onButtonPressed) forControlEvents:UIControlEventTouchUpInside];
        self.button = nil;
    }
}

- (void)onButtonPressed
{
    if (self.buttonHandler)
    {
        self.buttonHandler();
    }
}

- (void)stopProgress
{
    [self.spinner stopAnimating];
}

- (void)resumeProgress
{
    [self.spinner startAnimating];
}

@end

@implementation OnDemandManager
{
    void(^_handler)();
    UIWindow* _window;
    OnDemandViewController* _viewController;
    NSBundleResourceRequest* _resourceRequest;
}

- (void)dealloc
{
    [_resourceRequest endAccessingResources];
    [_window.rootViewController dismissViewControllerAnimated:YES completion:nil];
}

- (void)createView
{
    _window = [[UIWindow alloc] initWithFrame:[UIScreen mainScreen].bounds];
    _window.backgroundColor = [UIColor whiteColor];
    _viewController = [[OnDemandViewController alloc] init];
    _window.rootViewController = _viewController;
    [_window makeKeyAndVisible];
}

- (void)reportErrorInView:(NSString*)errorText buttonText:(NSString*)buttonText buttonHandler:(void (^)())buttonHandler
{
    dispatch_async(dispatch_get_main_queue(), ^{
        
        _viewController.label.textColor = [UIColor redColor];
        _viewController.label.text = errorText;
        [_viewController stopProgress];
        if (buttonText)
        {
            [_viewController showButtonWithText:buttonText handler:buttonHandler];
        }
    });
}

- (void)startWithHandler:(void(^)())handler
{
    _handler = handler;
    if (/*_enableUnpackedResourcesCheck &&*/ [self checkResourcesUnpacked])
    {
        [self finish];
        return;
    }
    
    [self createView];
    
    NSSet* resourceTags = [NSSet setWithObjects:@"Main", nil];
    _resourceRequest = [[NSBundleResourceRequest alloc] initWithTags:resourceTags];
    [_resourceRequest conditionallyBeginAccessingResourcesWithCompletionHandler:^(BOOL resourcesAvailable) {
        if (!resourcesAvailable)
        {
            [self downloadResources];
        }
        else
        {
            [self unpackResources];
        }
    }];
}
- (BOOL)checkResourcesUnpacked
{
    //NSLog(@"%@", [OnDemandManager getDocumentsPath]);
    
    NSString* dir = [OnDemandManager getDocumentsPath];
    //NSString* appVersion = [OnDemandManager getAppVersion];
    NSString* resourcesVersionFilePath = [OnDemandManager getResourcesVersionFilePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:resourcesVersionFilePath])
    {
        
        //NSLog(@"Resource: %@", resourcesVersionFilePath);
        NSFileHandle *fileHandle = [NSFileHandle fileHandleForReadingAtPath:resourcesVersionFilePath];
        NSData* data = [fileHandle readDataToEndOfFile];
        [fileHandle closeFile];
        
        NSString* content = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
        NSArray* paths = [content componentsSeparatedByString:@"\n"];
        
        for (NSString* path in paths) {
            
            if (![[NSFileManager defaultManager] fileExistsAtPath:[dir stringByAppendingString:path]]) {
                
                NSLog(@"File not found: %@", [dir stringByAppendingString:path]);
                return NO;
                
            }
            
        }
        
    } else {
        
        return NO;
        
    }
    
    return YES;
}

- (void)setResourcesUnpacked:(NSArray*)extractedFiles
{
    NSString* dir = [OnDemandManager getDocumentsPath];
    //NSString* appVersion = [OnDemandManager getAppVersion];
    NSString* resourcesVersionFilePath = [OnDemandManager getResourcesVersionFilePath];
    if ([[NSFileManager defaultManager] fileExistsAtPath:resourcesVersionFilePath])
    {
        [[NSFileManager defaultManager] removeItemAtPath:resourcesVersionFilePath error:nil];
    }
    
    [[NSFileManager defaultManager] createFileAtPath:resourcesVersionFilePath contents:nil attributes:nil];
    
    NSFileHandle *fileHandle = [NSFileHandle fileHandleForWritingAtPath:resourcesVersionFilePath];
    [fileHandle seekToEndOfFile];
    int i = 1;
    for (NSString* str in extractedFiles) {
        [fileHandle writeData:[[[str componentsSeparatedByString: dir] objectAtIndex:1] dataUsingEncoding:NSUTF8StringEncoding]];
        if (i < [extractedFiles count]) [fileHandle writeData:[@"\n" dataUsingEncoding:NSUTF8StringEncoding]];
        ++i;
    }
    [fileHandle closeFile];
}

- (void)downloadResources
{
    dispatch_async(dispatch_get_main_queue(), ^{
        _viewController.label.text = NSLocalizedString(@"downloading", nil);
        _viewController.label.textColor = [UIColor colorWithRed:0.3f green:0.3f blue:0.3f alpha:1.0f];
    });
    
    [_resourceRequest beginAccessingResourcesWithCompletionHandler:^(NSError* _Nullable error) {
        if (error)
        {
            [self reportErrorInView:NSLocalizedString(@"download_failed", nil) buttonText:NSLocalizedString(@"retry", nil) buttonHandler:^{
                [_viewController hideButton];
                [_viewController resumeProgress];
                [self downloadResources];
            }];
            return;
        }
        [self unpackResources];
    }];
}

- (void)unpackResources
{
    dispatch_async(dispatch_get_main_queue(), ^{
        _viewController.label.text = NSLocalizedString(@"unpacking", nil);
        _viewController.label.textColor = [UIColor colorWithRed:0.3f green:0.3f blue:0.3f alpha:1.0f];
    });
    
    NSBundle* bundle = _resourceRequest.bundle;
    NSString* archivePath = [bundle pathForResource:@"Data" ofType:@".7z"];
    NSString* documentsPath = [OnDemandManager getDocumentsPath];
    NSString* documetsDataPath = [documentsPath stringByAppendingString:@"/Data"];
    
    [[NSFileManager defaultManager] removeItemAtPath:documetsDataPath error:nil];
    
    unsigned long long freeSpace = [OnDemandManager getFreeSpace];
    if (freeSpace < _requiredFreeSpaceToUnpack)
    {
        long long int req = ceil((_requiredFreeSpaceToUnpack - freeSpace)/(1024*1024)) + 50;
        [self reportErrorInView:[NSString stringWithFormat:NSLocalizedString(@"no_space", nil), req] buttonText:NSLocalizedString(@"retry", nil) buttonHandler:^{
            [_viewController hideButton];
            [_viewController resumeProgress];
            [self unpackResources];
        }];
        return;
    }
    
    NSLog(@"DOC DIR: %@", documetsDataPath);
    
    NSArray* extractedFiles = [LZMAExtractor extract7zArchive:archivePath dirName:documetsDataPath preserveDir:YES];
    if ([extractedFiles count] == 0)
    {
        [self reportErrorInView:NSLocalizedString(@"unpack_failed", nil) buttonText:NSLocalizedString(@"retry", nil) buttonHandler:^{
            [_viewController hideButton];
            [self unpackResources];
        }];
        return;
    }
    
    [self setResourcesUnpacked: extractedFiles];
    [self finish];
}

- (void)finish
{
    dispatch_async(dispatch_get_main_queue(), _handler);
}

+ (void)startWithCompletionHandler:(void(^)())handler
{
    __block OnDemandManager* manager = [[OnDemandManager alloc] init];
    [manager startWithHandler:^{
        manager = nil;
        handler();
    }];
}

+ (NSString*)getAppVersion
{
    return [[[NSBundle mainBundle] infoDictionary] objectForKey:@"CFBundleVersion"];
}

+ (NSString*)getDocumentsPath
{
#if TARGET_OS_IOS
    return NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES)[0];
#elif TARGET_OS_TV
    return [NSSearchPathForDirectoriesInDomains(NSCachesDirectory, NSUserDomainMask, YES) lastObject];
    //return NSTemporaryDirectory(); //returns nil :(
#endif
}

+ (NSString*)getResourcesVersionFilePath
{
    NSString* documentsPath = [OnDemandManager getDocumentsPath];
    NSString* file = [NSString stringWithFormat:@"/resources_%@_version.txt", [OnDemandManager getAppVersion]];
    NSString* resourcesVersionFilePath = [documentsPath stringByAppendingString:file];
    return resourcesVersionFilePath;
}

+ (NSUInteger)getFreeSpace
{
    NSString* documentsPath = [OnDemandManager getDocumentsPath];
    NSDictionary* dict = [[NSFileManager defaultManager] attributesOfFileSystemForPath:documentsPath error:nil];
    unsigned long long freeSpace = [[dict objectForKey:NSFileSystemFreeSize] unsignedLongLongValue];
    return freeSpace;
}

@end
