import UserNotifications

/// Notification-Service-Extension — hängt das Cover an eine eingehende Push-Mitteilung.
///
/// iOS zeigt in einer Remote-Mitteilung NUR dann ein Bild, wenn eine Extension es als
/// `UNNotificationAttachment` anhängt. Der Server setzt dafür `mutable-content: 1` und legt die
/// Bild-URL als `image_url` in den Payload (signierte, kurzlebige Backend-URL — die Extension
/// schickt keinen Bearer-Token mit, siehe `server/push/cover.ts`).
///
/// Regeln des Systems: die Extension hat ~30 s, danach ruft iOS `serviceExtensionTimeWillExpire()`
/// auf. In JEDEM Fall muss der Handler genau einmal aufgerufen werden — sonst erscheint die
/// Mitteilung gar nicht. Deshalb: bei jedem Fehler der unveränderte Inhalt.
final class NotificationService: UNNotificationServiceExtension {

    private var contentHandler: ((UNNotificationContent) -> Void)?
    private var bestAttempt: UNMutableNotificationContent?
    private var task: URLSessionDownloadTask?

    override func didReceive(_ request: UNNotificationRequest,
                             withContentHandler contentHandler: @escaping (UNNotificationContent) -> Void) {
        self.contentHandler = contentHandler
        let content = (request.content.mutableCopy() as? UNMutableNotificationContent)
        bestAttempt = content

        guard let content,
              let urlString = content.userInfo["image_url"] as? String,
              let url = URL(string: urlString) else {
            contentHandler(request.content)
            return
        }

        // Eigene Konfiguration statt `.shared`: in einer Extension ist die geteilte Session
        // eingeschränkt, und ein enges Timeout hält uns sicher unter der 30-Sekunden-Grenze.
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 12
        config.timeoutIntervalForResource = 20
        let session = URLSession(configuration: config)

        task = session.downloadTask(with: url) { [weak self] tempURL, response, _ in
            guard let self else { return }
            defer { self.deliver() }
            guard let tempURL,
                  let http = response as? HTTPURLResponse, http.statusCode == 200 else { return }

            // Die Datei muss eine passende Endung tragen, sonst lehnt UNNotificationAttachment sie ab.
            let ext = Self.fileExtension(for: http.mimeType, url: url)
            let target = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .appendingPathExtension(ext)
            do {
                try FileManager.default.moveItem(at: tempURL, to: target)
                let attachment = try UNNotificationAttachment(identifier: "cover", url: target, options: nil)
                self.bestAttempt?.attachments = [attachment]
            } catch {
                try? FileManager.default.removeItem(at: target)
            }
        }
        task?.resume()
    }

    override func serviceExtensionTimeWillExpire() {
        // Letzte Chance: liefern, was bis hierher da ist (ggf. ohne Bild).
        task?.cancel()
        deliver()
    }

    /// Ruft den Handler genau EINMAL auf (Timeout und Download können sonst beide feuern).
    private func deliver() {
        guard let handler = contentHandler else { return }
        contentHandler = nil
        handler(bestAttempt ?? UNMutableNotificationContent())
    }

    private static func fileExtension(for mimeType: String?, url: URL) -> String {
        switch mimeType?.lowercased() {
        case "image/png": return "png"
        case "image/gif": return "gif"
        case "image/heic": return "heic"
        case "image/jpeg", "image/jpg": return "jpg"
        default:
            let ext = url.pathExtension.lowercased()
            return ["png", "gif", "heic", "jpg", "jpeg"].contains(ext) ? ext : "jpg"
        }
    }
}
