/**
 * Isi nama, nomor HP & ringkasan belanja di chat customer yang masih tampil
 * "Pelanggan" di NLCHAT (room lahir dari kartu bukti transfer web, sebelum
 * kartu ikut menulis data pembeli).
 *
 * Bawaan: HANYA menampilkan rencana perubahan. Tulis sungguhan dengan --apply.
 *   npx dotenv -e .env -- tsx scripts/backfill-chat-customer-names.ts
 *   npx dotenv -e .env -- tsx scripts/backfill-chat-customer-names.ts --apply
 *
 * Hanya menyentuh customerName/customerPhone/summary/summaryUpdatedAt; urutan
 * chat (lastMessageAt) dan isi pesan tidak diubah. Nama/nomor kosong tidak
 * pernah ditulis (lihat customerSnapshotRoomFields).
 */
import { getTokochatFirestore } from "@/lib/chat/firestore-admin";
import { loadCustomerSnapshot } from "@/lib/chat/customer-snapshot";
import { customerSnapshotRoomFields } from "@/lib/chat/rooms";
import { prisma } from "@/lib/prisma";

async function main() {
  const apply = process.argv.includes("--apply");
  const db = getTokochatFirestore();
  const rooms = await db.collection("customerChats").get();
  let candidates = 0;
  let updated = 0;
  let noName = 0;

  for (const doc of rooms.docs) {
    const data = doc.data();
    const name = typeof data.customerName === "string" ? data.customerName.trim() : "";
    if (name) continue;
    const customerId = typeof data.customerId === "string" ? data.customerId : "";
    if (!customerId) continue;
    candidates += 1;

    const snapshot = await loadCustomerSnapshot(customerId);
    const fields = customerSnapshotRoomFields(snapshot);
    if (!fields.customerName) noName += 1;
    console.log(
      `${apply ? "TULIS" : "RENCANA"} ${doc.id}: nama="${fields.customerName ?? "(tetap kosong)"}"` +
        ` belanja=${snapshot.summary.orderCount} pesanan`,
    );
    if (apply) {
      await doc.ref.set(fields, { merge: true });
      updated += 1;
    }
  }

  console.log(
    `\nSelesai. ${rooms.size} chat diperiksa, ${candidates} tanpa nama, ` +
      `${apply ? `${updated} diperbarui` : "belum ada yang ditulis (pakai --apply)"}, ` +
      `${noName} tetap tanpa nama (akun & pesanan tak punya nama).`,
  );
}

main()
  .catch((error) => {
    console.error(error);
    process.exitCode = 1;
  })
  .finally(() => prisma.$disconnect());
