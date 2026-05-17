//
//  NotificationService.swift
//  Natalo Petshop — Notification Service Extension
//
//  Wave 4 #9 — Push notification rich content.
//
//  iOS deliver push dengan `mutable-content: 1` ke extension ini dulu
//  sebelum tampil ke user. Extension punya 30 detik untuk:
//    - Download image attachment dari URL di custom payload
//    - Attach ke notification content
//    - Modify body / title kalau perlu (mis. translate)
//    - Call contentHandler dengan modified content
//
//  Kalau timeout / error, fallback ke text-only notification (iOS
//  automatic fallback via serviceExtensionTimeWillExpire).
//
//  Setup di Xcode:
//    1. File → New → Target → Notification Service Extension
//    2. Product Name: "NotificationServiceExtension"
//    3. Embed Without Signing di app target General → Frameworks
//    4. Bundle Identifier: com.natalo.petshop.NotificationServiceExtension
//    5. Add ATS exception untuk image CDN (Bunny) di Info.plist
//

import UserNotifications
import os.log

class NotificationService: UNNotificationServiceExtension {

    var contentHandler: ((UNNotificationContent) -> Void)?
    var bestAttemptContent: UNMutableNotificationContent?
    private let log = OSLog(subsystem: "com.natalo.petshop.NSE", category: "rich-notif")

    override func didReceive(
        _ request: UNNotificationRequest,
        withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void
    ) {
        self.contentHandler = contentHandler
        bestAttemptContent = (request.content.mutableCopy() as? UNMutableNotificationContent)

        guard let bestAttemptContent = bestAttemptContent else {
            contentHandler(request.content)
            return
        }

        // Server (lib/apns.ts) inject `attachment-url` di custom payload.
        // Kalau tidak ada, deliver text-only notification.
        guard let attachmentUrlString = bestAttemptContent.userInfo["attachment-url"] as? String,
              let attachmentUrl = URL(string: attachmentUrlString) else {
            os_log("no attachment-url, deliver text-only", log: log, type: .debug)
            contentHandler(bestAttemptContent)
            return
        }

        // Download image async + attach. Pakai URLSession default config
        // (NSE punya network access tapi limited time budget ~30s).
        let task = URLSession.shared.downloadTask(with: attachmentUrl) { [weak self] (downloadedUrl, response, error) in
            guard let self = self else { return }

            if let error = error {
                os_log("download failed: %@", log: self.log, type: .error, error.localizedDescription)
                contentHandler(bestAttemptContent)
                return
            }

            guard let downloadedUrl = downloadedUrl else {
                contentHandler(bestAttemptContent)
                return
            }

            // Pindah ke temp dir dengan extension yang benar — iOS sniff
            // file type dari extension, bukan content. Bunny thumbnail
            // default JPEG, fallback ke .jpg kalau MIME tidak terdeteksi.
            let fileManager = FileManager.default
            let tmpUrl = fileManager.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(self.fileExtensionForResponse(response, url: attachmentUrl))

            do {
                try fileManager.moveItem(at: downloadedUrl, to: tmpUrl)

                let attachment = try UNNotificationAttachment(
                    identifier: "thumbnail",
                    url: tmpUrl,
                    options: [
                        // Hint thumbnail-only — UN tampil sebagai inline
                        // image, bukan full-screen attachment view.
                        UNNotificationAttachmentOptionsThumbnailHiddenKey: false,
                    ]
                )
                bestAttemptContent.attachments = [attachment]
                os_log("attached image successfully", log: self.log, type: .debug)
            } catch {
                os_log("attach failed: %@", log: self.log, type: .error, error.localizedDescription)
            }

            contentHandler(bestAttemptContent)
        }
        task.resume()
    }

    override func serviceExtensionTimeWillExpire() {
        // iOS panggil ini saat 30s budget hampir habis. Deliver dengan
        // konten apa pun yang sudah ada (tanpa attachment kalau download
        // belum selesai).
        if let contentHandler = contentHandler, let bestAttemptContent = bestAttemptContent {
            os_log("timeout, deliver partial content", log: log, type: .info)
            contentHandler(bestAttemptContent)
        }
    }

    /// Derive file extension dari HTTP response MIME atau fallback ke URL
    /// path extension. Default jpg supaya iOS bisa decode attachment.
    private func fileExtensionForResponse(_ response: URLResponse?, url: URL) -> String {
        if let mime = response?.mimeType?.lowercased() {
            switch mime {
            case "image/jpeg", "image/jpg": return "jpg"
            case "image/png": return "png"
            case "image/gif": return "gif"
            case "image/webp": return "webp"
            case "video/mp4": return "mp4"
            default: break
            }
        }
        let ext = url.pathExtension.lowercased()
        if !ext.isEmpty && ["jpg", "jpeg", "png", "gif", "webp", "mp4"].contains(ext) {
            return ext
        }
        return "jpg"
    }
}
