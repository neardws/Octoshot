import Foundation

public struct DiaryCLIArguments {
    public let request: DiaryAgentRequest
    public let json: Bool

    public static func parse(_ arguments: [String]) throws -> Self {
        guard let first = arguments.first, let action = DiaryAgentRequest.Action(rawValue: first) else {
            throw DiaryAgentError("diary requires today, show, timeline, export, pause, resume, status, or purge")
        }
        var request = DiaryAgentRequest(action: action)
        var json = false
        var remaining = Array(arguments.dropFirst())
        func take() throws -> String {
            guard !remaining.isEmpty else { throw DiaryAgentError("Missing diary argument") }
            return remaining.removeFirst()
        }
        if action == .show { request.date = try take() }
        if action == .pause {
            guard let minutes = Int(try take()), (1...525600).contains(minutes) else {
                throw DiaryAgentError("minutes must be an integer from 1 to 525600")
            }
            request.minutes = minutes
        }
        var flags: Set<String> = []
        while !remaining.isEmpty {
            let flag = try take()
            guard flags.insert(flag).inserted else { throw DiaryAgentError("Duplicate option: \(flag)") }
            switch flag {
            case "--json" where [.today, .show, .timeline, .status].contains(action): json = true
            case "--confirm" where action == .purge: request.confirmed = true
            case "--date" where action == .export: request.date = try take()
            case "--format" where action == .export:
                let format = try take()
                guard ["md", "json"].contains(format) else { throw DiaryAgentError("format must be md or json") }
                json = format == "json"
            case "--from" where action == .timeline: request.from = try take()
            case "--to" where action == .timeline: request.to = try take()
            default: throw DiaryAgentError("Unexpected diary argument: \(flag)")
            }
        }
        if let date = request.date { _ = try DiaryAgentJSON.day(date, calendar: .current) }
        if action == .timeline {
            guard try DiaryAgentJSON.instant(request.from) < DiaryAgentJSON.instant(request.to) else {
                throw DiaryAgentError("from must be earlier than to")
            }
        }
        if action == .export && !flags.contains("--format") { throw DiaryAgentError("export requires --format md|json") }
        if action == .purge && !request.confirmed { throw DiaryAgentError("purge requires --confirm") }
        return Self(request: request, json: json)
    }
}
