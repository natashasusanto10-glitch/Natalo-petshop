/// Feature flags sederhana, di-hardcode (bukan remote-config). Ubah nilai
/// lalu rebuild app untuk mengaktifkan/menonaktifkan.

/// Menampilkan section "Tag Produk Pernah Dibeli" di layar New Post dan
/// memicu query pinnable-products terkait. Non-aktif sejak Spec A
/// (2026-07-22) — tab "Belanja" di Profil sudah diganti "Ditandai".
/// Membalikkan flag ini ke `true` HANYA menghidupkan lagi input New Post;
/// tab Profil TIDAK otomatis kembali "Belanja" (perlu revert manual
/// terpisah). Lihat
/// docs/superpowers/specs/2026-07-22-tutup-tag-belanja-spec-a-design.md.
const kShopTagEnabled = false;
