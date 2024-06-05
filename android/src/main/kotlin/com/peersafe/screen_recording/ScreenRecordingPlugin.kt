package com.peersafe.screen_recording

import android.app.Activity
import android.content.Context
import android.content.Intent
import android.hardware.display.DisplayManager
import android.hardware.display.VirtualDisplay
import android.media.MediaRecorder
import android.media.projection.MediaProjection
import android.media.projection.MediaProjectionManager
import android.util.DisplayMetrics
import android.util.Log
import android.view.WindowManager
import androidx.core.app.ActivityCompat
import io.flutter.plugin.common.EventChannel
import io.flutter.plugin.common.MethodCall
import io.flutter.plugin.common.MethodChannel
import io.flutter.plugin.common.MethodChannel.MethodCallHandler
import io.flutter.plugin.common.MethodChannel.Result
import io.flutter.plugin.common.PluginRegistry
import io.flutter.plugin.common.PluginRegistry.Registrar
import java.io.IOException

class ScreenRecordingPlugin(private val registrar: Registrar) : MethodCallHandler,
    PluginRegistry.ActivityResultListener {

    private val eventChannel = EventChannel(registrar.messenger(), "screen_recording_stream")
    private var eventSink: EventChannel.EventSink? = null

    private var mScreenDensity: Int = 0
    private var mMediaRecorder: MediaRecorder? = null
    private var mProjectionManager: MediaProjectionManager? = null
    private var mMediaProjection: MediaProjection? = null
    private var mMediaProjectionCallback: MediaProjectionCallback? = null
    private var mVirtualDisplay: VirtualDisplay? = null
    private var mDisplayWidth: Int = 1080
    private var mDisplayHeight: Int = 2208
    private var videoName: String? = ""
    private var recordAudio: Boolean? = false
    private val SCREEN_RECORD_REQUEST_CODE = 333

    private lateinit var _result: Result

    init {
        eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
            override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                eventSink = events
            }

            override fun onCancel(arguments: Any?) {
                eventSink = null
            }
        })
    }

    companion object {
        @JvmStatic
        fun registerWith(registrar: Registrar) {
            val channel = MethodChannel(registrar.messenger(), "screen_recording")
            val plugin = ScreenRecordingPlugin(registrar)
            channel.setMethodCallHandler(plugin)
            registrar.addActivityResultListener(plugin)

            // Ensure EventChannel is registered
            val eventChannel = EventChannel(registrar.messenger(), "screen_recording_stream")
            eventChannel.setStreamHandler(object : EventChannel.StreamHandler {
                override fun onListen(arguments: Any?, events: EventChannel.EventSink?) {
                    plugin.eventSink = events
                }

                override fun onCancel(arguments: Any?) {
                    plugin.eventSink = null
                }
            })
        }
    }

    override fun onActivityResult(requestCode: Int, resultCode: Int, data: Intent?): Boolean {
        if (requestCode == SCREEN_RECORD_REQUEST_CODE) {
            if (resultCode == Activity.RESULT_OK) {
                mMediaProjectionCallback = MediaProjectionCallback()
                mMediaProjection = mProjectionManager?.getMediaProjection(resultCode, data)
                mMediaProjection?.registerCallback(mMediaProjectionCallback, null)
                mVirtualDisplay = createVirtualDisplay()
                mMediaRecorder?.start()
                _result.success(true)
                return true
            } else {
                _result.success(false)
            }
        }
        return false
    }

    override fun onMethodCall(call: MethodCall, result: Result) {
        if (call.method == "startRecordScreen") {
            try {
                _result = result
                mMediaRecorder = MediaRecorder()
                mProjectionManager = registrar.context().getSystemService(Context.MEDIA_PROJECTION_SERVICE) as MediaProjectionManager
                val windowManager = registrar.context().getSystemService(Context.WINDOW_SERVICE) as WindowManager
                val metrics = DisplayMetrics()
                windowManager.defaultDisplay.getMetrics(metrics)
                mScreenDensity = metrics.densityDpi

                videoName = call.argument<String>("name")
                recordAudio = call.argument<Boolean>("audio")
                mDisplayHeight = call.argument<Int>("height")!!
                mDisplayWidth = call.argument<Int>("width")!!

                startRecordScreen()
            } catch (e: Exception) {
                Log.e("ScreenRecordingPlugin", "Error starting screen recording", e)
                result.success(false)
            }

        } else if (call.method == "stopRecordScreen") {
            try {
                if (mMediaRecorder != null) {
                    stopRecordScreen()
                    result.success(videoName)
                } else {
                    result.success("")
                }
            } catch (e: Exception) {
                result.success("")
            }

        } else {
            result.notImplemented()
        }
    }

    private fun startRecordScreen() {
        try {
            mMediaRecorder?.apply {
                setVideoSource(MediaRecorder.VideoSource.SURFACE)
                if (recordAudio == true) {
                    setAudioSource(MediaRecorder.AudioSource.MIC)
                    setOutputFormat(MediaRecorder.OutputFormat.THREE_GPP)
                    setAudioEncoder(MediaRecorder.AudioEncoder.AAC)
                } else {
                    setOutputFormat(MediaRecorder.OutputFormat.MPEG_4)
                }
                setOutputFile(videoName)
                setVideoSize(mDisplayWidth, mDisplayHeight)
                setVideoEncoder(MediaRecorder.VideoEncoder.H264)
                setVideoEncodingBitRate(5 * mDisplayWidth * mDisplayHeight)
                setVideoFrameRate(60)
                prepare()
            }

            val permissionIntent = mProjectionManager?.createScreenCaptureIntent()
            registrar.activity()?.let {
                ActivityCompat.startActivityForResult(it, permissionIntent!!, SCREEN_RECORD_REQUEST_CODE, null)
            } ?: run {
                _result.error("NoActivity", "No activity to startForResult", null)
            }

        } catch (e: IOException) {
            Log.e("ScreenRecordingPlugin", "Error preparing MediaRecorder", e)
        }
    }

    private fun stopRecordScreen() {
        try {
            mMediaRecorder?.stop()
            mMediaRecorder?.release()
            mMediaRecorder = null
            stopScreenSharing()
        } catch (e: Exception) {
            Log.e("ScreenRecordingPlugin", "Error stopping screen recording", e)
        }
    }

    private fun createVirtualDisplay(): VirtualDisplay? {
        return mMediaProjection?.createVirtualDisplay(
            "ScreenRecording",
            mDisplayWidth,
            mDisplayHeight,
            mScreenDensity,
            DisplayManager.VIRTUAL_DISPLAY_FLAG_AUTO_MIRROR,
            mMediaRecorder?.surface,
            null,
            null
        )
    }

    private fun stopScreenSharing() {
        mVirtualDisplay?.release()
        mMediaProjection?.unregisterCallback(mMediaProjectionCallback)
        mMediaProjection?.stop()
        mMediaProjection = null
    }

    private inner class MediaProjectionCallback : MediaProjection.Callback() {
        override fun onStop() {
            mMediaRecorder?.stop()
            mMediaRecorder?.release()
            mMediaRecorder = null
            stopScreenSharing()
        }
    }
}