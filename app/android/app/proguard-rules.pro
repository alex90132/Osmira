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
