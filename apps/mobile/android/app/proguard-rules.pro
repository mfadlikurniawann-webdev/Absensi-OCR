# Google ML Kit (google_mlkit_face_detection).
# Tanpa aturan ini, R8 di build rilis merusak konversi frame kamera ke
# InputImage (log: "ImageError: Getting Image failed ... NullPointerException"),
# sehingga wajah tidak pernah terdeteksi. Build debug tidak terpengaruh.
-keep class com.google.mlkit.** { *; }
-keep class com.google.android.gms.internal.mlkit_** { *; }
-keep class com.google_mlkit_** { *; }
-dontwarn com.google.mlkit.**
