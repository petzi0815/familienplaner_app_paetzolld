import SwiftUI
import UIKit

/// Öffnet einen Freitext-Ort direkt in Google Maps: bevorzugt die installierte Google-Maps-App
/// (URL-Schema `comgooglemaps://`, deshalb steht `comgooglemaps` in `LSApplicationQueriesSchemes`),
/// sonst der universelle HTTPS-Link (öffnet die App per Universal Link bzw. Google Maps im Browser).
enum MapsOpener {
    static func open(_ rawLocation: String) {
        let location = rawLocation.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !location.isEmpty else { return }
        // Sub-Delimiter (& + = ? # /) aus dem erlaubten Satz nehmen, sonst koennte ein Ort mit '&'
        // die Query zerlegen; Leerzeichen sind ohnehin nicht in urlQueryAllowed -> werden zu %20.
        let allowed = CharacterSet.urlQueryAllowed.subtracting(CharacterSet(charactersIn: "&+=?#/"))
        let q = location.addingPercentEncoding(withAllowedCharacters: allowed) ?? location
        if let appURL = URL(string: "comgooglemaps://?q=\(q)"), UIApplication.shared.canOpenURL(appURL) {
            UIApplication.shared.open(appURL)
        } else if let webURL = URL(string: "https://www.google.com/maps/search/?api=1&query=\(q)") {
            UIApplication.shared.open(webURL)
        }
    }
}

/// Antippbarer Ort (Kartennadel + Text). Tippen öffnet den Ort direkt in Google Maps.
/// Als Link erkennbar (blau); eigener Tap-Bereich, damit er in Listenzeilen nicht die Zeile aktiviert.
struct LocationLink: View {
    let location: String
    var body: some View {
        Button {
            UISelectionFeedbackGenerator().selectionChanged()
            MapsOpener.open(location)
        } label: {
            HStack(spacing: 3) {
                Image(systemName: "mappin.and.ellipse")
                Text(location).lineLimit(1)
            }
            .font(.caption)
            .foregroundStyle(.blue)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("agenda-location")
        .accessibilityLabel("Ort \(location), in Google Maps öffnen")
    }
}
