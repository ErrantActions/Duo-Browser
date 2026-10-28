import Foundation

enum JSONValue: Codable, Equatable {
    case string(String)
    case number(Double)
    case bool(Bool)
    case object([String: JSONValue])
    case array([JSONValue])
    case null

    init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self = .null }
        else if let value = try? container.decode(Bool.self) { self = .bool(value) }
        else if let value = try? container.decode(Double.self) { self = .number(value) }
        else if let value = try? container.decode(String.self) { self = .string(value) }
        else if let value = try? container.decode([String: JSONValue].self) { self = .object(value) }
        else { self = .array(try container.decode([JSONValue].self)) }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .string(let value): try container.encode(value)
        case .number(let value): try container.encode(value)
        case .bool(let value): try container.encode(value)
        case .object(let value): try container.encode(value)
        case .array(let value): try container.encode(value)
        case .null: try container.encodeNil()
        }
    }
}

struct DuoOption: Codable, Identifiable, Equatable {
    let id: String
    let label: String
}

struct DuoControl: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case button
        case toggle
        case segmented
        case menu
        case primary
        case spacer
    }

    let id: String
    let type: Kind
    let label: String
    var icon: String?
    var enabled: Bool?
    var badge: String?
    var accessibilityLabel: String?
    var requiresConfirmation: Bool?
    var payload: [String: JSONValue]?
    var value: JSONValue?
    var options: [DuoOption]?
}

struct DuoPanel: Codable, Identifiable, Equatable {
    let id: String
    var title: String?
    var accent: String?
    var controls: [DuoControl]
}

struct DuoMessage: Decodable {
    let version: String
    let documentId: String
    let method: String
    let configuration: DuoPanel?
    let requestId: String?
    let gestureToken: String?
}

struct DuoEvent: Encodable {
    let type: String
    let panelId: String?
    let controlId: String?
    let timestamp: String
    let payload: [String: JSONValue]
    let gestureToken: String?
    let requestId: String?
    let value: String?
    let format: String?
    let error: String?
}
