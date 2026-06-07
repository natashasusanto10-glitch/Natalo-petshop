import 'dart:io';
import 'dart:typed_data';

import 'package:intl/intl.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';

import 'api_client.dart';

/// Helper untuk generate dokumen yang admin sering butuh:
///   - PDF label resi pengiriman (untuk print + tempel di paket)
///   - CSV export semua order (untuk laporan bulanan)
///
/// Pattern: builder method (return Uint8List) + share method (write
/// file ke temp dir lalu open native share dialog). Print method pakai
/// `printing` package — di Android, akan munculkan share-to-printer-app
/// (mis. Mopria, HP Smart, Canon Print, dll).
class AdminExportService {
  AdminExportService._();
  static final AdminExportService instance = AdminExportService._();

  static final _idn = NumberFormat.decimalPattern('id_ID');
  static final _dateLong = DateFormat('dd MMMM yyyy HH:mm', 'id_ID');
  static final _dateShort = DateFormat('yyyy-MM-dd', 'id_ID');

  // ─────────────────── Label Resi PDF ───────────────────

  /// Generate PDF label resi (100mm x 150mm — thermal printer standard).
  /// `order` adalah JSON dari GET /api/admin/orders/[orderNumber].
  Future<List<int>> buildResiPdf(Map<String, dynamic> order) async {
    final pdf = pw.Document(
      title: 'Resi ${order['orderNumber']}',
      author: 'Natalo Petshop',
    );

    final orderNumber = (order['orderNumber'] ?? '-').toString();
    final customerName = (order['customerName'] ?? '-').toString();
    final customerPhone = (order['customerPhone'] ?? '-').toString();
    final address = _buildFullAddress(order);
    final trackingNumber = order['trackingNumber']?.toString() ?? '';
    final courier = _formatCourier(order);
    final items = (order['items'] as List?) ?? const [];
    final total = (order['total'] as num?)?.toInt() ?? 0;
    final createdAt = order['createdAt']?.toString();

    pdf.addPage(
      pw.Page(
        // 100mm x 150mm standar thermal printer A6-ish landscape format.
        // Bisa juga di-print di A4 kertas biasa.
        pageFormat: const PdfPageFormat(
          100 * PdfPageFormat.mm,
          150 * PdfPageFormat.mm,
          marginAll: 4 * PdfPageFormat.mm,
        ),
        build: (context) => pw.Column(
          crossAxisAlignment: pw.CrossAxisAlignment.start,
          children: [
            // Header: brand + nomor order.
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('NATALO PETSHOP',
                    style: pw.TextStyle(
                        fontSize: 12, fontWeight: pw.FontWeight.bold)),
                pw.Text(orderNumber,
                    style: const pw.TextStyle(fontSize: 9)),
              ],
            ),
            pw.SizedBox(height: 4),
            pw.Divider(thickness: 1.2, height: 1),
            pw.SizedBox(height: 6),

            // Kurir + resi (paling penting, font besar).
            if (courier.isNotEmpty)
              pw.Text(courier,
                  style: pw.TextStyle(
                      fontSize: 14, fontWeight: pw.FontWeight.bold)),
            if (trackingNumber.isNotEmpty) ...[
              pw.SizedBox(height: 2),
              pw.Text('Resi: $trackingNumber',
                  style: pw.TextStyle(
                      fontSize: 12, fontWeight: pw.FontWeight.bold)),
            ],
            pw.SizedBox(height: 8),

            // Penerima.
            pw.Text('PENERIMA',
                style: pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey700)),
            pw.SizedBox(height: 2),
            pw.Text(customerName,
                style: pw.TextStyle(
                    fontSize: 11, fontWeight: pw.FontWeight.bold)),
            pw.Text(customerPhone,
                style: const pw.TextStyle(fontSize: 10)),
            pw.SizedBox(height: 3),
            pw.Text(address, style: const pw.TextStyle(fontSize: 9.5)),
            pw.SizedBox(height: 8),

            // Pengirim (toko).
            pw.Text('PENGIRIM',
                style: pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey700)),
            pw.SizedBox(height: 2),
            pw.Text('Natalo Petshop',
                style: pw.TextStyle(
                    fontSize: 10, fontWeight: pw.FontWeight.bold)),
            pw.Text('natalopetshop.com',
                style: const pw.TextStyle(fontSize: 9)),
            pw.SizedBox(height: 8),

            pw.Divider(thickness: 0.5, height: 1),
            pw.SizedBox(height: 4),

            // Daftar barang ringkas.
            pw.Text('ISI PAKET (${items.length} item)',
                style: pw.TextStyle(
                    fontSize: 8, color: PdfColors.grey700)),
            pw.SizedBox(height: 2),
            for (final item in items.take(8))
              pw.Padding(
                padding: const pw.EdgeInsets.only(bottom: 1),
                child: pw.Row(
                  children: [
                    pw.Expanded(
                      child: pw.Text(
                        '${item['quantity'] ?? 1}x ${item['name'] ?? '-'}'
                        '${item['variantLabel'] != null ? ' (${item['variantLabel']})' : ''}',
                        style: const pw.TextStyle(fontSize: 8),
                        maxLines: 1,
                        overflow: pw.TextOverflow.clip,
                      ),
                    ),
                  ],
                ),
              ),
            if (items.length > 8)
              pw.Text('+${items.length - 8} item lagi',
                  style: pw.TextStyle(
                      fontSize: 8, color: PdfColors.grey600)),

            pw.Spacer(),

            // Footer: total + tanggal.
            pw.Divider(thickness: 0.5, height: 1),
            pw.SizedBox(height: 4),
            pw.Row(
              mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
              children: [
                pw.Text('Rp ${_idn.format(total)}',
                    style: pw.TextStyle(
                        fontSize: 11, fontWeight: pw.FontWeight.bold)),
                pw.Text(
                  createdAt != null
                      ? _dateLong.format(
                          DateTime.tryParse(createdAt)?.toLocal() ??
                              DateTime.now())
                      : '',
                  style: const pw.TextStyle(fontSize: 8),
                ),
              ],
            ),
          ],
        ),
      ),
    );

    return pdf.save();
  }

  /// Print resi via dialog native Android (Mopria / HP Smart / dll).
  Future<void> printResi(Map<String, dynamic> order) async {
    final bytes = await buildResiPdf(order);
    await Printing.layoutPdf(
      onLayout: (_) async => Uint8List.fromList(bytes),
      name: 'Resi ${order['orderNumber']}',
    );
  }

  /// Share resi PDF via WA/Drive/Gmail. File disimpan di temp dir,
  /// open share sheet, sheet auto-disclose & cleanup oleh OS.
  Future<void> shareResi(Map<String, dynamic> order) async {
    final bytes = await buildResiPdf(order);
    final dir = await getTemporaryDirectory();
    final file = File(
      '${dir.path}/resi_${order['orderNumber']}.pdf',
    );
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'application/pdf')],
      subject: 'Resi ${order['orderNumber']}',
      text: 'Label resi pengiriman ${order['orderNumber']}',
    );
  }

  String _buildFullAddress(Map<String, dynamic> order) {
    final parts = <String>[];
    final addr = order['shippingAddress']?.toString();
    final city = order['shippingCity']?.toString();
    final postal = order['shippingPostalCode']?.toString();
    if (addr != null && addr.isNotEmpty) parts.add(addr);
    if (city != null && city.isNotEmpty) parts.add(city);
    if (postal != null && postal.isNotEmpty) parts.add(postal);
    return parts.join(', ');
  }

  String _formatCourier(Map<String, dynamic> order) {
    final code = order['courierCode']?.toString().toUpperCase() ?? '';
    final service = order['courierService']?.toString() ?? '';
    if (code.isEmpty && service.isEmpty) return '';
    if (code.isEmpty) return service;
    if (service.isEmpty) return code;
    return '$code — $service';
  }

  // ─────────────────── Export Order CSV ───────────────────

  /// Fetch semua order dalam range tanggal lalu generate CSV.
  /// `startDate` & `endDate` di-format yyyy-MM-dd (local timezone).
  ///
  /// Catatan: pakai endpoint GET /api/admin/orders (limit 100/page,
  /// loop cursor sampai habis). Untuk dataset besar (>1000 order),
  /// pertimbangkan dedicated endpoint backend dengan streaming.
  Future<List<int>> buildOrdersCsv({
    String? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    // Fetch semua page (max 50 page untuk safety).
    final allOrders = <Map<String, dynamic>>[];
    String? cursor;
    for (var page = 0; page < 50; page++) {
      final data = await adminApi.getJson(
        '/api/admin/orders',
        query: {
          if (status != null && status != 'all') 'status': status,
          'limit': 100,
          if (cursor != null) 'cursor': cursor,
        },
      );
      if (data is! Map<String, dynamic>) break;
      final orders = data['orders'];
      if (orders is! List) break;
      allOrders.addAll(orders.whereType<Map<String, dynamic>>());
      cursor = data['nextCursor']?.toString();
      if (cursor == null || cursor.isEmpty) break;
    }

    // Filter date range client-side (backend belum support).
    final filtered = allOrders.where((o) {
      final createdStr = o['createdAt']?.toString();
      if (createdStr == null) return false;
      final created = DateTime.tryParse(createdStr);
      if (created == null) return false;
      if (startDate != null && created.isBefore(startDate)) return false;
      if (endDate != null &&
          created.isAfter(endDate.add(const Duration(days: 1)))) {
        return false;
      }
      return true;
    }).toList();

    // CSV columns. Excel/Sheets compatible. Quote semua string yang
    // kemungkinan punya koma (alamat, nama produk).
    final buffer = StringBuffer();
    buffer.writeln(
      'No. Order,Tanggal,Customer,HP,Alamat,Kota,Items,Subtotal,Ongkir,Diskon,Total,Status,Kurir,Resi',
    );
    for (final o in filtered) {
      final items = (o['items'] as List?) ?? const [];
      final itemSummary = items
          .take(5)
          .map((i) => '${i['quantity'] ?? 1}x${i['name'] ?? ''}')
          .join(' | ');
      final extra = items.length > 5 ? ' +${items.length - 5} item' : '';

      buffer.writeln([
        _csv(o['orderNumber']),
        _csv(_dateShort.format(
            DateTime.tryParse(o['createdAt']?.toString() ?? '')?.toLocal() ??
                DateTime.now())),
        _csv(o['customerName']),
        _csv(o['customerPhone']),
        _csv(o['shippingAddress']),
        _csv(o['shippingCity']),
        _csv('$itemSummary$extra'),
        '${(o['subtotal'] as num?)?.toInt() ?? 0}',
        '${(o['shippingCost'] as num?)?.toInt() ?? 0}',
        '${(o['discount'] as num?)?.toInt() ?? 0}',
        '${(o['total'] as num?)?.toInt() ?? 0}',
        _csv(o['status']),
        _csv(o['courierCode']),
        _csv(o['trackingNumber']),
      ].join(','));
    }

    // UTF-8 dengan BOM supaya Excel buka dengan benar (huruf é, dst).
    final csvString = buffer.toString();
    return [0xEF, 0xBB, 0xBF, ...csvString.codeUnits];
  }

  /// Share CSV via app native dialog.
  Future<void> shareOrdersCsv({
    String? status,
    DateTime? startDate,
    DateTime? endDate,
  }) async {
    final bytes = await buildOrdersCsv(
      status: status,
      startDate: startDate,
      endDate: endDate,
    );
    final dir = await getTemporaryDirectory();
    final dateLabel = startDate != null && endDate != null
        ? '${_dateShort.format(startDate)}_to_${_dateShort.format(endDate)}'
        : _dateShort.format(DateTime.now());
    final file = File('${dir.path}/orders_$dateLabel.csv');
    await file.writeAsBytes(bytes);
    await Share.shareXFiles(
      [XFile(file.path, mimeType: 'text/csv')],
      subject: 'Laporan Order $dateLabel',
      text: 'Export order Natalo Petshop — $dateLabel',
    );
  }

  String _csv(dynamic v) {
    if (v == null) return '""';
    final s = v.toString().replaceAll('"', '""');
    return '"$s"';
  }
}
