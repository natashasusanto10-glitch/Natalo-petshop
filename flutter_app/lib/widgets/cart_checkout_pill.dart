import 'package:flutter/material.dart';

// Warna pil mengikuti brand Natalo + turunan yang kebaca di atas biru.
const _pillBlue = Color(0xFF1E5FBF);
const _pillSavingPink = Color(0xFFFFD9E1);
const _pillVoucherDotGreen = Color(0xFF4ADE80);

/// Pil melayang pengganti voucher bar + summary bar saat user scroll
/// (pola "condense": CTA checkout tidak pernah hilang dari layar).
/// Konten: [ikon tiket + titik hijau jika voucher aktif] "N item • Rp X"
/// (+ "Hemat Rp Y" bila ada) [lingkaran panah]. Tap SELURUH pil = checkout.
/// String total/hemat sudah diformat pemanggil — widget ini presentasional
/// murni supaya gampang dites.
class CartCheckoutPill extends StatelessWidget {
  final int quantity;
  final String totalText;
  final String? savingText;
  final bool voucherActive;
  final VoidCallback onTap;

  const CartCheckoutPill({
    super.key,
    required this.quantity,
    required this.totalText,
    this.savingText,
    required this.voucherActive,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: _pillBlue,
      borderRadius: BorderRadius.circular(999),
      elevation: 8,
      shadowColor: _pillBlue.withValues(alpha: 0.38),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(999),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(14, 8, 10, 8),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (voucherActive) ...[
                const _VoucherDotIcon(),
                const SizedBox(width: 10),
              ],
              Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    '$quantity item • $totalText',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 13.5,
                      fontWeight: FontWeight.w900,
                    ),
                  ),
                  if (savingText != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 1),
                      child: Text(
                        savingText!,
                        style: const TextStyle(
                          color: _pillSavingPink,
                          fontSize: 10.5,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 11),
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.22),
                  shape: BoxShape.circle,
                ),
                child: const Icon(
                  Icons.arrow_forward_rounded,
                  color: Colors.white,
                  size: 19,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Ikon tiket kecil dengan titik hijau = penanda "voucher aktif kepasang"
/// tetap terlihat walau voucher bar sedang terlipat.
class _VoucherDotIcon extends StatelessWidget {
  const _VoucherDotIcon();

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: 30,
      height: 30,
      child: Stack(
        children: [
          Container(
            width: 30,
            height: 30,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.18),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.confirmation_number_rounded,
              color: _pillSavingPink,
              size: 15,
            ),
          ),
          Positioned(
            top: 0,
            right: 0,
            child: Container(
              width: 9,
              height: 9,
              decoration: BoxDecoration(
                color: _pillVoucherDotGreen,
                shape: BoxShape.circle,
                border: Border.all(color: _pillBlue, width: 2),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
