import XCTest
import CoreLocation
@testable import Momentra

@MainActor
final class StampProfilesStoreTests: XCTestCase {
    private var defaults: UserDefaults!
    private var suite: String!

    override func setUp() {
        super.setUp()
        suite = "momentra.tests.stamp." + UUID().uuidString
        defaults = UserDefaults(suiteName: suite)!
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        defaults = nil
        super.tearDown()
    }

    func testOrganizationProfileIsReadOnlyAndDoesNotOverwritePersonalSelection() {
        let store = StampProfilesStore(defaults: defaults)
        let personalID = store.selectedID
        let organizationID = UUID()
        let shared = StampProfile(name: "Empresa", note: "Original")
        store.replaceOrganizationProfiles([(organizationID.uuidString, shared)])
        store.select(organizationID)
        XCTAssertTrue(store.isOrganizationSelected)
        store.rename("Alterado")
        store.setNote("Alterado")
        XCTAssertEqual(store.selected.name, "Empresa")
        XCTAssertEqual(store.selected.note, "Original")
        XCTAssertEqual(StampProfilesStore(defaults: defaults).selectedID, personalID)
        let draft = StampProfilesStore(draftOf: store)
        draft.rename("Pessoal editado")
        store.applyDraft(draft)
        XCTAssertEqual(store.selectedID, organizationID)
        store.replaceOrganizationProfiles([])
        XCTAssertEqual(store.selectedID, personalID)
        XCTAssertEqual(store.selected.name, "Pessoal editado")
    }

    func testDraftChangesPersistOnlyAfterSaving() {
        let original = StampProfilesStore(defaults: defaults)
        let initial = original.selected
        let draft = StampProfilesStore(draftOf: original)
        draft.rename("Obra")
        draft.setLogo("obra.png", for: draft.selectedID)
        XCTAssertEqual(original.selected, initial)
        XCTAssertEqual(StampProfilesStore(defaults: defaults).selected, initial)
        original.applyDraft(draft)
        XCTAssertEqual(original.selected.name, "Obra")
        XCTAssertEqual(StampProfilesStore(defaults: defaults).selected.logoName, "obra.png")
    }

    func testTemplateImagesRemainIndependentAndDraftDoesNotOverwriteOriginal() {
        let store = StampProfilesStore(defaults: defaults)
        store.setLogo("company.png", for: store.selectedID)
        var initialLayout = store.selected.layout
        initialLayout.template = .portrait
        store.setLayout(initialLayout)
        XCTAssertEqual(store.selected.effectiveLogoName, "")
        initialLayout.template = .original
        store.setLayout(initialLayout)
        let draft = StampProfilesStore(draftOf: store)
        draft.setLogo("portrait.png", for: draft.selectedID, template: .portrait)
        draft.setLogo("delivery.png", for: draft.selectedID, template: .deliveryProof)
        var layout = draft.selected.layout
        layout.template = .portrait
        draft.setLayout(layout)
        XCTAssertEqual(draft.selected.effectiveLogoName, "portrait.png")
        XCTAssertEqual(store.selected.effectiveLogoName, "company.png")
        store.applyDraft(draft)
        let restored = StampProfilesStore(defaults: defaults)
        XCTAssertEqual(restored.selected.effectiveLogoName, "portrait.png")
        layout = restored.selected.layout
        layout.template = .deliveryProof
        restored.setLayout(layout)
        XCTAssertEqual(restored.selected.effectiveLogoName, "delivery.png")
        layout.template = .original
        restored.setLayout(layout)
        XCTAssertEqual(restored.selected.effectiveLogoName, "company.png")
    }

    func testConstructionLogosHaveIndependentSlotsAndPersist() {
        let store = StampProfilesStore(defaults: defaults)
        var layout = store.selected.layout
        layout.template = .construction
        store.setLayout(layout)
        for slot in 0..<3 { store.setLogo("logo\(slot).png", for: store.selectedID, template: .construction, slot: slot) }
        let restored = StampProfilesStore(defaults: defaults)
        XCTAssertEqual(restored.selected.effectiveLogoName, "logo0.png")
        XCTAssertEqual(restored.selected.additionalLogoNames, ["logo1.png", "logo2.png"])
        let locked = restored.selected.layout.lockedCaptureLayout()
        XCTAssertNil(locked.templateValues[StampLayout.Template.construction.rawValue]?["_image2"])
    }

    func testMigrationCreatesOneNamedProfileAndRetainsLegacyKeys() {
        defaults.set("PIRESCO", forKey: "native.profile")
        defaults.set("Nota existente", forKey: "native.profile.piresco.note")
        defaults.set("old-logo.png", forKey: "native.profile.piresco.logo")
        let store = StampProfilesStore(defaults: defaults)
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.selected.name, "Padrão")
        XCTAssertEqual(store.selected.note, "Nota existente")
        XCTAssertEqual(store.selected.logoName, "old-logo.png")
        XCTAssertEqual(defaults.string(forKey: "native.profile.piresco.logo"), "old-logo.png")
    }

    func testFiveProfilesPersistAndSixthIsRejected() {
        let store = StampProfilesStore(defaults: defaults)
        for _ in 0..<4 { XCTAssertTrue(store.create()) }
        XCTAssertFalse(store.create())
        XCTAssertEqual(store.profiles.count, 5)
        store.rename("Projeto")
        let restored = StampProfilesStore(defaults: defaults)
        XCTAssertEqual(restored.profiles.count, 5)
        XCTAssertEqual(restored.selected.name, "Projeto")
    }

    func testRemovingSelectedProfileKeepsAtLeastOne() {
        let store = StampProfilesStore(defaults: defaults)
        store.removeSelected()
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertTrue(store.create())
        store.removeSelected()
        XCTAssertEqual(store.profiles.count, 1)
        XCTAssertEqual(store.selected.name, "Padrão")
    }

    func testNormalizedPositionIsBoundedAndClampedIntoPhoto() {
        let point = StampPoint(x: -1, y: 2)
        XCTAssertEqual(point, StampPoint(x: 0, y: 1))
        let bounds = CGSize(width: 1000, height: 1500)
        let rect = StampRenderer.positionedRect(size: bounds, element: CGSize(width: 200, height: 200), centre: point, margin: 20)
        XCTAssertEqual(rect.minX, 20)
        XCTAssertEqual(rect.maxY, 1480)
    }

    func testCornerAnchorsStayFixedAsElementsGrowAndRemainInsideMargin() {
        let bounds = CGSize(width: 1000, height: 1500)
        let margin: CGFloat = 25
        for x in [0.0, 1.0] {
            for y in [0.0, 1.0] {
                let point = StampPoint(x: x, y: y)
                let small = StampRenderer.positionedRect(size: bounds, element: CGSize(width: 100, height: 100), centre: point, margin: margin)
                let large = StampRenderer.positionedRect(size: bounds, element: CGSize(width: 3000, height: 3000), centre: point, margin: margin)
                XCTAssertEqual(x == 0 ? small.minX : small.maxX, x == 0 ? large.minX : large.maxX, accuracy: 0.001)
                XCTAssertEqual(y == 0 ? small.minY : small.maxY, y == 0 ? large.minY : large.maxY, accuracy: 0.001)
                XCTAssertGreaterThanOrEqual(large.minX, margin)
                XCTAssertGreaterThanOrEqual(large.minY, margin)
                XCTAssertLessThanOrEqual(large.maxX, bounds.width - margin)
                XCTAssertLessThanOrEqual(large.maxY, bounds.height - margin)
            }
        }
    }

    func testMapStylePersistsAndOldLayoutsDefaultToMap() throws {
        let old = try JSONDecoder().decode(StampLayout.self, from: Data(#"{"mode":"separate"}"#.utf8))
        XCTAssertEqual(old.mapStyle, .map)
        XCTAssertEqual(old.mapSize, 1)
        XCTAssertEqual(old.informationSize, 1)
        XCTAssertEqual(old.logoSize, 1)
        var updated = old
        updated.mapStyle = .satellite
        updated.mapSize = 1.5
        updated.informationSize = 0.8
        updated.logoSize = 1.2
        let restored = try JSONDecoder().decode(StampLayout.self, from: JSONEncoder().encode(updated))
        XCTAssertEqual(restored.mapStyle, .satellite)
        XCTAssertEqual(restored.mapSize, 1.5, accuracy: 0.001)
        XCTAssertEqual(restored.informationSize, 0.8, accuracy: 0.001)
        XCTAssertEqual(restored.logoSize, 1.2, accuracy: 0.001)
        XCTAssertEqual(restored.mode, .separate)
    }

    func testStartupCanUseLastProfileOrAFixedProfile() {
        let store = StampProfilesStore(defaults: defaults)
        let first = store.selectedID
        XCTAssertTrue(store.create())
        let second = store.selectedID
        store.setStartup(first.uuidString)
        let fixed = StampProfilesStore(defaults: defaults)
        XCTAssertEqual(fixed.selectedID, first)
        fixed.select(second)
        let again = StampProfilesStore(defaults: defaults)
        XCTAssertEqual(again.selectedID, first)
        again.setStartup("last")
        again.select(second)
        let last = StampProfilesStore(defaults: defaults)
        XCTAssertEqual(last.selectedID, second)
    }

    func testDeletingFixedProfileFallsBackToLastSelection() {
        let store = StampProfilesStore(defaults: defaults)
        XCTAssertTrue(store.create())
        store.setStartup(store.selectedID.uuidString)
        store.removeSelected()
        XCTAssertEqual(store.startupSelection, "last")
        XCTAssertEqual(store.profiles.count, 1)
    }
}
