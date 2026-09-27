import XCTest

@testable import FableFlux

final class AppThemeTests: XCTestCase {

    func testStandaardIsOrigineelMetPrimairIcoon() {
        XCTAssertEqual(AppTheme.standaard, .origineel)
        XCTAssertNil(AppTheme.origineel.iconName, "Origineel hoort het primaire AppIcon te gebruiken")
    }

    func testOnbekendeOfOntbrekendeWaardeValtTerugOpStandaard() {
        XCTAssertEqual(AppTheme(storedValue: nil), .standaard)
        XCTAssertEqual(AppTheme(storedValue: ""), .standaard)
        XCTAssertEqual(AppTheme(storedValue: "bestaat-niet"), .standaard)
    }

    func testOpgeslagenWaardeRondtrip() {
        for theme in AppTheme.allCases {
            XCTAssertEqual(AppTheme(storedValue: theme.rawValue), theme)
        }
    }

    func testAlternatieveIcoonnamenZijnUniekEnVolgenAssetNaam() {
        let names = AppTheme.allCases.compactMap(\.iconName)
        XCTAssertEqual(names.count, AppTheme.allCases.count - 1)
        XCTAssertEqual(Set(names).count, names.count)
        XCTAssertTrue(names.allSatisfy { $0.hasPrefix("AppIcon-") })
    }
}
