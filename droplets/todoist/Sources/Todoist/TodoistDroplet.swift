//
//  TodoistDroplet.swift
//  Todoist
//
//  Today's Todoist tasks on the shelf, a reminder in the notch before a task
//  with a time, and quick add from the shelf or from any app through
//  droppy://droplet/todoist/add.
//

import AppKit
import Combine
import DroppyKit
import SwiftUI

/// The class Droppy's loader instantiates, named in the bundle's
/// `NSPrincipalClass`. Keep it empty: it runs before the host is ready.
@objc(TodoistPrincipal)
public final class TodoistPrincipal: NSObject, DropletPrincipal {
    public override init() { super.init() }

    @MainActor public func makeDroplet() -> AnyObject { TodoistDroplet() }
}

@MainActor
public final class TodoistDroplet: NSObject, ObservableObject, Droplet {
    /// Must equal `DroppyDropletID` in the bundle's Info.plist and `id` in
    /// droplet.json. The loader refuses the bundle if the three disagree.
    public nonisolated static let id: DropletID = "todoist"

    static let widgetID: ShelfWidgetID = "today"

    private(set) var host: DropletHost?

    // MARK: State the views read

    /// Overdue tasks and the next seven days, sorted.
    @Published private(set) var tasks: [TodoistTask] = []
    @Published private(set) var projects: [TodoistProject] = []
    @Published private(set) var completedToday = 0
    @Published private(set) var completedThisWeek = 0
    @Published private(set) var hasToken = false
    @Published private(set) var isLoading = false
    @Published private(set) var lastError: String?
    @Published private(set) var lastSync: Date?
    @Published private(set) var completing: Set<String> = []
    @Published private(set) var undoable: TodoistTask?
    @Published private(set) var accountName: String?
    @Published private(set) var now = Date()

    // Composer

    /// The quick add field's text, shared by every copy of the widget.
    @Published var draft = "" { didSet { if draft.isEmpty != oldValue.isEmpty { relayout() } } }
    /// A note that rides along with the draft, set when a link from another
    /// app opened the field (the page the text was selected on).
    @Published private(set) var draftNote: String?
    @Published var composerProjectID: String?
    @Published var composerDue: TodoistDueOption = .none
    @Published var composerPriority: TodoistPriority = .p4
    /// Which part of the result line has its list open.
    @Published var openPicker: ComposerPicker? { didSet { relayout() } }
    @Published private(set) var isAdding = false
    /// A line in the field's place for a few seconds after an add.
    @Published private(set) var flash: String?
    /// Bumped to ask the widget to focus its field.
    @Published private(set) var focusRequest = 0

    /// The task the notch is counting down to, if any.
    @Published private(set) var upcoming: TodoistTask?

    enum ComposerPicker { case project, due, priority }

    private let activitySubject = CurrentValueSubject<LiveActivityState?, Never>(nil)
    var activityPublisher: AnyPublisher<LiveActivityState?, Never> { activitySubject.eraseToAnyPublisher() }
    let lockScreenSubject = CurrentValueSubject<LockScreenStatusEntry?, Never>(nil)

    private var ticker: AnyCancellable?
    private var shelfObserver: AnyCancellable?
    private var refreshLoop: Task<Void, Never>?
    private var undoTimer: Task<Void, Never>?
    private var flashTimer: Task<Void, Never>?
    private var remindedKeys: Set<String> = []
    private var measuredHeight: CGFloat = 0
    /// True while the harness shows sample tasks; nothing syncs then.
    private var isSample = false

    // MARK: Lifecycle

    public func activate(host: DropletHost) throws {
        self.host = host
        hasToken = TodoistKeychain.token() != nil
        resetComposer()
        if host.environment.isHarness && !hasToken { loadHarnessSample() }

        ticker = Timer.publish(every: 20, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in
                guard let self else { return }
                let crossedMidnight = !Calendar.current.isDate(date, inSameDayAs: self.now)
                self.now = date
                if crossedMidnight { self.refresh() }
                self.evaluateReminder()
            }

        // Opening the shelf refreshes a list that is more than a minute old,
        // so what the user looks at is current without polling fast.
        shelfObserver = host.shelf.didChange
            .receive(on: RunLoop.main)
            .sink { [weak self] in
                guard let self, let host = self.host, host.shelf.isExpanded else { return }
                if (self.lastSync.map { Date().timeIntervalSince($0) > 60 } ?? true) { self.refresh() }
            }

        refreshLoop = Task { [weak self] in
            while !Task.isCancelled {
                await self?.refreshNow()
                try? await Task.sleep(for: .seconds(300))
            }
        }
    }

    public func deactivate() {
        ticker?.cancel(); ticker = nil
        shelfObserver?.cancel(); shelfObserver = nil
        refreshLoop?.cancel(); refreshLoop = nil
        undoTimer?.cancel(); undoTimer = nil
        flashTimer?.cancel(); flashTimer = nil
        activitySubject.send(nil)
        lockScreenSubject.send(nil)
        host = nil
    }

    // MARK: Preferences

    var showsUpcoming: Bool { host?.preferences.value(forKey: "showUpcoming", default: true) ?? true }
    var showsMatrix: Bool { host?.preferences.value(forKey: "view", default: "list") == "matrix" }
    var remindsBeforeTasks: Bool { host?.preferences.value(forKey: "remind", default: true) ?? true }
    var reminderLeadMinutes: Double { host?.preferences.value(forKey: "remindLead", default: 15.0) ?? 15 }
    var acceptsLinks: Bool { host?.preferences.value(forKey: "acceptLinks", default: true) ?? true }
    private var lastProjectID: String? { host?.preferences.value(forKey: "lastProject", as: String.self) }

    func binding<Value: Codable>(_ key: String, default value: Value, then: (() -> Void)? = nil) -> Binding<Value> {
        Binding(
            get: { self.host?.preferences.value(forKey: key, default: value) ?? value },
            set: {
                self.objectWillChange.send()
                self.host?.preferences.setValue($0, forKey: key)
                then?()
            }
        )
    }

    func toggleView() {
        objectWillChange.send()
        host?.preferences.setValue(showsMatrix ? "list" : "matrix", forKey: "view")
        relayout()
    }

    // MARK: Derived lists

    private var startOfToday: Date { Calendar.current.startOfDay(for: now) }

    private var open: [TodoistTask] { tasks.filter { !completing.contains($0.id) } }

    var overdue: [TodoistTask] { open.filter { ($0.due?.day ?? .distantFuture) < startOfToday } }
    var dueToday: [TodoistTask] { open.filter { $0.due?.day == startOfToday } }
    var later: [TodoistTask] { open.filter { ($0.due?.day ?? .distantPast) > startOfToday } }

    /// What the list shows under Kommande: a few, so today stays the focus.
    var laterShown: [TodoistTask] { showsUpcoming ? Array(later.prefix(3)) : [] }

    var remainingToday: Int { overdue.count + dueToday.count }
    var totalToday: Int { remainingToday + completedToday }
    var progress: Double { totalToday == 0 ? 0 : Double(completedToday) / Double(totalToday) }

    /// The next task to point at: one with a time today first, else the
    /// first open task today, else the first one coming up.
    var nextTask: TodoistTask? {
        let timed = (overdue + dueToday).filter { ($0.due?.time ?? .distantPast) > now }
        return timed.min { ($0.due?.time ?? .distantFuture) < ($1.due?.time ?? .distantFuture) }
            ?? dueToday.first ?? overdue.first ?? later.first
    }

    func project(_ id: String?) -> TodoistProject? {
        guard let id else { return nil }
        return projects.first { $0.id == id }
    }

    var inboxProject: TodoistProject? { projects.first { $0.isInbox } }

    /// Inbox first, then the user's projects in their own order.
    var composerProjects: [TodoistProject] {
        projects.filter(\.isInbox) + projects.filter { !$0.isInbox }.sorted { $0.childOrder < $1.childOrder }
    }

    var composerProject: TodoistProject? { project(composerProjectID) ?? inboxProject }

    // MARK: Token

    /// Checks the token against Todoist before keeping it, so a typo is
    /// caught here and not as an empty widget later.
    func connect(token raw: String) async -> String? {
        let token = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !token.isEmpty else { return "Klistra in din API-token." }
        do {
            let user = try await TodoistAPI(token: token).user()
            guard TodoistKeychain.save(token) else { return "Kunde inte spara i nyckelringen." }
            isSample = false
            hasToken = true
            accountName = user.fullName ?? user.email
            lastError = nil
            relayout()
            await refreshNow()
            return nil
        } catch {
            return (error as? LocalizedError)?.errorDescription ?? "Kunde inte ansluta."
        }
    }

    func disconnect() {
        TodoistKeychain.delete()
        hasToken = false
        accountName = nil
        tasks = []
        projects = []
        completedToday = 0
        completedThisWeek = 0
        lastSync = nil
        upcoming = nil
        activitySubject.send(nil)
        lockScreenSubject.send(nil)
        relayout()
    }

    // MARK: Sync

    func refresh() {
        Task { await refreshNow() }
    }

    private func refreshNow() async {
        guard !isSample else { return }
        guard let token = TodoistKeychain.token() else {
            hasToken = false
            return
        }
        hasToken = true
        guard !isLoading else { return }
        isLoading = true
        defer { isLoading = false }
        let api = TodoistAPI(token: token)
        let cal = Calendar.current
        let weekStart = cal.dateInterval(of: .weekOfYear, for: Date())?.start ?? cal.startOfDay(for: Date())
        do {
            async let fetchedTasks = api.tasks(filter: "overdue | 7 days")
            async let fetchedProjects = api.projects()
            async let fetchedDone = api.completed(since: weekStart, until: Date())
            let (list, projectList) = try await (fetchedTasks, fetchedProjects)
            projects = projectList
            if composerProjectID == nil || project(composerProjectID) == nil { resetComposer() }
            // Progress is a nicety: a failure there must not empty the list.
            if let done = try? await fetchedDone {
                let today = cal.startOfDay(for: Date())
                completedThisWeek = done.count
                completedToday = done.filter {
                    ($0.completedAt.flatMap(TodoistDates.parseDateTime) ?? .distantPast) >= today
                }.count
            }
            if accountName == nil, let user = try? await api.user() {
                accountName = user.fullName ?? user.email
            }
            tasks = sorted(list).filter { !completing.contains($0.id) }
            lastSync = Date()
            lastError = nil
            relayout()
            evaluateReminder()
            publishLockScreen()
        } catch {
            lastError = (error as? LocalizedError)?.errorDescription ?? "Kunde inte hämta uppgifter."
            host?.log.error("refresh failed: \(lastError ?? "")")
        }
    }

    /// Overdue first, then by day, then by time, then priority, then the
    /// order Todoist keeps for the day.
    private func sorted(_ list: [TodoistTask]) -> [TodoistTask] {
        list.sorted { a, b in
            let ad = a.due?.day ?? .distantFuture, bd = b.due?.day ?? .distantFuture
            if ad != bd { return ad < bd }
            switch (a.due?.time, b.due?.time) {
            case let (x?, y?) where x != y: return x < y
            case (_?, nil): return true
            case (nil, _?): return false
            default: break
            }
            if a.priority != b.priority { return a.priority > b.priority }
            return (a.dayOrder ?? a.childOrder ?? 0) < (b.dayOrder ?? b.childOrder ?? 0)
        }
    }

    // MARK: Actions on a task

    func complete(_ task: TodoistTask) {
        guard !completing.contains(task.id) else { return }
        withAnimation(DroppyAnimation.state) { _ = completing.insert(task.id) }
        Task {
            // Long enough to see the check land before the row goes.
            try? await Task.sleep(for: .milliseconds(450))
            let countsToday = (task.due?.day ?? .distantFuture) <= startOfToday
            withAnimation(DroppyAnimation.state) {
                tasks.removeAll { $0.id == task.id }
                if countsToday { completedToday += 1 }
                completedThisWeek += 1
            }
            relayout()
            publishLockScreen()
            guard let token = TodoistKeychain.token() else { completing.remove(task.id); return }
            do {
                try await TodoistAPI(token: token).close(task.id)
                completing.remove(task.id)
                host?.feedback.play(.success)
                // A recurring task moves to its next date when closed; reopening
                // it would not move it back, so it gets no undo.
                if task.due?.isRecurring != true { offerUndo(task) }
                evaluateReminder()
            } catch {
                completing.remove(task.id)
                lastError = (error as? LocalizedError)?.errorDescription
                await refreshNow()
            }
        }
    }

    func undo() {
        guard let task = undoable, let token = TodoistKeychain.token() else { return }
        undoable = nil
        Task {
            try? await TodoistAPI(token: token).reopen(task.id)
            await refreshNow()
        }
    }

    private func offerUndo(_ task: TodoistTask) {
        undoable = task
        undoTimer?.cancel()
        undoTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(6))
            guard !Task.isCancelled else { return }
            withAnimation(DroppyAnimation.state) { self?.undoable = nil }
        }
    }

    /// Moves a one-off task to tomorrow. Recurring tasks never get here.
    func postpone(_ task: TodoistTask) {
        guard task.due?.isRecurring != true, let token = TodoistKeychain.token() else { return }
        withAnimation(DroppyAnimation.state) { tasks.removeAll { $0.id == task.id } }
        Task {
            do {
                try await TodoistAPI(token: token).update(task.id, dueString: "tomorrow")
            } catch {
                lastError = (error as? LocalizedError)?.errorDescription
            }
            await refreshNow()
        }
    }

    func setPriority(_ task: TodoistTask, _ priority: TodoistPriority) {
        guard let token = TodoistKeychain.token(), task.priority != priority.rawValue else { return }
        Task {
            do {
                try await TodoistAPI(token: token).update(task.id, priority: priority.rawValue)
            } catch {
                lastError = (error as? LocalizedError)?.errorDescription
            }
            await refreshNow()
        }
    }

    func open(_ task: TodoistTask) {
        openInTodoist(
            app: URL(string: "todoist://task?id=\(task.id)")!,
            web: URL(string: "https://app.todoist.com/app/task/\(task.id)")!
        )
    }

    func openTodoist() {
        openInTodoist(app: URL(string: "todoist://today")!, web: URL(string: "https://app.todoist.com/app/today")!)
    }

    /// The Todoist app when it is installed, the web app otherwise.
    ///
    /// `host.workspace.open` only passes http, https, mailto and file URLs,
    /// so the app's own `todoist://` link goes through NSWorkspace, the way
    /// Droppy's Thaw droplet drives Thaw. The droplet runs in Droppy's
    /// process, so this opens it exactly as Droppy would.
    private func openInTodoist(app: URL, web: URL) {
        guard NSWorkspace.shared.urlForApplication(toOpen: app) != nil else {
            host?.workspace.open(web)
            return
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        NSWorkspace.shared.open(app, configuration: configuration) { [weak self] _, error in
            guard error != nil else { return }
            Task { @MainActor in self?.host?.workspace.open(web) }
        }
    }

    func openSettings() {
        _ = host?.workspace.openSettings()
    }

    // MARK: Composer

    /// The project last added to, no date, P4.
    private func resetComposer() {
        composerProjectID = project(lastProjectID)?.id ?? lastProjectID ?? inboxProject?.id
        composerDue = .none
        composerPriority = .p4
    }

    func togglePicker(_ picker: ComposerPicker) {
        withAnimation(DroppyAnimation.state) { openPicker = openPicker == picker ? nil : picker }
    }

    func choose(project: TodoistProject) {
        composerProjectID = project.id
        withAnimation(DroppyAnimation.state) { openPicker = nil }
    }

    func choose(due: TodoistDueOption) {
        composerDue = due
        withAnimation(DroppyAnimation.state) { openPicker = nil }
    }

    func choose(priority: TodoistPriority) {
        composerPriority = priority
        withAnimation(DroppyAnimation.state) { openPicker = nil }
    }

    func cancelDraft() {
        draft = ""
        draftNote = nil
        openPicker = nil
        resetComposer()
    }

    func clearDraftNote() { draftNote = nil }

    /// Adds the field's text with the project, date and priority the result
    /// line shows. The text goes in as written.
    func submitDraft() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !isAdding, let token = TodoistKeychain.token() else { return }
        isAdding = true
        let note = draftNote
        let projectID = composerProject?.id
        let due = composerDue
        let priority = composerPriority
        Task {
            defer { isAdding = false }
            do {
                _ = try await TodoistAPI(token: token).add(
                    content: text,
                    description: note,
                    projectID: projectID,
                    priority: priority.rawValue,
                    dueString: due.dueString
                )
                if let projectID { host?.preferences.setValue(projectID, forKey: "lastProject") }
                let projectName = project(projectID)?.displayName ?? "Inkorg"
                draft = ""
                draftNote = nil
                openPicker = nil
                resetComposer()
                host?.feedback.play(.success)
                showFlash("Tillagd i \(projectName)" + (due.dueString == nil ? "" : " · \(due.title)"))
                await refreshNow()
            } catch {
                showFlash((error as? LocalizedError)?.errorDescription ?? "Kunde inte lägga till.")
            }
        }
    }

    private func showFlash(_ text: String) {
        withAnimation(DroppyAnimation.state) { flash = text }
        flashTimer?.cancel()
        flashTimer = Task { [weak self] in
            try? await Task.sleep(for: .seconds(4))
            guard !Task.isCancelled else { return }
            withAnimation(DroppyAnimation.state) { self?.flash = nil }
        }
    }

    // MARK: Layout

    /// Re-measures the widget when the height it needs changes, not on every
    /// sync or keystroke.
    func relayout() {
        let height = TodoistLayout.height(for: self)
        guard height != measuredHeight else { return }
        measuredHeight = height
        host?.shelf.invalidateLayout(for: Self.widgetID)
    }

    // MARK: Reminder

    /// The task with a time that is due within the lead time, or started less
    /// than ten minutes ago.
    private func evaluateReminder() {
        guard hasToken, remindsBeforeTasks else {
            if upcoming != nil { upcoming = nil }
            activitySubject.send(nil)
            return
        }
        let lead = reminderLeadMinutes * 60
        let current = Date()
        let next = open
            .compactMap { task -> (TodoistTask, Date)? in
                guard let time = task.due?.time else { return nil }
                let delta = time.timeIntervalSince(current)
                return (delta <= lead && delta > -600) ? (task, time) : nil
            }
            .min { $0.1 < $1.1 }

        guard let (task, time) = next else {
            if upcoming != nil { upcoming = nil }
            activitySubject.send(nil)
            return
        }
        upcoming = task
        let label = Self.countdown(to: time, now: current)
        activitySubject.send(
            LiveActivityState(
                priority: 150,
                accessibilityTitle: "\(task.displayTitle), \(label.spoken)",
                isInteractive: false
            )
        )

        // One card on the notch when the reminder starts, so it is seen even
        // while media or the shelf holds the live activity seat.
        let key = task.id + "@" + String(Int(time.timeIntervalSince1970))
        if !remindedKeys.contains(key) {
            remindedKeys.insert(key)
            presentHUD(title: label.long, detail: task.displayTitle, symbol: "bell.fill")
        }
    }

    static func countdown(to time: Date, now: Date) -> (short: String, long: String, spoken: String) {
        let minutes = Int((time.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return ("Nu", "Nu", "nu") }
        if minutes < 60 { return ("\(minutes) min", "Om \(minutes) min", "om \(minutes) minuter") }
        let f = DateFormatter()
        f.dateFormat = "HH:mm"
        let clock = f.string(from: time)
        return (clock, "Kl. \(clock)", "klockan \(clock)")
    }

    // MARK: Lock screen

    private func publishLockScreen() {
        guard hasToken else { lockScreenSubject.send(nil); return }
        let remaining = remainingToday
        let next = nextTask.flatMap { task -> String? in
            guard let due = task.due, (due.day ?? .distantFuture) <= startOfToday else { return nil }
            return Self.dueLabel(due, now: Date()).text == "Idag" ? task.displayTitle : Self.dueLabel(due, now: Date()).text
        }
        lockScreenSubject.send(
            LockScreenStatusEntry(
                id: "todoist.today",
                systemImage: remaining == 0 ? "checkmark.circle.fill" : "checkmark.circle",
                text: remaining == 0 ? "Allt klart idag" : "\(remaining) kvar idag",
                detail: remaining == 0 ? nil : next,
                roundedCenterText: "\(remaining)",
                roundedBottomText: "kvar",
                progress: totalToday == 0 ? nil : progress,
                ticksEverySecond: false
            )
        )
    }

    // MARK: HUD

    func presentHUD(title: String, detail: String, symbol: String) {
        guard let host else { return }
        let request = DropletHUDRequest(
            id: "todoist.notice",
            duration: 4,
            priority: .normal,
            accessibilityLabel: "\(title): \(detail)",
            isExpanded: true,
            expandedContentHeight: 44
        ) {
            HStack(spacing: 0) {
                Image(systemName: symbol)
                    .font(.system(size: DroppyLiveActivityMetrics.iconSize, weight: .semibold))
                Spacer(minLength: 0)
                Text(verbatim: title)
                    .font(.system(size: DroppyLiveActivityMetrics.labelFontSize, weight: .semibold))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
        } expanded: {
            HStack(spacing: DroppySpacing.md) {
                Image(systemName: symbol)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: title)
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                    Text(verbatim: detail)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        _ = host.hud.present(request)
    }

    // MARK: Formatting

    struct DueLabel { let text: String; let isOverdue: Bool }

    static func dueLabel(_ due: TodoistDue, now: Date) -> DueLabel {
        let cal = Calendar.current
        let today = cal.startOfDay(for: now)
        let clock = DateFormatter(); clock.dateFormat = "HH:mm"
        if let time = due.time {
            let day = cal.startOfDay(for: time)
            if day == today { return DueLabel(text: clock.string(from: time), isOverdue: time < now.addingTimeInterval(-60)) }
            return DueLabel(text: dayName(day, today: today) + " " + clock.string(from: time), isOverdue: day < today)
        }
        guard let day = due.day else { return DueLabel(text: due.string ?? "", isOverdue: false) }
        if day == today { return DueLabel(text: "Idag", isOverdue: false) }
        return DueLabel(text: dayName(day, today: today), isOverdue: day < today)
    }

    private static func dayName(_ day: Date, today: Date) -> String {
        let cal = Calendar.current
        let days = cal.dateComponents([.day], from: today, to: day).day ?? 0
        switch days {
        case -1: return "Igår"
        case 0: return "Idag"
        case 1: return "Imorgon"
        case 2...6:
            let f = DateFormatter(); f.locale = Locale(identifier: "sv_SE"); f.dateFormat = "EEE"
            return f.string(from: day).replacingOccurrences(of: ".", with: "").capitalized
        default:
            let f = DateFormatter(); f.locale = Locale(identifier: "sv_SE"); f.dateFormat = "d MMM"
            return f.string(from: day)
        }
    }

    /// "13:15 · om 40 min" for a task later today, the due label otherwise.
    func nextLine(for task: TodoistTask) -> String {
        guard let due = task.due else { return project(task.projectID)?.displayName ?? "" }
        if let time = due.time, Calendar.current.isDate(time, inSameDayAs: now), time > now {
            let f = DateFormatter(); f.dateFormat = "HH:mm"
            let minutes = Int(time.timeIntervalSince(now) / 60)
            if minutes < 120 { return "\(f.string(from: time)) · om \(max(minutes, 1)) min" }
            return f.string(from: time)
        }
        let label = Self.dueLabel(due, now: now).text
        return label == "Idag" ? (project(task.projectID)?.displayName ?? "Idag") : label
    }

    // MARK: Harness

    /// Sample tasks so the harness shots show a populated widget. Only in the
    /// harness, and only without a token.
    private func loadHarnessSample() {
        let day = TodoistDates.day
        let today = day.string(from: Date())
        let yesterday = day.string(from: Date().addingTimeInterval(-86_400))
        let friday = day.string(from: Date().addingTimeInterval(3 * 86_400))
        let soon = DateFormatter(); soon.dateFormat = "yyyy-MM-dd'T'HH:mm:00"
        let inForty = soon.string(from: Date().addingTimeInterval(2400))
        let json = """
        [
          {"id":"1","content":"Lämna in inlämning 2","project_id":"hh","priority":4,"due":{"date":"\(yesterday)","is_recurring":false}},
          {"id":"2","content":"Seminarium corporate finance","project_id":"hh","priority":2,"due":{"date":"\(inForty)","is_recurring":false}},
          {"id":"3","content":"Bokföra leverantörsfakturor","project_id":"lav","priority":3,"due":{"date":"\(today)","is_recurring":true}},
          {"id":"4","content":"Posta bok","project_id":"mel","priority":1,"due":{"date":"\(today)","is_recurring":false}},
          {"id":"5","content":"Läs kapitel 4","project_id":"hh","priority":3,"due":{"date":"\(friday)","is_recurring":false}}
        ]
        """
        tasks = sorted((try? JSONDecoder().decode([TodoistTask].self, from: Data(json.utf8))) ?? [])
        projects = [
            TodoistProject(id: "inbox", name: "Inbox", color: "charcoal", isInbox: true),
            TodoistProject(id: "mel", name: "Melker", color: "green", childOrder: 0),
            TodoistProject(id: "hh", name: "Handelshögskolan", color: "yellow", childOrder: 1),
            TodoistProject(id: "lav", name: "Lavendla", color: "violet", childOrder: 2),
            TodoistProject(id: "som", name: "Sommarkurser", color: "blue", childOrder: 3),
        ]
        completedToday = 2
        completedThisWeek = 11
        isSample = true
        hasToken = true
        accountName = "Exempel"
        lastSync = Date()
        composerProjectID = "hh"
        measuredHeight = TodoistLayout.height(for: self)
        DispatchQueue.main.async { [weak self] in
            self?.evaluateReminder()
            self?.publishLockScreen()
        }
    }
}

// MARK: - URLs from other apps

extension TodoistDroplet: DropletURLHandling {
    /// `droppy://droplet/todoist/add?text=…&note=…&mode=edit|quick|plain&due=…`
    ///
    /// - `edit` (default) opens the shelf with the text in the composer, where
    ///   the result line picks the project, date and priority.
    /// - `quick` adds it straight away through Todoist's quick add.
    /// - `plain` adds it as written, with `due` as a due string ("today").
    ///
    /// Anything on the Mac can open these URLs, so they only ever add a task,
    /// the size is bounded, and the user can switch them off.
    public func handle(_ request: DropletURLRequest) {
        switch request.path {
        case "add":
            guard acceptsLinks else {
                host?.log.notice("ignored an add link: links are switched off")
                return
            }
            let text = String((request.query["text"] ?? "").prefix(1000)).trimmingCharacters(in: .whitespacesAndNewlines)
            let note = request.query["note"].map { String($0.prefix(2000)) }
            guard !text.isEmpty else { return }
            guard let token = TodoistKeychain.token() else {
                presentHUD(title: "Todoist", detail: "Anslut Todoist i inställningarna", symbol: "exclamationmark.circle")
                return
            }
            switch request.query["mode"] ?? "edit" {
            case "quick":
                addFromLink { try await TodoistAPI(token: token).quickAdd(text, note: note) }
            case "plain":
                let due = request.query["due"].map { String($0.prefix(60)) }
                addFromLink { try await TodoistAPI(token: token).add(content: text, description: note, dueString: due) }
            default:
                resetComposer()
                openPicker = nil
                draft = text
                draftNote = note
                _ = host?.shelf.open(revealing: Self.widgetID)
                focusRequest += 1
            }
        case "open":
            _ = host?.shelf.open(revealing: Self.widgetID)
        default:
            break
        }
    }

    private func addFromLink(_ add: @escaping () async throws -> TodoistTask) {
        Task {
            do {
                let task = try await add()
                let when = task.due.map { Self.dueLabel($0, now: Date()).text } ?? "Inkorgen"
                presentHUD(title: "Tillagd · \(when)", detail: task.displayTitle, symbol: "checkmark.circle.fill")
                await refreshNow()
            } catch {
                presentHUD(
                    title: "Kunde inte lägga till",
                    detail: (error as? LocalizedError)?.errorDescription ?? "Försök igen",
                    symbol: "exclamationmark.circle"
                )
            }
        }
    }
}

// MARK: - HUD and lock screen

extension TodoistDroplet: HUDPresenting {}

extension TodoistDroplet: LockScreenStatusProviding {
    public var lockScreenStatus: AnyPublisher<LockScreenStatusEntry?, Never> {
        lockScreenSubject.eraseToAnyPublisher()
    }
}
