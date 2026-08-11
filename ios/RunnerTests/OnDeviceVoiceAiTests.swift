import XCTest
@testable import Runner

/// Placeholder native tests. Full mic/model tests require a device + .litertlm file.
final class OnDeviceVoiceAiTests: XCTestCase {
  func testCompatibilityDictionaryHasRuntimeKey() {
    let manager = ModelManager()
    let info = manager.checkCompatibility()
    XCTAssertEqual(info["runtime"] as? String, "LiteRT-LM")
    XCTAssertNotNil(info["supported"])
  }
}
