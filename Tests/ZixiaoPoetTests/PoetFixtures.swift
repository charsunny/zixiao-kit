@testable import ZixiaoPoetCore
import Foundation
@testable import ZixiaoPoet

/// 占位诗人 / 占位产品的测试数据。内核测试里不出现真实诗人。
enum PoetFixtures {
    static var workspaceRoot: URL {
        if let path = ProcessInfo.processInfo.environment["ZX_TEST_WORKSPACE_ROOT"] {
            return URL(fileURLWithPath: path)
        }
        return URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
    }

    static func compositionJSON(cards: [String], includesOnThisDayConfig: Bool, dayPrecise: Int) throws -> String {
        let cardJSON = cards.map { "\"\($0)\"" }.joined(separator: ",")
        let onThisDay = includesOnThisDayConfig
            ? #", "onThisDay": {"calendar":"lunar","fallback":"hide"}"#
            : ""
        return """
        {
          "schemaVersion": 1,
          "poet": {"slug":"test","name":"测试","dynasty":"tang","birth":700,"death":760},
          "app": {"bundleId":"com.example.test","displayName":"测试志"},
          "capabilities": {
            "daily": {"prominence":"tab","label":"今日","order":0,"cards":[\(cardJSON)]\(onThisDay)},
            "corpus": {"prominence":"tab","label":"读本","order":1,"genres":[]}
          },
          "identity": {
            "era":"唐","rationale":"测试",
            "palette":{"paper":"#FFFFFF","ink":"#000000","accent":"#555555","seal":"#884433","rule":"#CCCCCC","night":"#111111"},
            "type":{"display":"system","body":"system","ui":"system"},
            "slots":{},
            "chronology":{"style":"era-name"}
          },
          "data":{"events":{"count":\(dayPrecise),"dayPrecise":\(dayPrecise)}}
        }
        """
    }

    static func composition(cards: [String], includesOnThisDayConfig: Bool, dayPrecise: Int) throws -> PoetComposition {
        let json = try compositionJSON(cards: cards, includesOnThisDayConfig: includesOnThisDayConfig,
                                       dayPrecise: dayPrecise)
        return try JSONDecoder().decode(PoetComposition.self, from: Data(json.utf8))
    }

    /// 临时目录当「包」: 写入给定文件后用 `Bundle(url:)` 打开。
    static func bundle(files: [String: String]) throws -> Bundle {
        let dir = FileManager.default.temporaryDirectory
            .appendingPathComponent("ZixiaoPoetTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        for (name, content) in files {
            try Data(content.utf8).write(to: dir.appendingPathComponent(name))
        }
        guard let bundle = Bundle(url: dir) else { throw CocoaError(.fileNoSuchFile) }
        return bundle
    }

    static let poemA = "11111111-1111-4111-8111-111111111111"
    static let poemB = "22222222-2222-4222-8222-222222222222"

    /// 两章、每章一篇的占位导读。
    static let guideJSON = """
    {
      "biography": "占位小传。", "chronologyNote": "占位。", "snapshotDate": "2026-10-01",
      "yearCounts": {"700": 3, "701": 1},
      "chapters": [
        {"epoch": {"sequence": 1, "label": "少年", "year_start": 700, "year_end": 720},
         "introduction": "第一章。", "paragraphs": ["一段。"], "milestones": [],
         "workIDs": ["\(poemA)"], "sourceIDs": ["s1"]},
        {"epoch": {"sequence": 2, "label": "晚年", "year_start": 721, "year_end": 760},
         "introduction": "第二章。", "paragraphs": ["二段。"], "milestones": [],
         "workIDs": ["\(poemB)"], "sourceIDs": ["s1"]}
      ],
      "places": [], "visits": [], "featured": [],
      "poems": [
        {"id": "\(poemA)", "title": "其一", "form": "shi", "content": "占位诗句一"},
        {"id": "\(poemB)", "title": "其二", "form": "shi", "content": "占位诗句二"}
      ],
      "sources": [{"id": "s1", "title": "占位来源", "note": "测试"}]
    }
    """
}
