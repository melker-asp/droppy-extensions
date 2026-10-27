//
//  TodoistModels.swift
//  Todoist
//
//  The slice of Todoist's API v1 objects the droplet reads. Decoding is
//  lenient on purpose: every field the droplet does not need to draw a row is
//  optional, so a field Todoist adds or drops never empties the list.
//

import Foundation
import SwiftUI

struct TodoistTask: Decodable, Identifiable, Equatable, Sendable {
    let id: String
    let content: String
    let description: String?
    let projectID: String?
    let priority: Int
    let due: TodoistDue?
    let dayOrder: Int?
    let childOrder: Int?
    let completedAt: String?

    enum CodingKeys: String, CodingKey {
        case id, content, description, priority, due
        case projectID = "project_id"
        case dayOrder = "day_order"
        case childOrder = "child_order"
        case completedAt = "completed_at"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        content = (try? c.decode(String.self, forKey: .content)) ?? ""
        description = try? c.decodeIfPresent(String.self, forKey: .description)
        projectID = try? c.decodeIfPresent(String.self, forKey: .projectID)
        priority = (try? c.decodeIfPresent(Int.self, forKey: .priority)) ?? 1
        due = try? c.decodeIfPresent(TodoistDue.self, forKey: .due)
        dayOrder = try? c.decodeIfPresent(Int.self, forKey: .dayOrder)
        childOrder = try? c.decodeIfPresent(Int.self, forKey: .childOrder)
        completedAt = try? c.decodeIfPresent(String.self, forKey: .completedAt)
    }

    /// The content without Todoist's Markdown link syntax, so a task made from
    /// "[Kapitel 4](https://…)" reads "Kapitel 4" on the shelf.
    var displayTitle: String {
        let pattern = #"\[([^\]]+)\]\([^)]+\)"#
        return content.replacingOccurrences(of: pattern, with: "$1", options: .regularExpression)
    }

    var priorityLevel: TodoistPriority { TodoistPriority(api: priority) }
}

/// Todoist's priority is inverted in the API: 4 is what the apps call p1. The
/// user's projects read p1–p4 as the Eisenhower matrix, so the labels do too.
enum TodoistPriority: Int, CaseIterable, Identifiable, Sendable {
    case p1 = 4, p2 = 3, p3 = 2, p4 = 1

    init(api: Int) { self = TodoistPriority(rawValue: api) ?? .p4 }

    var id: Int { rawValue }
    var short: String { "P\(5 - rawValue)" }

    var quadrant: String {
        switch self {
        case .p1: return "Bråttom och viktigt"
        case .p2: return "Viktigt"
        case .p3: return "Bråttom"
        case .p4: return "Övrigt"
        }
    }

    var color: Color? {
        switch self {
        case .p1: return Color(red: 1.0, green: 0.42, blue: 0.38)
        case .p2: return Color(red: 0.92, green: 0.54, blue: 0.04)
        case .p3: return Color(red: 0.36, green: 0.56, blue: 0.94)
        case .p4: return nil
        }
    }
}

struct TodoistDue: Decodable, Equatable, Sendable {
    let date: String
    let datetime: String?
    let string: String?
    let isRecurring: Bool

    enum CodingKeys: String, CodingKey {
        case date, datetime, string
        case isRecurring = "is_recurring"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        date = try c.decode(String.self, forKey: .date)
        datetime = try? c.decodeIfPresent(String.self, forKey: .datetime)
        string = try? c.decodeIfPresent(String.self, forKey: .string)
        isRecurring = (try? c.decodeIfPresent(Bool.self, forKey: .isRecurring)) ?? false
    }

    /// The moment the task is due when it has a time, `nil` for an all-day
    /// task. Todoist writes a time either in `datetime` or inside `date`, as a
    /// floating local time ("2026-10-19T14:00:00") or a fixed UTC one ("…Z").
    var time: Date? {
        let raw = datetime ?? date
        guard raw.contains("T") else { return nil }
        return TodoistDates.parseDateTime(raw)
    }

    /// The local calendar day the task is due on.
    var day: Date? {
        if let time { return Calendar.current.startOfDay(for: time) }
        return TodoistDates.day.date(from: String(date.prefix(10)))
    }
}

enum TodoistDates {
    static let day: DateFormatter = {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        f.dateFormat = "yyyy-MM-dd"
        return f
    }()

    static func parseDateTime(_ raw: String) -> Date? {
        if raw.hasSuffix("Z") || raw.contains("+") {
            let iso = ISO8601DateFormatter()
            iso.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
            if let d = iso.date(from: raw) { return d }
            iso.formatOptions = [.withInternetDateTime]
            return iso.date(from: raw)
        }
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = .current
        for format in ["yyyy-MM-dd'T'HH:mm:ss.SSSSSS", "yyyy-MM-dd'T'HH:mm:ss", "yyyy-MM-dd'T'HH:mm"] {
            f.dateFormat = format
            if let d = f.date(from: raw) { return d }
        }
        return nil
    }

    /// For the completed-tasks endpoint, which takes UTC instants.
    static func utc(_ date: Date) -> String {
        let iso = ISO8601DateFormatter()
        iso.formatOptions = [.withInternetDateTime]
        return iso.string(from: date)
    }
}

struct TodoistProject: Decodable, Identifiable, Sendable {
    let id: String
    let name: String
    let color: String
    let isInbox: Bool
    let childOrder: Int

    enum CodingKeys: String, CodingKey {
        case id, name, color
        case isInbox = "inbox_project"
        case childOrder = "child_order"
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = (try? c.decode(String.self, forKey: .name)) ?? ""
        color = (try? c.decodeIfPresent(String.self, forKey: .color)) ?? "charcoal"
        isInbox = (try? c.decodeIfPresent(Bool.self, forKey: .isInbox)) ?? false
        childOrder = (try? c.decodeIfPresent(Int.self, forKey: .childOrder)) ?? 0
    }

    init(id: String, name: String, color: String, isInbox: Bool = false, childOrder: Int = 0) {
        self.id = id; self.name = name; self.color = color; self.isInbox = isInbox; self.childOrder = childOrder
    }

    var displayName: String { isInbox ? "Inkorg" : name }

    /// Todoist's named project colours, lifted a little towards white so the
    /// darker ones still read as text on the shelf's black.
    var tint: Color {
        let hex: UInt32
        switch color {
        case "berry_red": hex = 0xB8256F
        case "red": hex = 0xDB4035
        case "orange": hex = 0xFF9933
        case "yellow": hex = 0xFAD000
        case "olive_green": hex = 0xAFB83B
        case "lime_green": hex = 0x7ECC49
        case "green": hex = 0x299438
        case "mint_green": hex = 0x6ACCBC
        case "teal": hex = 0x158FAD
        case "sky_blue": hex = 0x14AAF5
        case "light_blue": hex = 0x96C3EB
        case "blue": hex = 0x4073FF
        case "grape": hex = 0x884DFF
        case "violet": hex = 0xAF38EB
        case "lavender": hex = 0xEB96EB
        case "magenta": hex = 0xE05194
        case "salmon": hex = 0xFF8D85
        case "taupe": hex = 0xCCAC93
        case "grey", "gray": hex = 0xB8B8B8
        default: return Color.white.opacity(0.6)
        }
        let lift = 0.25
        func channel(_ shift: UInt32) -> Double {
            let v = Double((hex >> shift) & 0xFF) / 255
            return v + (1 - v) * lift
        }
        return Color(red: channel(16), green: channel(8), blue: channel(0))
    }
}

struct TodoistUser: Decodable, Sendable {
    let fullName: String?
    let email: String?

    enum CodingKeys: String, CodingKey {
        case fullName = "full_name"
        case email
    }
}

/// One page of a list endpoint.
struct TodoistPage<Item: Decodable>: Decodable {
    let results: [Item]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case results
        case nextCursor = "next_cursor"
    }
}

/// One page of the completed-tasks endpoint, which names its list `items`.
struct TodoistCompletedPage: Decodable {
    let items: [TodoistTask]
    let nextCursor: String?

    enum CodingKeys: String, CodingKey {
        case items
        case nextCursor = "next_cursor"
    }
}

/// A date the composer offers, sent to Todoist as an English due string.
struct TodoistDueOption: Identifiable, Equatable, Sendable {
    let id: String
    let title: String
    let dueString: String?

    static let none = TodoistDueOption(id: "none", title: "Inget datum", dueString: nil)

    /// No date, today, tomorrow, the four named days after that, next week.
    static func all(from now: Date = Date()) -> [TodoistDueOption] {
        var options: [TodoistDueOption] = [
            .none,
            TodoistDueOption(id: "today", title: "Idag", dueString: "today"),
            TodoistDueOption(id: "tomorrow", title: "Imorgon", dueString: "tomorrow"),
        ]
        let cal = Calendar.current
        let sv = DateFormatter(); sv.locale = Locale(identifier: "sv_SE"); sv.dateFormat = "EEEE"
        let en = DateFormatter(); en.locale = Locale(identifier: "en_US_POSIX"); en.dateFormat = "EEEE"
        for offset in 2...5 {
            guard let day = cal.date(byAdding: .day, value: offset, to: now) else { continue }
            options.append(TodoistDueOption(
                id: "day\(offset)",
                title: sv.string(from: day).capitalized,
                dueString: en.string(from: day).lowercased()
            ))
        }
        options.append(TodoistDueOption(id: "nextweek", title: "Nästa vecka", dueString: "next week"))
        return options
    }
}
