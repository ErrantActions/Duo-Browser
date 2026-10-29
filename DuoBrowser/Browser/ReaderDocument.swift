import CoreText
import UIKit

enum ReaderError: LocalizedError {
    case unavailable(String), invalidDocument, changedPage, invalidPDF

    var errorDescription: String? {
        switch self {
        case .unavailable(let message): return message
        case .invalidDocument: return "This page has no readable article, or exceeds the supported reading limits."
        case .changedPage: return "The page changed while Reading View was opening. Open it again."
        case .invalidPDF: return "The reading PDF could not be completed within the export limits. Nothing was shared."
        }
    }
}

struct ReaderBlock: Identifiable, Decodable, Equatable, Sendable {
    enum Kind: String, Decodable, Sendable { case heading, body, list, quote, code }
    var id: Int
    let kind: Kind
    let level: Int
    let text: String
}

struct ReaderDocument: Sendable {
    let tabID: UUID
    let navigationID: UUID
    let sourceURL: URL
    let title: String
    let language: String
    let blocks: [ReaderBlock]
    let truncated: Bool

    private struct Raw: Decodable {
        struct Block: Decodable { let kind: ReaderBlock.Kind; let level: Int; let text: String }
        let url: String
        let documentID: String
        let title: String
        let language: String
        let blocks: [Block]
        let truncated: Bool
    }

    init(data: Data, tabID: UUID, navigationID: UUID, sourceURL: URL) throws {
        guard data.count <= 262_144, Self.allowedSource(sourceURL) else { throw ReaderError.invalidDocument }
        let raw = try JSONDecoder().decode(Raw.self, from: data)
        guard URL(string: raw.url) == sourceURL, UUID(uuidString: raw.documentID) != nil,
              !raw.blocks.isEmpty, raw.blocks.count <= 400 else { throw ReaderError.invalidDocument }
        self.tabID = tabID
        self.navigationID = navigationID
        self.sourceURL = sourceURL
        title = String(raw.title.prefix(160))
        language = String(raw.language.prefix(20))
        truncated = raw.truncated
        var result: [ReaderBlock] = []
        var total = 0
        for item in raw.blocks {
            let text = item.text.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !text.isEmpty, text.count <= 4000, (0...3).contains(item.level) else { throw ReaderError.invalidDocument }
            total += text.count
            guard total <= 30_000 else { throw ReaderError.invalidDocument }
            if result.isEmpty, item.kind == .heading, text == title { continue }
            result.append(ReaderBlock(id: result.count, kind: item.kind, level: item.level, text: text))
        }
        guard !result.isEmpty else { throw ReaderError.invalidDocument }
        blocks = result
    }

    static func allowedSource(_ url: URL) -> Bool {
        if DuoOrigin.canonical(url) == "duo-demo" { return true }
        return ["https", "http"].contains(url.scheme?.lowercased() ?? "")
            && url.host?.isEmpty == false && url.user == nil && url.password == nil
    }

    var bodyText: String {
        blocks.map { $0.kind == .list ? "• \($0.text)" : $0.text }.joined(separator: "\n\n")
    }

    var spokenText: String { blocks.map(\.text).joined(separator: "\n\n") }
    var wordCount: Int { spokenText.split(whereSeparator: \.isWhitespace).count }
    var minutesToRead: Int { max(1, Int(ceil(Double(wordCount) / 220))) }
    var attribution: String { sourceURL.host ?? "DuoKit Demo" }

    @MainActor
    func isCurrent(for model: BrowserViewModel) -> Bool {
        model.id == tabID && model.navigationID == navigationID && model.webView.url == sourceURL
            && AskDuoPageReader.readingBlockedReason(for: model) == nil
    }
}

@MainActor
enum ReadingPDF {
    static func data(for document: ReaderDocument) throws -> Data {
        let text = NSMutableAttributedString(string: document.title + "\n\n", attributes: [
            .font: UIFont.systemFont(ofSize: 22, weight: .bold), .foregroundColor: UIColor.black
        ])
        text.append(NSAttributedString(string: "Source: \(document.attribution)\n\n", attributes: [
            .font: UIFont.systemFont(ofSize: 11), .foregroundColor: UIColor.darkGray
        ]))
        text.append(NSAttributedString(string: document.bodyText, attributes: [
            .font: UIFont.systemFont(ofSize: 14), .foregroundColor: UIColor.black
        ]))
        let size = CGRect(x: 0, y: 0, width: 595, height: 842)
        let printable = size.insetBy(dx: 44, dy: 44)
        let framesetter = CTFramesetterCreateWithAttributedString(text as CFAttributedString)
        let renderer = UIGraphicsPDFRenderer(bounds: size)
        var failed = false
        let data = renderer.pdfData { context in
            var position = 0
            var page = 0
            while position < text.length {
                guard page < 64 else { failed = true; break }
                context.beginPage()
                let canvas = context.cgContext
                canvas.saveGState()
                canvas.translateBy(x: 0, y: size.height)
                canvas.scaleBy(x: 1, y: -1)
                let frame = CTFramesetterCreateFrame(
                    framesetter, CFRange(location: position, length: 0),
                    CGPath(rect: printable, transform: nil), nil
                )
                let count = CTFrameGetVisibleStringRange(frame).length
                guard count > 0 else {
                    canvas.restoreGState()
                    failed = true
                    break
                }
                CTFrameDraw(frame, canvas)
                canvas.restoreGState()
                position += count
                page += 1
            }
        }
        guard !failed, !data.isEmpty, data.count <= 20 * 1024 * 1024 else { throw ReaderError.invalidPDF }
        return data
    }
}
