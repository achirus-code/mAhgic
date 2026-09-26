import Foundation
import Security

// lockdownd and the device services speak TLS on top of an already-open usbmuxd tunnel
// (STARTTLS style), so we need a TLS engine that runs over our own socket. SecureTransport
// is deprecated but still the only system TLS stack on macOS that allows custom I/O callbacks.

private final class IOBox {
    let socket: Socket
    init(_ socket: Socket) { self.socket = socket }
}

private let tlsReadCallback: SSLReadFunc = { connection, data, dataLength in
    let box = Unmanaged<IOBox>.fromOpaque(connection).takeUnretainedValue()
    do {
        try box.socket.readRaw(into: data, count: dataLength.pointee)
        return noErr
    } catch MahgicError.connectionClosed {
        dataLength.pointee = 0
        return errSSLClosedGraceful
    } catch {
        dataLength.pointee = 0
        return errSSLClosedAbort
    }
}

private let tlsWriteCallback: SSLWriteFunc = { connection, data, dataLength in
    let box = Unmanaged<IOBox>.fromOpaque(connection).takeUnretainedValue()
    do {
        try box.socket.writeRaw(data, count: dataLength.pointee)
        return noErr
    } catch {
        dataLength.pointee = 0
        return errSSLClosedAbort
    }
}

public final class TLSStream: ByteStream {
    private let context: SSLContext
    private let box: Unmanaged<IOBox>
    private let socket: Socket
    private var closed = false

    /// Wraps `socket` in a TLS client session authenticated with `identity`.
    /// The peer certificate is not validated: devices use self-signed certs from the pairing record.
    public init(socket: Socket, identity: SecIdentity) throws {
        guard let ctx = SSLCreateContext(nil, .clientSide, .streamType) else {
            throw MahgicError.tls("Could not create TLS context")
        }
        self.context = ctx
        self.socket = socket
        self.box = Unmanaged.passRetained(IOBox(socket))

        SSLSetIOFuncs(ctx, tlsReadCallback, tlsWriteCallback)
        SSLSetConnection(ctx, box.toOpaque())
        SSLSetSessionOption(ctx, .breakOnServerAuth, true)
        SSLSetProtocolVersionMin(ctx, .tlsProtocol1)
        SSLSetProtocolVersionMax(ctx, .tlsProtocol12)
        SSLSetCertificate(ctx, [identity] as CFArray)

        var status: OSStatus
        repeat {
            status = SSLHandshake(ctx)
        } while status == errSSLPeerAuthCompleted || status == errSSLWouldBlock
        guard status == noErr else {
            throw MahgicError.tls("Handshake failed (\(status)): \(SecCopyErrorMessageString(status, nil) as String? ?? "unknown")")
        }
    }

    deinit {
        close()
        box.release()
    }

    public func write(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < raw.count {
                var processed = 0
                let status = SSLWrite(context, base + offset, raw.count - offset, &processed)
                if status != noErr && status != errSSLWouldBlock {
                    throw MahgicError.tls("Write failed (\(status))")
                }
                offset += processed
            }
        }
    }

    public func read(exactly count: Int) throws -> Data {
        var buffer = Data(count: count)
        try buffer.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            var offset = 0
            while offset < count {
                var processed = 0
                let status = SSLRead(context, base + offset, count - offset, &processed)
                offset += processed
                if status == errSSLClosedGraceful || status == errSSLClosedNoNotify {
                    if offset < count { throw MahgicError.connectionClosed }
                } else if status != noErr && status != errSSLWouldBlock {
                    throw MahgicError.tls("Read failed (\(status))")
                }
            }
        }
        return buffer
    }

    public func close() {
        guard !closed else { return }
        closed = true
        SSLClose(context)
        socket.close()
    }
}

public enum TLSIdentity {
    private typealias SecIdentityCreateFn = @convention(c) (CFAllocator?, SecCertificate, SecKey) -> Unmanaged<SecIdentity>?

    /// Builds an in-memory SecIdentity from PEM encoded certificate + RSA private key
    /// (as stored in iOS pairing records) without touching the keychain.
    public static func make(certificatePEM: Data, privateKeyPEM: Data) throws -> SecIdentity {
        guard let (_, certDER) = PEM.decode(certificatePEM),
              let certificate = SecCertificateCreateWithData(nil, certDER as CFData) else {
            throw MahgicError.pairing("The pairing record contains an invalid host certificate.")
        }
        guard let (label, keyDER) = PEM.decode(privateKeyPEM) else {
            throw MahgicError.pairing("The pairing record contains an invalid private key.")
        }
        let pkcs1 = label.contains("RSA") ? keyDER : (PEM.pkcs8ToPKCS1(keyDER) ?? keyDER)
        var error: Unmanaged<CFError>?
        let attrs: [CFString: Any] = [
            kSecAttrKeyType: kSecAttrKeyTypeRSA,
            kSecAttrKeyClass: kSecAttrKeyClassPrivate,
        ]
        guard let key = SecKeyCreateWithData(pkcs1 as CFData, attrs as CFDictionary, &error) else {
            let reason = error?.takeRetainedValue().localizedDescription ?? "unknown"
            throw MahgicError.pairing("Could not load the host private key: \(reason)")
        }
        let rtldDefault = UnsafeMutableRawPointer(bitPattern: -2)
        guard let sym = dlsym(rtldDefault, "SecIdentityCreate") else {
            throw MahgicError.tls("SecIdentityCreate is not available on this macOS version.")
        }
        let create = unsafeBitCast(sym, to: SecIdentityCreateFn.self)
        guard let identity = create(kCFAllocatorDefault, certificate, key)?.takeRetainedValue() else {
            throw MahgicError.tls("Could not create TLS identity from pairing record.")
        }
        return identity
    }
}

enum PEM {
    /// Returns the PEM label (e.g. "RSA PRIVATE KEY") and DER payload of the first block.
    static func decode(_ data: Data) -> (String, Data)? {
        let text = String(decoding: data, as: UTF8.self)
        guard let begin = text.range(of: "-----BEGIN "),
              let beginEnd = text.range(of: "-----", range: begin.upperBound..<text.endIndex) else {
            // Might already be DER.
            return data.first == 0x30 ? ("DER", data) : nil
        }
        let label = String(text[begin.upperBound..<beginEnd.lowerBound])
        guard let end = text.range(of: "-----END ", range: beginEnd.upperBound..<text.endIndex) else { return nil }
        let body = text[beginEnd.upperBound..<end.lowerBound].filter { !$0.isWhitespace }
        guard let der = Data(base64Encoded: String(body)) else { return nil }
        return (label, der)
    }

    /// PrivateKeyInfo ::= SEQUENCE { version INTEGER, algorithm AlgorithmIdentifier, privateKey OCTET STRING }
    static func pkcs8ToPKCS1(_ der: Data) -> Data? {
        let bytes = [UInt8](der)
        var i = 0
        guard let outer = readTLV(bytes, &i), outer.tag == 0x30 else { return nil }
        var j = outer.start
        guard let version = readTLV(bytes, &j), version.tag == 0x02,
              let algo = readTLV(bytes, &j), algo.tag == 0x30,
              let key = readTLV(bytes, &j), key.tag == 0x04 else { return nil }
        return Data(bytes[key.start..<key.end])
    }

    private static func readTLV(_ b: [UInt8], _ i: inout Int) -> (tag: UInt8, start: Int, end: Int)? {
        guard i + 2 <= b.count else { return nil }
        let tag = b[i]; i += 1
        var length = Int(b[i]); i += 1
        if length & 0x80 != 0 {
            let n = length & 0x7F
            guard n > 0, n <= 4, i + n <= b.count else { return nil }
            length = 0
            for _ in 0..<n { length = (length << 8) | Int(b[i]); i += 1 }
        }
        guard i + length <= b.count else { return nil }
        let start = i
        i += length
        return (tag, start, i)
    }
}
