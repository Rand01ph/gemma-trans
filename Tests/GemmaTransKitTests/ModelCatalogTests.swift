import XCTest
@testable import GemmaTransKit

final class ModelCatalogTests: XCTestCase {
    func test_entries_haveUniqueStableIDs() {
        let ids = ModelCatalog.entries.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "catalog id 必须唯一")
        XCTAssertTrue(ids.contains("gemma-e4b-4bit"))
        XCTAssertTrue(ids.contains("gemma-e2b-4bit"))
    }

    func test_entry_lookupByID() {
        let e = ModelCatalog.entry(id: "gemma-e2b-4bit")
        XCTAssertEqual(e?.repo, "mlx-community/gemma-4-e2b-it-4bit")
        XCTAssertEqual(e?.family, .gemma)
        XCTAssertNil(ModelCatalog.entry(id: "nope"))
    }

    func test_autoID_isNotAnEntry() {
        XCTAssertNil(ModelCatalog.entry(id: ModelCatalog.autoID))
    }
}
