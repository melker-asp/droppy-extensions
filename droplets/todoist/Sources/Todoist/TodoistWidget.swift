//
//  TodoistWidget.swift
//  Todoist
//
//  The shelf widget. Solo: a header with today's progress, the composer, and
//  either the grouped list, the Eisenhower matrix, or "all done". Paired: a
//  progress ring and the next task.
//

import AppKit
import DroppyKit
import SwiftUI

// MARK: - Layout

/// The widget's height, worked out from what it shows. The views below use
/// the same numbers, so the declared rectangle and the drawn content agree.
enum TodoistLayout {
    static let header: CGFloat = 16
    static let bar: CGFloat = 3
    static let field: CGFloat = 28
    static let resultLine: CGFloat = 16
    static let row: CGFloat = 28
    static let sectionHeader: CGFloat = 20
    static let optionRow: CGFloat = 26
    static let tile: CGFloat = 62
    static let maxList: CGFloat = 252
    static let allDone: CGFloat = 44

    @MainActor
    static func height(for d: TodoistDroplet) -> CGFloat {
        let insets: CGFloat = 16
        guard d.hasToken else { return insets + header + DroppySpacing.sm + field }
        var h = insets + header + DroppySpacing.xs + bar + DroppySpacing.sm + field
        if !d.draft.isEmpty { h += DroppySpacing.xsm + resultLine }
        return h + DroppySpacing.sm + body(for: d)
    }

    @MainActor
    static func body(for d: TodoistDroplet) -> CGFloat {
        if let picker = d.openPicker, !d.draft.isEmpty {
            switch picker {
            case .project: return CGFloat(max(d.composerProjects.count, 1)) * optionRow + 8
            case .due: return CGFloat((TodoistDueOption.all().count + 1) / 2) * optionRow + 8
            case .priority: return 4 * optionRow + 8
            }
        }
        if d.remainingToday == 0 {
            return allDone + (d.nextTask == nil ? 0 : DroppySpacing.sm + row)
        }
        if d.showsMatrix { return tile * 2 + DroppySpacing.xsm }
        return min(listHeight(for: d), maxList)
    }

    @MainActor
    static func listHeight(for d: TodoistDroplet) -> CGFloat {
        var height: CGFloat = 0
        for count in [d.overdue.count, d.dueToday.count, d.laterShown.count] where count > 0 {
            height += sectionHeader + CGFloat(count) * row
        }
        return height
    }
}

// MARK: - Descriptor

extension TodoistDroplet: ShelfWidgetProviding {
    public var widgetDescriptors: [ShelfWidgetDescriptor] {
        [
            ShelfWidgetDescriptor(
                id: Self.widgetID,
                title: "Todoist",
                systemImage: "checkmark.circle",
                layoutTraits: ShelfWidgetLayoutTraits(
                    preferredSoloWidth: 440,
                    preferredPairedWidth: 220,
                    contentHeight: .fixed(TodoistLayout.height(for: self))
                ),
                focusPolicy: .keyboardFocusable,
                searchKeywords: ["tasks", "todo", "uppgifter", "att göra"]
            )
        ]
    }

    public func makeWidgetView(_ id: ShelfWidgetID, context: ShelfWidgetContext) -> AnyView {
        AnyView(TodoistWidget(droplet: self, context: context))
    }

    public func makeWidgetSettingsPopover(_ id: ShelfWidgetID) -> AnyView? { nil }
}

// MARK: - Widget

struct TodoistWidget: View {
    @ObservedObject var droplet: TodoistDroplet
    let context: ShelfWidgetContext

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header
            if !droplet.hasToken {
                setUp.padding(.top, DroppySpacing.sm)
            } else if context.isCompact {
                TodoistCompact(droplet: droplet, context: context).padding(.top, DroppySpacing.sm)
            } else {
                TodoistProgressBar(progress: droplet.progress)
                    .padding(.top, DroppySpacing.xs)
                TodoistComposer(droplet: droplet)
                    .padding(.top, DroppySpacing.sm)
                content.padding(.top, DroppySpacing.sm)
            }
            Spacer(minLength: 0)
        }
        .padding(context.contentInsets)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
    }

    @ViewBuilder
    private var content: some View {
        if droplet.openPicker != nil && !droplet.draft.isEmpty {
            TodoistPickerList(droplet: droplet)
        } else if droplet.remainingToday == 0 {
            TodoistAllDone(droplet: droplet)
        } else if droplet.showsMatrix {
            TodoistMatrix(droplet: droplet)
        } else {
            TodoistList(droplet: droplet)
        }
    }

    // MARK: Header

    private var header: some View {
        HStack(spacing: DroppySpacing.xsm) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 12, weight: .medium))
            Text("Idag")
                .font(.system(size: 12, weight: .semibold))
            if droplet.hasToken && droplet.totalToday > 0 {
                Text(context.isCompact ? "\(droplet.completedToday)/\(droplet.totalToday)" : "\(droplet.completedToday) av \(droplet.totalToday) klara")
                    .font(.system(size: 12))
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                    .contentTransition(.numericText())
            }
            if droplet.lastError != nil && droplet.hasToken {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                    .help(droplet.lastError ?? "")
            }
            Spacer(minLength: 0)
            if droplet.hasToken && !context.isCompact {
                if droplet.undoable != nil {
                    Button("Ångra") { droplet.undo() }
                        .buttonStyle(DroppyQuietButtonStyle(size: .small))
                        .transition(DroppyTransition.element)
                }
                Button { droplet.toggleView() } label: {
                    Image(systemName: droplet.showsMatrix ? "list.bullet" : "square.grid.2x2")
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 20))
                .help(droplet.showsMatrix ? "Visa som lista" : "Visa som matris")
                .accessibilityLabel(droplet.showsMatrix ? "Visa som lista" : "Visa som matris")
                Button { droplet.refresh() } label: {
                    Image(systemName: "arrow.clockwise")
                        .rotationEffect(.degrees(droplet.isLoading ? 360 : 0))
                        .animation(droplet.isLoading ? .linear(duration: 0.8).repeatForever(autoreverses: false) : .default, value: droplet.isLoading)
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 20))
                .help("Uppdatera")
                .accessibilityLabel("Uppdatera")
                Button { droplet.openTodoist() } label: {
                    Image(systemName: "arrow.up.right")
                }
                .buttonStyle(DroppyCircleButtonStyle(size: 20))
                .help("Öppna Todoist")
                .accessibilityLabel("Öppna Todoist")
            }
        }
        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
        .frame(height: TodoistLayout.header)
    }

    // MARK: Not connected

    private var setUp: some View {
        HStack(spacing: DroppySpacing.sm) {
            Text("Anslut ditt Todoist-konto för att se dagens uppgifter.")
                .font(.system(size: 13))
                .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                .lineLimit(context.isCompact ? 3 : 2)
            if !context.isCompact {
                Spacer(minLength: DroppySpacing.md)
                Button("Anslut") { droplet.openSettings() }
                    .buttonStyle(DroppyAccentButtonStyle(size: .small))
            }
        }
        .frame(minHeight: TodoistLayout.field)
        .contentShape(Rectangle())
        .onTapGesture { if context.isCompact { droplet.openSettings() } }
    }
}

// MARK: - Progress

struct TodoistProgressBar: View {
    let progress: Double

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(AdaptiveColors.notchSurfacePrimaryText)
                    .frame(width: geo.size.width * progress)
            }
        }
        .frame(height: TodoistLayout.bar)
        .animation(DroppyAnimation.state, value: progress)
        .accessibilityLabel("\(Int(progress * 100)) procent klart idag")
    }
}

struct TodoistProgressRing: View {
    let progress: Double
    let label: String
    var size: CGFloat = 40

    var body: some View {
        ZStack {
            // Inset by half the line, so the stroke stays inside the frame
            // and the widget's edge never clips it.
            Circle().inset(by: 2).stroke(Color.white.opacity(0.15), lineWidth: 4)
            Circle()
                .inset(by: 2)
                .trim(from: 0, to: progress)
                .stroke(AdaptiveColors.notchSurfacePrimaryText, style: StrokeStyle(lineWidth: 4, lineCap: .round))
                .rotationEffect(.degrees(-90))
            Text(label)
                .font(.system(size: 11, weight: .semibold))
                .monospacedDigit()
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
        }
        .frame(width: size, height: size)
        .animation(DroppyAnimation.state, value: progress)
    }
}

// MARK: - Composer (variant B: the result line is the control)

struct TodoistComposer: View {
    @ObservedObject var droplet: TodoistDroplet
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.xsm) {
            field
            if !droplet.draft.isEmpty {
                resultLine.transition(DroppyTransition.element)
            }
        }
        .onChange(of: droplet.focusRequest) { _, _ in focus() }
        .onAppear { if droplet.focusRequest > 0 && !droplet.draft.isEmpty { focus() } }
    }

    private var field: some View {
        HStack(spacing: DroppySpacing.xsm) {
            Group {
                if droplet.isAdding {
                    ProgressView().controlSize(.mini)
                } else {
                    Image(systemName: "plus").font(.system(size: 11, weight: .semibold))
                }
            }
            .frame(width: 14)
            .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)

            if let flash = droplet.flash, droplet.draft.isEmpty, !focused {
                Text(flash)
                    .font(.system(size: 13))
                    .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                    .lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
                    .onTapGesture { focus() }
            } else {
                TextField(
                    "",
                    text: $droplet.draft,
                    prompt: Text("Lägg till uppgift").foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                )
                .textFieldStyle(.plain)
                .font(.system(size: 13))
                .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                .focused($focused)
                .onSubmit { droplet.submitDraft() }
                .onExitCommand { droplet.cancelDraft() }
                .disabled(droplet.isAdding)
            }

            if droplet.draftNote != nil {
                Button { droplet.clearDraftNote() } label: { Image(systemName: "link") }
                    .buttonStyle(DroppyCircleButtonStyle(size: 20))
                    .help("Länken till källan följer med som beskrivning. Klicka för att ta bort den.")
                    .accessibilityLabel("Ta bort länken till källan")
            }
            if !droplet.draft.isEmpty {
                Button { droplet.cancelDraft() } label: { Image(systemName: "xmark") }
                    .buttonStyle(DroppyCircleButtonStyle(size: 20))
                    .help("Avbryt")
                    .accessibilityLabel("Avbryt")
            }
        }
        .padding(.horizontal, DroppySpacing.sm)
        .frame(height: TodoistLayout.field)
        .background(
            RoundedRectangle(cornerRadius: DroppyRadius.small, style: .continuous)
                .fill(focused ? AdaptiveColors.notchSurfaceCardHoverFill : AdaptiveColors.notchSurfaceCardFill)
        )
    }

    /// "Handelshögskolan · Fre 24 okt · P2": each part opens its list.
    private var resultLine: some View {
        HStack(spacing: DroppySpacing.xs) {
            part(
                droplet.composerProject?.displayName ?? "Inkorg",
                color: droplet.composerProject?.tint ?? AdaptiveColors.notchSurfaceSecondaryText,
                picker: .project
            )
            dot
            part(
                droplet.composerDue.title,
                color: droplet.composerDue.dueString == nil ? AdaptiveColors.notchSurfaceTertiaryText : AdaptiveColors.notchSurfacePrimaryText,
                picker: .due
            )
            dot
            part(
                droplet.composerPriority.short,
                color: droplet.composerPriority.color ?? AdaptiveColors.notchSurfaceTertiaryText,
                picker: .priority
            )
            Spacer(minLength: DroppySpacing.md)
            Text("↩ lägg till")
                .font(.system(size: 12))
                .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
        }
        .padding(.leading, DroppySpacing.xs)
        .frame(height: TodoistLayout.resultLine)
    }

    private var dot: some View {
        Text("·").font(.system(size: 12)).foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
    }

    private func part(_ title: String, color: Color, picker: TodoistDroplet.ComposerPicker) -> some View {
        let isOpen = droplet.openPicker == picker
        return Text(title)
            .font(.system(size: 12, weight: isOpen ? .semibold : .regular))
            .foregroundStyle(color)
            .underline(!isOpen, pattern: .dot, color: color.opacity(0.6))
            .padding(.horizontal, isOpen ? 4 : 0)
            .background(
                RoundedRectangle(cornerRadius: DroppyRadius.xs, style: .continuous)
                    .fill(isOpen ? AdaptiveColors.notchSurfaceCardFill : .clear)
            )
            .contentShape(Rectangle())
            .onTapGesture { droplet.togglePicker(picker) }
            .accessibilityAddTraits(.isButton)
            .accessibilityHint("Ändra")
    }

    private func focus() {
        _ = droplet.host?.shelf.requestKeyboardFocus()
        DispatchQueue.main.async {
            focused = true
            // Focusing selects the whole field; put the caret after the text
            // instead, so what the user types is added to it.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                for window in NSApp.windows where window.isKeyWindow {
                    if let editor = window.firstResponder as? NSTextView {
                        editor.setSelectedRange(NSRange(location: (editor.string as NSString).length, length: 0))
                    }
                }
            }
        }
    }
}

/// The list one part of the result line opens, in the body's place.
struct TodoistPickerList: View {
    @ObservedObject var droplet: TodoistDroplet

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            switch droplet.openPicker {
            case .project:
                ForEach(droplet.composerProjects) { project in
                    option(project.displayName, color: project.tint, selected: project.id == droplet.composerProject?.id) {
                        droplet.choose(project: project)
                    }
                }
            case .due:
                let options = TodoistDueOption.all()
                LazyVGrid(columns: [GridItem(.flexible(), spacing: 4), GridItem(.flexible(), spacing: 4)], spacing: 0) {
                    ForEach(options) { option in
                        self.option(option.title, color: AdaptiveColors.notchSurfacePrimaryText, selected: option == droplet.composerDue) {
                            droplet.choose(due: option)
                        }
                    }
                }
            case .priority:
                ForEach(TodoistPriority.allCases) { priority in
                    option(
                        "\(priority.short)  \(priority.quadrant)",
                        color: priority.color ?? AdaptiveColors.notchSurfaceSecondaryText,
                        selected: priority == droplet.composerPriority
                    ) { droplet.choose(priority: priority) }
                }
            case nil:
                EmptyView()
            }
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous)
                .fill(Color.white.opacity(0.06))
        )
    }

    private func option(_ title: String, color: Color, selected: Bool, action: @escaping () -> Void) -> some View {
        TodoistOptionRow(title: title, color: color, selected: selected, action: action)
    }
}

private struct TodoistOptionRow: View {
    let title: String
    let color: Color
    let selected: Bool
    let action: () -> Void
    @State private var hovering = false

    var body: some View {
        HStack {
            Text(title).font(.system(size: 13)).foregroundStyle(color).lineLimit(1)
            Spacer(minLength: DroppySpacing.sm)
            if selected {
                Image(systemName: "checkmark")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
            }
        }
        .padding(.horizontal, DroppySpacing.sm)
        .frame(height: TodoistLayout.optionRow)
        .background(
            RoundedRectangle(cornerRadius: DroppyRadius.sm, style: .continuous)
                .fill(hovering || selected ? AdaptiveColors.notchSurfaceCardFill : .clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: action)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

// MARK: - List

struct TodoistList: View {
    @ObservedObject var droplet: TodoistDroplet

    var body: some View {
        let height = TodoistLayout.listHeight(for: droplet)
        ScrollView(.vertical, showsIndicators: false) {
            VStack(alignment: .leading, spacing: 0) {
                section("Försenat", droplet.overdue, tint: Color(red: 1, green: 0.42, blue: 0.38))
                section("Idag", droplet.dueToday, tint: nil)
                section("Kommande", droplet.laterShown, tint: nil)
            }
        }
        .frame(height: min(height, TodoistLayout.maxList))
        .scrollDisabled(height <= TodoistLayout.maxList)
        .droppyFlatGlassControls()
    }

    @ViewBuilder
    private func section(_ title: String, _ tasks: [TodoistTask], tint: Color?) -> some View {
        if !tasks.isEmpty {
            Text(title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(tint ?? AdaptiveColors.notchSurfaceTertiaryText)
                .padding(.leading, DroppySpacing.xs)
                .frame(height: TodoistLayout.sectionHeader, alignment: .bottomLeading)
                .padding(.bottom, 0)
            ForEach(tasks) { task in
                TodoistTaskRow(droplet: droplet, task: task)
                    .transition(DroppyTransition.element)
            }
        }
    }
}

struct TodoistCheckButton: View {
    @ObservedObject var droplet: TodoistDroplet
    let task: TodoistTask
    var size: CGFloat = 15
    @State private var hover = false

    private var isDone: Bool { droplet.completing.contains(task.id) }

    var body: some View {
        Button { droplet.complete(task) } label: {
            Image(systemName: isDone ? "checkmark.circle.fill" : (hover ? "checkmark.circle" : "circle"))
                // Droppy draws widgets with a filled symbol variant; an open
                // task is a ring, as in Todoist.
                .symbolVariant(.none)
                .font(.system(size: size, weight: task.priorityLevel == .p4 ? .regular : .semibold))
                .foregroundStyle(task.priorityLevel.color ?? AdaptiveColors.notchSurfaceTertiaryText)
                .contentTransition(.symbolEffect(.replace))
                .frame(width: size + 3, height: size + 3)
                .contentShape(Circle())
        }
        .buttonStyle(.plain)
        .onHover { hover = $0 }
        .help("Klar")
        .accessibilityLabel("Markera \(task.displayTitle) som klar")
    }
}

struct TodoistTaskRow: View {
    @ObservedObject var droplet: TodoistDroplet
    let task: TodoistTask
    @State private var hovering = false
    @State private var choosingPriority = false

    private var isDone: Bool { droplet.completing.contains(task.id) }

    var body: some View {
        HStack(spacing: DroppySpacing.sm) {
            TodoistCheckButton(droplet: droplet, task: task)

            Text(task.displayTitle)
                .font(.system(size: 13))
                .foregroundStyle(isDone ? AdaptiveColors.notchSurfaceTertiaryText : AdaptiveColors.notchSurfacePrimaryText)
                .strikethrough(isDone, color: AdaptiveColors.notchSurfaceTertiaryText)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: DroppySpacing.md)

            if choosingPriority {
                priorityChoices
            } else if hovering && !isDone {
                hoverControls
            } else {
                details
            }
        }
        .padding(.horizontal, DroppySpacing.xs)
        .frame(height: TodoistLayout.row)
        .background(
            RoundedRectangle(cornerRadius: DroppyRadius.sm, style: .continuous)
                .fill(hovering ? AdaptiveColors.notchSurfaceCardFill : .clear)
        )
        .contentShape(Rectangle())
        .onHover { inside in
            hovering = inside
            if !inside { choosingPriority = false }
        }
        .onTapGesture { droplet.open(task) }
        .help(task.description?.isEmpty == false ? task.description! : "Öppna i Todoist")
        .animation(DroppyAnimation.hover, value: hovering)
    }

    private var details: some View {
        HStack(spacing: DroppySpacing.xsm) {
            if let project = droplet.project(task.projectID) {
                Text(project.displayName)
                    .font(.system(size: 11))
                    .foregroundStyle(project.tint)
                    .lineLimit(1)
            }
            if task.due?.isRecurring == true {
                Image(systemName: "repeat")
                    .font(.system(size: 9, weight: .semibold))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            }
            if let due = task.due {
                let label = TodoistDroplet.dueLabel(due, now: droplet.now)
                if label.text != "Idag" {
                    Text(label.text)
                        .font(.system(size: 12, weight: .medium))
                        .monospacedDigit()
                        .foregroundStyle(label.isOverdue ? Color(red: 1, green: 0.42, blue: 0.38) : AdaptiveColors.notchSurfaceSecondaryText)
                }
            }
        }
        .fixedSize()
    }

    private var hoverControls: some View {
        HStack(spacing: DroppySpacing.xs) {
            if task.due?.isRecurring != true && !isDueTomorrow {
                Button { droplet.postpone(task) } label: {
                    Label("Imorgon", systemImage: "arrow.right")
                }
                .buttonStyle(DroppyQuietButtonStyle(size: .small))
                .help("Flytta till imorgon")
            }
            Button { choosingPriority = true } label: { Image(systemName: "flag") }
                .buttonStyle(DroppyCircleButtonStyle(size: 20))
                .help("Ändra prioritet")
                .accessibilityLabel("Ändra prioritet")
            Button { droplet.open(task) } label: { Image(systemName: "arrow.up.right") }
                .buttonStyle(DroppyCircleButtonStyle(size: 20))
                .help("Öppna i Todoist")
                .accessibilityLabel("Öppna i Todoist")
        }
        .fixedSize()
        .transition(DroppyTransition.element)
    }

    private var priorityChoices: some View {
        HStack(spacing: 2) {
            ForEach(TodoistPriority.allCases) { priority in
                Text(priority.short)
                    .font(.system(size: 12, weight: priority == task.priorityLevel ? .bold : .medium))
                    .foregroundStyle(priority.color ?? AdaptiveColors.notchSurfaceSecondaryText)
                    .padding(.horizontal, 6)
                    .frame(height: 20)
                    .background(
                        RoundedRectangle(cornerRadius: DroppyRadius.xs, style: .continuous)
                            .fill(priority == task.priorityLevel ? AdaptiveColors.notchSurfaceCardHoverFill : .clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture {
                        droplet.setPriority(task, priority)
                        choosingPriority = false
                    }
                    .help(priority.quadrant)
                    .accessibilityAddTraits(.isButton)
            }
        }
        .fixedSize()
        .transition(DroppyTransition.element)
    }

    private var isDueTomorrow: Bool {
        guard let day = task.due?.day else { return false }
        return Calendar.current.isDateInTomorrow(day)
    }
}

// MARK: - Matrix

struct TodoistMatrix: View {
    @ObservedObject var droplet: TodoistDroplet

    var body: some View {
        let open = droplet.overdue + droplet.dueToday
        let columns = [GridItem(.flexible(), spacing: DroppySpacing.xsm), GridItem(.flexible(), spacing: DroppySpacing.xsm)]
        LazyVGrid(columns: columns, spacing: DroppySpacing.xsm) {
            ForEach(TodoistPriority.allCases) { priority in
                tile(priority, tasks: open.filter { $0.priorityLevel == priority })
            }
        }
    }

    private func tile(_ priority: TodoistPriority, tasks: [TodoistTask]) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack {
                Text(priority.quadrant)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(priority.color ?? AdaptiveColors.notchSurfaceTertiaryText)
                Spacer(minLength: DroppySpacing.xs)
                Text("\(tasks.count)")
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            }
            if tasks.isEmpty {
                Text("Inget här")
                    .font(.system(size: 12))
                    .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
            }
            ForEach(tasks.prefix(2)) { task in
                HStack(spacing: DroppySpacing.xsm) {
                    TodoistCheckButton(droplet: droplet, task: task, size: 12)
                    Text(task.displayTitle)
                        .font(.system(size: 12))
                        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                        .lineLimit(1)
                        .contentShape(Rectangle())
                        .onTapGesture { droplet.open(task) }
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, DroppySpacing.smd)
        .padding(.vertical, DroppySpacing.sm)
        .frame(maxWidth: .infinity, minHeight: TodoistLayout.tile, maxHeight: TodoistLayout.tile, alignment: .topLeading)
        .background(
            RoundedRectangle(cornerRadius: DroppyRadius.medium, style: .continuous)
                .fill(Color.white.opacity(0.08))
        )
    }
}

// MARK: - All done

struct TodoistAllDone: View {
    @ObservedObject var droplet: TodoistDroplet

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            HStack(spacing: DroppySpacing.md) {
                ZStack {
                    Circle().strokeBorder(Color(red: 0.30, green: 0.76, blue: 0.35), lineWidth: 4)
                    Image(systemName: "checkmark")
                        .font(.system(size: 16, weight: .bold))
                        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                }
                .frame(width: 40, height: 40)
                VStack(alignment: .leading, spacing: 2) {
                    Text(droplet.lastSync == nil ? "Hämtar…" : "Allt klart för idag")
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                    Text(stats)
                        .font(.system(size: 12))
                        .monospacedDigit()
                        .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                }
                Spacer(minLength: 0)
            }
            .frame(height: TodoistLayout.allDone)

            if let next = droplet.nextTask {
                HStack(spacing: DroppySpacing.sm) {
                    Text("Nästa")
                        .font(.system(size: 11))
                        .foregroundStyle(AdaptiveColors.notchSurfaceTertiaryText)
                        .frame(width: 40, alignment: .leading)
                    Text(next.displayTitle)
                        .font(.system(size: 13))
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                        .lineLimit(1)
                    Spacer(minLength: DroppySpacing.md)
                    if let due = next.due {
                        Text(TodoistDroplet.dueLabel(due, now: droplet.now).text)
                            .font(.system(size: 12, weight: .medium))
                            .monospacedDigit()
                            .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                    }
                }
                .padding(.horizontal, DroppySpacing.xs)
                .frame(height: TodoistLayout.row)
                .contentShape(Rectangle())
                .onTapGesture { droplet.open(next) }
            }
        }
    }

    private var stats: String {
        let today = droplet.completedToday
        let week = droplet.completedThisWeek
        let first = today == 1 ? "1 avbockad idag" : "\(today) avbockade idag"
        return week > today ? "\(first) · \(week) den här veckan" : first
    }
}

// MARK: - Paired

/// The paired card: a progress ring with the next task beside it, then as
/// many of the following tasks as the row's height holds. A row shares the
/// solo widget's height, so the room under the ring is used, not left black.
struct TodoistCompact: View {
    @ObservedObject var droplet: TodoistDroplet
    let context: ShelfWidgetContext

    private static let ringBlock: CGFloat = 40
    private static let row: CGFloat = 22

    var body: some View {
        VStack(alignment: .leading, spacing: DroppySpacing.sm) {
            summary
            ForEach(following) { task in
                HStack(spacing: DroppySpacing.xsm) {
                    TodoistCheckButton(droplet: droplet, task: task, size: 12)
                    Text(task.displayTitle)
                        .font(.system(size: 12))
                        .foregroundStyle(AdaptiveColors.notchSurfaceSecondaryText)
                        .lineLimit(1)
                    Spacer(minLength: DroppySpacing.xs)
                    if let due = task.due {
                        let label = TodoistDroplet.dueLabel(due, now: droplet.now)
                        if label.text != "Idag" {
                            Text(label.text)
                                .font(.system(size: 11))
                                .monospacedDigit()
                                .foregroundStyle(label.isOverdue ? Color(red: 1, green: 0.42, blue: 0.38) : AdaptiveColors.notchSurfaceTertiaryText)
                        }
                    }
                }
                .frame(height: Self.row)
                .contentShape(Rectangle())
                .onTapGesture { droplet.open(task) }
            }
        }
    }

    private var lead: TodoistTask? { droplet.upcoming ?? droplet.nextTask }

    /// The tasks after the one beside the ring, as many as fit.
    private var following: [TodoistTask] {
        let used = 16 + TodoistLayout.header + DroppySpacing.sm + Self.ringBlock + DroppySpacing.sm
        let room = context.availableSize.height - used
        let count = max(0, Int(room / (Self.row + DroppySpacing.sm)))
        let rest = (droplet.overdue + droplet.dueToday + droplet.later).filter { $0.id != lead?.id }
        return Array(rest.prefix(count))
    }

    private var summary: some View {
        HStack(spacing: DroppySpacing.smd) {
            if droplet.remainingToday == 0 {
                ZStack {
                    Circle().strokeBorder(Color(red: 0.30, green: 0.76, blue: 0.35), lineWidth: 4)
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                }
                .frame(width: Self.ringBlock, height: Self.ringBlock)
            } else {
                TodoistProgressRing(progress: droplet.progress, label: "\(droplet.completedToday)/\(droplet.totalToday)", size: Self.ringBlock)
            }
            VStack(alignment: .leading, spacing: 2) {
                if droplet.remainingToday == 0 {
                    Text("Allt klart")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(AdaptiveColors.notchSurfacePrimaryText)
                }
                if let next = lead {
                    Text(next.displayTitle)
                        .font(.system(size: 13, weight: .medium))
                        .foregroundStyle(droplet.remainingToday == 0 ? AdaptiveColors.notchSurfaceTertiaryText : AdaptiveColors.notchSurfacePrimaryText)
                        .lineLimit(1)
                    Text(droplet.nextLine(for: next))
                        .font(.system(size: 11))
                        .monospacedDigit()
                        .foregroundStyle(droplet.project(next.projectID)?.tint ?? AdaptiveColors.notchSurfaceTertiaryText)
                        .lineLimit(1)
                }
            }
            Spacer(minLength: 0)
        }
        .frame(height: Self.ringBlock)
        .contentShape(Rectangle())
        .onTapGesture { if let next = lead { droplet.open(next) } }
    }
}
