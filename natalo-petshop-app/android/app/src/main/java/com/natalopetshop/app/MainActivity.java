package com.natalopetshop.app;

import android.annotation.SuppressLint;
import android.app.AlertDialog;
import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.webkit.JavascriptInterface;
import android.webkit.WebResourceError;
import android.webkit.WebResourceRequest;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import androidx.activity.OnBackPressedCallback;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {

    private static final String SITE_URL = "https://www.natalopetshop.com";
    private static final String OFFLINE_URL = "file:///android_asset/offline.html";
    private static final String ROOT_HOST = "www.natalopetshop.com";

    private boolean isShowingOffline = false;

    @Override
    @SuppressLint({"AddJavascriptInterface", "SetJavaScriptEnabled"})
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        final WebView webView = this.bridge.getWebView();

        // ── 1. URL routing: WhatsApp / mailto / tel / external app intents ──
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, WebResourceRequest request) {
                String url = request.getUrl().toString();
                return handleUrl(url);
            }

            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                return handleUrl(url);
            }

            // ── 2. Offline / error handling ──────────────────────────────
            // Tampilkan offline.html kalau load main URL gagal (timeout,
            // DNS error, host unreachable, dll). Hindari blank WebView
            // putih yang user kira app crashed.
            @Override
            public void onReceivedError(
                WebView view,
                WebResourceRequest request,
                WebResourceError error
            ) {
                super.onReceivedError(view, request, error);
                // Hanya intercept main-frame error (page itself), bukan
                // sub-resource (image, script). Sub-resource error tidak
                // boleh trigger offline page.
                if (request != null && request.isForMainFrame() && !isShowingOffline) {
                    isShowingOffline = true;
                    view.loadUrl(OFFLINE_URL);
                }
            }

            @Override
            public void onPageFinished(WebView view, String url) {
                super.onPageFinished(view, url);
                // Reset flag setelah main URL berhasil load lagi
                if (url != null && url.contains("natalopetshop.com")) {
                    isShowingOffline = false;
                }
            }
        });

        // ── 3. JS bridge utk offline.html "Tutup App" button ────────────
        webView.addJavascriptInterface(new AndroidBridge(), "AndroidBridge");

        // ── 4. Hardware back button ─────────────────────────────────────
        // Custom: kalau WebView bisa back → goBack(). Kalau di root
        // (homepage) → AlertDialog konfirmasi exit. Hindari accidental
        // app close dari product/cart/checkout pages.
        getOnBackPressedDispatcher().addCallback(this, new OnBackPressedCallback(true) {
            @Override
            public void handleOnBackPressed() {
                if (isShowingOffline) {
                    // Saat offline page tampil, back = retry load main URL
                    webView.loadUrl(SITE_URL);
                    return;
                }
                String currentUrl = webView.getUrl();
                if (currentUrl != null && isRootUrl(currentUrl)) {
                    showExitDialog();
                    return;
                }
                if (webView.canGoBack()) {
                    webView.goBack();
                    return;
                }
                showExitDialog();
            }
        });
    }

    /**
     * URL handler — return true kalau URL di-handle native, false kalau
     * biarkan WebView load normally.
     */
    private boolean handleUrl(String url) {
        // Domain natalopetshop.com → tetap di WebView
        if (url.contains("natalopetshop.com")) {
            return false;
        }

        // WhatsApp / sms / tel / mailto / intent / market → app native
        if (url.startsWith("whatsapp://")
            || url.startsWith("https://wa.me/")
            || url.startsWith("http://wa.me/")
            || url.startsWith("https://api.whatsapp.com/")
            || url.startsWith("mailto:")
            || url.startsWith("tel:")
            || url.startsWith("sms:")
            || url.startsWith("intent://")
            || url.startsWith("market://")) {
            return openExternal(url);
        }

        // Payment gateway redirect (Midtrans Snap / bank redirect) tetap
        // di WebView supaya checkout flow tidak putus. Midtrans Snap di-host
        // di app.midtrans.com & app.sandbox.midtrans.com.
        if (url.contains("midtrans.com")
            || url.contains("snap.midtrans.com")
            || url.contains("simulator.sandbox.midtrans.com")) {
            return false;
        }

        // Domain lain (eksternal link) → Chrome/browser
        if (url.startsWith("http://") || url.startsWith("https://")) {
            return openExternal(url);
        }

        return false;
    }

    private boolean openExternal(String url) {
        try {
            Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
            intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
            startActivity(intent);
            return true;
        } catch (Exception e) {
            return false;
        }
    }

    private boolean isRootUrl(String url) {
        try {
            Uri uri = Uri.parse(url);
            String host = uri.getHost();
            String path = uri.getPath();
            return host != null
                && (host.equals(ROOT_HOST) || host.equals("natalopetshop.com"))
                && (path == null || path.isEmpty() || path.equals("/"));
        } catch (Exception e) {
            return false;
        }
    }

    private void showExitDialog() {
        new AlertDialog.Builder(this)
            .setTitle("Keluar dari Natalo Petshop?")
            .setMessage("Apakah kamu yakin ingin menutup aplikasi?")
            .setPositiveButton("Keluar", (dialog, which) -> finish())
            .setNegativeButton("Batal", (dialog, which) -> dialog.dismiss())
            .setCancelable(true)
            .show();
    }

    /**
     * Bridge object untuk offline.html — supaya tombol "Tutup App" di
     * offline page bisa close activity.
     */
    private class AndroidBridge {
        @JavascriptInterface
        public void exit() {
            runOnUiThread(MainActivity.this::finish);
        }
    }
}
