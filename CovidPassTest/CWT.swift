// Developed by Ben Dodson (ben@bendodson.com)

import Foundation
import SwiftCBOR

public struct CWT {
    let iss: String
    let exp: UInt64
    let iat: UInt64
    let pass: CovidPass
    
    enum PayloadKeys : String {
        case iss = "1"
        case exp = "4"
        case iat = "6"
        case hcert = "-260"
        
        enum HcertKeys: String {
            case euHealthCertV1 = "1"
        }
    }
    
    init?(from cbor: CBOR) {
        guard let cbor = cbor.asMap() else { return nil }
        guard let iss = cbor[PayloadKeys.iss]?.asString() else { return nil }
        guard let exp = (cbor[PayloadKeys.exp]?.asUInt64() ?? cbor[PayloadKeys.exp]?.asDouble()?.toUInt64()) else { return nil }
        guard let iat = (cbor[PayloadKeys.iat]?.asUInt64() ?? cbor[PayloadKeys.iat]?.asDouble()?.toUInt64()) else { return nil }
        
        var pass: CovidPass? = nil
        if let hCertMap = cbor[PayloadKeys.hcert]?.asMap(), let certData = hCertMap[PayloadKeys.HcertKeys.euHealthCertV1]?.asData() {
            pass = try? CodableCBORDecoder().decode(CovidPass.self, from: certData)
        }
        guard let pass = pass else { return nil }
        
        self.iss = iss
        self.exp = exp
        self.iat = iat
        self.pass = pass
    }
    
    public var issuedAt: Date? {
        get {
            return iat.toDate()
        }
    }
    
    public var expiresAt : Date? {
        get {
            return exp.toDate()
        }
    }

    func isValid(using dateService: DateService) -> Bool {
        guard let expDate = exp.toDate() else {
            return false
        }
        var isValid = dateService.isNowBefore(expDate)
        if let iatDate = iat.toDate() {
            isValid = isValid && dateService.isNowAfter(iatDate)
        }
        return isValid
    }
}
