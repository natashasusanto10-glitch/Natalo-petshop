package com.natalopetshop.app

import io.flutter.embedding.android.FlutterFragmentActivity

// Pakai FlutterFragmentActivity (bukan FlutterActivity) supaya local_auth
// BiometricPrompt jalan — plugin attach DialogFragment yang butuh
// FragmentManager. Tidak ada side-effect untuk plugin lain.
class MainActivity : FlutterFragmentActivity()
