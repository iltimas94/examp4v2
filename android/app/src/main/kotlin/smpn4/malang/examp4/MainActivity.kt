package smpn4.malang.examp4

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
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

    private lateinit var activityMonitorChannelInstance: MethodChannel

    private var isMonitoringActivity = false
    private val handler = Handler(Looper.getMainLooper())
    private var isAppInFocus = true
    private var initialSystemUiVisibility: Int = 0
    private var isCurrentlyLocked = false

    override fun configureFlutterEngine(flutterEngine: FlutterEngine) {
        super.configureFlutterEngine(flutterEngine)

        // Handler untuk FLAG_SECURE
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

        // Handler untuk Activity Monitor
        activityMonitorChannelInstance = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ACTIVITY_MONITOR_CHANNEL)
        activityMonitorChannelInstance.setMethodCallHandler { call, result ->
            when (call.method) {
                "startMonitoring" -> {
                    isMonitoringActivity = true
                    isAppInFocus = true
                    isCurrentlyLocked = false
                    initialSystemUiVisibility = window.decorView.systemUiVisibility
                    hideSystemUI()
                    result.success("Activity monitoring started")
                    Log.d("ActivityMonitor", "Monitoring started")
                }
                "stopMonitoring" -> {
                    isMonitoringActivity = false
                    showSystemUI(initialSystemUiVisibility)
                    result.success("Activity monitoring stopped")
                    Log.d("ActivityMonitor", "Monitoring stopped")
                }
                else -> result.notImplemented()
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

    private fun getRunningAppsReason(): String {
        try {
            val activityManager = getSystemService(Context.ACTIVITY_SERVICE) as ActivityManager
            val runningApps = activityManager.runningAppProcesses ?: return "Aktivitas mencurigakan terdeteksi."
            val myPackageName = packageName
            val otherForegroundApps = runningApps
                .filter { it.importance == ActivityManager.RunningAppProcessInfo.IMPORTANCE_FOREGROUND && it.processName != myPackageName }
                .mapNotNull { it.processName }
                .distinct()
                .joinToString(", ")

            return if (otherForegroundApps.isNotEmpty()) {
                "Aplikasi berjalan: $otherForegroundApps"
            } else {
                "Terdeteksi kehilangan fokus jendela."
            }
        } catch (e: Exception) {
            Log.e("ActivityMonitor", "Error getting running apps", e)
            return "Gagal mendeteksi aplikasi lain."
        }
    }

    private fun lockAppIfNeeded() {
        if (isMonitoringActivity && !isAppInFocus && !isCurrentlyLocked) {
            val reason = getRunningAppsReason()
            Log.w("ActivityMonitor", "Requesting app lock. Reason: $reason")
            activityMonitorChannelInstance.invokeMethod("lockApp", reason)
            isCurrentlyLocked = true
        }
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        if (!::activityMonitorChannelInstance.isInitialized) return

        if (isMonitoringActivity) {
            isAppInFocus = hasFocus
            if (!hasFocus) {
                handler.postDelayed({ lockAppIfNeeded() }, 250)
            } else {
                hideSystemUI()
                if (isCurrentlyLocked) {
                    isCurrentlyLocked = false
                }
            }
        }
    }

    override fun onPause() {
        super.onPause()
        if (!::activityMonitorChannelInstance.isInitialized) return

        if (isMonitoringActivity && !isFinishing) {
            isAppInFocus = false
            handler.postDelayed({ lockAppIfNeeded() }, 300)
        }
    }

    override fun onResume() {
        super.onResume()
        if (isMonitoringActivity) {
            isAppInFocus = true
            hideSystemUI()
            if (isCurrentlyLocked) {
                isCurrentlyLocked = false
            }
        }
    }
}
