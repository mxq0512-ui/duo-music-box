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
        let base = Melody.blankTemplate // 64 步
        XCTAssertTrue(base.addingNote(pitchIndex: 8, step: 0).events.isEmpty)
        XCTAssertTrue(base.addingNote(pitchIndex: 0, step: 64).events.isEmpty)
        XCTAssertTrue(base.addingNote(pitchIndex: -1, step: 0).events.isEmpty)
        XCTAssertTrue(base.addingNote(pitchIndex: 0, step: -1).events.isEmpty)
    }

    func testAddingNoteClampsDurationAtEnd() {
        let m = Melody.blankTemplate.addingNote(pitchIndex: 0, step: 63, durationSteps: 4)
        XCTAssertEqual(m.note(pitchIndex: 0, step: 63)?.durationSteps, 1)
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
        XCTAssertEqual(m.stepCount, 64)
        XCTAssertEqual(m.events.count, 28)
        // 四句：C C G G A A G—— / F F E E D D C—— / G G F F E E D—— ×2
        XCTAssertEqual(m.events.map(\.pitchIndex),
                       [0, 0, 4, 4, 5, 5, 4,
                        3, 3, 2, 2, 1, 1, 0,
                        4, 4, 3, 3, 2, 2, 1,
                        4, 4, 3, 3, 2, 2, 1])
        XCTAssertEqual(m.events.map(\.step),
                       [0, 2, 4, 6, 8, 10, 12,
                        16, 18, 20, 22, 24, 26, 28,
                        32, 34, 36, 38, 40, 42, 44,
                        48, 50, 52, 54, 56, 58, 60])
        XCTAssertEqual(m.events.last?.durationSteps, 4, "每句结尾长音用 duration 表达为 4 步")
        for e in m.events {
            XCTAssertTrue((0..<8).contains(e.pitchIndex))
            XCTAssertTrue((0..<64).contains(e.step))
            XCTAssertLessThanOrEqual(e.step + e.durationSteps, 64)
        }
    }

    func testOdeToJoyPresetWithinGrid() {
        let m = Melody.odeToJoy
        XCTAssertEqual(m.stepCount, 64)
        XCTAssertEqual(m.events.count, 30)
        XCTAssertEqual(m.events.map(\.pitchIndex),
                       [2, 2, 3, 4, 4, 3, 2, 1, 0, 0, 1, 2, 2, 1, 1,
                        2, 2, 3, 4, 4, 3, 2, 1, 0, 0, 1, 2, 1, 0, 0])
        XCTAssertTrue(m.events.allSatisfy { $0.step + $0.durationSteps <= m.stepCount })
    }

    // MARK: - Phase 3：64 步默认与旧预置迁移

    func testMakeBlankDefaultsTo64Steps() {
        XCTAssertEqual(Melody.makeBlank(name: "x").stepCount, 64)
        XCTAssertEqual(Melody.blankTemplate.stepCount, 64)
    }

    func testLegacyPresetMigrationReplacesUntouchedOnly() {
        let legacy = Melody.legacyPresets
        XCTAssertEqual(legacy.count, 3)
        XCTAssertTrue(legacy.allSatisfy { $0.stepCount == 16 }, "旧定义必须保持 16 步原样")
        // 用户改动过的旧预置：同 id、不同内容 → 不得被迁移覆盖
        let edited = legacy[0].addingNote(pitchIndex: 7, step: 15)
        // 用户自建旋律 → 原样保留
        let mine = Melody.makeBlank(name: "我的", stepCount: 16).addingNote(pitchIndex: 0, step: 0)
        let migrated = Melody.refreshingLegacyPresets(legacy + [edited, mine])
        XCTAssertEqual(migrated.count, 5)
        XCTAssertEqual(migrated[0], Melody.twinkleTwinkle)
        XCTAssertEqual(migrated[1], Melody.odeToJoy)
        XCTAssertEqual(migrated[2], Melody.blankTemplate)
        XCTAssertEqual(migrated[3], edited, "用户改过的预置必须原样保留")
        XCTAssertEqual(migrated[4], mine)
        // 幂等：再迁一次结果不变
        XCTAssertEqual(Melody.refreshingLegacyPresets(migrated), migrated)
    }
}

final class MelodyLibraryTests: XCTestCase {

    // MARK: - Phase 4：100 首旋律库目录

    func testLibraryCatalogHas100UniqueValidTunes() {
        let catalog = Melody.libraryCatalog
        XCTAssertEqual(catalog.count, 100)
        XCTAssertEqual(Set(catalog.map(\.id)).count, 100, "目录 ID 必须唯一（确定性 ID 按序号生成）")
        XCTAssertEqual(Set(catalog.map(\.name)).count, 100, "目录名称必须唯一")
        XCTAssertEqual(Melody.presets.count, 103, "预置总数 = 小星星 + 欢乐颂 + 100 首目录 + 空白模板")
        for tune in catalog {
            XCTAssertTrue((16...64).contains(tune.stepCount), "\(tune.name) 步数越界")
            XCTAssertGreaterThanOrEqual(tune.events.count, 6, "\(tune.name) 音钉过少")
            for e in tune.events {
                XCTAssertTrue((0..<8).contains(e.pitchIndex), "\(tune.name) 音高越界")
                XCTAssertTrue((0..<tune.stepCount).contains(e.step), "\(tune.name) 步位越界")
                XCTAssertLessThanOrEqual(e.step + e.durationSteps, tune.stepCount,
                                         "\(tune.name) 音符尾巴超出全曲")
            }
        }
        // 五大分类齐全且各有一定规模
        for category in Melody.Category.allCases {
            let count = catalog.filter { Melody.catalogCategory(id: $0.id) == category }.count
            XCTAssertGreaterThanOrEqual(count, 10, "分类 \(category.rawValue) 只有 \(count) 首")
        }
        XCTAssertNil(Melody.catalogCategory(id: Melody.twinkleTwinkle.id), "经典预置不归目录分类")
        XCTAssertNil(Melody.catalogCategory(id: UUID()), "用户自编旋律不归目录分类")
    }

    func testLibraryParserSpotChecks() {
        // 《玛丽有只小羊羔》开头：Mi Re Do Re Mi Mi Mi——（3 2 1 2 3 3 3）
        let mary = Melody.libraryCatalog.first { $0.name == "玛丽有只小羊羔" }
        XCTAssertNotNil(mary)
        XCTAssertEqual(mary?.events.prefix(7).map(\.pitchIndex), [2, 1, 0, 1, 2, 2, 2])
        XCTAssertEqual(mary?.events.prefix(7).map(\.step), [0, 2, 4, 6, 8, 10, 12])
        XCTAssertEqual(mary?.events[6].durationSteps, 4, "句尾长音 3--- 应解析为 4 步")
        // 《平安夜》开头附点节奏：Sol. La Sol Mi. → 首音时长 3 步
        let silent = Melody.libraryCatalog.first { $0.name == "平安夜" }
        XCTAssertEqual(silent?.events.first?.pitchIndex, 4)
        XCTAssertEqual(silent?.events.first?.durationSteps, 3)
    }

    func testScoreExamplesResolve() {
        let examples = Melody.scoreExamples
        XCTAssertEqual(examples.count, 7, "谱例 = 小星星/欢乐颂 + 5 首点名目录曲")
        XCTAssertTrue(examples.allSatisfy { !$0.events.isEmpty })
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

    /// Phase 4 升级路径：老用户库里只有旧预置时，应一次性补入 100 首新目录；
    /// 旧预置里被删掉的（欢乐颂）不复活，新目录里被删掉的也不复活。
    func testUpgradeAppendsCatalogAndRespectsDeletions() throws {
        let key = "duo.knownPresetIDs.v1"
        UserDefaults.standard.set(["11111111-1111-1111-1111-111111111111",
                                   "22222222-2222-2222-2222-222222222222",
                                   "33333333-3333-3333-3333-333333333333"], forKey: key)
        defer { UserDefaults.standard.removeObject(forKey: key) }
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        let data = try encoder.encode([Melody.twinkleTwinkle])
        try data.write(to: tempDir.appendingPathComponent("duo-melodies.json"))

        let store = MelodyStore(documentsDirectory: tempDir)
        XCTAssertEqual(store.melodies.count, 1 + Melody.libraryCatalog.count, "升级应补入全部新目录")
        XCTAssertNotNil(store.melody(id: Melody.twinkleTwinkle.id))
        XCTAssertNil(store.melody(id: Melody.odeToJoy.id), "老用户已删掉的旧预置不应被复活")

        let victim = Melody.libraryCatalog[0]
        store.delete(id: victim.id)
        let reloaded = MelodyStore(documentsDirectory: tempDir)
        XCTAssertNil(reloaded.melody(id: victim.id), "用户删掉的目录旋律不应复活")
        XCTAssertEqual(reloaded.melodies.count, Melody.libraryCatalog.count)
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
        XCTAssertEqual(decoded.melodySnapshot.events.count, 28, "礼物必须自带完整旋律快照")
    }

    /// Phase 4 分享：exportData（分享文件）→ decode（导入）必须无损往返。
    func testGiftShareExportImportRoundTrip() throws {
        let gift = GiftPackage(melody: Melody.odeToJoy,
                               title: "给你的礼物",
                               message: "生日快乐",
                               createdAt: Date(timeIntervalSince1970: 1_700_000_000))
        let decoded = try GiftPackage.decode(data: gift.exportData())
        XCTAssertEqual(gift, decoded)
    }
}
