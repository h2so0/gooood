## Flutter
-keep class io.flutter.** { *; }
-dontwarn io.flutter.embedding.**

## Firebase
-keep class com.google.firebase.** { *; }
-dontwarn com.google.firebase.**
-keep class com.google.android.gms.** { *; }
-dontwarn com.google.android.gms.**

## Firestore
-keep class com.google.cloud.firestore.** { *; }
-keep class io.grpc.** { *; }

## Hive
-keep class com.crazecoder.openfile.** { *; }
-keepclassmembers class * extends com.google.protobuf.GeneratedMessageLite { *; }

## OkHttp / HTTP
-dontwarn okhttp3.**
-dontwarn okio.**
-dontwarn com.squareup.okhttp.**
-keep class okhttp3.** { *; }
-keep class com.squareup.okhttp.** { *; }

## Keep annotations
-keepattributes *Annotation*
-keepattributes Signature
-keepattributes InnerClasses,EnclosingMethod
