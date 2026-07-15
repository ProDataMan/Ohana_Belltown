import Vapor

struct MenuItem: Codable, Content {
    var name: String
    var description: String?
    var price: Double?
    var images: [String]

    enum CodingKeys: String, CodingKey {
        case name, description, price, images, image
    }

    init(name: String, description: String? = nil, price: Double? = nil, images: [String] = []) {
        self.name = name
        self.description = description
        self.price = price
        self.images = images
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        description = try container.decodeIfPresent(String.self, forKey: .description)
        price = try container.decodeIfPresent(Double.self, forKey: .price)
        if let imgs = try container.decodeIfPresent([String].self, forKey: .images) {
            images = imgs
        } else if let single = try container.decodeIfPresent(String.self, forKey: .image) {
            images = [single]
        } else {
            images = []
        }
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(price, forKey: .price)
        try container.encode(images, forKey: .images)
    }
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
