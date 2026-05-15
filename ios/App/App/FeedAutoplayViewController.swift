import Capacitor
import WebKit

/**
 * Custom CAPBridgeViewController so we can tweak the underlying
 * WKWebViewConfiguration before the bridge spins up its WKWebView.
 *
 * Capacitor's default ships WKWebView with
 * `mediaTypesRequiringUserActionForPlayback = .all`, which blocks
 * autoplay until the user has tapped somewhere inside the web view.
 * That's the wrong default for a TikTok-style feed: the first video
 * needs to start the moment the page mounts. We override it to `[]`
 * (no media types require interaction) and explicitly enable inline
 * playback so muted videos can autoplay without going fullscreen.
 *
 * Wired in `Main.storyboard` — the Initial View Controller's custom
 * class is set to `FeedAutoplayViewController` (Module: App).
 */
class FeedAutoplayViewController: CAPBridgeViewController {
    override func instanceConfiguration() -> InstanceConfiguration {
        let config = super.instanceConfiguration()
        return config
    }

    override func webView(with frame: CGRect, configuration: WKWebViewConfiguration) -> WKWebView {
        // No-tap autoplay for the feed. Safe because our autoplay videos are
        // always muted (`<video muted playsinline>`) — iOS only enforces the
        // user-gesture requirement to prevent sound surprises on cold pages.
        configuration.mediaTypesRequiringUserActionForPlayback = []
        configuration.allowsInlineMediaPlayback = true
        configuration.allowsPictureInPictureMediaPlayback = false
        return super.webView(with: frame, configuration: configuration)
    }
}
