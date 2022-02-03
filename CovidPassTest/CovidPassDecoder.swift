// Developed by Ben Dodson (ben@bendodson.com)

import CryptoKit
import Foundation
import SwiftCBOR
import Compression

class CovidPassDecoder  {
    
    struct NHSKeyPair: Codable {
        let kid: String
        let publicKey: String
    }
    
    struct KIDPK {
        let kid: [UInt8]
        let pk: P256.Signing.PublicKey
    }
    
    var trust = [KIDPK]()

    init(keys: String) throws {
        guard let data = keys.data(using: .utf8), let pairs = try? JSONDecoder().decode([NHSKeyPair].self, from: data) else {
            throw "Could not decode JSON for NHS Keys"
        }
        
        for pair in pairs {
            let kid = [UInt8](Data(base64Encoded: pair.kid)!)
            let key = [UInt8](Data(base64Encoded: pair.publicKey)!)
            let pk = try! P256.Signing.PublicKey(derRepresentation: key)
            let entry: KIDPK = KIDPK( kid: kid, pk: pk )
            self.trust.append(entry)
        }
    }
    
    let COSE_TAG = UInt64(18)
    let COSE_PHDR_SIG = CBOR.unsignedInt(1)
    let COSE_PHDR_KID = CBOR.unsignedInt(4)
    let COSE_PHDR_SIG_ES256 = CBOR.negativeInt(6 /* Value is -7 -- ECDSA256 with a NIST P256 curve */)
    let COSE_CONTEXT_SIGN1 = "Signature1" /// magic value from RFC8152 section 4.4
    let ZLIB_HDR = 0x78 /* Magic ZLIB header constant (see file(8)) */
    
    private func getPublicKeyByKid(kid: [UInt8]) -> [P256.Signing.PublicKey] {
        var pks: [P256.Signing.PublicKey] = []
        for i: KIDPK in self.trust {
            if (i.kid == kid) {
                pks.append(i.pk)
            }
        }
        return pks
    }
    
    public func decodeHC1(barcode: String) throws -> CWT  {
        var bc = barcode
        
        // Remove HC1 header
        if (bc.hasPrefix("HC1")) {
            bc = String(bc.suffix(bc.count-3))
        }
        if (bc.hasPrefix(":")) {
            bc = String(bc.suffix(bc.count-1))
        }
        
        // Decode Base54
        var raw: Data = bc.fromBase45()
        
        // Inflate using zlib
        if (raw[0] == ZLIB_HDR) {
            raw.removeFirst(2)
            let sourceSize = raw.count
            var sourceBuffer = Array<UInt8>(repeating: 0, count: sourceSize)
            raw.copyBytes(to: &sourceBuffer, count: sourceSize)
            let destinationSize = 32 * 1024
            let destinationBuffer = UnsafeMutablePointer<UInt8>.allocate(capacity: destinationSize)
            let decodedSize = compression_decode_buffer(destinationBuffer, destinationSize, &sourceBuffer, sourceSize, nil, COMPRESSION_ZLIB)
            raw = Data(bytes: destinationBuffer, count: decodedSize)
        };

        // Decode COSE wrapper
        let cose = try CBORDecoder(input: [UInt8](raw)).decodeItem()!
        
        if case let CBOR.tagged(tag, cborElement) = cose {
            switch tag.rawValue {
            case COSE_TAG:
                if case let CBOR.array(coseElements) = cborElement {
                    var kid: [UInt8] = []
                    
                    if (coseElements.count != 4) {
                        throw "Not a COSE array"
                    }
                    
                    guard case let CBOR.byteString(shdr) = coseElements[0], let protected = try? CBOR.decode(shdr), case let CBOR.byteString(byteArray) = coseElements[2], let payload = try? CBOR.decode(byteArray), case let CBOR.byteString(signature) = coseElements[3] else {
                        throw "Not a COSE data structure."
                    }
                    
                    // Attempt to extract KID from unprotected header
                    if case let CBOR.byteString(uhdr) = coseElements[1], let  unprotected = try? CBOR.decode(uhdr), case let CBOR.map(map) = unprotected, case let CBOR.byteString(k) = map[COSE_PHDR_KID]! {
                        kid = k
                    }
                    
                    // Attempt to extract KID from protected header (overwrites unprotected if available)
                    if case let CBOR.map(map) = protected {
                        let k = map[COSE_PHDR_SIG]!
                        if (k != COSE_PHDR_SIG_ES256) {
                            throw "Not a ECDSA NIST P-256 signature"
                        }
                        if case let CBOR.byteString(k) = map[COSE_PHDR_KID]!  {
                            kid = k
                        }
                    }
                    
                    let externalData = CBOR.byteString([])
                    let signedPayload: [UInt8] = CBOR.encode(["Signature1", coseElements[0], externalData, coseElements[2]])
                    let digest = SHA256.hash(data: signedPayload)
                    let signatureForData = try! P256.Signing.ECDSASignature.init(rawRepresentation: signature)
                    let publicKeys = getPublicKeyByKid(kid: kid)
                    for pk in publicKeys {
                        if (pk.isValidSignature(signatureForData, for: digest)) {
                            guard let cwt = CWT(from: payload) else {
                                throw "Could not convert CBOR to CWT"
                            }
                            if cwt.pass == nil || cwt.exp == nil {
                                throw "Pass is missing critical information i.e. name, expiration, etc"
                            }
                            return cwt
                        }
                    }
                    throw "Data payload found but signature could not be validated. Make sure the latest keys are being used."
                };
            default:
                throw "Not a COSE Sign1(18) message"
            };
        }
        throw "Error processing COSE"
    }
}

extension Array where Element == UInt8 {
    func bytesToHex(spacing: String) -> String {
        var hexString: String = ""
        var count = self.count
        for byte in self {
            hexString.append(String(format:"%02X", byte))
            count = count - 1
            if count > 0 {
                hexString.append(spacing)
            }
        }
        return hexString
    }
}

extension String {
    func fromBase45()->Data {
        let BASE45_CHARSET = "0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZ $%*+-./:"
        var d = Data()
        var o = Data()
        for c in self {
            if let at = BASE45_CHARSET.firstIndex(of: c) {
                let idx  = BASE45_CHARSET.distance(from: BASE45_CHARSET.startIndex, to: at)
                d.append(UInt8(idx))
            }
        }
        for i in stride(from:0, to:d.count, by: 3) {
            var x : UInt32 = UInt32(d[i]) + UInt32(d[i+1])*45
            if (d.count - i >= 3) {
                x += 45 * 45 * UInt32(d[i+2])
                o.append(UInt8(x / 256))
                o.append(UInt8(x % 256))
            } else {
                o.append(UInt8(x % 256))
            }
        }
        return o
    }
}

extension String: Error {}

extension CBOR {
    func unwrap() -> Any? {
        switch self {
        case .simple(let value): return value
        case .boolean(let value): return value
        case .byteString(let value): return value
        case .date(let value): return value
        case .double(let value): return value
        case .float(let value): return value
        case .half(let value): return value
        case .tagged(let tag, let cbor): return (tag, cbor)
        case .array(let array): return array
        case .map(let map): return map
        case .utf8String(let value): return value
        case .negativeInt(let value): return value
        case .unsignedInt(let value): return value
        default:
            return nil
        }
    }
    
    func asUInt64() -> UInt64? {
        return self.unwrap() as? UInt64
    }
    
    func asDouble() -> Double? {
        return self.unwrap() as? Double
    }
    
    func asInt64() -> Int64? {
        return self.unwrap() as? Int64
    }
    
    func asString() -> String? {
        return self.unwrap() as? String
    }
    
    func asList() -> [CBOR]? {
        return self.unwrap() as? [CBOR]
    }
    
    func asMap() -> [CBOR:CBOR]? {
        return self.unwrap() as? [CBOR:CBOR]
    }
    
    func asBytes() -> [UInt8]? {
        return self.unwrap() as? [UInt8]
    }
    
    public func asData() -> Data {
        return Data(self.encode())
    }
     
    func asCose() -> (CBOR.Tag, [CBOR])? {
        guard let rawCose =  self.unwrap() as? (CBOR.Tag, CBOR),
              let cosePayload = rawCose.1.asList() else {
            return nil
        }
        return (rawCose.0, cosePayload)
    }
    
    func decodeBytestring() -> CBOR? {
        guard let bytestring = self.asBytes(),
              let decoded = try? CBORDecoder(input: bytestring).decodeItem() else {
            return nil
        }
        return decoded
    }
    
}

extension CBOR.Tag {
    public static let coseSign1Item = CBOR.Tag(rawValue: 18)
    public static let coseSignItem = CBOR.Tag(rawValue: 98)
}


extension Dictionary where Key == CBOR {
    subscript<Index: RawRepresentable>(index: Index) -> Value? where Index.RawValue == String {
        return self[CBOR(stringLiteral: index.rawValue)]
    }
    
    subscript<Index: RawRepresentable>(index: Index) -> Value? where Index.RawValue == Int {
        return self[CBOR(integerLiteral: index.rawValue)]
    }
}
