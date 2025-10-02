package smpn4.malang.examp4 // PASTIKAN INI SESUAI DENGAN PACKAGE ANDA

import android.app.ActivityManager
import android.content.Context
import android.os.Build
import android.os.Bundle
import android.os.Handler
import android.os.Looper
import android.util.Log
import android.view.View
import android.view.WindowManager
import io.flutter.embedding.android.FlutterActivity
import io.flutter.embedding.engine.FlutterEngine
import io.flutter.plugin.common.MethodChannel

class MainActivity: FlutterActivity() {
    private val SECURE_FLAG_CHANNEL = "com.example.exam_browser/secure_flag"
    private val ACTIVITY_MONITOR_CHANNEL = "com.example.exam_browser/activity_monitor"

    private lateinit var activityMonitorChannelInstance: MethodChannel // Ganti nama agar tidak konflik dengan variabel lokal
    private var isMonitoringActivity = false
    private val handler = Handler(Looper.getMainLooper())
    private var isAppInFocus = true
    private var initialSystemUiVisibility: Int = 0

    // Hapus atau komentari focusCheckRunnable jika tidak digunakan
    /*
    private val focusCheckRunnable = object : Runnable {
        override fun run() {
            if (isMonitoringActivity) {
                // checkWindowFocus() // Fungsi ini sudah dihapus/dikomentari
                handler.postDelayed(this, 1000)
            }
        }
    }
    */

    // Perbaiki tanda tangan metode dan penggunaan binaryMessenger
    override fun configureFlutterEngine(flutterEngine: FlutterEngine) { // Perbaikan di sini
        super.configureFlutterEngine(flutterEngine)

        // Handler untuk FLAG_SECURE
        MethodChannel(flutterEngine.dartExecutor.binaryMessenger, SECURE_FLAG_CHANNEL).setMethodCallHandler { // Pastikan ini benar
                call, result ->
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
        activityMonitorChannelInstance = MethodChannel(flutterEngine.dartExecutor.binaryMessenger, ACTIVITY_MONITOR_CHANNEL) // Pastikan ini benar
        activityMonitorChannelInstance.setMethodCallHandler {
                call, result ->
            when (call.method) {
                "startMonitoring" -> {
                    isMonitoringActivity = true
                    isAppInFocus = true
                    initialSystemUiVisibility = window.decorView.systemUiVisibility
                    hideSystemUI()
                    // handler.post(focusCheckRunnable) // Jika focusCheckRunnable dihapus
                    result.success("Activity monitoring started")
                    Log.d("ActivityMonitor", "Monitoring started")
                }
                "stopMonitoring" -> {
                    isMonitoringActivity = false
                    // handler.removeCallbacks(focusCheckRunnable) // Jika focusCheckRunnable dihapus
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
            window.setDecorFitsSystemWindows(false)
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
            window.setDecorFitsSystemWindows(true)
        } else {
            @Suppress("DEPRECATION")
            window.decorView.systemUiVisibility = previousVisibility
        }
        window.clearFlags(WindowManager.LayoutParams.FLAG_FULLSCREEN)
    }

    override fun onWindowFocusChanged(hasFocus: Boolean) {
        super.onWindowFocusChanged(hasFocus)
        Log.d("ActivityMonitor", "onWindowFocusChanged: $hasFocus, isMonitoring: $isMonitoringActivity")
        if (isMonitoringActivity) {
            isAppInFocus = hasFocus
            if (!hasFocus) {
                Log.w("ActivityMonitor", "Window lost focus! Requesting app lock.")
                activityMonitorChannelInstance.invokeMethod("lockApp", null) // Gunakan activityMonitorChannelInstance
            } else {
                hideSystemUI()
            }
        }
    }

    override fun onPause() {
        super.onPause()
        Log.d("ActivityMonitor", "onPause, isMonitoring: $isMonitoringActivity")
        if (isMonitoringActivity && !isFinishing) {
            Log.w("ActivityMonitor", "App paused! Requesting app lock.")
            handler.postDelayed({
                if (isMonitoringActivity && !isAppInFocus) { // Periksa juga isAppInFocus
                    activityMonitorChannelInstance.invokeMethod("lockApp", null) // Gunakan activityMonitorChannelInstance
                }
            }, 300)
        }
    }

    override fun onResume() {
        super.onResume()
        Log.d("ActivityMonitor", "onResume, isMonitoring: $isMonitoringActivity")
        if (isMonitoringActivity) {
            isAppInFocus = true
            hideSystemUI()
        }
    }
}
