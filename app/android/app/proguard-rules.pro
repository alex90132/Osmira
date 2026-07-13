# The JNI symbols in libwg-go.so are hard-coded as
# Java_org_amnezia_awg_GoBackend_*, so this class and its native methods must
# keep their exact names — R8 must never rename or remove them.
-keep class org.amnezia.awg.GoBackend { *; }
-keepclasseswithmembernames class * {
    native <methods>;
}

# VpnService / Activity are instantiated by the OS via the manifest.
-keep class osmi.awg2.MainActivity { *; }
-keep class osmi.awg2.AwgVpnService { *; }

# Flutter engine (kept by the tool's bundled rules too, but be explicit).
-keep class io.flutter.** { *; }
-dontwarn io.flutter.**

# Belt-and-suspenders: strip every android.util.Log call from release. Our
# Kotlin logging is already guarded by BuildConfig.DEBUG, but this guarantees
# that even a stray or dependency Log.* emits nothing in release — R8 drops the
# call and the dead argument/string-building along with it.
-assumenosideeffects class android.util.Log {
    public static *** v(...);
    public static *** d(...);
    public static *** i(...);
    public static *** w(...);
    public static *** e(...);
    public static *** wtf(...);
}
