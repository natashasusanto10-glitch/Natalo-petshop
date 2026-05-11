# ProGuard rules for Capacitor + WebView app

# Keep Capacitor core classes
-keep class com.getcapacitor.** { *; }
-keep @com.getcapacitor.annotation.CapacitorPlugin class * { *; }
-keep class * extends com.getcapacitor.Plugin { *; }

# Keep all classes annotated with @PluginMethod
-keepclassmembers class * {
    @com.getcapacitor.PluginMethod *;
}

# Keep Cordova classes (used by Capacitor's compatibility layer)
-keep class org.apache.cordova.** { *; }

# Keep WebView JS interfaces
-keepclassmembers class * {
    @android.webkit.JavascriptInterface <methods>;
}

# Keep AndroidX
-keep class androidx.** { *; }
-dontwarn androidx.**

# Standard Android
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes Exceptions
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# Keep enums
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Keep R class
-keep class **.R$* { *; }

# Suppress warnings for missing classes
-dontwarn java.lang.invoke.**
-dontwarn javax.annotation.**
