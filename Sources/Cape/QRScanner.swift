import Foundation
import Vision

/// Reads QR codes in an image, on-device with Vision. The buffer runs it on
/// every copied image (a screenshot to the clipboard, "Copy Image" in a
/// browser…) and files each code's contents — usually a link — as its own
/// entry. Nothing is captured from the screen, so no extra permission.
enum QRScanner {
    /// QR payloads in the image, top to bottom, without duplicates.
    static func codes(in image: URL) -> [String] {
        let request = VNDetectBarcodesRequest()
        request.symbologies = [.qr]
        try? VNImageRequestHandler(url: image).perform([request])
        var payloads: [String] = []
        for code in (request.results ?? []).sorted(by: { $0.boundingBox.midY > $1.boundingBox.midY }) {
            // Vision's y grows upward, hence the descending sort.
            if let text = code.payloadStringValue, !text.isEmpty, !payloads.contains(text) {
                payloads.append(text)
            }
        }
        return payloads
    }

    /// Short label for the notch flash: the link's host, or the start of the text.
    static func label(_ payload: String) -> String {
        if let url = URL(string: payload), let host = url.host, url.scheme != nil {
            return host.hasPrefix("www.") ? String(host.dropFirst(4)) : host
        }
        let line = payload.split(whereSeparator: \.isNewline).first.map(String.init) ?? payload
        return line.count > 22 ? String(line.prefix(21)) + "…" : line
    }
}
