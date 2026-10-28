import Foundation

public enum DiaryMCPTools {
    public static let names = ["diary_get_report", "diary_get_timeline", "diary_status", "diary_pause"]

    public static var definitions: [MCPJSONValue] {
        [definition(names[0], "Read a diary report; date defaults to today", properties: ["date": "string"]),
         definition(names[1], "Read text-only diary windows overlapping an ISO8601 range",
                    properties: ["from": "string", "to": "string"], required: ["from", "to"]),
         definition(names[2], "Read diary enabled and pause status", properties: [:]),
         definition(names[3], "Pause diary; minutes defaults to 60", properties: ["minutes": "integer"])]
    }

    public static func request(name: String, arguments: MCPJSONValue) throws -> DiaryAgentRequest {
        guard case .object(let args) = arguments else { throw DiaryAgentError("arguments must be an object") }
        func text(_ key: String) throws -> String? {
            guard let value = args[key] else { return nil }
            guard case .string(let text) = value else { throw DiaryAgentError("\(key) must be a string") }
            return text
        }
        let allowed: Set<String>
        let request: DiaryAgentRequest
        switch name {
        case "diary_get_report":
            allowed = ["date"]
            let date = try text("date")
            if let date { _ = try DiaryAgentJSON.day(date, calendar: .current) }
            request = DiaryAgentRequest(action: date == nil ? .today : .show, date: date)
        case "diary_get_timeline":
            allowed = ["from", "to"]
            let from = try text("from"), to = try text("to")
            guard try DiaryAgentJSON.instant(from) < DiaryAgentJSON.instant(to) else {
                throw DiaryAgentError("from must be earlier than to")
            }
            request = DiaryAgentRequest(action: .timeline, from: from, to: to)
        case "diary_status":
            allowed = []
            request = DiaryAgentRequest(action: .status)
        case "diary_pause":
            allowed = ["minutes"]
            var minutes = 60
            if let value = args["minutes"] {
                guard case .number(let number) = value, number.isFinite,
                      number.rounded() == number, (1...525600).contains(number) else {
                    throw DiaryAgentError("minutes must be an integer from 1 to 525600")
                }
                minutes = Int(number)
            }
            request = DiaryAgentRequest(action: .pause, minutes: minutes)
        default: throw DiaryAgentError("Unknown diary tool: \(name)")
        }
        guard Set(args.keys).isSubset(of: allowed) else { throw DiaryAgentError("Unexpected diary tool argument") }
        return request
    }

    private static func definition(_ name: String, _ description: String, properties: [String: String],
                                   required: [String] = []) -> MCPJSONValue {
        .object(["name": .string(name), "description": .string(description),
            "inputSchema": .object(["type": .string("object"),
                "properties": .object(properties.mapValues { .object(["type": .string($0)]) }),
                "required": .array(required.map { .string($0) }), "additionalProperties": .bool(false)])])
    }
}
