#import "ScreenRecordingPlugin.h"
#import <AVKit/AVKit.h>
#import <AVFoundation/AVFoundation.h>
#import <Photos/Photos.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#import <CommonCrypto/CommonDigest.h>

API_AVAILABLE(ios(10.0))
@interface ScreenRecordingPlugin ()<RPBroadcastActivityViewControllerDelegate,RPBroadcastControllerDelegate, AVCaptureVideoDataOutputSampleBufferDelegate, UIDocumentPickerDelegate, PHPhotoLibraryChangeObserver>
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
@property (nonatomic, copy) FlutterResult resultStart;
@property (nonatomic, copy) FlutterResult resultStop;
// 视频的帧率
@property (nonatomic, strong) NSNumber *frameRate;
@property (nonatomic, strong) NSNumber *bitRate;
@property (nonatomic, assign) BOOL isRecordingStopped;
@property (nonatomic, strong) PHFetchResult<PHAsset *> *previousFetchResult;
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
        [[NSNotificationCenter defaultCenter] addObserver:self
                                                 selector:@selector(screenRecordingChanged:)
                                                     name:UIScreenCapturedDidChangeNotification
                                                   object:nil];
    }
    return self;
}

- (void)dealloc {
    [[NSNotificationCenter defaultCenter] removeObserver:self];
}

- (void)screenRecordingChanged:(NSNotification *)notification {
    if ([UIScreen mainScreen].isCaptured) {
        NSLog(@"检测到屏幕录制开启");
        self.resultStart(@YES);
    } else {
        NSLog(@"检测到屏幕录制关闭");
        self.resultStart(@NO);
    }
}

- (void)handleMethodCall:(FlutterMethodCall*)call result:(FlutterResult)result {
    if ([@"getPlatformVersion" isEqualToString:call.method]) {
        result([@"iOS " stringByAppendingString:[[UIDevice currentDevice] systemVersion]]);
    } else if ([@"startRecordScreen" isEqualToString:call.method]) {
        self.resultStart = result;
        if(self.isInited){
            NSLog(@"has inited");
        }else{
            [self initParam];
            self.isInited = YES;
        }
        [self startRecorScreen:call];
    } else if ([@"stopRecordScreen" isEqualToString:call.method]) {
        self.resultStop = result;
        [self stopRecordScreen];
    }else if ([@"chooseSavePath" isEqualToString:call.method]) {
        [self chooseSavePathWithResult:result];
    }else if ([@"queryMd5" isEqualToString:call.method]) {
        NSString *md5 = [self queryMd5: call];
        result(md5);
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
    // 申请相册权限以及初始化
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status != PHAuthorizationStatusAuthorized) {
            return;
        }
        PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
        fetchOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
        fetchOptions.fetchLimit = 1;
        
        self.previousFetchResult = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeVideo options:fetchOptions];
    }];
    [[PHPhotoLibrary sharedPhotoLibrary] registerChangeObserver:self];
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
    self.isRecordingStopped = NO;
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
    if ([UIScreen mainScreen].isCaptured) {
        NSLog(@"正在录屏");
    }else {
        UIAlertController *alertController = [UIAlertController alertControllerWithTitle:@"录屏未启动"
                                                                                 message:@"您尚未启动系统录屏，请先启动录屏后再进行操作。"
                                                                          preferredStyle:UIAlertControllerStyleAlert];
        [alertController addAction:[UIAlertAction actionWithTitle:@"确定" style:UIAlertActionStyleDefault handler:nil]];
        
        UIViewController *rootViewController = [UIApplication sharedApplication].keyWindow.rootViewController;
        [rootViewController presentViewController:alertController animated:YES completion:nil];
        return;
    }
    self.isRecordingStopped = YES;
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
    [PHPhotoLibrary requestAuthorization:^(PHAuthorizationStatus status) {
        if (status == PHAuthorizationStatusAuthorized) {
            // 相册访问权限已授权，可以进行下一步操作
            [self fetchRecentVideo];
        } else {
            // 没有权限，无法访问相册
        }
    }];
}

// 实现 PHPhotoLibraryChangeObserver 协议方法
- (void)photoLibraryDidChange:(PHChange *)changeInstance {
    if (self.isRecordingStopped) {
        PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
        fetchOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
        fetchOptions.fetchLimit = 1;
        
        PHFetchResult<PHAsset *> *currentFetchResult = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeVideo options:fetchOptions];
        PHFetchResultChangeDetails *changeDetails = [changeInstance changeDetailsForFetchResult:self.previousFetchResult];
        
        if (changeDetails != nil) {
            // 有新的视频添加到相册中
            if (currentFetchResult.count > 0) {
                PHAsset *recentVideoAsset = currentFetchResult.firstObject;
                
                // 删除最近的一条视频
                [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
                    [PHAssetChangeRequest deleteAssets:@[recentVideoAsset]];
                } completionHandler:^(BOOL success, NSError * _Nullable error) {
                    if (success) {
                        NSLog(@"最近的一条视频删除成功");
                    } else {
                        NSLog(@"最近的一条视频删除失败：%@", error);
                    }
                    
                    // 注销相册变化观察者
                    [[PHPhotoLibrary sharedPhotoLibrary] unregisterChangeObserver:self];
                }];
            }
        }
    }
}

- (void)fetchRecentVideo {
    PHFetchOptions *options = [[PHFetchOptions alloc] init];
    options.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
    PHFetchResult *videos = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeVideo options:options];
    if (videos.count > 0) {
        PHAsset *videoAsset = videos.firstObject;
        [self requestVideoURLFromAsset:videoAsset];
    }
}

- (void)requestVideoURLFromAsset:(PHAsset *)asset {
    [[PHImageManager defaultManager] requestAVAssetForVideo:asset options:nil resultHandler:^(AVAsset * _Nullable asset, AVAudioMix * _Nullable audioMix, NSDictionary * _Nullable info) {
        if ([asset isKindOfClass:[AVURLAsset class]]) {
            NSURL *videoURL = [(AVURLAsset *)asset URL];
            [self saveVideoToCustomPath:videoURL];
        }
    }];
}

- (void)saveVideoToCustomPath:(NSURL *)videoURL {
    NSError *error = nil;
    BOOL isDir = NO;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL fileExists = [fileManager fileExistsAtPath:self.targetFileName isDirectory:&isDir];
    if (fileExists) {
        // 文件存在，先删除
        BOOL isSuccess = [fileManager removeItemAtPath:self.targetFileName error:&error];
        if (error) {
            NSLog(@"删除文件时发生错误: %@", error);
            return;
        }
    }
    
    BOOL success = [[NSFileManager defaultManager] copyItemAtURL:videoURL toURL:[NSURL fileURLWithPath:self.targetFileName] error:&error];
    if (success) {
        NSLog(@"视频已保存到自定义路径: %@", self.targetFileName);
        NSData *videoData = [NSData dataWithContentsOfURL:[NSURL fileURLWithPath:self.targetFileName]];
        
        // 处理视频数据，设置帧率和码率等参数
        NSData *processedVideoData = [self processVideoData:videoData];
        NSString *md5 = [self MD5ForData:processedVideoData];
        NSLog(@"视频文件 MD5: %@", md5);
        
        // 将处理后的视频数据覆盖写入目标路径
        NSError *error = nil;
        NSFileManager *fileManager = [NSFileManager defaultManager];
        BOOL fileExists = [fileManager fileExistsAtPath:self.targetFileName];
        if (fileExists) {
            // 文件存在，先删除
            BOOL isSuccess = [fileManager removeItemAtPath:self.targetFileName error:&error];
            if (error) {
                NSLog(@"删除文件时发生错误: %@", error);
                return;
            } else {
                NSLog(@"已删除文件: %@", self.targetFileName);
            }
        }
        BOOL isSuccess = [processedVideoData writeToFile:self.targetFileName atomically:YES];
        if (isSuccess) {
            NSLog(@"写入处理好的视频成功");
        } else {
            NSLog(@"写入处理好的视频失败");
        }
        
        
//        // 创建 PHFetchOptions 对象，用于排序和限制获取视频数量
//        PHFetchOptions *fetchOptions = [[PHFetchOptions alloc] init];
//        fetchOptions.sortDescriptors = @[[NSSortDescriptor sortDescriptorWithKey:@"creationDate" ascending:NO]];
//        fetchOptions.fetchLimit = 1; // 限制只获取一条视频记录
//        
//        // 获取最近的一条视频 PHAsset 对象
//        PHFetchResult<PHAsset *> *recentVideoAssets = [PHAsset fetchAssetsWithMediaType:PHAssetMediaTypeVideo options:fetchOptions];
//        
//        // 检查是否获取到了视频
//        if (recentVideoAssets.count > 0) {
//            PHAsset *recentVideoAsset = recentVideoAssets.firstObject;
//            
//            // 删除最近的一条视频
//            [[PHPhotoLibrary sharedPhotoLibrary] performChanges:^{
//                [PHAssetChangeRequest deleteAssets:@[recentVideoAsset]];
//            } completionHandler:^(BOOL success, NSError * _Nullable error) {
//                if (success) {
//                    NSLog(@"最近的一条视频删除成功");
//                } else {
//                    NSLog(@"最近的一条视频删除失败：%@", error);
//                }
//            }];
//        } else {
//            NSLog(@"相册中没有视频可供删除");
//        }
//        
        
        
        
        
        // 将视频路径和 MD5 码一起返回给 Flutter
        if (self.resultStop) {
            self.resultStop(@{@"path": self.targetFileName, @"md5": md5});
            self.resultStop = nil;
        }
    } else {
        NSLog(@"保存视频时发生错误: %@", error);
        // 通知 Flutter 视频保存失败，并提供错误信息
    }
}

# pragma mark - 对视频进行处理，设置帧率码率，再回传给flutter
- (NSData *)processVideoData:(NSData *)videoData {
    // 创建临时文件存储传入的视频数据
    NSString *tempFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"tempVideo.mp4"];
    [videoData writeToFile:tempFilePath atomically:YES];
    
    // 使用临时文件创建 AVAsset
    AVAsset *asset = [AVAsset assetWithURL:[NSURL fileURLWithPath:tempFilePath]];
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
    
    // 设置视频的帧率和渲染大小
    AVMutableVideoComposition *videoComposition = [AVMutableVideoComposition videoComposition];
    videoComposition.frameDuration = CMTimeMake(1, [self.frameRate intValue]);
    videoComposition.renderSize = videoTrack.naturalSize;
    
    // 设置视频合成指令
    AVMutableVideoCompositionInstruction *instruction = [AVMutableVideoCompositionInstruction videoCompositionInstruction];
    instruction.timeRange = CMTimeRangeMake(kCMTimeZero, asset.duration);
    
    AVMutableVideoCompositionLayerInstruction *layerInstruction = [AVMutableVideoCompositionLayerInstruction videoCompositionLayerInstructionWithAssetTrack:compositionVideoTrack];
    [layerInstruction setTransform:videoTrack.preferredTransform atTime:kCMTimeZero];
    
    instruction.layerInstructions = @[layerInstruction];
    videoComposition.instructions = @[instruction];
    
    // 创建 AVAssetExportSession
    AVAssetExportSession *exportSession = [[AVAssetExportSession alloc] initWithAsset:composition
                                                                           presetName:AVAssetExportPresetHighestQuality];
    exportSession.outputFileType = AVFileTypeMPEG4;
    NSString *processedFilePath = [NSTemporaryDirectory() stringByAppendingPathComponent:@"processedVideo.mp4"];
    NSError *reerror = nil;
    BOOL isDir = NO;
    NSFileManager *fileManager = [NSFileManager defaultManager];
    BOOL fileExists = [fileManager fileExistsAtPath:processedFilePath isDirectory:&isDir];
    if (fileExists) {
        // 文件存在，先删除
        [fileManager removeItemAtPath:processedFilePath error:&error];
        if (reerror) {
            NSLog(@"删除临时文件发生错误: %@", error);
            return nil;
        }else {
            NSLog(@"已经删除%@路径文件",processedFilePath);
        }
    }
    exportSession.outputURL = [NSURL fileURLWithPath:processedFilePath];
    exportSession.videoComposition = videoComposition;
    
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
        if (exportSession.error) {
            NSLog(@"Error details: %@", exportSession.error.localizedDescription);
        }
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
