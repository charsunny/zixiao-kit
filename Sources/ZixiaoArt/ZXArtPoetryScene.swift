// Versioned scene composition. No change to the frozen shanshui@1 / @2 / @3 paths.
import Foundation

public extension ZXArt {
    enum PoetryScene: String, Sendable, Hashable, Codable, CaseIterable {
        case retreat = "山居林泉", fishing = "江行渔隐", waterTown = "江南水乡", farewell = "折柳送别"
        case village = "田园村居", spring = "春日花事", lotusPond = "荷塘夏景", autumnTravel = "秋江羁旅"
        case winterForest = "冬雪寒林", moonNight = "月夜怀人", temple = "山寺访僧", courtyard = "庭院闺思"
        case historic = "登高怀古", desert = "边塞大漠", ocean = "海天江潮"
    }

    enum SceneMotif: String, Sendable, Hashable, Codable, CaseIterable {
        case oldTree, bareTree, layeredTree, pine, bamboo, willow, reeds, grass, maple, vine, blossom, lotus
        case bridge, house, hut, pavilion, pagoda, templeGate, courtyard, window, curtain, terrace, ruins, cityGate
        case fence, fields, path, boat, sail, mooredBoat, angler, traveler, horse, egret, crow, swallow, dragonfly, butterfly
        case stream, waterfall, dunes, beaconSmoke, cookingSmoke, mist, moon, crescent, sunrise, sunset, stars, snow, afterRain, rain, waves, reef
    }

    /// Optional, versioned presentation. Missing values preserve the first @5 painting exactly.
    enum ScenePurpose: String, Sendable, Hashable, Codable, CaseIterable {
        case inscription = "inscription-v1", reading = "reading-v1", recommendation = "recommendation-v1"
    }

    enum SceneComposition: String, Sendable, Hashable, Codable, CaseIterable {
        case corner = "corner-v1", oppositeBank = "opposite-bank-v1", depth = "depth-v1"
    }

    /// Persist this selection in the recipe. Rendering never reinterprets the poem or the current date.
    struct SceneOptions: Sendable, Hashable, Codable {
        public var motifs: [SceneMotif]
        public var purpose: ScenePurpose?
        public var composition: SceneComposition?
        public init(motifs: [SceneMotif] = [], purpose: ScenePurpose? = nil, composition: SceneComposition? = nil) {
            self.motifs = motifs; self.purpose = purpose; self.composition = composition
        }
        public var canonicalMotifs: [SceneMotif] {
            let selected = Set(motifs)
            return SceneMotif.allCases.filter(selected.contains)
        }
        public func contains(_ motif: SceneMotif) -> Bool { motifs.contains(motif) }
    }

    struct SceneSelection: Sendable, Hashable {
        public var scene: PoetryScene
        public var options: SceneOptions
        public var matched: [String]

        /// Painterly scene version. The first scene draft (@4) remains reproducible.
        public func paintingProcedural(seed: String, verseSide: String? = "right", columns: Int? = nil, chars: Int? = nil,
                                       purpose: ScenePurpose? = nil, composition: SceneComposition? = nil) -> Procedural {
            var result = procedural(seed: seed, verseSide: verseSide, columns: columns, chars: chars)
            result.generator = "shanshui@5"
            if let purpose {
                var hash: UInt32 = 2_166_136_261
                for byte in seed.utf8 { hash = (hash ^ UInt32(byte)) &* 16_777_619 }
                let candidates: [SceneComposition]
                switch scene {
                case .fishing, .waterTown, .farewell, .lotusPond, .ocean, .desert: candidates = [.oppositeBank, .corner]
                case .retreat, .temple, .historic: candidates = [.depth, .corner]
                default: candidates = SceneComposition.allCases
                }
                result.params.scene?.purpose = purpose
                result.params.scene?.composition = composition ?? candidates[Int(hash) % candidates.count]
                result.params.quietTop = purpose == .recommendation ? 0.22 : (purpose == .reading ? 0.12 : 0.18)
            } else if let composition { result.params.scene?.composition = composition }
            return result
        }

        public func procedural(seed: String, verseSide: String? = "right", columns: Int? = nil, chars: Int? = nil) -> Procedural {
            .init(generator: "shanshui@4", seed: seed, variant: scene.rawValue,
                  params: .init(quietTop: 0.18, verseSide: verseSide, verseColumns: columns, verseChars: chars, scene: options))
        }
    }

    /// Explicit scene evidence outranks broad landscape words. A tune name is not a landscape.
    static func poetryScene(text: String, title: String = "") -> SceneSelection {
        let cleanTitle = title.replacingOccurrences(of: "天净沙", with: "").replacingOccurrences(of: "鹊桥仙", with: "")
        let body = text + "\n" + cleanTitle
        let moonWords = ["正月", "二月", "三月", "四月", "五月", "六月", "七月", "八月", "九月", "十月", "十一月", "十二月", "腊月", "岁月", "年月"]
        let moonText = moonWords.reduce(body) { $0.replacingOccurrences(of: $1, with: "") }
        let rules: [(PoetryScene, [String])] = [
            (.desert, ["大漠", "沙漠", "塞外", "边塞", "关山月", "玉门关", "出塞", "凉州", "燕然"]),
            (.ocean, ["海上", "沧海", "观海", "海潮", "江潮", "潮头", "碣石", "海天"]),
            (.courtyard, ["庭院", "帘幕", "帘卷", "深闺", "楼头", "玉阶", "画堂", "梧桐", "芭蕉"]),
            (.temple, ["古寺", "山寺", "禅院", "禅房", "访僧", "寺后", "僧舍", "寺钟"]),
            (.historic, ["怀古", "幽州台", "古台", "故垒", "故国", "登楼", "城阙", "登高", "登鹳雀楼"]),
            (.lotusPond, ["荷", "莲叶", "采莲", "小池", "菡萏", "芙蕖"]),
            (.farewell, ["送别", "送元", "送友", "送孟", "折柳", "渭城", "阳关", "长亭", "劳劳亭"]),
            (.winterForest, ["江雪", "寒江雪", "风雪", "积雪", "白雪", "寒林", "暮雪", "宿芙蓉山"]),
            (.autumnTravel, ["秋思", "羁旅", "古道", "枯藤", "昏鸦", "秋江", "枫桥", "客愁", "秋浦"]),
            (.village, ["田园", "村居", "归园田居", "田家", "墟里", "炊烟", "稻", "麦", "桑麻", "农家", "柴门"]),
            (.fishing, ["渔", "钓", "蓑", "箬笠", "泛舟", "行舟", "泊舟", "独舟", "独钓"]),
            (.waterTown, ["小桥", "水村", "江南", "流水人家", "水乡", "乌衣巷", "秦淮"]),
            (.retreat, ["山居", "竹里", "幽篁", "松间", "清泉", "瀑", "溪", "山中", "空山", "隐居"]),
            (.spring, ["寻花", "花满", "桃花", "杏花", "春日", "春游", "春色", "芳菲", "踏青"]),
            (.moonNight, ["月", "思乡", "静夜", "夜思", "夜泊", "相思"]),
        ]
        let titleRules: [(PoetryScene, [String])] = [
            (.retreat, ["山居", "竹里", "山中", "寻隐"]), (.fishing, ["渔歌", "渔父", "垂钓", "泛舟"]),
            (.waterTown, ["江南春", "水乡"]), (.farewell, ["送元", "送友", "送别", "送孟", "劳劳亭"]),
            (.village, ["归园田居", "村居", "田家", "田园"]), (.spring, ["寻花", "春日", "春游"]),
            (.lotusPond, ["小池", "采莲", "荷塘"]), (.autumnTravel, ["秋思", "枫桥夜泊", "秋浦"]),
            (.winterForest, ["江雪", "逢雪", "寒林", "暮雪"]), (.moonNight, ["静夜思", "夜思"]),
            (.temple, ["寺", "访僧", "禅院"]), (.courtyard, ["庭院", "闺思"]),
            (.historic, ["怀古", "幽州台", "登楼", "登高", "登鹳雀楼"]),
            (.desert, ["使至塞上", "出塞", "凉州", "边塞"]), (.ocean, ["观沧海", "观海", "江潮"]),
        ]
        let selected = titleRules.first { _, words in words.contains(where: cleanTitle.contains) } ?? rules.first { scene, words in
            let source = scene == .moonNight ? moonText : body
            return words.contains(where: source.contains)
        }
        let scene = selected?.0 ?? .retreat
        var motifs = defaultMotifs(for: scene)
        func has(_ words: [String]) -> Bool { words.contains(where: body.contains) }
        func add(_ motif: SceneMotif, _ words: [String]) { if has(words) { motifs.append(motif) } }
        add(.pine, ["松"]); add(.bamboo, ["竹", "篁"]); add(.willow, ["柳"])
        add(.reeds, ["芦", "荻", "蒹葭"]); add(.maple, ["枫"]); add(.vine, ["藤"])
        add(.blossom, ["桃花", "杏花", "梅", "花满"]); add(.lotus, ["荷", "莲叶", "菡萏"])
        add(.waterfall, ["瀑"]); add(.stream, ["溪", "泉", "长河"]); add(.bridge, ["小桥", "枫桥", "石桥"])
        add(.sail, ["帆"]); add(.mooredBoat, ["泊", "系舟", "系船"]); add(.angler, ["钓"])
        add(.egret, ["鹭"]); add(.crow, ["鸦"]); add(.swallow, ["燕子", "双燕"])
        add(.dragonfly, ["蜻蜓"]); add(.butterfly, ["蝶"]); add(.horse, ["马"])
        add(.traveler, ["归人", "行人", "游子"]); add(.window, ["窗"]); add(.curtain, ["帘"]); add(.stars, ["星", "银河", "天河"])
        // Smoke is not automatically mountain mist. Rain that has ended stays ended.
        let afterRain = has(["雨后", "新雨", "雨歇", "雨霁", "雨过", "初霁"])
        if afterRain { motifs.append(.afterRain) }
        else if has(["雨", "霖"]) { motifs.append(.rain) }
        if has(["雪"]) { motifs.append(.snow); motifs.removeAll { $0 == .rain } }
        if has(["炊烟", "墟里烟", "村烟"]) { motifs.append(.cookingSmoke) }
        if has(["孤烟", "烽烟", "烽火"]) { motifs.append(scene == .desert ? .beaconSmoke : .mist) }
        if has(["雾", "岚", "烟雨", "烟波"]) { motifs.append(.mist) }

        if moonText.contains("月") {
            let phase: SceneMotif = has(["残月", "新月", "晓月", "月落"]) ? .crescent : .moon
            motifs.removeAll { $0 == .moon || $0 == .crescent }
            motifs.append(phase)
            motifs.removeAll { $0 == .sunrise || $0 == .sunset }
        } else if has(["日出", "初日", "朝日", "旭日"]) { motifs.append(.sunrise) }
        else if has(["夕", "落日", "斜阳", "晚", "暮"]) { motifs.append(.sunset) }
        let options = SceneOptions(motifs: motifs)
        return SceneSelection(scene: scene, options: .init(motifs: options.canonicalMotifs),
                              matched: selected.map { $0.1.filter(body.contains) } ?? [])
    }

    static func defaultMotifs(for scene: PoetryScene) -> [SceneMotif] {
        switch scene {
        case .retreat: return [.pine, .bamboo, .stream, .hut]
        case .fishing: return [.boat, .angler, .reeds]
        case .waterTown: return [.bridge, .willow, .house, .mooredBoat]
        case .farewell: return [.willow, .pavilion, .path, .traveler, .mooredBoat]
        case .village: return [.fields, .fence, .house, .path]
        case .spring: return [.blossom, .layeredTree, .path]
        case .lotusPond: return [.lotus, .willow, .dragonfly]
        case .autumnTravel: return [.bareTree, .vine, .path, .crow, .traveler]
        case .winterForest: return [.bareTree, .oldTree, .house, .snow]
        case .moonNight: return [.window, .moon, .boat]
        case .temple: return [.templeGate, .pagoda, .bamboo, .path]
        case .courtyard: return [.courtyard, .window, .curtain, .willow]
        case .historic: return [.terrace, .ruins, .cityGate, .traveler]
        case .desert: return [.dunes]
        case .ocean: return [.waves, .reef]
        }
    }

    struct SceneElement: Sendable, Hashable {
        public var motif: String
        public var bounds: CGRectCodable
        public init(motif: String, bounds: CGRectCodable) { self.motif = motif; self.bounds = bounds }
    }
}
