import AppKit
import SwiftUI

/// Small bit of shared UI state so the desktop widget can open an item
/// in the main window's detail sheet.
@MainActor
final class UIState: ObservableObject {
    static let shared = UIState()
    @Published var editing: Item?
}

// MARK: - Row

struct ItemRow: View {
    let item: Item
    var now: Date = Date()
    var compact = false
    var onToggle: () -> Void
    var onOpen: () -> Void

    @Environment(\.colorScheme) var scheme

    var body: some View {
        let p = Palette(isDark: scheme == .dark)
        let label = Due.label(item, now: now)
        HStack(spacing: compact ? 10 : 12) {
            Button(action: onToggle) {
                ZStack {
                    Circle().fill(item.done ? p.accent : Color.clear)
                    Circle().strokeBorder(item.done ? p.accent : p.check, lineWidth: 1.5)
                }
                .frame(width: compact ? 16 : 19, height: compact ? 16 : 19)
                .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(item.done ? "Mark not done" : "Mark done")

            Text(item.title.isEmpty ? "Untitled" : item.title)
                .font(.system(size: compact ? 13 : 14.5))
                .strikethrough(item.done)
                .foregroundColor(item.done ? p.faint : p.text)
                .lineLimit(1)
                .truncationMode(.tail)

            Spacer(minLength: 8)

            Text(label.text)
                .font(.system(size: compact ? 11.5 : 13, weight: label.tone == .normal ? .regular : .semibold)
                    .monospacedDigit())
                .foregroundColor(p.tone(label.tone))
                .lineLimit(1)
        }
        .padding(.horizontal, compact ? 11 : 14)
        .padding(.vertical, compact ? 7 : 10)
        .themedChip(cornerRadius: compact ? 10 : 13)
        .contentShape(Rectangle())
        .onTapGesture(perform: onOpen)
    }
}

struct GroupLabel: View {
    let text: String
    var compact = false
    @Environment(\.colorScheme) var scheme

    var body: some View {
        let p = Palette(isDark: scheme == .dark)
        Text(text.uppercased())
            .font(.system(size: compact ? 9.5 : 10.5, weight: .semibold))
            .tracking(0.8)
            .foregroundColor(text == Due.Bucket.overdue.rawValue ? p.overdue : p.faint)
            .padding(.top, compact ? 4 : 12)
            .padding(.leading, 4)
    }
}

// MARK: - Main window

/// Full-window backdrop: Cosmic Glass (blurred desktop + dark tint) when
/// dark, brushed Liquid Silver when light.
struct WindowBackdrop: View {
    @Environment(\.colorScheme) private var scheme

    var body: some View {
        if scheme == .dark {
            ZStack {
                CosmicGlassBackground()
                Color.black.opacity(0.55)
                Color.white.opacity(0.07)
            }
            .ignoresSafeArea()
        } else {
            SilverBackground().ignoresSafeArea()
        }
    }
}

struct ContentView: View {
    @ObservedObject private var store = Store.shared
    @ObservedObject private var ui = UIState.shared
    @Environment(\.colorScheme) private var scheme

    @State private var showDone = false
    @State private var draft = ""
    @State private var busy = false
    @State private var parsed: [ClaudeParser.Parsed] = []
    @State private var excluded: Set<UUID> = []
    @State private var errorText: String?

    var body: some View {
        let p = Palette(isDark: scheme == .dark)
        VStack(spacing: 0) {
            header(p)
            TimelineView(.periodic(from: .now, by: 60)) { context in
                list(now: context.date, p)
            }
            if !parsed.isEmpty { preview(p) }
            if let errorText {
                Text(errorText)
                    .font(.system(size: 12.5))
                    .foregroundColor(p.overdue)
                    .padding(.horizontal, 20)
                    .padding(.bottom, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            composer(p)
        }
        .background(WindowBackdrop())
        .frame(minWidth: 380, idealWidth: 440, minHeight: 480, idealHeight: 640)
        .sheet(item: $ui.editing) { item in
            DetailView(item: item)
        }
    }

    private func header(_ p: Palette) -> some View {
        HStack(spacing: 8) {
            Text("KeepUp")
                .font(.system(size: 22, weight: .bold))
                .foregroundColor(p.text)
            Circle()
                .fill(syncColor(p))
                .frame(width: 7, height: 7)
                .help(store.syncState.description)
            Spacer()
            Button { ui.editing = Item() } label: {
                Image(systemName: "plus").font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .foregroundColor(p.dim)
                    .themedChip(cornerRadius: 10)
            }
            .buttonStyle(.plain)
            .help("New item (⌘N)")
            Button {
                NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
            } label: {
                Image(systemName: "gearshape").font(.system(size: 13, weight: .semibold))
                    .frame(width: 30, height: 30)
                    .foregroundColor(p.dim)
                    .themedChip(cornerRadius: 10)
            }
            .buttonStyle(.plain)
            .help("Settings (⌘,)")
        }
        .padding(.horizontal, 20)
        .padding(.top, 34) // clear the traffic lights
        .padding(.bottom, 6)
    }

    private func syncColor(_ p: Palette) -> Color {
        switch store.syncState {
        case .off: return p.faint.opacity(0.5)
        case .ok: return Color(red: 0.23, green: 0.7, blue: 0.45)
        case .failed: return p.overdue
        }
    }

    private func list(now: Date, _ p: Palette) -> some View {
        let open = store.openItems
        let done = store.doneItems
        return ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                if open.isEmpty {
                    Text("Nothing on your plate.\nType below to add something.")
                        .multilineTextAlignment(.center)
                        .font(.system(size: 14))
                        .foregroundColor(p.faint)
                        .frame(maxWidth: .infinity)
                        .padding(.top, 140)
                }
                ForEach(Due.Bucket.allCases, id: \.self) { bucket in
                    let group = open.filter { Due.bucket($0, now: now) == bucket }
                    if !group.isEmpty {
                        GroupLabel(text: bucket.rawValue)
                        ForEach(group) { item in
                            ItemRow(item: item, now: now,
                                    onToggle: { store.toggleDone(item) },
                                    onOpen: { ui.editing = item })
                        }
                    }
                }
                if !done.isEmpty {
                    Button(showDone ? "Hide done (\(done.count))" : "Show done (\(done.count))") {
                        showDone.toggle()
                    }
                    .buttonStyle(.plain)
                    .font(.system(size: 12.5))
                    .foregroundColor(p.faint)
                    .padding(.top, 14)
                    .padding(.leading, 4)
                    if showDone {
                        ForEach(done.prefix(30)) { item in
                            ItemRow(item: item, now: now,
                                    onToggle: { store.toggleDone(item) },
                                    onOpen: { ui.editing = item })
                        }
                    }
                }
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)
        }
    }

    // MARK: Chatbox

    private func composer(_ p: Palette) -> some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField("Throw it in… e.g. “strategy essay due fri 23:59” — or paste a syllabus",
                      text: $draft, axis: .vertical)
                .textFieldStyle(.plain)
                .font(.system(size: 14.5))
                .foregroundColor(p.text)
                .lineLimit(1...8)
                .padding(.vertical, 7)
                .onSubmit(send)
                .disabled(busy)
            Button(action: send) {
                Group {
                    if busy {
                        ProgressView().controlSize(.small)
                    } else {
                        Image(systemName: "arrow.up").font(.system(size: 14, weight: .bold))
                    }
                }
                .frame(width: 30, height: 30)
                .foregroundColor(.white)
                .background(Circle().fill(p.accent))
            }
            .buttonStyle(.plain)
            .disabled(busy || draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
        }
        .padding(.leading, 14)
        .padding(.trailing, 6)
        .padding(.vertical, 6)
        .themedChip(cornerRadius: 18)
        .padding(.horizontal, 16)
        .padding(.bottom, 16)
    }

    private func send() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty, !busy else { return }
        busy = true
        errorText = nil
        Task {
            do {
                let result = try await ClaudeParser.parse(text, knownCourses: store.courses)
                if result.isEmpty {
                    errorText = "Couldn't find anything to add in that."
                } else {
                    parsed = result
                    excluded = []
                    draft = ""
                }
            } catch {
                errorText = error.localizedDescription
            }
            busy = false
        }
    }

    private func preview(_ p: Palette) -> some View {
        let chosen = parsed.filter { !excluded.contains($0.id) }
        return VStack(alignment: .leading, spacing: 6) {
            HStack {
                Text(parsed.count == 1 ? "Add this?" : "Found \(parsed.count) items")
                    .font(.system(size: 12.5))
                    .foregroundColor(p.dim)
                Spacer()
                Button("Cancel") { parsed = [] }
                    .keyboardShortcut(.cancelAction)
                Button(chosen.count == 1 ? "Add" : "Add \(chosen.count)") {
                    store.add(chosen.map { $0.toItem() })
                    parsed = []
                }
                .keyboardShortcut(.defaultAction)
                .disabled(chosen.isEmpty)
            }
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(parsed) { item in
                        previewRow(item, p)
                    }
                }
            }
            .frame(maxHeight: 260)
        }
        .padding(12)
        .themedChip(cornerRadius: 16)
        .padding(.horizontal, 16)
        .padding(.bottom, 8)
    }

    private func previewRow(_ parsedItem: ClaudeParser.Parsed, _ p: Palette) -> some View {
        let item = parsedItem.toItem()
        let meta = [Due.label(item).text.isEmpty ? "No date" : Due.label(item).text, item.place, item.course]
            .filter { !$0.isEmpty }
            .joined(separator: " · ")
        let isOn = Binding(
            get: { !excluded.contains(parsedItem.id) },
            set: { on in
                if on { excluded.remove(parsedItem.id) } else { excluded.insert(parsedItem.id) }
            }
        )
        return Toggle(isOn: isOn) {
            VStack(alignment: .leading, spacing: 2) {
                Text(item.title).font(.system(size: 14)).foregroundColor(p.text)
                Text(meta).font(.system(size: 11.5)).foregroundColor(p.dim)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .toggleStyle(.checkbox)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
    }
}

// MARK: - Detail sheet

struct DetailView: View {
    @State private var item: Item
    @State private var hasDate: Bool
    @State private var hasTime: Bool
    @State private var day: Date
    @State private var time: Date
    private let isNew: Bool

    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var store = Store.shared

    init(item: Item) {
        _item = State(initialValue: item)
        isNew = !Store.shared.items.contains { $0.id == item.id }
        _hasDate = State(initialValue: item.due != nil)
        _hasTime = State(initialValue: item.due != nil && !item.allDay)
        _day = State(initialValue: item.due ?? Date())
        let nineAM = Calendar.current.date(bySettingHour: 9, minute: 0, second: 0, of: Date()) ?? Date()
        _time = State(initialValue: (item.due != nil && !item.allDay) ? item.due! : nineAM)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            TextField("What", text: $item.title)
                .textFieldStyle(.roundedBorder)
                .font(.system(size: 16, weight: .semibold))

            HStack(spacing: 10) {
                Toggle("Due", isOn: $hasDate)
                if hasDate {
                    DatePicker("", selection: $day, displayedComponents: .date)
                        .labelsHidden()
                    Toggle("Time", isOn: $hasTime)
                    if hasTime {
                        DatePicker("", selection: $time, displayedComponents: .hourAndMinute)
                            .labelsHidden()
                    }
                }
                Spacer()
            }

            field("Place") {
                TextField("", text: $item.place).textFieldStyle(.roundedBorder)
            }
            field("Course / tag") {
                HStack(spacing: 6) {
                    TextField("", text: $item.course).textFieldStyle(.roundedBorder)
                    if !store.courses.isEmpty {
                        Menu {
                            ForEach(store.courses, id: \.self) { c in
                                Button(c) { item.course = c }
                            }
                        } label: {
                            Image(systemName: "chevron.down")
                        }
                        .menuStyle(.borderlessButton)
                        .fixedSize()
                    }
                }
            }
            field("Type") {
                Picker("", selection: $item.kind) {
                    ForEach(Item.Kind.allCases, id: \.self) { Text($0.label).tag($0) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
            }
            field("Notes") {
                TextEditor(text: $item.notes)
                    .font(.system(size: 13))
                    .frame(height: 80)
                    .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(Color.secondary.opacity(0.3)))
            }

            HStack {
                if !isNew {
                    Button("Delete", role: .destructive) {
                        store.delete(item)
                        dismiss()
                    }
                }
                Spacer()
                Button("Cancel") { dismiss() }
                    .keyboardShortcut(.cancelAction)
                Button("Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(item.title.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(20)
        .frame(width: 440)
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label).font(.system(size: 11, weight: .semibold)).foregroundColor(.secondary)
            content()
        }
    }

    private func save() {
        item.title = item.title.trimmingCharacters(in: .whitespaces)
        item.place = item.place.trimmingCharacters(in: .whitespaces)
        item.course = item.course.trimmingCharacters(in: .whitespaces)
        item.notes = item.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if hasDate {
            let (due, allDay) = Due.make(day: day, time: hasTime ? time : nil)
            item.due = due
            item.allDay = allDay
        } else {
            item.due = nil
            item.allDay = false
        }
        store.upsert(item)
        dismiss()
    }
}
