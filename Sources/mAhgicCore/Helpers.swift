import Foundation
import UniformTypeIdentifiers
import AppKit

public typealias PlistDict = [String: Any]

extension Dictionary where Key == String, Value == Any {
    func int(_ key: String) -> Int? {
        if let n = self[key] as? NSNumber { return n.intValue }
        if let s = self[key] as? String { return Int(s) }
        return nil
    }

    func double(_ key: String) -> Double? {
        if let n = self[key] as? NSNumber { return n.doubleValue }
        if let s = self[key] as? String { return Double(s) }
        return nil
    }

    func bool(_ key: String) -> Bool? {
        if let b = self[key] as? Bool { return b }
        if let n = self[key] as? NSNumber { return n.boolValue }
        return nil
    }

    func string(_ key: String) -> String? {
        if let s = self[key] as? String { return s }
        if let d = self[key] as? Data { return String(decoding: d, as: UTF8.self).trimmingCharacters(in: .controlCharacters) }
        return nil
    }

    func dict(_ key: String) -> PlistDict? { self[key] as? PlistDict }
}

public enum MahgicError: LocalizedError {
    case socket(String)
    case timeout
    case connectionClosed
    case usbmux(String)
    case lockdown(String)
    case tls(String)
    case pairing(String)
    case diagnostics(String)

    public var errorDescription: String? {
        switch self {
        case .socket(let s): return "Socket: \(s)"
        case .timeout: return "The device did not respond in time."
        case .connectionClosed: return "The connection was closed by the device."
        case .usbmux(let s): return "usbmuxd: \(s)"
        case .lockdown(let s): return s
        case .tls(let s): return "TLS: \(s)"
        case .pairing(let s): return s
        case .diagnostics(let s): return "Diagnostics: \(s)"
        }
    }
}

/// Marketing names and device icons come straight from macOS' CoreTypes database,
/// keyed by model identifiers like "Mac15,13" or "iPhone17,1".
public enum DeviceCatalog {
    static let modelCodeTagClass = UTTagClass(rawValue: "com.apple.device-model-code")

    public static func type(for modelIdentifier: String) -> UTType? {
        UTType(tag: modelIdentifier, tagClass: modelCodeTagClass, conformingTo: nil)
    }

    public static func marketingName(for modelIdentifier: String) -> String? {
        guard let t = type(for: modelIdentifier), !t.isDynamic else { return nil }
        return t.localizedDescription
    }

    nonisolated(unsafe) private static var iconCache: [String: NSImage] = [:]

    /// Device artwork; cached because views ask for it on every render. Call from the main thread.
    public static func icon(for modelIdentifier: String, fallbackSymbol: String) -> NSImage {
        let key = modelIdentifier + "|" + fallbackSymbol
        if let cached = iconCache[key] { return cached }
        let image: NSImage
        if let t = type(for: modelIdentifier), !t.isDynamic {
            image = NSWorkspace.shared.icon(for: t)
        } else {
            image = NSImage(systemSymbolName: fallbackSymbol, accessibilityDescription: nil) ?? NSImage()
        }
        iconCache[key] = image
        return image
    }
}

/// Turns a (nested) IORegistry dictionary into sorted "Key.SubKey" → value rows for display.
public enum RawValues {
    public static func flatten(_ dict: PlistDict, prefix: String = "", depth: Int = 0) -> [(String, String)] {
        var rows: [(String, String)] = []
        for key in dict.keys.sorted() {
            let name = prefix.isEmpty ? key : "\(prefix).\(key)"
            switch dict[key] {
            case let nested as PlistDict where depth < 2:
                rows += flatten(nested, prefix: name, depth: depth + 1)
            case let value?:
                rows.append((name, describe(value)))
            case nil:
                break
            }
        }
        return rows
    }

    static func describe(_ value: Any) -> String {
        switch value {
        case let n as NSNumber:
            return CFGetTypeID(n) == CFBooleanGetTypeID() ? (n.boolValue ? "true" : "false") : n.stringValue
        case let s as String:
            return s
        case let d as Data:
            let hex = d.prefix(24).map { String(format: "%02x", $0) }.joined()
            return d.count > 24 ? "<\(hex)… \(d.count) bytes>" : "<\(hex)>"
        case let a as [Any]:
            let items = a.prefix(8).map { item -> String in
                if item is PlistDict { return "{…}" }
                return describe(item)
            }
            return "[" + items.joined(separator: ", ") + (a.count > 8 ? ", … (\(a.count))" : "") + "]"
        case is PlistDict:
            return "{…}"
        default:
            return "\(value)"
        }
    }
}
