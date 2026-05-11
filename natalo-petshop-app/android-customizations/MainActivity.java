package com.natalopetshop.app;

import android.content.Intent;
import android.net.Uri;
import android.os.Bundle;
import android.webkit.WebView;
import android.webkit.WebViewClient;

import com.getcapacitor.BridgeActivity;

public class MainActivity extends BridgeActivity {

    @Override
    public void onCreate(Bundle savedInstanceState) {
        super.onCreate(savedInstanceState);

        // Intercept URL clicks: kirim WhatsApp/email/tel/external ke app native
        WebView webView = this.bridge.getWebView();
        webView.setWebViewClient(new WebViewClient() {
            @Override
            public boolean shouldOverrideUrlLoading(WebView view, String url) {
                // Domain natalopetshop.com → tetap di webview
                if (url.contains("natalopetshop.com")) {
                    return false;
                }

                // wa.me, whatsapp://, mailto:, tel:, intent: → buka app native
                if (url.startsWith("whatsapp://")
                    || url.startsWith("https://wa.me/")
                    || url.startsWith("http://wa.me/")
                    || url.startsWith("https://api.whatsapp.com/")
                    || url.startsWith("mailto:")
                    || url.startsWith("tel:")
                    || url.startsWith("sms:")
                    || url.startsWith("intent://")
                    || url.startsWith("market://")) {
                    try {
                        Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        startActivity(intent);
                        return true;
                    } catch (Exception e) {
                        return false;
                    }
                }

                // Domain lain (Instagram, Maps, dll) → buka di Chrome/browser eksternal
                if (url.startsWith("http://") || url.startsWith("https://")) {
                    try {
                        Intent intent = new Intent(Intent.ACTION_VIEW, Uri.parse(url));
                        intent.addFlags(Intent.FLAG_ACTIVITY_NEW_TASK);
                        startActivity(intent);
                        return true;
                    } catch (Exception e) {
                        return false;
                    }
                }

                return false;
            }
        });
    }
}
