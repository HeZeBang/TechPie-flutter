import Foundation

/// Wire-format handling shared by the packet tunnel and standalone Swift smoke programs.
/// All offsets and lengths are checked before reading untrusted interface bytes.
enum EcardBindPackets {
    static let dnsPort = 53
    static let virtualDNS: [UInt8] = [198, 18, 0, 2]
    static let mirror: [UInt8] = [119, 78, 254, 196]

    struct Datagram {
        let source: [UInt8]
        let destination: [UInt8]
        let sourcePort: UInt16
        let destinationPort: UInt16
        let identification: UInt16
        let payload: Data
    }

    static func parseUDP(_ packet: Data) -> Datagram? {
        let bytes = [UInt8](packet)
        guard bytes.count >= 28, bytes[0] >> 4 == 4 else { return nil }
        let header = Int(bytes[0] & 0x0f) * 4
        guard header >= 20, header <= bytes.count - 8,
              bytes[9] == 17, word(bytes, 6) & 0x3fff == 0 else { return nil }
        let total = Int(word(bytes, 2))
        let udp = Int(word(bytes, header + 4))
        guard total >= header + 8, total <= bytes.count,
              udp >= 8, udp == total - header else { return nil }
        return Datagram(
            source: Array(bytes[12..<16]), destination: Array(bytes[16..<20]),
            sourcePort: word(bytes, header), destinationPort: word(bytes, header + 2),
            identification: word(bytes, 4), payload: Data(bytes[(header + 8)..<total])
        )
    }

    /// Returns nil rather than constructing a packet larger than IPv4's length field.
    static func buildUDPReply(to query: Datagram, payload: Data) -> Data? {
        guard query.source.count == 4, query.destination.count == 4,
              payload.count <= Int(UInt16.max) - 28 else { return nil }
        let length = 28 + payload.count
        let udpLength = 8 + payload.count
        var bytes = [UInt8](repeating: 0, count: length)
        bytes[0] = 0x45
        put(UInt16(length), in: &bytes, at: 2)
        put(query.identification, in: &bytes, at: 4)
        put(0x4000, in: &bytes, at: 6)
        bytes[8] = 64
        bytes[9] = 17
        bytes.replaceSubrange(12..<16, with: query.destination)
        bytes.replaceSubrange(16..<20, with: query.source)
        put(checksum(bytes, from: 0, count: 20), in: &bytes, at: 10)
        put(query.destinationPort, in: &bytes, at: 20)
        put(query.sourcePort, in: &bytes, at: 22)
        put(UInt16(udpLength), in: &bytes, at: 24)
        bytes.replaceSubrange(28..<length, with: payload)
        var sum = words(bytes, from: 12, count: 8)
        sum += UInt64(17 + udpLength)
        sum += words(bytes, from: 20, count: udpLength)
        let udpChecksum = complement(sum)
        put(udpChecksum == 0 ? 0xffff : udpChecksum, in: &bytes, at: 26)
        return Data(bytes)
    }

    private static func word(_ bytes: [UInt8], _ offset: Int) -> UInt16 {
        (UInt16(bytes[offset]) << 8) | UInt16(bytes[offset + 1])
    }

    private static func put(_ value: UInt16, in bytes: inout [UInt8], at offset: Int) {
        bytes[offset] = UInt8(value >> 8)
        bytes[offset + 1] = UInt8(truncatingIfNeeded: value)
    }

    private static func words(_ bytes: [UInt8], from start: Int, count: Int) -> UInt64 {
        var result: UInt64 = 0
        var index = start
        while index + 1 < start + count {
            result += UInt64(word(bytes, index))
            index += 2
        }
        if index < start + count { result += UInt64(bytes[index]) << 8 }
        return result
    }

    private static func complement(_ value: UInt64) -> UInt16 {
        var value = value
        while value >> 16 != 0 { value = (value & 0xffff) + (value >> 16) }
        return ~UInt16(value)
    }

    private static func checksum(_ bytes: [UInt8], from start: Int, count: Int) -> UInt16 {
        complement(words(bytes, from: start, count: count))
    }
}

enum EcardBindDNS {
    static let host = "ecard.shanghaitech.edu.cn"
    static let typeA: UInt16 = 1
    static let rcodeServerFailure: UInt8 = 2

    struct Question {
        let name: String // Lowercase ASCII, no trailing root dot.
        let type: UInt16
        let dnsClass: UInt16
        let end: Int
    }

    /// A single, ordinary DNS question. Compression, extended labels, malformed
    /// lengths, unsupported opcodes and multi-question messages are not rewritten.
    static func parseQuestion(_ message: Data) -> Question? {
        let bytes = [UInt8](message)
        guard bytes.count >= 17, bytes[2] & 0xf8 == 0,
              bytes[4] == 0, bytes[5] == 1 else { return nil }
        var index = 12
        var nameLength = 0
        var labels: [String] = []
        while index < bytes.count {
            let length = Int(bytes[index])
            index += 1
            if length == 0 { break }
            guard length <= 63, index <= bytes.count - length,
                  nameLength + length + 1 <= 254 else { return nil }
            // ASCII DNS letters are compared case-insensitively; never let an
            // arbitrary Unicode conversion alias an allowed ASCII hostname.
            let label = bytes[index..<(index + length)]
            guard label.allSatisfy({ $0 >= 33 && $0 <= 126 }) else { return nil }
            let normalized = String(decoding: label.map { byte in
                byte >= 65 && byte <= 90 ? byte + 32 : byte
            }, as: UTF8.self)
            // A dot *inside* a wire label must not impersonate multiple labels.
            labels.append(label.contains(46) ? normalized.replacingOccurrences(of: ".", with: "\\.") : normalized)
            nameLength += length + 1
            index += length
        }
        guard index <= bytes.count - 4, bytes[index - 1] == 0 else { return nil }
        let type = (UInt16(bytes[index]) << 8) | UInt16(bytes[index + 1])
        let dnsClass = (UInt16(bytes[index + 2]) << 8) | UInt16(bytes[index + 3])
        guard dnsClass != 0 else { return nil }
        return Question(name: labels.joined(separator: "."), type: type,
                        dnsClass: dnsClass, end: index + 4)
    }

    /// Checks that an upstream response actually answers this exact question.
    static func matchesResponse(_ response: Data, to query: Data, question: Question) -> Bool {
        let bytes = [UInt8](response)
        let sent = [UInt8](query)
        guard bytes.count >= question.end, sent.count >= question.end,
              bytes[0] == sent[0], bytes[1] == sent[1],
              bytes[2] & 0x80 != 0, bytes[2] & 0x78 == 0,
              bytes[4] == 0, bytes[5] == 1 else { return false }
        return bytes[12..<question.end].elementsEqual(sent[12..<question.end])
    }

    /// Echo the original question; only exact IN/A gets an A record. AAAA and
    /// every other type/class get NOERROR with no records (NODATA).
    static func reply(to query: Data, question: Question, address: [UInt8]? = nil,
                      rcode: UInt8 = 0) -> Data? {
        let sent = [UInt8](query)
        guard question.end >= 17, question.end <= sent.count,
              (address == nil || address?.count == 4), rcode <= 15 else { return nil }
        let addAnswer = address != nil && question.type == typeA && question.dnsClass == 1 && rcode == 0
        var bytes = [UInt8](repeating: 0, count: question.end + (addAnswer ? 16 : 0))
        bytes[0] = sent[0]
        bytes[1] = sent[1]
        bytes[2] = 0x80 | (sent[2] & 1)
        bytes[3] = 0x80 | rcode
        bytes[5] = 1
        if addAnswer { bytes[7] = 1 }
        bytes.replaceSubrange(12..<question.end, with: sent[12..<question.end])
        if addAnswer, let address {
            let offset = question.end
            bytes.replaceSubrange(offset..<(offset + 16), with:
                [0xc0, 0x0c, 0, 1, 0, 1, 0, 0, 0, 60, 0, 4] + address)
        }
        return Data(bytes)
    }
}
