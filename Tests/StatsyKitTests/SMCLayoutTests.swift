import Testing
@testable import StatsyKit

@Suite("SMC request layout")
struct SMCLayoutTests {
    @Test("the request struct matches the kernel's 80-byte layout")
    func matchesKernelLayout() {
        // Every field offset below is what the SMC's struct method expects; a
        // mismatch silently returns garbage rather than failing, so it is
        // pinned here.
        #expect(MemoryLayout<SMCKeyData>.stride == 80)
        #expect(MemoryLayout<SMCKeyData>.size == 80)
        #expect(MemoryLayout<SMCKeyData.Version>.size == 6)
        #expect(MemoryLayout<SMCKeyData.PLimitData>.size == 16)
        #expect(MemoryLayout<SMCKeyData.KeyInfo>.stride == 12)
        #expect(MemoryLayout.offset(of: \SMCKeyData.bytes) == SMCKeyData.payloadOffset)
    }

    @Test("packs and unpacks four-character keys")
    func fourCharCodes() {
        #expect(FourCharCode.decode(FourCharCode.encode("Tp0C")) == "Tp0C")
        #expect(FourCharCode.encode("#KEY") == 0x234B_4559)
        #expect(FourCharCode.encode("toolong") == 0)
    }
}
