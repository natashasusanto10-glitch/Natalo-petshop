# ProGuard/R8 rules — Natalo Petshop.
#
# KONTEKS: R8 sudah aktif secara default untuk semua release build Flutter
# (FlutterPlugin.kt menyetel isMinifyEnabled + isShrinkResources sendiri),
# dan plugin itu juga memungut file ini otomatis kalau ada. Jadi TIDAK perlu
# menulis isMinifyEnabled di build.gradle.kts.
#
# PRINSIP: sesedikit mungkin, dan setiap baris harus punya bukti bahwa ia
# memang dibutuhkan. Dua sumber sudah menutup sebagian besar kebutuhan:
#   1. proguard-android-optimize.txt bawaan AGP
#   2. flutter_proguard_rules.pro bawaan Flutter
#   3. consumer-rules.pro di dalam AAR tiap library (Firebase, Media3, Glide)
# Menambahkan `-keep class <lib>.** { *; }` justru MEMBATALKAN shrinking
# untuk library itu — pernah dicoba dan bikin dex membengkak tanpa manfaat.
#
# Yang SENGAJA TIDAK ada di sini karena terbukti tidak perlu (diverifikasi
# di configuration.txt hasil build, yaitu gabungan semua aturan yang aktif):
#   - `-keepattributes *Annotation*, Signature, InnerClasses, EnclosingMethod`
#     → sudah di-keep default AGP.
#   - Aturan Parcelable dan enum values()/valueOf()
#     → sudah di-keep default AGP.
#   - `-dontwarn androidx.media3.**` dan `-dontwarn com.google.android.play.core.**`
#     → build release sukses tanpa keduanya.
#
# Kalau nanti ada crash yang HANYA muncul di build release (bukan debug),
# curigai R8 me-strip class yang dipanggil lewat reflection → tambahkan
# -keep spesifik untuk class itu di sini, JANGAN blanket-keep satu paket.

# ── Keterbacaan stack trace Crashlytics ───────────────────────────────
# INI ALASAN UTAMA FILE INI ADA. Diverifikasi: SourceFile dan
# LineNumberTable TIDAK di-keep oleh aturan default mana pun. Tanpa dua
# atribut ini, R8 membuang nomor baris dari bytecode — dan yang hilang di
# bytecode tidak bisa dikembalikan oleh mapping.txt. Akibatnya setiap crash
# produksi muncul sebagai `a.b.c()` tanpa nomor baris.
-keepattributes SourceFile,LineNumberTable

# Pasangan wajib dari aturan di atas: nama file asli diganti string generik
# "SourceFile" (tidak membocorkan struktur sumber), nomor baris tetap utuh.
# Plugin firebase.crashlytics meng-upload mapping.txt supaya Firebase bisa
# memulihkan nama asli saat menampilkan crash.
-renamesourcefileattribute SourceFile

# ── Serialisasi Java ──────────────────────────────────────────────────
# Diverifikasi tidak di-cover aturan default mana pun. Anggota di bawah
# dibaca runtime lewat refleksi, bukan dari kode kita — kalau R8 membuangnya,
# kegagalannya SENYAP dan hanya muncul saat deserialisasi di perangkat user.
-keepclassmembers class * implements java.io.Serializable {
    static final long serialVersionUID;
    private static final java.io.ObjectStreamField[] serialPersistentFields;
    private void writeObject(java.io.ObjectOutputStream);
    private void readObject(java.io.ObjectInputStream);
    java.lang.Object writeReplace();
    java.lang.Object readResolve();
}
