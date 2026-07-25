import XCTest
@testable import App

final class MenuTests: XCTestCase {
    func testDecodesOldFormatWithSingularImageAndNoNewFields() throws {
        let json = """
        {
            "name": "Loco Moco",
            "description": "Rice, patty, egg, gravy.",
            "price": 18.5,
            "image": "/uploads/loco-moco.jpg"
        }
        """
        let item = try JSONDecoder().decode(MenuItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.images, ["/uploads/loco-moco.jpg"])
        XCTAssertEqual(item.tags, [])
        XCTAssertFalse(item.featured)
        XCTAssertTrue(item.available, "items should default to available when the field predates the sold-out toggle")
    }

    func testDecodesNewFormatWithImagesArray() throws {
        let json = """
        {
            "name": "Shogun Bento",
            "price": 28,
            "images": ["/uploads/a.jpg", "/uploads/b.jpg"],
            "tags": ["gluten-free-available"],
            "featured": true,
            "available": false
        }
        """
        let item = try JSONDecoder().decode(MenuItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.images, ["/uploads/a.jpg", "/uploads/b.jpg"])
        XCTAssertEqual(item.tags, ["gluten-free-available"])
        XCTAssertTrue(item.featured)
        XCTAssertFalse(item.available)
    }

    func testDecodesItemWithNoImageAtAll() throws {
        let json = """
        { "name": "Miso Soup", "price": 4 }
        """
        let item = try JSONDecoder().decode(MenuItem.self, from: Data(json.utf8))
        XCTAssertEqual(item.images, [])
    }

    func testRoundTripEncodeDecodePreservesData() throws {
        let original = MenuItem(
            name: "Spam Musubi", description: "Classic.", price: 6.5,
            images: ["/uploads/x.jpg"], tags: ["shellfish"], featured: true, available: false
        )
        let encoded = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(MenuItem.self, from: encoded)
        XCTAssertEqual(decoded.name, original.name)
        XCTAssertEqual(decoded.images, original.images)
        XCTAssertEqual(decoded.tags, original.tags)
        XCTAssertEqual(decoded.featured, original.featured)
        XCTAssertEqual(decoded.available, original.available)
    }

    func testFullMenuStructureDecodes() throws {
        let json = """
        {
            "restaurant": "Ohana Belltown",
            "lastUpdated": "2026-01-01",
            "categories": [
                {
                    "section": "menu",
                    "name": "Pupu's",
                    "items": [
                        { "name": "Gyoza", "price": 9 }
                    ]
                }
            ]
        }
        """
        let menu = try JSONDecoder().decode(Menu.self, from: Data(json.utf8))
        XCTAssertEqual(menu.categories.count, 1)
        XCTAssertEqual(menu.categories[0].items.first?.name, "Gyoza")
    }
}
