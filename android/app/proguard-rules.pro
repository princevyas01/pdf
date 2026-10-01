# Flutter Wrapper Rules
-keep class io.flutter.app.** { *; }
-keep class io.flutter.plugin.**  { *; }
-keep class io.flutter.util.**  { *; }
-keep class io.flutter.view.**  { *; }
-keep class io.flutter.**  { *; }
-keep class io.flutter.plugins.**  { *; }
-keep class com.google_mlkit_text_recognition.** { *; }

# Ignore ML Kit language specific missing classes (we only use Latin)
-dontwarn com.google.mlkit.vision.text.chinese.**
-dontwarn com.google.mlkit.vision.text.devanagari.**
-dontwarn com.google.mlkit.vision.text.japanese.**
-dontwarn com.google.mlkit.vision.text.korean.**

# Ignore Play Core missing classes (used by Flutter for deferred components which we don't use)
-dontwarn com.google.android.play.core.**

# llama_flutter_android native bindings and Pigeon classes
-keep class com.write4me.llama_flutter_android.** { *; }
