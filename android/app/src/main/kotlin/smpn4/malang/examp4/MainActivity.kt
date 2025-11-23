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

    private lateinit var activityMonitorChannelInstance: MethodChannel

    private var isMonitoringActivity = false
    private val handler = Handler(Looper.getMainLooper())
    private var isAppInFocus = true
    private var initialSystemUiVisibility: Int = 0
    private var isCurrentlyLocked = false
    private var previousDndState: Int = -1

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
                    window.addFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    setDndMode(true) // Aktifkan DND
                    result.success("Activity monitoring started")
                    Log.d("ActivityMonitor", "Monitoring started, DND activated")
                }
                "stopMonitoring" -> {
                    isMonitoringActivity = false
                    showSystemUI(initialSystemUiVisibility)
                    window.clearFlags(WindowManager.LayoutParams.FLAG_KEEP_SCREEN_ON)
                    setDndMode(false) // Nonaktifkan DND
                    result.success("Activity monitoring stopped")
                    Log.d("ActivityMonitor", "Monitoring stopped, DND deactivated")
                }
                else -> result.notImplemented()
            }
        }

        // Channel baru untuk mengelola izin DND dari Flutter
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
                else -> result.notImplemented()
            }
        }
    }

    private fun setDndMode(enable: Boolean) {
        val notificationManager = getSystemService(Context.NOTIFICATION_SERVICE) as NotificationManager
        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.M) {
            if (!notificationManager.isNotificationPolicyAccessGranted) {
                Log.w("DND", "Izin 'Jangan Ganggu' belum diberikan.")
                // Opsional: Buka pengaturan jika izin belum ada saat ujian dimulai
                // val intent = Intent(Settings.ACTION_NOTIFICATION_POLICY_ACCESS_SETTINGS)
                // startActivity(intent)
                return
            }

            if (enable) {
                // Simpan state DND saat ini sebelum mengubahnya
                previousDndState = notificationManager.currentInterruptionFilter
                // Aktifkan mode Jangan Ganggu total (semua diblok)
                notificationManager.setInterruptionFilter(NotificationManager.INTERRUPTION_FILTER_NONE)
                Log.d("DND", "Mode 'Jangan Ganggu' diaktifkan.")
            } else {
                // Kembalikan state DND ke state sebelumnya
                if (previousDndState != -1) {
                    notificationManager.setInterruptionFilter(previousDndState)
                    Log.d("DND", "Mode 'Jangan Ganggu' dikembalikan ke normal.")
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
            Log.w("ActivityMonitor", "Locking app. Reason: $reason")
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
            if (!hasFocus && !isInMultiWindowMode) { // Hanya kunci jika bukan karena multi-window
                handler.postDelayed({
                    if (!isAppInFocus) {
                        lockApp("Terdeteksi kehilangan fokus jendela.")
                    }
                }, 250)
            } else {
                hideSystemUI()
                if (isCurrentlyLocked && !isInMultiWindowMode) {
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
            // Pengecekan utama untuk multi-window saat jeda
            handler.postDelayed({ checkMultiWindowAndLock() }, 100)
        }
    }

    override fun onResume() {
        super.onResume()
        if (isMonitoringActivity) {
            isAppInFocus = true
            hideSystemUI()

            // Pengecekan multi-window saat aplikasi kembali aktif
            checkMultiWindowAndLock()

            if (isCurrentlyLocked && !isInMultiWindowMode) {
                isCurrentlyLocked = false
            }
        }
    }
}