import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// Files | Clipboard switch in the tab row, Shelf tab only (clipboard-spec.md §1).
struct ShelfModeSwitch: View {
    @EnvironmentObject var model: NotchModel

    var body: some View {
        HStack(spacing: 0) {
            segment(.files, symbol: "doc.on.doc", label: "Files")
            segment(.clipboard, symbol: "list.clipboard", label: "Clipboard")
        }
        .padding(2)
        .background(Capsule().fill(.white.opacity(0.07)))
        .glassGroup()
        .accessibilityRepresentation {
            Picker("Shelf view", selection: $model.shelfMode) {
                Text("Files").tag(NotchModel.ShelfMode.files)
                Text("Clipboard").tag(NotchModel.ShelfMode.clipboard)
            }
        }
    }

    private func segment(_ mode: NotchModel.ShelfMode, symbol: String, label: String) -> some View {
        let on = model.shelfMode == mode
        return Button { model.shelfMode = mode } label: {
            Image(systemName: symbol).font(.system(size: 10.5, weight: .medium))
                .frame(width: 26, height: 18)
                .modifier(SelectedGlass(selected: on))
        }
        .buttonStyle(.plain)
        .foregroundStyle(on ? .white : .white.opacity(0.45))
        .help(label)
    }
}

/// The Clipboard segment: up to 5 cards, newest first, and Clear (clipboard-spec.md §2, §5).
struct ClipboardView: View {
    @ObservedObject var history: ClipboardHistory
    @AppStorage(ClipboardHistory.defaultsKey) private var enabled = true

    var body: some View {
        if !enabled {
            message("list.clipboard", "Clipboard history is off") {
                Button("Turn it on in Settings…") { (NSApp.delegate as? AppDelegate)?.openSettings() }
                    .buttonStyle(.link).font(.system(size: 11, weight: .medium))
            }
        } else if history.blocked {
            message("lock", "Notch can't read the clipboard.") {
                Text("Allow it in System Settings → Privacy & Security.").font(.system(size: 11)).foregroundStyle(.white.opacity(0.4))
            }
        } else if history.entries.isEmpty {
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(.primary.opacity(0.25), style: StrokeStyle(lineWidth: 1.5, dash: [6]))
                .overlay {
                    VStack(spacing: 6) {
                        Image(systemName: "list.clipboard").font(.system(size: 22))
                        Text("Copy something and it shows up here.").font(.system(size: 12))
                    }
                    .foregroundStyle(.white.opacity(0.5))
                }
        } else {
            // 5×84 + 4×6 + 6 + 84 = 534, the Shelf content width.
            HStack(spacing: 6) {
                HStack(spacing: 6) {
                    ForEach(Array(history.entries.enumerated()), id: \.element.id) { i, entry in
                        ClipCard(entry: entry, index: i + 1, count: history.entries.count, history: history)
                    }
                }
                Spacer(minLength: 0)
                Button(action: history.clear) {
                    Label("Clear", systemImage: "trash")
                        .font(.system(size: 11, weight: .medium))
                        .frame(width: 84, height: 28)
                        .glass(Capsule(), interactive: true)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear clipboard history")
                .glassGroup()
            }
        }
    }

    private func message<Extra: View>(_ symbol: String, _ text: String, @ViewBuilder extra: () -> Extra) -> some View {
        VStack(spacing: 6) {
            Image(systemName: symbol).font(.system(size: 22))
            Text(text).font(.system(size: 12))
            extra()
        }
        .foregroundStyle(.white.opacity(0.5))
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// One entry, 84×100 (clipboard-spec.md §3). Hover, X and grace copied from ShelfItem.
struct ClipCard: View {
    let entry: ClipEntry
    let index: Int, count: Int
    @ObservedObject var history: ClipboardHistory
    @State private var hovering = false
    @State private var unhover: Task<Void, Never>?
    @State private var copied = false
    @State private var copyTask: Task<Void, Never>?
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: 12, style: .continuous) }

    var body: some View {
        Button(action: copy) {
            VStack(alignment: .leading, spacing: 0) {
                content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                footer
            }
            .padding(8)
            .frame(width: 84, height: 100)
            .background { shape.fill(.white.opacity(0.06)).opacity(hovering ? 0 : 1) }
            .background { Color.clear.glass(shape).opacity(hovering ? 1 : 0) }
            .overlay { if copied { copiedOverlay.transition(.opacity) } }
            .contentShape(shape)
        }
        .buttonStyle(Press())
        .onDrag(drag, preview: { dragPreview })
        .overlay(alignment: .topTrailing) {
            Button { history.remove(entry) } label: {
                Image(systemName: "xmark.circle.fill").font(.system(size: 14))
                    .foregroundStyle(.white, .gray)
                    .frame(width: 24, height: 24).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .offset(x: 7, y: -7)
            .opacity(hovering ? 1 : 0)
            .allowsHitTesting(hovering)
            .accessibilityLabel("Remove entry \(index)")
        }
        .animation(.easeOut(duration: 0.15), value: hovering)
        .onHover { inside in
            unhover?.cancel()
            if inside { hovering = true; return }
            unhover = Task { @MainActor in
                try? await Task.sleep(for: .milliseconds(300))
                if !Task.isCancelled { hovering = false }
            }
        }
        .onDisappear { copyTask?.cancel() }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Clipboard entry \(index) of \(count), \(spokenKind), \(spokenPreview)")
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { copy() }
        .accessibilityAction(named: "Remove") { history.remove(entry) }
    }

    // MARK: Click → "Copied" 0.8 s → moves to first

    private func copy() {
        history.copyBack(entry)
        AccessibilityNotification.Announcement("Copied").post()
        copyTask?.cancel()
        withAnimation(.easeOut(duration: 0.15)) { copied = true }
        copyTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            withAnimation(.easeOut(duration: 0.15)) { copied = false }
            try? await Task.sleep(for: .milliseconds(150))
            guard !Task.isCancelled else { return }
            withAnimation(reduceMotion ? nil : .spring(duration: 0.3)) { history.promote(entry) }
        }
    }

    private var copiedOverlay: some View {
        shape.fill(.black.opacity(0.75)).overlay {
            VStack(spacing: 4) {
                Image(systemName: "checkmark.circle.fill").font(.system(size: 20)).foregroundStyle(.white, .green)
                Text("Copied").font(.system(size: 10, weight: .semibold)).foregroundStyle(.white)
            }
        }
    }

    // MARK: Content per kind (spec §3 table)

    @ViewBuilder private var content: some View {
        switch entry.kind {
        case .text, .rich:
            Text(entry.preview).font(.system(size: 10)).foregroundStyle(.white.opacity(0.88))
                .lineLimit(4).lineSpacing(1).truncationMode(.tail)
        case .image:
            Group {
                if let thumb = entry.thumbnail {
                    Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fill)
                } else {
                    Color.white.opacity(0.08)
                }
            }
            .frame(width: 68, height: 44)
            .clipShape(RoundedRectangle(cornerRadius: 6, style: .continuous))
            .frame(maxWidth: .infinity)
        case .file:
            VStack(spacing: 4) {
                Image(nsImage: NSWorkspace.shared.icon(forFile: entry.files.first?.path ?? "/"))
                    .resizable().frame(width: 40, height: 40)
                Text(entry.preview).font(.system(size: 10)).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(.white.opacity(0.88))
            }
            .frame(maxWidth: .infinity)
        case .url:
            VStack(alignment: .leading, spacing: 3) {
                Image(systemName: "link").font(.system(size: 11, weight: .semibold))
                    .frame(width: 24, height: 24).background(Circle().fill(.white.opacity(0.10)))
                Text(entry.preview).font(.system(size: 10.5, weight: .semibold)).lineLimit(1).truncationMode(.middle)
                    .foregroundStyle(.white.opacity(0.88))
                if !entry.detail.isEmpty, entry.detail != "/" {
                    Text(entry.detail).font(.system(size: 9)).lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(.white.opacity(0.45))
                }
            }
        }
    }

    private var footer: some View {
        let (symbol, label): (String, String) = switch entry.kind {
        case .text: ("text.alignleft", "Text")
        case .rich: ("textformat", "Rich text")
        case .image: ("photo", "Image")
        case .file: ("doc", entry.files.count > 1 ? "Files" : "File")
        case .url: ("globe", "Link")
        }
        return HStack(spacing: 3) {
            Image(systemName: symbol).font(.system(size: 8, weight: .semibold))
            Text(label).font(.system(size: 8.5, weight: .medium)).lineLimit(1)
        }
        .foregroundStyle(.white.opacity(0.45))
        .frame(height: 11)
    }

    // MARK: Drag out (spec §4): a copy; the card stays.

    private func drag() -> NSItemProvider {
        let first = entry.items.first ?? [:]
        switch entry.kind {
        case .file:
            return NSItemProvider(object: (entry.files.first ?? URL(fileURLWithPath: "/")) as NSURL)
        case .image:
            let provider = NSItemProvider()
            for (type, uti) in [(NSPasteboard.PasteboardType.png, UTType.png), (.tiff, .tiff)] {
                if let data = first[type] {
                    provider.registerDataRepresentation(forTypeIdentifier: uti.identifier, visibility: .all) { done in
                        done(data, nil); return nil
                    }
                }
            }
            return provider
        case .url:
            let link = first[.URL].flatMap { String(data: $0, encoding: .utf8) } ?? first[.string].flatMap { String(data: $0, encoding: .utf8) } ?? ""
            return URL(string: link).map { NSItemProvider(object: $0 as NSURL) } ?? NSItemProvider(object: link as NSString)
        case .text, .rich:
            let text = first[.string].flatMap { String(data: $0, encoding: .utf8) } ?? entry.preview
            return NSItemProvider(object: text as NSString)
        }
    }

    @ViewBuilder private var dragPreview: some View {
        switch entry.kind {
        case .file:
            Image(nsImage: NSWorkspace.shared.icon(forFile: entry.files.first?.path ?? "/")).resizable().frame(width: 48, height: 48)
        case .image:
            if let thumb = entry.thumbnail {
                Image(nsImage: thumb).resizable().aspectRatio(contentMode: .fit).frame(maxWidth: 84, maxHeight: 84)
            }
        default:
            VStack(alignment: .leading, spacing: 0) {
                content.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                footer
            }
            .padding(8)
            .frame(width: 84, height: 100)
            .background(shape.fill(Color(white: 0.16)))
        }
    }

    // MARK: VoiceOver

    private var spokenKind: String {
        switch entry.kind {
        case .text: "text"
        case .rich: "rich text"
        case .image: "image"
        case .file: entry.files.count > 1 ? "files" : "file"
        case .url: "link"
        }
    }

    private var spokenPreview: String {
        switch entry.kind {
        case .text, .rich:
            let words = entry.preview.split(whereSeparator: \.isWhitespace)
            return words.prefix(8).joined(separator: " ") + (words.count > 8 ? "…" : "")
        case .image: return "image"
        case .file, .url: return entry.preview
        }
    }

    private struct Press: ButtonStyle {
        func makeBody(configuration: Configuration) -> some View {
            configuration.label.scaleEffect(configuration.isPressed ? 0.97 : 1)
                .animation(.spring(duration: 0.15), value: configuration.isPressed)
        }
    }
}
