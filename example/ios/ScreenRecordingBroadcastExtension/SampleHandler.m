//
//  SampleHandler.m
//  ScreenRecordingBroadcastExtension
//
//  Created by liwei on 2024/5/31.
//


#import "SampleHandler.h"
#import <ReplayKit/ReplayKit.h>


@interface NSDate (Timestamp)
+ (NSString *)timestamp;
@end
 
@implementation NSDate (Timestamp)
+ (NSString *)timestamp {
    long long timeinterval = (long long)([NSDate timeIntervalSinceReferenceDate] * 1000);
    return [NSString stringWithFormat:@"%lld", timeinterval];
}
@end

@interface SampleHandler ()
@property (nonatomic,strong) AVAssetWriter *assetWriter;
@property (nonatomic,strong) AVAssetWriterInput *videoInput;
@property (nonatomic,strong) AVAssetWriterInput *audioInput;
@end

@implementation SampleHandler
- (AVAssetWriter *)assetWriter{
    if (!_assetWriter) {
        NSError *error = nil;
        _assetWriter = [[AVAssetWriter alloc] initWithURL:[self getFilePathUrl] fileType:(AVFileTypeMPEG4) error:&error];
        NSAssert(!error, @"_assetWriter 初始化失败");
    }
    return _assetWriter;
}

-(AVAssetWriterInput *)videoInput{
    if (!_videoInput) {
        
        CGSize size = [UIScreen mainScreen].bounds.size;
        // 视频大小
        NSInteger numPixels = size.width * size.height;
        // 像素比
        CGFloat bitsPerPixel = 7.5;
        NSInteger bitsPerSecond = numPixels * bitsPerPixel;
        // 码率和帧率设置
        NSDictionary *videoCompressionSettings = @{
            AVVideoAverageBitRateKey:@(bitsPerSecond),//码率
            AVVideoExpectedSourceFrameRateKey:@(25),// 帧率
            AVVideoMaxKeyFrameIntervalKey:@(15),// 关键帧最大间隔
            AVVideoProfileLevelKey:AVVideoProfileLevelH264BaselineAutoLevel,
            AVVideoPixelAspectRatioKey:@{
                    AVVideoPixelAspectRatioVerticalSpacingKey:@(1),
                    AVVideoPixelAspectRatioHorizontalSpacingKey:@(1)
            }
        };
        CGFloat scale = [UIScreen mainScreen].scale;
        
        // 视频参数
        NSDictionary *videoOutputSettings = @{
            AVVideoCodecKey:AVVideoCodecTypeH264,
            AVVideoScalingModeKey:AVVideoScalingModeResizeAspectFill,
            AVVideoWidthKey:@(size.width*scale),
            AVVideoHeightKey:@(size.height*scale),
            AVVideoCompressionPropertiesKey:videoCompressionSettings
        };
        
        _videoInput  = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoOutputSettings];
        _videoInput.expectsMediaDataInRealTime = true;
    }
    return _videoInput;
}
- (NSURL *)getFilePathUrl {
    NSString *time = [NSDate timestamp];
    NSString *fileName = [time stringByAppendingPathExtension:@"mp4"];
    NSString *fullPath = [[self getDocumentPath] stringByAppendingPathComponent:fileName];
    return [NSURL fileURLWithPath:fullPath];
}

- (NSString *)getDocumentPath {
    
    static NSString *replaysPath;
    if (!replaysPath) {
        NSFileManager *fileManager = [NSFileManager defaultManager];
        NSURL *documentRootPath = [fileManager containerURLForSecurityApplicationGroupIdentifier:@"group.com.recordscreen.app"];
        replaysPath = [documentRootPath.path stringByAppendingPathComponent:@"Replays"];
        if (![fileManager fileExistsAtPath:replaysPath]) {
            NSError *error_createPath = nil;
            BOOL success_createPath = [fileManager createDirectoryAtPath:replaysPath withIntermediateDirectories:true attributes:@{} error:&error_createPath];
            if (success_createPath && !error_createPath) {
                NSLog(@"%@路径创建成功!", replaysPath);
            } else {
                NSLog(@"%@路径创建失败:%@", replaysPath, error_createPath);
            }
        }else{
            NSLog(@"%@路径已存在!", replaysPath);
        }
    }
    return replaysPath;
}

- (void)broadcastStartedWithSetupInfo:(NSDictionary<NSString *,NSObject *> *)setupInfo {
    NSLog(@"广播上传扩展开始");
        NSError *error = nil;
        self.assetWriter = [[AVAssetWriter alloc] initWithURL:[self getFilePathUrl] fileType:AVFileTypeMPEG4 error:&error];
        NSAssert(!error, @"AssetWriter 初始化失败: %@", error);

        CGSize screenSize = [UIScreen mainScreen].bounds.size;
        CGFloat screenScale = [UIScreen mainScreen].scale;
        NSDictionary *videoOutputSettings = @{
            AVVideoCodecKey: AVVideoCodecTypeH264,
            AVVideoWidthKey: @(screenSize.width * screenScale),
            AVVideoHeightKey: @(screenSize.height * screenScale)
        };

        self.videoInput = [AVAssetWriterInput assetWriterInputWithMediaType:AVMediaTypeVideo outputSettings:videoOutputSettings];
        self.videoInput.expectsMediaDataInRealTime = YES;
        
        [self.assetWriter addInput:self.videoInput];
}

- (void)broadcastPaused {
    NSLog(@"广播上传扩展停止");
}

- (void)broadcastResumed {
    NSLog(@"广播上传扩展恢复");
}

- (void)broadcastFinished {
    NSLog(@"广播上传扩展停止");
        [self.assetWriter finishWritingWithCompletionHandler:^{
            NSLog(@"视频写入完成");
            // 将视频数据保存到共享容器
            NSURL *fileURL = self.assetWriter.outputURL;
            NSData *videoData = [NSData dataWithContentsOfURL:fileURL];
            [self saveDataToSharedContainer:videoData];
        }];
}

- (void)processSampleBuffer:(CMSampleBufferRef)sampleBuffer withType:(RPSampleBufferType)sampleBufferType {
    
    if (self.assetWriter.status != AVAssetWriterStatusWriting && sampleBufferType == RPSampleBufferTypeVideo) {
            [self.assetWriter startWriting];
            [self.assetWriter startSessionAtSourceTime:CMSampleBufferGetPresentationTimeStamp(sampleBuffer)];
        }

        if (sampleBufferType == RPSampleBufferTypeVideo && self.videoInput.readyForMoreMediaData) {
            [self.videoInput appendSampleBuffer:sampleBuffer];
        }
}

- (void)handleVideoSampleBuffer:(CMSampleBufferRef)sampleBuffer {
    // 将视频数据处理并保存到共享容器中
    NSData *videoData = [self convertSampleBufferToData:sampleBuffer];
    [self saveDataToSharedContainer:videoData];
}

- (NSData *)convertSampleBufferToData:(CMSampleBufferRef)sampleBuffer {
    // Convert CMSampleBufferRef to NSData
    // Implement your conversion logic here
    return [NSData data];
}

- (void)saveDataToSharedContainer:(NSData *)data {
    NSUserDefaults *userDefaults = [[NSUserDefaults alloc] initWithSuiteName:@"group.com.recordscreen.app"];
       [userDefaults setObject:data forKey:@"videoData"];
       [userDefaults synchronize];
}
@end
