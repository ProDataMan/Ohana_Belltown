import Vapor

struct MenuItem: Codable, Content {
    var id: String
    var name: String
    var description: String?
    var price: Double?
    var images: [String]
    var tags: [String]
    var featured: Bool
    var available: Bool
    /// Whether this item is offered during Happy Hour — independent of
    /// which category/section it's filed under.
    var happyHour: Bool

    enum CodingKeys: String, CodingKey {
        case id, name, description, price, images, image, tags, featured, available, happyHour
    }

    init(
        id: String = UUID().uuidString,
        name: String,
        description: String? = nil,
        price: Double? = nil,
        images: [String] = [],
        tags: [String] = [],
        featured: Bool = false,
        available: Bool = true,
        happyHour: Bool = false
    ) {
        self.id = id
        self.name = name
        self.description = description
        self.price = price
        self.images = images
        self.tags = tags
        self.featured = featured
        self.available = available
        self.happyHour = happyHour
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        // Older persisted items predate stable IDs — MenuStore.loadIfNeeded()
        // immediately re-persists after decoding so any freshly-generated ID
        // here becomes durable rather than changing on every restart.
        id = try container.decodeIfPresent(String.self, forKey: .id) ?? UUID().uuidString
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
        tags = try container.decodeIfPresent([String].self, forKey: .tags) ?? []
        featured = try container.decodeIfPresent(Bool.self, forKey: .featured) ?? false
        available = try container.decodeIfPresent(Bool.self, forKey: .available) ?? true
        happyHour = try container.decodeIfPresent(Bool.self, forKey: .happyHour) ?? false
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(name, forKey: .name)
        try container.encodeIfPresent(description, forKey: .description)
        try container.encodeIfPresent(price, forKey: .price)
        try container.encode(images, forKey: .images)
        try container.encode(tags, forKey: .tags)
        try container.encode(featured, forKey: .featured)
        try container.encode(available, forKey: .available)
        try container.encode(happyHour, forKey: .happyHour)
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
