import Vapor

struct MenuItem: Codable, Content {
    var name: String
    var description: String?
    var price: Double?
    var image: String?
}

struct MenuCategory: Codable, Content {
    var section: String
    var name: String
    var note: String?
    var items: [MenuItem]
}

struct Menu: Codable, Content {
    var restaurant: String
    var lastUpdated: String
    var categories: [MenuCategory]
}
