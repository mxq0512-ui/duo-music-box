import XCTest
@testable import DuoMusicBox

final class MelodyTests: XCTestCase {

    // MARK: - Pitch

    func testPitchFrequencies() {
        XCTAssertEqual(Pitch.c5.frequency, 523.25, accuracy: 0.01)
        XCTAssertEqual(Pitch.a5.frequency, 880.00, accuracy: 0.01)
        XCTAssertEqual(Pitch.c6.frequency, 1046.50, accuracy: 0.01)
        let freqs = Pitch.allCases.map(\.frequency)
        XCTAssertEqual(freqs, freqs.sorted(), "8 个音高频率必须单调递增")
        XCTAssertEqual(Pitch.allCases.count, Melody.pitchCount)
    }

    // MARK: - 编解码 round-trip

    func testMelodyCodableRoundTrip() throws {
        let original = Melody.twinkleTwinkle
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(Melody.self, from: data)
        XCTAssertEqual(original, decoded)
    }

    func testNoteEventCodableRoundTrip() throws {
        let event = NoteEvent(pitchIndex: 5, step: 9, durationSteps: 3, velocity: 0.7)
        let data = try JSONEncoder().encode(event)
        let decoded = try JSONDecoder().decode(NoteEvent.self, from: data)
        XCTAssertEqual(event, decoded)
    }

    // MARK: - 纯函数式编辑

    func testToggleNoteAddsThenRemoves() {
        let base = Melody.blankTemplate
        let added = base.togglingNote(pitchIndex: 3, step: 5)
        XCTAssertEqual(added.events.count, 1)
        XCTAssertTrue(added.hasNote(pitchIndex: 3, step: 5))
        // 原值不被修改（纯函数式）
        XCTAssertTrue(base.events.isEmpty)

        let removed = added.togglingNote(pitchIndex: 3, step: 5)
        XCTAssertTrue(removed.events.isEmpty)
    }

    func testAddingNoteReplacesSameCell() {
        var m = Melody.blankTemplate
        m = m.addingNote(pitchIndex: 2, step: 4, durationSteps: 1)
        m = m.addingNote(pitchIndex: 2, step: 4, durationSteps: 3)
        XCTAssertEqual(m.events.count, 1, "同格重复装钉应替换而非叠加")
        XCTAssertEqual(m.note(pitchIndex: 2, step: 4)?.durationSteps, 3)
    }

    func testAddingNoteOutOfBoundsIgnored() {
        let base = Melody.blankTemplate // 16 步
        XCTAssertTrue(base.addingNote(pitchIndex: 8, step: 0).events.isEmpty)
        XCTAssertTrue(base.addingNote(pitchIndex: 0, step: 16).events.isEmpty)
        XCTAssertTrue(base.addingNote(pitchIndex: -1, step: 0).events.isEmpty)
        XCTAssertTrue(base.addingNote(pitchIndex: 0, step: -1).events.isEmpty)
    }

    func testAddingNoteClampsDurationAtEnd() {
        let m = Melody.blankTemplate.addingNote(pitchIndex: 0, step: 15, durationSteps: 4)
        XCTAssertEqual(m.note(pitchIndex: 0, step: 15)?.durationSteps, 1)
    }

    func testEventsAtStepSortedByPitch() {
        var m = Melody.blankTemplate
        m = m.addingNote(pitchIndex: 7, step: 0)
        m = m.addingNote(pitchIndex: 0, step: 0)
        m = m.addingNote(pitchIndex: 4, step: 0)
        XCTAssertEqual(m.events(atStep: 0).map(\.pitchIndex), [0, 4, 7])
        XCTAssertTrue(m.events(atStep: 1).isEmpty)
    }

    func testResizedDropsOverflowEvents() {
        var m = Melody.makeBlank(name: "t", stepCount: 32)
        m = m.addingNote(pitchIndex: 0, step: 20)
        let shrunk = m.resized(stepCount: 16)
        XCTAssertEqual(shrunk.stepCount, 16)
        XCTAssertTrue(shrunk.events.isEmpty)
    }

    // MARK: - 预置旋律

    func testTwinklePresetShape() {
        let m = Melody.twinkleTwinkle
        XCTAssertEqual(m.stepCount, 16)
        XCTAssertEqual(m.events.count, 7)
        // C C G G A A G——
        XCTAssertEqual(m.events.map(\.pitchIndex), [0, 0, 4, 4, 5, 5, 4])
        XCTAssertEqual(m.events.map(\.step), [0, 2, 4, 6, 8, 10, 12])
        XCTAssertEqual(m.events.last?.durationSteps, 4, "结尾长音用 duration 表达为 4 步")
        for e in m.events {
            XCTAssertTrue((0..<8).contains(e.pitchIndex))
            XCTAssertTrue((0..<16).contains(e.step))
            XCTAssertLessThanOrEqual(e.step + e.durationSteps, 16)
        }
    }

    func testOdeToJoyPresetWithinGrid() {
        let m = Melody.odeToJoy
        XCTAssertEqual(m.events.count, 8)
        XCTAssertEqual(m.events.map(\.pitchIndex), [2, 2, 3, 4, 4, 3, 2, 1])
        XCTAssertTrue(m.events.allSatisfy { $0.step + $0.durationSteps <= m.stepCount })
    }
}

final class MelodyStoreTests: XCTestCase {
    private var tempDir: URL!

    override func setUpWithError() throws {
        tempDir = FileManager.default.temporaryDirectory
            .appendingPathComponent("duo-tests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: tempDir, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: tempDir)
    }

    func testFirstLaunchSeedsPresets() {
        let store = MelodyStore(documentsDirectory: tempDir)
        XCTAssertEqual(store.melodies.count, Melody.presets.count)
        XCTAssertNotNil(store.melody(id: Melody.twinkleTwinkle.id))
    }

    func testSaveRenameDeletePersistAcrossInstances() {
        let store = MelodyStore(documentsDirectory: tempDir)
        let mine = Melody.makeBlank(name: "我的第一首")
            .addingNote(pitchIndex: 0, step: 0)
        store.save(mine)
        store.rename(id: mine.id, to: "改名了")

        let reloaded = MelodyStore(documentsDirectory: tempDir)
        XCTAssertEqual(reloaded.melody(id: mine.id)?.name, "改名了")
        XCTAssertEqual(reloaded.melody(id: mine.id)?.events.count, 1)

        reloaded.delete(id: mine.id)
        let again = MelodyStore(documentsDirectory: tempDir)
        XCTAssertNil(again.melody(id: mine.id))
    }

    func testDeletingAllDoesNotReseed() {
        let store = MelodyStore(documentsDirectory: tempDir)
        for m in store.melodies { store.delete(id: m.id) }
        XCTAssertTrue(store.melodies.isEmpty)
        let reloaded = MelodyStore(documentsDirectory: tempDir)
        XCTAssertTrue(reloaded.melodies.isEmpty, "文件已存在时不应重新播种预置")
    }
}

final class GiftPackageTests: XCTestCase {
    func testGiftPackageCodableRoundTrip() throws {
        let gift = GiftPackage(melody: Melody.twinkleTwinkle,
                               title: "生日快乐",
                               message: "送给你",
                               createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        let data = try encoder.encode(gift)
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        let decoded = try decoder.decode(GiftPackage.self, from: data)
        XCTAssertEqual(gift, decoded)
        XCTAssertEqual(decoded.melodyId, Melody.twinkleTwinkle.id)
        XCTAssertEqual(decoded.melodySnapshot.events.count, 7, "礼物必须自带完整旋律快照")
    }
}
