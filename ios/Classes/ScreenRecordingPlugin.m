#import "ScreenRecordingPlugin.h"
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>

API_AVAILABLE(ios(10.0))
@interface ScreenRecordingPlugin ()<RPBroadcastActivityViewControllerDelegate,RPBroadcastControllerDelegate>
@property RPBroadcastController *broadcastController;
@property NSTimer *timer;
@property UIView *view;
@property (nonatomic, strong) RPSystemBroadcastPickerView *broadcastPickerView API_AVAILABLE(ios(12.0));
@property(nonatomic,strong)NSURL* fileURL;
@property NSString *extensionBundleId;
@property NSString *groupId;
@property NSString *targetFileName;
@property BOOL isInited;
@end

static NSString * const ScreenHoleNotificationName = @"ScreenHoleNotificationName";
void MyHoleNotificationCallback(CFNotificationCenterRef center,
                                   void * observer,
                                   CFStringRef name,
                                   void const * object,
                                   CFDictionaryRef userInfo) {
    NSString *identifier = (__bridge NSString *)name;
    NSObject *sender = (__bridge NSObject *)observer;
    //NSDictionary *info = (__bridge NSDictionary *)userInfo;
    NSDictionary *info = CFBridgingRelease(userInfo);

    NSDictionary *notiUserInfo = @{@"identifier":identifier};
    [[NSNotificationCenter defaultCenter] postNotificationName:ScreenHoleNotificationName
                                                        object:sender
                                                      userInfo:notiUserInfo];
}

@implementation ScreenRecordingPlugin
+ (void)registerWithRegistrar:(NSObject<FlutterPluginRegistrar>*)registrar {
  FlutterMethodChannel* channel = [FlutterMethodChannel
      methodChannelWithName:@"screen_recording"
            binaryMessenger:[registrar messenger]];
  ScreenRecordingPlugin* instance = [[ScreenRecordingPlugin alloc] init];
  [registrar addMethodCallDelegate:instance channel:channel];
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
  if ([@"getPlatformVersion" isEqualToString:call.method]) {
      result([@"iOS " stringByAppendingString:[[UIDevice currentDevice] systemVersion]]);
    } else if ([@"startRecordScreen" isEqualToString:call.method]) {
      if(self.isInited){
        NSLog(@"has inited");
      }else{
        [self initParam];
        self.isInited = YES;
      }
      [self startRecorScreen:call];
    } else if ([@"stopRecordScreen" isEqualToString:call.method]) {
      result(@"FDK");
    }else {
      result(FlutterMethodNotImplemented);
    }
}

- (void)initParam{
    //获取主view
    UIViewController* viewController = [UIApplication sharedApplication].keyWindow.rootViewController;
    self.view = viewController.view;

    NSString *bundleId = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleIdentifier"];
    self.extensionBundleId = [bundleId stringByAppendingString:@".screencap"];
    self.groupId = [@"group." stringByAppendingString:bundleId];

    //共享文件名字

    NSURL *groupURL = [[NSFileManager defaultManager] containerURLForSecurityApplicationGroupIdentifier:self.groupId];
    self.fileURL = [groupURL URLByAppendingPathComponent:@"test.mp4"];

    self.broadcastPickerView = [[RPSystemBroadcastPickerView alloc] initWithFrame:(CGRect){0, 0, 100, 100}];
    if(@available(iOS 12.2, *)) {
      self.broadcastPickerView.preferredExtension = self.extensionBundleId;
    }
    [self.view addSubview:_broadcastPickerView];
    self.broadcastPickerView.hidden = YES;
    self.broadcastPickerView.showsMicrophoneButton = YES;

    [self addUploaderEventMonitor];

    NSLog(@"init success");
}

- (void)startRecorScreen:(FlutterMethodCall*)call {
    self.targetFileName = call.arguments[@"name"];
    NSLog(@"targetFileName:%@",self.targetFileName);
    if (@available(iOS 12.0, *)) {

      for (UIView *view in self.broadcastPickerView.subviews) {
          if ([view isKindOfClass:[UIButton class]]) {
              if (@available(iOS 13, *)) {
                  [(UIButton *)view sendActionsForControlEvents:UIControlEventTouchUpInside];
              } else {
                  [(UIButton *)view sendActionsForControlEvents:UIControlEventTouchDown];
              }
          }
      }
    } else {
        // Fallback on earlier versions
    }

}
#pragma mark - 接收来自extension的消息
- (void)addUploaderEventMonitor {
    [self registerForNotificationsWithIdentifier:@"broadcastStarted"];
    [self registerForNotificationsWithIdentifier:@"broadcastFinished"];
    [[NSNotificationCenter defaultCenter] addObserver:self selector:@selector(broadcastInfo:) name:ScreenHoleNotificationName object:nil];
}

- (void)broadcastInfo:(NSNotification *)noti {

    NSDictionary *userInfo = noti.userInfo;
    NSString *identifier = userInfo[@"identifier"];
    FlutterViewController *controller = (FlutterViewController*)[UIApplication sharedApplication].keyWindow.rootViewController;
    FlutterMethodChannel *methodChannel = [FlutterMethodChannel methodChannelWithName:@"screen_recording"
                                                                      binaryMessenger: controller.binaryMessenger];

    if ([identifier isEqualToString:@"broadcastStarted"]) {
        NSLog(@"开始录屏");
        [methodChannel invokeMethod:@"start" arguments:nil];
    }
    if ([identifier isEqualToString:@"broadcastFinished"]) {
        NSLog(@"结束录屏");
        //reload数据
        NSData* data = [[NSFileManager defaultManager] contentsAtPath:[self.fileURL path]];
        NSLog(@"%@", self.targetFileName);
        [data writeToURL:[NSURL fileURLWithPath:self.targetFileName] atomically:NO];
        NSLog(@"获取的总长度%lu",data.length);

        [methodChannel invokeMethod:@"end" arguments:nil];


    }
}

#pragma mark - 移除Observer
- (void)removeUploaderEventMonitor {

    [self unregisterForNotificationsWithIdentifier:@"broadcastFinished"];
    [[NSNotificationCenter defaultCenter] removeObserver:self name:ScreenHoleNotificationName object:nil];

}
#pragma mark - 宿主与extension之间的通知
- (void)registerForNotificationsWithIdentifier:(nullable NSString *)identifier {
    [self unregisterForNotificationsWithIdentifier:identifier];
    CFNotificationCenterRef const center = CFNotificationCenterGetDarwinNotifyCenter();
    CFStringRef str = (__bridge CFStringRef)identifier;
    NSLog(@"identifier:%@",str);
    CFNotificationCenterAddObserver(center,
                                    (__bridge const void *)(self),
                                    MyHoleNotificationCallback,
                                    str,
                                    NULL,
                                    CFNotificationSuspensionBehaviorDeliverImmediately);
}

- (void)unregisterForNotificationsWithIdentifier:(nullable NSString *)identifier {
    CFNotificationCenterRef const center = CFNotificationCenterGetDarwinNotifyCenter();
    CFStringRef str = (__bridge CFStringRef)identifier;
    CFNotificationCenterRemoveObserver(center,
                                       (__bridge const void *)(self),
                                       str,
                                       NULL);
}
@end
