# Flutter specific rules (default)
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }

# flutter_inappwebview rules
-keep class com.pichillilorenzo.flutter_inappwebview.** { *; }
-dontwarn com.pichillilorenzo.flutter_inappwebview.**
-keep class com.pichillilorenzo.flutter_inappwebview_android.** { *; }
-dontwarn com.pichillilorenzo.flutter_inappwebview_android.**

# url_launcher
-keep class io.flutter.plugins.urllauncher.** { *; }

# shared_preferences
-keep class com.shared_preferences.** { *; }
-keep class io.flutter.plugins.sharedpreferences.** { *; }

# package_info_plus
-keep class dev.fluttercommunity.plus.packageinfo.** { *; }
-keep class dev.fluttercommunity.plus.packageinfo.PackageInfoPlugin { *; }
-keep class io.flutter.plugins.packageinfo.** { *; }

# http (optional, but often needed for reflection-based plugins)
-keep class org.apache.http.** { *; }
-dontwarn org.apache.http.**

# General webview / android rules (needed by flutter_inappwebview)
-keep class android.webkit.** { *; }
-dontwarn android.webkit.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

# Google Play Core rules
-keep class com.google.android.play.core.** { *; }
-dontwarn com.google.android.play.core.**
