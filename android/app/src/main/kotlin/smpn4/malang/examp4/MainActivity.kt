package smpn4.malang.examp4

import android.app.ActivityManager
import android.app.NotificationManager
import android.content.Context
import android.content.Intent
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.provider.Settings
import android.util.Log
import android.view.View
import android.view.WindowInsets
import android.view.WindowInsetsController
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val SECURE_FLAG_CHANNEL = "com.example.exam_browser/secure_flag"
    private val ACTIVITY_MONITOR_CHANNEL = "com.example.exam_browser/activity_monitor"
    private val DND_CHANNEL = "com.example.exam_browser/dnd"
    private val BRIGHTNESS_CHANNEL = "com.example.exam_browser/brightness"

    private lateinit var activityMonitorChannelInstance: MethodChannel

    private var isMonitoringActivity = false
    private val handler = Handler(Looper.getMainLooper())
    private var isAppInFocus = true
    private var initialSystemUiVisibility: Int = 0
    private var isCurrentlyLocked = false
    private var previousDndState: Int = -1

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_FLAG_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "setSecureFlag" -> {
                    window.addFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                "clearSecureFlag" -> {
                    window.clearFlags(WindowManager.LayoutParams.FLAG_SECURE)
                    result.success(null)
                }
                else -> result.notImplemented()
            }
        }

        activityMonitorChannelInstance = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ACTIVITY_MONITOR_CHANNEL)
        activityMonitorChannelInstance.setMethodCallHandler { call, result ->
            when (call.method) {
                "startMonitoring" -> {
                    isMonitoringActivity = true
                    isAppInFocus = true
                    isCurrentlyLocked = false
                    initialSystemUiVisibility = window.decorView.systemUiVisibility
                    hideSystemUI()
                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    setDndMode(true)
                    result.success("Activity monitoring started")
                }
                "stopMonitoring" -> {
                    isMonitoringActivity = false
                    showSystemUI(initialSystemUiVisibility)
                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    setDndMode(false)
                    setBrightness(-1.0f)
                    result.success("Activity monitoring stopped")
                }
                else -> result.notImplemented()
            }
        }

        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, DND_CHANNEL).setMethodCallHandler { call, result ->
            when (call.method) {
                "requestDndPermission" -> {
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M && !notificationManager.isNotificationPolicyAccessGranted) {
                        val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                        startActivity(intent)
                    }
                    result.success(null)
                }
                "checkDndPermission" -> {
                    val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
                    val granted = if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
                        notificationManager.isNotificationPolicyAccessGranted
                    } else {
                        true
                    }
                    result.success(granted)
                }
                else -> result.notImplemented()
            }
        }
        
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, BRIGHTNESS_CHANNEL).setMethodCallHandler { call, result ->
            if (call.method == "setBrightness") {
                val brightness = call.argument<Double>("brightness")?.toFloat() ?: -1.0f
                setBrightness(brightness)
                result.success(null)
            } else {
                result.notImplemented()
            }
        }
    }

    private fun setBrightness(brightness: Float) {
        val layoutParams: WindowManager.LayoutParams = window.attributes
        layoutParams.screenBrightness = brightness
        window.attributes = layoutParams
    }

    private fun setDndMode(enable: Boolean) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!notificationManager.isNotificationPolicyAccessGranted) {
                return
            }

            if (enable) {
                previousDndState = notificationManager.currentInterruptionFilter
                notificationManager.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_NONE)
            } else {
                if (previousDndState != -1) {
                    notificationManager.setInterruptionFilter(previousDndState)
                }
            }
        }
    }
    
    private fun hideSystemUI() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.let {
                it.hide(WindowInsets.Type.systemBars())
                it.systemBarsBehavior = WindowInsetsController.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
            }
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = (
                    View.SYSTEM_UI_FLAG_IMMERSIVE_STICKY
                            or View.SYSTEM_UI_FLAG_LAYOUT_STABLE
                            or View.SYSTEM_UI_FLAG_LAYOUT_HIDE_NAVIGATION
                            or View.SYSTEM_UI_FLAG_LAYOUT_FULLSCREEN
                            or View.SYSTEM_UI_FLAG_HIDE_NAVIGATION
                            or View.SYSTEM_UI_FLAG_FULLSCREEN)
        }
        window.addFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
    }

    private fun showSystemUI(previousVisibility: Int) {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
            window.insetsController?.show(WindowInsets.Type.systemBars())
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = previousVisibility
        }
        window.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
    }

    private fun lockApp(reason: String) {
        if (!isCurrentlyLocked) {
            activityMonitorChannelInstance.invokeMethod("lockApp", reason)
            isCurrentlyLocked = true
        }
    }

    private fun checkMultiWindowAndLock() {
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.N && isInMultiWindowMode) {
            lockApp("Mode Layar Terpisah (Split Screen) tidak diizinkan.")
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!::activityMonitorChannelInstance.isInitialized) return

        if (isMonitoringActivity) {
            isAppInFocus = hasFocus
            if (!hasFocus) {
                handler.postDelayed({
                    if (!isAppInFocus) {
                        lockApp("Terdeteksi kehilangan fokus jendela.")
                    }
                }, 250)
            } else {
                hideSystemUI()
            }
        }
    }

    override fun onPause() {
        super.onPause()
        if (!::activityMonitorChannelInstance.isInitialized) return

        if (isMonitoringActivity && !isFinishing) {
            handler.postDelayed({ checkMultiWindowAndLock() }, 100)
        }
    }

    override fun onResume() {
        super.onResume()
        if (isMonitoringActivity) {
            isCurrentlyLocked = false 
            hideSystemUI()
            checkMultiWindowAndLock()
        }
    }
}