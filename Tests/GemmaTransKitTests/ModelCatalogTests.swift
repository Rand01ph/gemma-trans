import XCTest
@testable import GemmaTransKit

final class ModelCatalogTests: XCTestCase {
    func test_entries_haveUniqueStableIDs() {
        let ids = ModelCatalog.entries.map(\.id)
        XCTAssertEqual(Set(ids).count, ids.count, "catalog id 必须唯一")
        XCTAssertEqual(ids, [
            "gemma-e4b-4bit",
            "gemma-e2b-4bit",
            "hymt2-4bit",
            "hymt2-8bit",
            "hymt2-1.25bit",
            "hymt2-2bit",
        ])
    }

    func test_entry_lookupByID() {
        let e = ModelCatalog.entry(id: "gemma-e2b-4bit")
        XCTAssertEqual(e?.repo, "mlx-community/gemma-4-e2b-it-4bit")
        XCTAssertEqual(e?.family, .gemma)
        XCTAssertNil(ModelCatalog.entry(id: "nope"))
    }

    func test_autoIsNotAnEntry() {
        XCTAssertNil(ModelCatalog.entry(id: "auto"))
    }

    func test_curatedGGUFMetadataIsPinned() throws {
        let light = try XCTUnwrap(ModelCatalog.entry(id: "hymt2-1.25bit"))
        XCTAssertEqual(light.backend, .llamaGGUF(.stq1_0))
        XCTAssertEqual(light.distribution, .singleFile(SingleFileDistribution(
            fileName: "Hy-MT2-1.8B-1.25bit-v2.gguf",
            huggingFaceRevision: "0989912c0cc2d3edeeecd76171d1c7d94ee17255",
            modelScopeRevision: "2d3896c601bb165415669c31e8cf43c2554e7900",
            bytes: 461_860_800,
            sha256: "13a33fc4f72d5c92c439a65fd343696de4ccd0485bca84de2712bc0d8cc4e773"
        )))

        let balanced = try XCTUnwrap(ModelCatalog.entry(id: "hymt2-2bit"))
        XCTAssertEqual(balanced.backend, .llamaGGUF(.q2_0c))
        XCTAssertEqual(balanced.distribution, .singleFile(SingleFileDistribution(
            fileName: "Hy-MT2-1.8B-2bit-v2.gguf",
            huggingFaceRevision: "2245b9ea2bdd68a67b21b44db9564e7d32fc3bc6",
            modelScopeRevision: "6689e68668273c14fb5a45bd04ffe12e0601077b",
            bytes: 600_534_976,
            sha256: "ae35b1ee4e4a12011e8105d5e7e2bd10f0c4b4e09320367274922184c0831c95"
        )))
    }

    func test_existingCatalogEntriesRemainRepositoryMLX() {
        for id in ["gemma-e4b-4bit", "gemma-e2b-4bit", "hymt2-4bit", "hymt2-8bit"] {
            XCTAssertEqual(ModelCatalog.entry(id: id)?.backend, .mlx)
            XCTAssertEqual(ModelCatalog.entry(id: id)?.distribution, .repositorySnapshot)
        }
    }
}
