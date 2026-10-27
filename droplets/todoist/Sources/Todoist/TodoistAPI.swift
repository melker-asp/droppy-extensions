//
//  TodoistAPI.swift
//  Todoist
//
//  A small client for Todoist's API v1 (https://developer.todoist.com/api/v1).
//  Only the calls the droplet makes: list tasks by filter, list projects,
//  quick add, add, close, reopen, and who the token belongs to.
//

import Foundation

enum TodoistAPIError: LocalizedError {
    case unauthorized
    case rateLimited
    case http(Int)
    case transport(String)

    var errorDescription: String? {
        switch self {
        case .unauthorized: return "Todoist godkände inte API-token."
        case .rateLimited: return "Todoist ber oss vänta en stund."
        case .http(let code): return "Todoist svarade \(code)."
        case .transport(let message): return message
        }
    }
}

struct TodoistAPI: Sendable {
    let token: String

    private static let base = URL(string: "https://api.todoist.com/api/v1/")!

    private static let session: URLSession = {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.waitsForConnectivity = false
        return URLSession(configuration: config)
    }()

    // MARK: Reads

    func tasks(filter: String) async throws -> [TodoistTask] {
        try await allPages(path: "tasks/filter", query: [
            URLQueryItem(name: "query", value: filter),
            URLQueryItem(name: "lang", value: "en"),
        ])
    }

    func projects() async throws -> [TodoistProject] {
        try await allPages(path: "projects", query: [])
    }

    func user() async throws -> TodoistUser {
        let data = try await send("GET", "user")
        return try JSONDecoder().decode(TodoistUser.self, from: data)
    }

    // MARK: Writes

    /// Quick add: Todoist reads dates, #projects, @labels and p1–p4 out of
    /// the text, in the language the user's Todoist runs in.
    func quickAdd(_ text: String, note: String?) async throws -> TodoistTask {
        var body: [String: Any] = ["text": text, "auto_reminder": true]
        if let note, !note.isEmpty { body["note"] = note }
        let data = try await send("POST", "tasks/quick", body: body)
        return try JSONDecoder().decode(TodoistTask.self, from: data)
    }

    /// A plain add, for text that should land as written: the composer's
    /// project, date and priority come from its own pickers, so nothing in the
    /// text is reread for dates or hashtags.
    func add(
        content: String,
        description: String?,
        projectID: String? = nil,
        priority: Int? = nil,
        dueString: String?
    ) async throws -> TodoistTask {
        var body: [String: Any] = ["content": content]
        if let description, !description.isEmpty { body["description"] = description }
        if let projectID { body["project_id"] = projectID }
        if let priority { body["priority"] = priority }
        if let dueString, !dueString.isEmpty {
            body["due_string"] = dueString
            body["due_lang"] = "en"
        }
        let data = try await send("POST", "tasks", body: body)
        return try JSONDecoder().decode(TodoistTask.self, from: data)
    }

    /// Moves a task to another day (an English due string) or changes its
    /// priority. Never called with a due string on a recurring task: that
    /// would replace its recurrence.
    func update(_ id: String, dueString: String? = nil, priority: Int? = nil) async throws {
        var body: [String: Any] = [:]
        if let dueString {
            body["due_string"] = dueString
            body["due_lang"] = "en"
        }
        if let priority { body["priority"] = priority }
        _ = try await send("POST", "tasks/\(id)", body: body)
    }

    /// Tasks completed between two instants, for the progress count.
    func completed(since: Date, until: Date) async throws -> [TodoistTask] {
        var items: [TodoistTask] = []
        var cursor: String?
        for _ in 0..<3 {
            var q = [
                URLQueryItem(name: "since", value: TodoistDates.utc(since)),
                URLQueryItem(name: "until", value: TodoistDates.utc(until)),
                URLQueryItem(name: "limit", value: "200"),
            ]
            if let cursor { q.append(URLQueryItem(name: "cursor", value: cursor)) }
            let data = try await send("GET", "tasks/completed/by_completion_date", query: q)
            let page = try JSONDecoder().decode(TodoistCompletedPage.self, from: data)
            items += page.items
            guard let next = page.nextCursor, !next.isEmpty else { break }
            cursor = next
        }
        return items
    }

    func close(_ id: String) async throws {
        _ = try await send("POST", "tasks/\(id)/close")
    }

    func reopen(_ id: String) async throws {
        _ = try await send("POST", "tasks/\(id)/reopen")
    }

    // MARK: Transport

    private func allPages<Item: Decodable>(path: String, query: [URLQueryItem]) async throws -> [Item] {
        var items: [Item] = []
        var cursor: String?
        // Five pages of 200 is a thousand tasks; a filter wider than that is
        // not one the shelf can show anyway.
        for _ in 0..<5 {
            var q = query + [URLQueryItem(name: "limit", value: "200")]
            if let cursor { q.append(URLQueryItem(name: "cursor", value: cursor)) }
            let data = try await send("GET", path, query: q)
            let page = try JSONDecoder().decode(TodoistPage<Item>.self, from: data)
            items += page.results
            guard let next = page.nextCursor, !next.isEmpty else { break }
            cursor = next
        }
        return items
    }

    private func send(
        _ method: String,
        _ path: String,
        query: [URLQueryItem] = [],
        body: [String: Any]? = nil
    ) async throws -> Data {
        var components = URLComponents(url: Self.base.appendingPathComponent(path), resolvingAgainstBaseURL: false)!
        if !query.isEmpty { components.queryItems = query }
        var request = URLRequest(url: components.url!)
        request.httpMethod = method
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        if let body {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
            request.httpBody = try JSONSerialization.data(withJSONObject: body)
        }
        if method == "POST" {
            // Lets Todoist drop a retried write instead of doing it twice.
            request.setValue(UUID().uuidString, forHTTPHeaderField: "X-Request-Id")
        }

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await Self.session.data(for: request)
        } catch {
            throw TodoistAPIError.transport("Kunde inte nå Todoist.")
        }
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300: return data
        case 401, 403: throw TodoistAPIError.unauthorized
        case 429: throw TodoistAPIError.rateLimited
        default: throw TodoistAPIError.http(status)
        }
    }
}
