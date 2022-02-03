// Developed by Ben Dodson (ben@bendodson.com)

import Foundation
import SwiftCBOR


public struct CovidPass : Codable {
    public let person: Person
    public let dateOfBirth : String
    public let version: String

    private enum CodingKeys : String, CodingKey {
        case person = "nam"
        case dateOfBirth = "dob"
        case version = "ver"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.person = try container.decode(Person.self, forKey: .person)
        self.version = try container.decode(String.self, forKey: .version)
        self.dateOfBirth = try container.decode(String.self, forKey: .dateOfBirth)
    }
}



public struct Person : Codable {
    public let givenName: String?
    public let standardizedGivenName: String?
    public let familyName: String?
    public let standardizedFamilyName: String
    
    private enum CodingKeys : String, CodingKey {
        case givenName = "gn"
        case standardizedGivenName = "gnt"
        case familyName = "fn"
        case standardizedFamilyName = "fnt"
    }
    
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.givenName = try? container.decode(String.self, forKey: .givenName)
        self.standardizedGivenName = try? container.decode(String.self, forKey: .standardizedGivenName)
        self.familyName = try? container.decode(String.self, forKey: .familyName)
        self.standardizedFamilyName = try container.decode(String.self, forKey: .standardizedFamilyName)
    }
}

