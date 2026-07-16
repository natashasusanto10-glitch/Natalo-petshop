import '../models/member_profile.dart';

/// Builds the versioned order-context payload accepted by the internal chat.
///
/// The server validates ownership and reconstructs the authoritative order
/// summary. This client payload makes the selected order explicit so a
/// customer can ask about an older order in the same NLCATTER conversation.
Map<String, dynamic> buildOrderChatContext(OrderSummary order) {
  final hasPaymentProof = (order.paymentProofUrl ?? '').trim().isNotEmpty;
  return {
    'type': 'order',
    'orderNumber': order.orderNumber,
    'schemaVersion': 1,
    'order': {
      'orderNumber': order.orderNumber,
      'status': order.status,
      'paymentStatus': order.paymentStatus,
      'paymentProofStatus': order.paymentProofStatus ??
          (hasPaymentProof ? 'PENDING_REVIEW' : null),
      'total': order.total.round(),
      'itemCount': order.itemCount,
      'hasPaymentProof': hasPaymentProof,
      'proofVersion': order.paymentProofVersion,
      'createdAt': order.createdAt.millisecondsSinceEpoch,
    },
  };
}

/// Only order contexts entered from an order action become their own message
/// immediately. Product contexts retain the existing "attach to first typed
/// message" interaction.
bool shouldAutoForwardOrderContext({
  required Map<String, dynamic>? context,
  required bool contextAlreadySent,
}) =>
    !contextAlreadySent && context?['type'] == 'order';
