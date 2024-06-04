#import "ScreenRecordingPlugin.h"
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CommonCrypto/CommonDigest.h>

API_AVAILABLE(ios(10.0))
@interface ScreenRecordingPlugin ()<RPBroadcastActivityViewControllerDelegate,RPBroadcastControllerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, UIDocumentPickerDelegate>
@property RPBroadcastController *broadcastController;
@property NSTimer *timer;
@property UIView *view;
@property (nonatomic, strong) RPSystemBroadcastPickerView *broadcastPickerView API_AVAILABLE(ios(12.0));
@property(nonatomic,strong)NSURL* fileURL;
@property NSString *extensionBundleId;
@property NSString *groupId;
@property NSString *targetFileName;
@property (nonatomic, strong) FlutterEventSink eventSink;
@property BOOL isInited;
@property (nonatomic, assign) BOOL isRecording;
@property (nonatomic, copy) FlutterResult result;
// 视频的帧率
@property (nonatomic, strong) NSNumber *frameRate;
@property (nonatomic, strong) NSNumber *bitRate;
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
    
    FlutterEventChannel* eventChannel = [FlutterEventChannel eventChannelWithName:@"screen_recording_stream" binaryMessenger:[registrar messenger]];
    [eventChannel setStreamHandler:instance];
}

- (instancetype)init {
    self = [super init];
    if (self) {
        self.isRecording = NO;
    }
    return self;
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    self.result = result;
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
        [self stopRecordScreen];
    }else if ([@"chooseSavePath" isEqualToString:call.method]) {
        [self chooseSavePathWithResult:result];
    }else if ([@"queryMd5" isEqualToString:call.method]) {
        [self queryMd5: call];
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
    
    if (@available(iOS 12.0, *)) {
        self.broadcastPickerView = [[RPSystemBroadcastPickerView alloc] initWithFrame:(CGRect){0, 0, 100, 100}];
    } else {
        // Fallback on earlier versions
    }
    if(@available(iOS 12.2, *)) {
        self.broadcastPickerView.preferredExtension = self.extensionBundleId;
    }
    [self.view addSubview:_broadcastPickerView];
    if (@available(iOS 12.0, *)) {
        self.broadcastPickerView.hidden = YES;
    } else {
        // Fallback on earlier versions
    }
    if (@available(iOS 12.0, *)) {
        self.broadcastPickerView.showsMicrophoneButton = YES;
    } else {
        // Fallback on earlier versions
    }
    
    [self addUploaderEventMonitor];
    
    NSLog(@"init success");
}

- (void)chooseSavePathWithResult:(FlutterResult)result {
    if (@available(iOS 14.0, *)) {
        UIDocumentPickerViewController *documentPicker = [[UIDocumentPickerViewController alloc] initForOpeningContentTypes:@[UTTypeFolder]];
        documentPicker.delegate = self;
        documentPicker.directoryURL = [NSURL URLWithString:[NSHomeDirectory() stringByAppendingPathComponent:@"Documents"]];
        documentPicker.modalPresentationStyle = UIModalPresentationFormSheet;
        
        UIViewController *rootViewController = [UIApplication sharedApplication].keyWindow.rootViewController;
        [rootViewController presentViewController:documentPicker animated:YES completion:nil];
        
        self.result = result;
    } else {
        NSLog(@"选择文件夹在此 iOS 版本不可用。");
        //        result(FlutterError(code: "UNAVAILABLE", message: "Choosing folder is unavailable on this iOS version.", details: nil));
    }
}

- (NSString *)queryMd5:(FlutterMethodCall *)call {
    NSString *path = call.arguments[@"path"];
    NSData *videoData = [NSData dataWithContentsOfFile:path];
    return [self MD5ForData:videoData];
}

# pragma mark - 用户选择完文件夹地址后，回传给flutter
- (void)documentPicker:(UIDocumentPickerViewController *)controller didPickDocumentsAtURLs:(NSArray<NSURL *> *)urls {
    NSURL *pickedURL = [urls firstObject];
    self.result([pickedURL path]);
}

# pragma mark - 生成md5
- (NSString *)MD5ForData:(NSData *)data {
    unsigned char result[CC_MD5_DIGEST_LENGTH];
    CC_MD5(data.bytes, (CC_LONG)data.length, result);
    NSMutableString *hash = [NSMutableString stringWithCapacity:CC_MD5_DIGEST_LENGTH * 2];
    for (int i = 0; i < CC_MD5_DIGEST_LENGTH; i++) {
        [hash appendFormat:@"%02x", result[i]];
    }
    return hash;
}


- (void)startRecorScreen:(FlutterMethodCall*)call {
    // 这个path就是自定义保存路径的参数
    self.targetFileName = call.arguments[@"path"];
    NSLog(@"targetFileName:%@",self.targetFileName);
    // 获取帧率参数，默认值为 25
    self.frameRate = call.arguments[@"frameRate"] ?: @(25);
    NSLog(@"帧率：%@", self.frameRate);
    
    // 获取码率参数，默认值为 7500000
    self.bitRate = call.arguments[@"bitRate"] ?: @(7500000);
    NSLog(@"码率：%@", self.bitRate);
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
    [self startFetchingSharedContainerData];
}

- (void)startFetchingSharedContainerData {
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0
                                                  target:self
                                                selector:@selector(fetchSharedContainerData)
                                                userInfo:nil
                                                 repeats:YES];
}

- (void)fetchSharedContainerData {
    NSUserDefaults *userDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"group.com.recordscreen.app"];
    NSData *videoData = [userDefaults objectForKey:@"videoData"];
    if (videoData) {
        // Process the video data and send it to Flutter
        if (self.eventSink) {
            self.eventSink([videoData base64EncodedStringWithOptions:0]);
        }
    }
}

// 处理视频帧并生成MD5
- (void)captureOutput:(AVCaptureOutput *)output didOutputSampleBuffer:(CMSampleBufferRef)sampleBuffer fromConnection:(AVCaptureConnection *)connection {
    if (self.eventSink) {
        NSData *videoData = [self processSampleBuffer:sampleBuffer];
        self.eventSink([videoData base64EncodedStringWithOptions:0]);
        // 生成 MD5 码
        NSString *md5 = [self MD5ForData:videoData];
        NSLog(@"MD5: %@", md5);
    }
}

- (NSData *)processSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    // Convert sample buffer to NSData
    // This is just a placeholder implementation
    return [NSData data];
}

- (void)saveVideoWithUrl:(NSURL *)url {
    PHPhotoLibrary *photoLibrary = [PHPhotoLibrary sharedPhotoLibrary];
    [photoLibrary performChanges:^{
        [PHAssetChangeRequest creationRequestForAssetFromVideoAtFileURL:url];
        
    } completionHandler:^(BOOL success, NSError * _Nullable error) {
        if (success) {
            NSLog(@"已将视频保存至相册");
        } else {
            NSLog(@"未能保存视频到相册");
        }
    }];
}

// 想要停止系统录屏，您需要使用特定的API来执行此操作。在iOS中，系统录屏是由用户手动启动并控制的，因此您无法直接停止系统录屏，而只能提供给用户一个停止录屏的选项。您可以通过调用系统提供的停止录屏的接口来实现这一点。
// 在录制完成时，生成视频文件的 MD5 码，并将它与视频路径一起返回
- (void)stopRecordScreen {
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
    }
    [self.timer invalidate];
    self.timer = nil;
    NSLog(@"Stopped fetching shared container data");
    // 读取视频文件数据并生成 MD5 码
    NSData *videoData = [NSData dataWithContentsOfURL:self.fileURL];
    NSString *md5 = [self MD5ForData:videoData];
    NSLog(@"视频文件 MD5: %@", md5);
    if (self.targetFileName) {
        NSData *data = [[NSFileManager defaultManager] contentsAtPath:[self.fileURL path]];
        [data writeToFile:self.targetFileName atomically:YES];
        NSLog(@"Video saved to custom path: %@", self.targetFileName);
    } else {
        [self saveVideoWithUrl:self.fileURL];
    }
    // 处理视频数据，设置帧率和码率等参数
    NSData *processedVideoData = [self processVideoData:[NSData dataWithContentsOfURL:self.fileURL]];
    
    // 将处理后的视频数据写入临时文件
    NSString *tempFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"processedVideo.mp4"];
    [processedVideoData writeToFile:tempFilePath atomically:YES];
    // 将视频路径和 MD5 码一起返回给 Flutter
    if (self.result) {
        self.result(@{@"path": tempFilePath, @"md5": md5});
        self.result = nil;
    }
}

# pragma mark - 对视频进行处理，设置帧率码率，再回传给flutter
- (NSData *)processVideoData:(NSData *)videoData {
    AVAsset *asset = [AVAsset assetWithURL:self.fileURL];
    AVAssetTrack *videoTrack = [[asset tracksWithMediaType:AVMediaTypeVideo] firstObject];
    
    // 设置视频属性
    AVMutableComposition *composition = [AVMutableComposition composition];
    AVMutableCompositionTrack *compositionVideoTrack = [composition addMutableTrackWithMediaType:AVMediaTypeVideo preferredTrackID:kCMPersistentTrackID_Invalid];
    NSError *error = nil;
    BOOL success = [compositionVideoTrack insertTimeRange:CMTimeRangeMake(kCMTimeZero, asset.duration)
                                                  ofTrack:videoTrack
                                                   atTime:kCMTimeZero
                                                    error:&error];
    if (!success) {
        NSLog(@"Error inserting video track: %@", error);
        return nil;
    }
    
    // 设置视频的帧率和码率等参数
    NSDictionary *videoCompressionProperties = @{
        AVVideoAverageBitRateKey: self.bitRate, // 码率
        AVVideoExpectedSourceFrameRateKey: self.frameRate // 帧率
    };
    
    NSDictionary *videoSettings = @{
        AVVideoCompressionPropertiesKey: videoCompressionProperties
    };
    
    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:composition
                                                                           presetName:AVAssetExportPresetPassthrough];
    exportSession.outputFileType = AVFileTypeMPEG4;
    NSString *processedFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"processedVideo.mp4"];
    exportSession.outputURL = [NSURL fileURLWithPath:processedFilePath];
    exportSession.videoComposition = videoSettings;
    
    dispatch_semaphore_t semaphore = dispatch_semaphore_create(0);
    [exportSession exportAsynchronouslyWithCompletionHandler:^{
        dispatch_semaphore_signal(semaphore);
    }];
    
    dispatch_semaphore_wait(semaphore, DISPATCH_TIME_FOREVER);
    
    if (exportSession.status == AVAssetExportSessionStatusCompleted) {
        NSData *processedVideoData = [NSData dataWithContentsOfFile:processedFilePath];
        return processedVideoData;
    } else {
        NSLog(@"Video processing failed with error: %@", exportSession.error);
        return nil;
    }
}

#pragma mark - FlutterStreamHandler

- (FlutterError* _Nullable)onListenWithArguments:(id _Nullable)arguments eventSink:(FlutterEventSink)events {
    self.eventSink = events;
    return nil;
}

- (FlutterError* _Nullable)onCancelWithArguments:(id _Nullable)arguments {
    self.eventSink = nil;
    return nil;
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
