import 'package:flutter/material.dart';

import '../../models/chat_message.dart';
import '../../theme/app_radius.dart';
import '../../theme/app_spacing.dart';
import '../../theme/natalo_colors.dart';

/// Catatan sistem terpusat — dirender untuk `ChatMessage` ber-`type ==
/// ChatMsgType.system` (greeting/away otomatis, transisi status room mis.
/// "Percakapan dibuka kembali."), TERLEPAS dari `sender` mentahnya.
///
/// **Penting:** dispatch di `ChatRoomScreen` SENGAJA key off `type`, BUKAN
/// `sender` — proyeksi proxy customer (`projectMessageForCustomer`) SELALU
/// menormalisasi `senderRole` mentah 'system' jadi 'customer' sebelum
/// sampai client (lihat docstring `chat_message.dart`), jadi kalau dispatch
/// pakai `sender`, catatan sistem akan salah dirender sebagai bubble
/// customer biasa.
///
/// Teks note diambil apa adanya dari `message.text` (proxy sudah mengirim
/// kalimat siap-tampil, mis. "Halo! Terima kasih sudah menghubungi..." atau
/// "Percakapan dibuka kembali.") — widget ini TIDAK menghardcode salinan
/// pesan otomatis, hanya menambahkan tag kecil "Balasan otomatis" saat
/// `message.auto == true` supaya beda visual dgn catatan transisi status.
class ChatSystemNote extends StatelessWidget {
  final ChatMessage message;

  const ChatSystemNote({super.key, required this.message});

  @override
  Widget build(BuildContext context) {
    final text = (message.text ?? '').trim();
    final label = text.isEmpty ? 'Pembaruan percakapan' : text;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Center(
        child: Container(
          constraints: const BoxConstraints(maxWidth: 300),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.sm,
          ),
          decoration: BoxDecoration(
            color: NataloColors.primarySoft,
            borderRadius: AppRadius.pill,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (message.auto) ...[
                const Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.smart_toy_outlined,
                      size: 12,
                      color: NataloColors.primaryNavy,
                    ),
                    SizedBox(width: 4),
                    Text(
                      'Balasan otomatis',
                      style: TextStyle(
                        color: NataloColors.primaryNavy,
                        fontSize: 10,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 0.2,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
              ],
              Text(
                label,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: NataloColors.primaryNavy,
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  height: 1.3,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
