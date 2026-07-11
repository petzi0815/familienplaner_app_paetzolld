import Foundation

// JSONDecoder nutzt .convertFromSnakeCase → storage_key → storageKey usw.

struct Lebensbereich: Decodable, Identifiable {
    let key: String
    let titel: String
    let emoji: String?
    var id: String { key }
}
struct LebensbereichList: Decodable { let data: [Lebensbereich]; let total: Int }

struct FotoInboxItem: Decodable, Identifiable {
    let id: Int
    let storageKey: String
    let storageKeyUrl: String?
    let bereich: String?
    let status: String
    let notiz: String?
    let erstelltAm: String?
    let zugeordnetResource: String?
}
struct FotoInboxList: Decodable { let data: [FotoInboxItem]; let total: Int }

struct FotoUploadResult: Decodable {
    let id: Int
    let status: String
    let url: String?
}
