import CP2077ArchiveCore
import Testing

@Test func fnvKnownDepotPath() {
    #expect(Hashes.fnv1a64Path("base\\characters\\appearances\\main_npc\\example.app") == 0xcb69df8a62b2314b)
}
