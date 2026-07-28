import XCTest
@testable import App

final class MenuStoreTests: XCTestCase {
    var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
        MenuStore.shared.configure(dataDirectory: tempDir.path, resourcesDirectory: tempDir.path)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    private func seedMenu(items: [MenuItem]) throws {
        let menu = Menu(restaurant: "Ohana", lastUpdated: "now", categories: [
            MenuCategory(section: "menu", name: "Test Category", note: nil, items: items)
        ])
        try MenuStore.shared.save(menu)
    }

    func testFindItemLocatesItemAndItsCategory() throws {
        let item = MenuItem(id: "abc", name: "Volcano Roll", price: 14)
        try seedMenu(items: [item])

        let found = try MenuStore.shared.findItem(id: "abc")
        XCTAssertEqual(found.item.name, "Volcano Roll")
        XCTAssertEqual(found.categoryName, "Test Category")
        XCTAssertEqual(found.section, "menu")
    }

    func testFindItemThrowsForUnknownId() throws {
        try seedMenu(items: [])
        XCTAssertThrowsError(try MenuStore.shared.findItem(id: "does-not-exist")) { error in
            guard let menuError = error as? MenuItemError else { return XCTFail("wrong error type") }
            XCTAssertEqual(menuError, .itemNotFound)
        }
    }

    func testUpdateItemAppliesChangesAndPersists() throws {
        try seedMenu(items: [MenuItem(id: "abc", name: "Volcano Roll", price: 14)])

        let updated = try MenuStore.shared.updateItem(id: "abc") { item in
            item.price = 16
            item.featured = true
        }
        XCTAssertEqual(updated.price, 16)
        XCTAssertTrue(updated.featured)

        // Re-point at the same directory to force a fresh reload from disk,
        // confirming the update was actually persisted, not just in-memory.
        MenuStore.shared.configure(dataDirectory: tempDir.path, resourcesDirectory: tempDir.path)
        let reloaded = try MenuStore.shared.findItem(id: "abc")
        XCTAssertEqual(reloaded.item.price, 16)
        XCTAssertTrue(reloaded.item.featured)
    }

    func testDeleteItemRemovesItFromItsCategory() throws {
        try seedMenu(items: [
            MenuItem(id: "keep", name: "Rainbow Roll", price: 13),
            MenuItem(id: "remove-me", name: "Discontinued Roll", price: 11),
        ])

        try MenuStore.shared.deleteItem(id: "remove-me")

        XCTAssertThrowsError(try MenuStore.shared.findItem(id: "remove-me"))
        let stillThere = try MenuStore.shared.findItem(id: "keep")
        XCTAssertEqual(stillThere.item.name, "Rainbow Roll")
    }

    func testDeletingUnknownItemThrows() throws {
        try seedMenu(items: [])
        XCTAssertThrowsError(try MenuStore.shared.deleteItem(id: "does-not-exist"))
    }

    func testLegacyItemsWithoutIdsGetStableIdsAfterFirstLoad() throws {
        // Simulate a pre-existing menu.json from before stable ids existed.
        let legacyJSON = """
        {"restaurant":"Ohana","lastUpdated":"now","categories":[
          {"section":"menu","name":"Legacy Category","note":null,"items":[
            {"name":"Old Item","price":10}
          ]}
        ]}
        """
        try legacyJSON.write(to: tempDir.appendingPathComponent("menu.json"), atomically: true, encoding: .utf8)
        MenuStore.shared.configure(dataDirectory: tempDir.path, resourcesDirectory: tempDir.path)

        let firstLoadMenu = try MenuStore.shared.get()
        let assignedId = try XCTUnwrap(firstLoadMenu.categories.first?.items.first?.id)
        XCTAssertFalse(assignedId.isEmpty)

        // Reload from a fresh store instance pointed at the same file — since
        // loadIfNeeded() re-persists immediately after the first migration,
        // the id should now be stable across restarts instead of changing.
        MenuStore.shared.configure(dataDirectory: tempDir.path, resourcesDirectory: tempDir.path)
        let secondLoadMenu = try MenuStore.shared.get()
        XCTAssertEqual(secondLoadMenu.categories.first?.items.first?.id, assignedId)
    }

    func testSeedCommonAdditionsAddsCatalogAndMatchingItemModifiers() throws {
        try seedMenu(items: [
            MenuItem(id: "loco", name: "Loco Moco", price: 18),
            MenuItem(id: "unrelated", name: "Miso Soup", price: 4),
        ])

        let result = try MenuStore.shared.seedCommonAdditions()

        XCTAssertEqual(result.catalogAdded, 15)
        XCTAssertEqual(result.itemsUpdated, ["Loco Moco"])

        let catalog = try MenuStore.shared.additionsCatalog()
        XCTAssertTrue(catalog.contains { $0.name == "Add Bacon" && $0.priceDelta == 5.50 })

        let locoMoco = try MenuStore.shared.findItem(id: "loco")
        let modNames = Set(locoMoco.item.modifiers.map { $0.name })
        XCTAssertEqual(modNames, ["Sub Fried Rice", "Sub Kalua Pork", "Add Bacon", "Add Katsu", "Add Spam", "Yosh Size"])
        XCTAssertEqual(locoMoco.item.modifiers.first { $0.name == "Yosh Size" }?.priceDelta, 25.20)

        let misoSoup = try MenuStore.shared.findItem(id: "unrelated")
        XCTAssertEqual(misoSoup.item.modifiers, [], "items with no known upcharge shouldn't get modifiers invented for them")
    }

    func testSeedCommonAdditionsIsIdempotent() throws {
        try seedMenu(items: [MenuItem(id: "loco", name: "Loco Moco", price: 18)])

        try MenuStore.shared.seedCommonAdditions()
        let second = try MenuStore.shared.seedCommonAdditions()

        XCTAssertEqual(second.catalogAdded, 0)
        XCTAssertEqual(second.itemsUpdated, [])
        let locoMoco = try MenuStore.shared.findItem(id: "loco")
        XCTAssertEqual(locoMoco.item.modifiers.count, 6, "running it twice shouldn't duplicate modifiers")
    }

    func testSeedCommonAdditionsSkipsAModifierAlreadyPresentByName() throws {
        try seedMenu(items: [
            MenuItem(id: "loco", name: "loco moco", price: 18, modifiers: [MenuItemModifier(name: "add bacon", priceDelta: 999)]),
        ])

        try MenuStore.shared.seedCommonAdditions()

        let locoMoco = try MenuStore.shared.findItem(id: "loco")
        let bacon = locoMoco.item.modifiers.first { $0.name.lowercased() == "add bacon" }
        XCTAssertEqual(bacon?.priceDelta, 999, "a pre-existing modifier (matched case-insensitively) should be left alone, not overwritten")
    }
}
