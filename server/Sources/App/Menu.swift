import Vapor

/// A customer-selectable add-on/upgrade — e.g. "Add Katsu +$6", "Yosh Size
/// +$25.20" — priced as a delta added to the item's base price, since that's
/// how staff already describe these in the menu ("YOSH size: $53.20" on a
/// $28 item becomes a +$25.20 modifier here).
struct MenuItemModifier: Codable, Content, Equatable {
    var id: String
    var name: String
    var priceDelta: Double

    init(id: String = UUID().uuidString, name: String, priceDelta: Double) {
        self.id = id
        self.name = name
        self.priceDelta = priceDelta
    }
}

/// A required, mutually-exclusive choice bundled into one dish — e.g. Shogun
/// Bento's "your choice of chicken or beef teriyaki," or a burger's choice
/// of fries or side salad. Unlike a modifier (an optional priced add-on), a
/// customer must pick exactly one option and none of them change the price
/// — the dish is priced as a whole either way.
struct MenuItemChoiceGroup: Codable, Content, Equatable {
    var id: String
    var label: String
    var options: [String]

    init(id: String = UUID().uuidString, label: String, options: [String] = []) {
        self.id = id
        self.label = label
        self.options = options
    }
}

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
    /// Optional add-ons/upgrades a customer can check when placing a table
    /// order (see TableOrders.swift) — empty for the vast majority of items.
    var modifiers: [MenuItemModifier]
    /// Required single-pick choices bundled into this dish (e.g. a bento's
    /// choice of protein) — empty for the vast majority of items.
    var choiceGroups: [MenuItemChoiceGroup]

    enum CodingKeys: String, CodingKey {
        case id, name, description, price, images, image, tags, featured, available, happyHour, modifiers, choiceGroups
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
        happyHour: Bool = false,
        modifiers: [MenuItemModifier] = [],
        choiceGroups: [MenuItemChoiceGroup] = []
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
        self.modifiers = modifiers
        self.choiceGroups = choiceGroups
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
        modifiers = try container.decodeIfPresent([MenuItemModifier].self, forKey: .modifiers) ?? []
        choiceGroups = try container.decodeIfPresent([MenuItemChoiceGroup].self, forKey: .choiceGroups) ?? []
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
        try container.encode(modifiers, forKey: .modifiers)
        try container.encode(choiceGroups, forKey: .choiceGroups)
    }
}

struct MenuCategory: Codable, Content {
    var section: String
    var name: String
    var note: String?
    var items: [MenuItem]
}

/// A reusable add-on definition staff can pick from when adding a modifier
/// to any menu item (e.g. "Add Bacon +$5.50"), instead of retyping the same
/// name/price on every item that offers it. The price here is just a
/// starting point — an item-specific modifier copied from the catalog can
/// still be edited afterward, since some add-ons (like "Yosh Size") price
/// differently depending on the dish.
struct AdditionCatalogItem: Codable, Content, Equatable {
    var id: String
    var name: String
    var priceDelta: Double

    init(id: String = UUID().uuidString, name: String, priceDelta: Double) {
        self.id = id
        self.name = name
        self.priceDelta = priceDelta
    }
}

struct Menu: Codable, Content {
    var restaurant: String
    var lastUpdated: String
    var categories: [MenuCategory]
    var additionsCatalog: [AdditionCatalogItem]

    enum CodingKeys: String, CodingKey {
        case restaurant, lastUpdated, categories, additionsCatalog
    }

    init(restaurant: String, lastUpdated: String, categories: [MenuCategory], additionsCatalog: [AdditionCatalogItem] = []) {
        self.restaurant = restaurant
        self.lastUpdated = lastUpdated
        self.categories = categories
        self.additionsCatalog = additionsCatalog
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        restaurant = try container.decode(String.self, forKey: .restaurant)
        lastUpdated = try container.decode(String.self, forKey: .lastUpdated)
        categories = try container.decode([MenuCategory].self, forKey: .categories)
        additionsCatalog = try container.decodeIfPresent([AdditionCatalogItem].self, forKey: .additionsCatalog) ?? []
    }
}
