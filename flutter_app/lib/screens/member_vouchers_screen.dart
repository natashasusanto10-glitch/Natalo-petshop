import 'package:flutter/material.dart';

import '../widgets/stub_screen.dart';

class MemberVouchersScreen extends StatelessWidget {
  const MemberVouchersScreen({super.key});

  @override
  Widget build(BuildContext context) => const StubScreen(
        title: 'Voucher',
        icon: Icons.local_offer_outlined,
      );
}
