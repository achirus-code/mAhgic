import Foundation

/// Anything that can carry a byte stream (plain socket or TLS on top of it).
public protocol ByteStream: AnyObject {
    func write(_ data: Data) throws
    func read(exactly count: Int) throws -> Data
    func close()
}

/// Minimal blocking BSD socket with read/write timeouts.
public final class Socket: ByteStream {
    public private(set) var fd: Int32
    private var closed = false

    public init(unixPath: String, timeout: TimeInterval = 10) throws {
        fd = Darwin.socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { throw MahgicError.socket("socket() failed: \(String(cString: strerror(errno)))") }
        var addr = sockaddr_un()
        addr.sun_family = sa_family_t(AF_UNIX)
        let pathBytes = Array(unixPath.utf8CString)
        withUnsafeMutableBytes(of: &addr.sun_path) { raw in
            for (i, b) in pathBytes.prefix(raw.count - 1).enumerated() { raw[i] = UInt8(bitPattern: b) }
        }
        let len = socklen_t(MemoryLayout<sockaddr_un>.size)
        let rc = withUnsafePointer(to: &addr) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, len) }
        }
        guard rc == 0 else {
            let msg = String(cString: strerror(errno))
            Darwin.close(fd)
            throw MahgicError.socket("connect(\(unixPath)) failed: \(msg)")
        }
        configure(timeout: timeout)
    }

    public init(host: String, port: UInt16, timeout: TimeInterval = 10) throws {
        var hints = addrinfo(ai_flags: 0, ai_family: AF_UNSPEC, ai_socktype: SOCK_STREAM, ai_protocol: 0,
                             ai_addrlen: 0, ai_canonname: nil, ai_addr: nil, ai_next: nil)
        var res: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, String(port), &hints, &res) == 0, let info = res else {
            throw MahgicError.socket("cannot resolve \(host)")
        }
        defer { freeaddrinfo(res) }
        fd = Darwin.socket(info.pointee.ai_family, info.pointee.ai_socktype, info.pointee.ai_protocol)
        guard fd >= 0 else { throw MahgicError.socket("socket() failed") }
        guard Darwin.connect(fd, info.pointee.ai_addr, info.pointee.ai_addrlen) == 0 else {
            let msg = String(cString: strerror(errno))
            Darwin.close(fd)
            throw MahgicError.socket("connect(\(host):\(port)) failed: \(msg)")
        }
        configure(timeout: timeout)
    }

    private func configure(timeout: TimeInterval) {
        var on: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &on, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: Int(timeout), tv_usec: Int32((timeout - floor(timeout)) * 1_000_000))
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
    }

    deinit { close() }

    public func close() {
        guard !closed else { return }
        closed = true
        Darwin.close(fd)
    }

    public func write(_ data: Data) throws {
        try data.withUnsafeBytes { raw in
            guard let base = raw.baseAddress else { return }
            try writeRaw(base, count: raw.count)
        }
    }

    func writeRaw(_ ptr: UnsafeRawPointer, count: Int) throws {
        var sent = 0
        while sent < count {
            let n = Darwin.send(fd, ptr + sent, count - sent, 0)
            if n < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { throw MahgicError.timeout }
                throw MahgicError.socket("send failed: \(String(cString: strerror(errno)))")
            }
            sent += n
        }
    }

    public func read(exactly count: Int) throws -> Data {
        var buffer = Data(count: count)
        try buffer.withUnsafeMutableBytes { raw in
            guard let base = raw.baseAddress else { return }
            try readRaw(into: base, count: count)
        }
        return buffer
    }

    func readRaw(into ptr: UnsafeMutableRawPointer, count: Int) throws {
        var got = 0
        while got < count {
            let n = Darwin.recv(fd, ptr + got, count - got, 0)
            if n == 0 { throw MahgicError.connectionClosed }
            if n < 0 {
                if errno == EINTR { continue }
                if errno == EAGAIN || errno == EWOULDBLOCK { throw MahgicError.timeout }
                throw MahgicError.socket("recv failed: \(String(cString: strerror(errno)))")
            }
            got += n
        }
    }
}

/// Property-list service framing used by lockdownd and most device services:
/// a 32-bit big-endian length followed by an XML/binary plist.
public final class PlistService {
    public var stream: ByteStream

    public init(stream: ByteStream) { self.stream = stream }

    public func send(_ dict: PlistDict) throws {
        let body = try PropertyListSerialization.data(fromPropertyList: dict, format: .xml, options: 0)
        var len = UInt32(body.count).bigEndian
        var packet = Data(bytes: &len, count: 4)
        packet.append(body)
        try stream.write(packet)
    }

    public func receive() throws -> PlistDict {
        let header = try stream.read(exactly: 4)
        let len = header.withUnsafeBytes { UInt32(bigEndian: $0.loadUnaligned(as: UInt32.self)) }
        guard len > 0, len < 64 * 1024 * 1024 else { throw MahgicError.lockdown("Invalid message length \(len)") }
        let body = try stream.read(exactly: Int(len))
        guard let dict = try PropertyListSerialization.propertyList(from: body, format: nil) as? PlistDict else {
            throw MahgicError.lockdown("Unexpected response from device")
        }
        return dict
    }

    public func request(_ dict: PlistDict) throws -> PlistDict {
        try send(dict)
        return try receive()
    }

    public func close() { stream.close() }
}
