# Flutter
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.** { *; }
-keep class io.flutter.util.** { *; }
-keep class io.flutter.view.** { *; }
-keep class io.flutter.** { *; }
-keep class io.flutter.plugins.** { *; }

# Agora RTC
-keep class io.agora.** { *; }

# Gson / JSON
-keepattributes Signature
-keepattributes *Annotation*
-dontwarn sun.misc.**
-keep class com.google.gson.** { *; }

# Keep native methods
-keepclasseswithmembernames class * {
    native <methods>;
}

# Apache POI legacy Office extraction uses only text/table APIs on Android.
# Desktop drawing and optional Log4j OSGi/analysis annotations are not present
# on Android and are removed by R8 because the preview path never calls them.
-dontwarn java.awt.**
-dontwarn javax.imageio.**
-dontwarn aQute.bnd.annotation.**
-dontwarn edu.umd.cs.findbugs.annotations.**
-dontwarn org.osgi.framework.**

# Play Core split install (Flutter references these; build as APK, not AAB deferred components)
-dontwarn com.google.android.play.core.splitcompat.SplitCompatApplication
-dontwarn com.google.android.play.core.splitinstall.SplitInstallException
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManager
-dontwarn com.google.android.play.core.splitinstall.SplitInstallManagerFactory
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest$Builder
-dontwarn com.google.android.play.core.splitinstall.SplitInstallRequest
-dontwarn com.google.android.play.core.splitinstall.SplitInstallSessionState
-dontwarn com.google.android.play.core.splitinstall.SplitInstallStateUpdatedListener
-dontwarn com.google.android.play.core.tasks.OnFailureListener
-dontwarn com.google.android.play.core.tasks.OnSuccessListener
-dontwarn com.google.android.play.core.tasks.Task

# App entry
-keep class com.nuanlin.im.MainActivity { *; }
-keep class * extends android.app.Application {
    <init>();
}

# Parcelable / Serializable / enum
-keepclassmembers class * implements android.os.Parcelable {
    public static final android.os.Parcelable$Creator CREATOR;
}
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}
-keepclassmembers enum * {
    public static **[] values();
    public static ** valueOf(java.lang.String);
}

# Reflection-heavy paths
-keepattributes EnclosingMethod
-keepattributes InnerClasses
-keepattributes RuntimeVisibleAnnotations
-keepattributes RuntimeVisibleParameterAnnotations

# WebView
-keepclassmembers class * extends android.webkit.WebViewClient {
    public void *(android.webkit.WebView, java.lang.String, android.graphics.Bitmap);
    public boolean *(android.webkit.WebView, java.lang.String);
}
-keepclassmembers class * extends android.webkit.WebChromeClient {
    public void *(android.webkit.WebView, java.lang.String);
}

# Notifications and background service
-keep class androidx.core.app.NotificationCompat { *; }
-keep class androidx.core.app.NotificationManagerCompat { *; }
-keep class id.flutter.flutter_background_service.** { *; }

# Optional Room (if any module uses it)
-keep class * extends androidx.room.RoomDatabase { *; }
-keep @androidx.room.Entity class * { *; }
-keep @androidx.room.Dao class * { *; }

# OkHttp / OkIO
-keep class okhttp3.** { *; }
-keep interface okhttp3.** { *; }
-dontwarn okhttp3.**
-keep class okio.** { *; }
-dontwarn okio.**

# Retrofit
-dontwarn retrofit2.**
-keep class retrofit2.** { *; }
-keepclasseswithmembers class * {
    @retrofit2.http.* <methods>;
}

# Glide
-keep class com.bumptech.glide.** { *; }
-keep public class * implements com.bumptech.glide.module.GlideModule
-keep class * extends com.bumptech.glide.module.AppGlideModule {
    <init>();
}

# Vendor push SDKs (Huawei/JPush/Xiaomi/OPPO)
-keep class com.huawei.hms.** { *; }
-dontwarn com.huawei.hms.**

-keep class cn.jpush.** { *; }
-dontwarn cn.jpush.**
-keep class cn.jiguang.** { *; }
-dontwarn cn.jiguang.**

-keep class com.xiaomi.** { *; }
-dontwarn com.xiaomi.**

-keep class com.heytap.msp.** { *; }
-keep interface com.heytap.msp.push.callback.** { *; }
-dontwarn com.heytap.msp.**

# Keep debug stack mapping quality
-keepattributes Exceptions
-keepattributes SourceFile,LineNumberTable
-renamesourcefileattribute SourceFile

# jverify / unicom one-click login references optional BouncyCastle SM2/SM3 APIs
-dontwarn org.bouncycastle.crypto.CipherParameters
-dontwarn org.bouncycastle.crypto.InvalidCipherTextException
-dontwarn org.bouncycastle.crypto.digests.SM3Digest
-dontwarn org.bouncycastle.crypto.engines.SM2Engine
-dontwarn org.bouncycastle.crypto.params.ECDomainParameters
-dontwarn org.bouncycastle.crypto.params.ECPublicKeyParameters
-dontwarn org.bouncycastle.crypto.params.ParametersWithRandom
-dontwarn org.bouncycastle.crypto.signers.SM2Signer
-dontwarn org.bouncycastle.jce.ECNamedCurveTable
-dontwarn org.bouncycastle.jce.provider.BouncyCastleProvider
-dontwarn org.bouncycastle.jce.spec.ECNamedCurveParameterSpec
-dontwarn org.bouncycastle.jce.spec.ECParameterSpec
-dontwarn org.bouncycastle.math.ec.ECCurve
-dontwarn org.bouncycastle.math.ec.ECPoint
