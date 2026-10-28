import Foundation
import CoreFoundation

struct DuoValidationError: LocalizedError {
    let errorDescription: String?
    init(_ message: String) { errorDescription = message }
}

enum DuoMessageValidator {
    static let maximumBytes = 32_768
    static let maximumControls = 8
    static let icons: Set<String> = [
        "barcode.viewfinder", "qrcode", "checkmark.circle", "plus", "minus",
        "star", "heart", "cart", "magnifyingglass", "arrow.clockwise",
        "person.crop.circle.badge.plus", "square.and.arrow.up", "list.bullet",
        "play", "pause", "stop", "chevron.left", "chevron.right", "trash"
    ]

    static func decode(_ data: Data) throws -> DuoMessage {
        guard data.count <= maximumBytes else { throw DuoValidationError("Message exceeds 32768 bytes.") }
        guard let root = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DuoValidationError("A message must be an object.")
        }
        try keys(root, required: ["version", "documentId", "method"], optional: [
            "configuration", "requestId", "gestureToken"
        ])
        guard root["version"] as? String == "1.0",
              let document = root["documentId"] as? String, UUID(uuidString: document) != nil,
              let method = root["method"] as? String else {
            throw DuoValidationError("Invalid version, document identifier, or method.")
        }
        switch method {
        case "controls.set", "controls.update":
            guard Set(root.keys) == ["version", "documentId", "method", "configuration"],
                  let panel = root["configuration"] as? [String: Any] else {
                throw DuoValidationError("A complete panel configuration is required.")
            }
            try validatePanel(panel)
        case "controls.clear", "device.capabilities":
            guard Set(root.keys) == ["version", "documentId", "method"] else {
                throw DuoValidationError("Unexpected method parameters.")
            }
        case "scanner.request":
            guard Set(root.keys) == ["version", "documentId", "method", "requestId", "gestureToken"] else {
                throw DuoValidationError("Scanner requires a requestId and gestureToken.")
            }
            try identifier(root["requestId"])
            guard let token = root["gestureToken"] as? String, UUID(uuidString: token) != nil else {
                throw DuoValidationError("Invalid gesture token.")
            }
        default:
            throw DuoValidationError("Unsupported method.")
        }
        return try JSONDecoder().decode(DuoMessage.self, from: data)
    }

    private static func validatePanel(_ panel: [String: Any]) throws {
        try keys(panel, required: ["id", "controls"], optional: ["title", "accent"])
        try identifier(panel["id"])
        try text(panel["title"], maximum: 80, optional: true)
        if let accent = panel["accent"] {
            guard let accent = accent as? String,
                  ["blue", "green", "orange", "purple", "pink"].contains(accent) else {
                throw DuoValidationError("Unsupported accent.")
            }
        }
        guard let controls = panel["controls"] as? [[String: Any]],
              !controls.isEmpty, controls.count <= maximumControls else {
            throw DuoValidationError("A panel must contain 1 to 8 controls.")
        }
        var identifiers = Set<String>()
        var visibleControls = 0
        for control in controls {
            try keys(control, required: ["id", "type", "label"], optional: [
                "icon", "enabled", "badge", "accessibilityLabel", "requiresConfirmation",
                "payload", "value", "options"
            ])
            try identifier(control["id"])
            guard let id = control["id"] as? String, identifiers.insert(id).inserted else {
                throw DuoValidationError("Control identifiers must be unique.")
            }
            try text(control["label"], maximum: 80)
            try text(control["accessibilityLabel"], maximum: 160, optional: true)
            try text(control["badge"], maximum: 12, optional: true)
            guard let type = control["type"] as? String, DuoControl.Kind(rawValue: type) != nil else {
                throw DuoValidationError("Unsupported control type.")
            }
            if type != "spacer" { visibleControls += 1 }
            if let icon = control["icon"] {
                guard let icon = icon as? String, icons.contains(icon) else {
                    throw DuoValidationError("Unsupported icon.")
                }
            }
            for key in ["enabled", "requiresConfirmation"] where control[key] != nil {
                guard let number = control[key] as? NSNumber,
                      CFGetTypeID(number) == CFBooleanGetTypeID() else {
                    throw DuoValidationError("\(key) must be a boolean.")
                }
            }
            if let payload = control["payload"] {
                guard let payload = payload as? [String: Any] else {
                    throw DuoValidationError("Payload must be an object.")
                }
                try validatePayload(payload, depth: 0)
            }
            if type == "segmented" || type == "menu" {
                guard let options = control["options"] as? [[String: Any]],
                      (2...5).contains(options.count) else {
                    throw DuoValidationError("Menus and segmented controls require 2 to 5 options.")
                }
                var optionIDs = Set<String>()
                for option in options {
                    try keys(option, required: ["id", "label"], optional: [])
                    try identifier(option["id"])
                    try text(option["label"], maximum: 40)
                    guard let optionID = option["id"] as? String,
                          optionIDs.insert(optionID).inserted else {
                        throw DuoValidationError("Option identifiers must be unique.")
                    }
                }
                if let value = control["value"] {
                    guard let value = value as? String, optionIDs.contains(value) else {
                        throw DuoValidationError("Value must identify an option.")
                    }
                }
            } else if type == "toggle" {
                guard control["options"] == nil else { throw DuoValidationError("Toggle has no options.") }
                if let value = control["value"] {
                    guard let number = value as? NSNumber,
                          CFGetTypeID(number) == CFBooleanGetTypeID() else {
                        throw DuoValidationError("Toggle value must be boolean.")
                    }
                }
            } else if control["value"] != nil || control["options"] != nil {
                throw DuoValidationError("This control does not accept a value or options.")
            }
        }
        guard visibleControls > 0 else { throw DuoValidationError("A panel must contain a visible control.") }
    }

    private static func keys(
        _ object: [String: Any], required: Set<String>, optional: Set<String>
    ) throws {
        let actual = Set(object.keys)
        guard required.isSubset(of: actual), actual.isSubset(of: required.union(optional)) else {
            throw DuoValidationError("Missing or unknown fields.")
        }
    }

    private static func identifier(_ value: Any?) throws {
        guard let value = value as? String, !value.isEmpty, value.utf8.count <= 64,
              value.unicodeScalars.allSatisfy({
                  CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-").contains($0)
              }) else { throw DuoValidationError("Invalid identifier.") }
    }

    private static func text(_ value: Any?, maximum: Int, optional: Bool = false) throws {
        if value == nil && optional { return }
        guard let value = value as? String, !value.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
              value.count <= maximum, !value.unicodeScalars.contains(where: {
                  CharacterSet.controlCharacters.contains($0)
              }) else { throw DuoValidationError("Invalid or oversized text.") }
    }

    private static func validatePayload(_ value: Any, depth: Int) throws {
        guard depth <= 6 else { throw DuoValidationError("Payload nesting exceeds 6 levels.") }
        if let object = value as? [String: Any] {
            guard object.count <= 32 else { throw DuoValidationError("Too many payload fields.") }
            for (key, child) in object {
                try text(key, maximum: 80)
                try validatePayload(child, depth: depth + 1)
            }
        } else if let array = value as? [Any] {
            guard array.count <= 32 else { throw DuoValidationError("Payload array exceeds 32 entries.") }
            for child in array { try validatePayload(child, depth: depth + 1) }
        } else if let string = value as? String {
            guard string.count <= 2048 else { throw DuoValidationError("Payload text exceeds 2048 characters.") }
        } else if let number = value as? NSNumber {
            guard number.doubleValue.isFinite else { throw DuoValidationError("Invalid payload number.") }
        } else if !(value is NSNull) {
            throw DuoValidationError("Invalid payload value.")
        }
    }
}
