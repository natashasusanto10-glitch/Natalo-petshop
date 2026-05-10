//
//  SwipeBackPlugin.swift
//  Natalo Petshop iOS shell.
//
//  Mengaktifkan native iOS edge-swipe gesture untuk WKWebView
//  (allowsBackForwardNavigationGestures). User bisa swipe dari edge kiri
//  layar untuk trigger history.back() — behavior native Safari-style.
//
//  Default: enable saat plugin load (cold start app).
//
//  JS API:
//    SwipeBack.enable()    — aktifkan gesture
//    SwipeBack.disable()   — matikan gesture (untuk halaman dgn carousel
//                            horizontal di edge kiri biar tidak konflik
//                            mis. /onboarding, /checkout, /login)
//    SwipeBack.isEnabled() — query status saat ini
//
//  Pattern: Capacitor 8 CAPBridgedPlugin (new-style). Auto-discovered oleh
//  runtime introspection — TIDAK perlu register manual di
//  capacitor.config.ts atau AppDelegate.
//

import Capacitor
import WebKit

@objc(SwipeBackPlugin)
public class SwipeBackPlugin: CAPPlugin, CAPBridgedPlugin {
    public let identifier = "SwipeBackPlugin"
    public let jsName = "SwipeBack"
    public let pluginMethods: [CAPPluginMethod] = [
        CAPPluginMethod(name: "enable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "disable", returnType: CAPPluginReturnPromise),
        CAPPluginMethod(name: "isEnabled", returnType: CAPPluginReturnPromise),
    ]

    /// Dipanggil saat plugin di-load oleh bridge (cold start). Set default
    /// gesture aktif supaya behavior global = swipe-back enabled.
    public override func load() {
        DispatchQueue.main.async { [weak self] in
            self?.bridge?.webView?.allowsBackForwardNavigationGestures = true
        }
    }

    @objc func enable(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            guard let webView = self?.bridge?.webView else {
                call.reject("WebView belum siap")
                return
            }
            webView.allowsBackForwardNavigationGestures = true
            call.resolve(["enabled": true])
        }
    }

    @objc func disable(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            guard let webView = self?.bridge?.webView else {
                call.reject("WebView belum siap")
                return
            }
            webView.allowsBackForwardNavigationGestures = false
            call.resolve(["enabled": false])
        }
    }

    @objc func isEnabled(_ call: CAPPluginCall) {
        DispatchQueue.main.async { [weak self] in
            let value = self?.bridge?.webView?.allowsBackForwardNavigationGestures ?? false
            call.resolve(["enabled": value])
        }
    }
}
