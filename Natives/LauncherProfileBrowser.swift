import SwiftUI
import UIKit

final class ProfileBrowserState: ObservableObject {
    struct Snapshot: Equatable {
        let rows: [[String: String]]
        let selected: String?
    }

    @Published private(set) var snapshot: Snapshot

    init(rows: [[String: String]], selected: String?) {
        snapshot = Snapshot(rows: rows, selected: selected)
    }

    func update(rows: [[String: String]], selected: String?) {
        let next = Snapshot(rows: rows, selected: selected)
        if snapshot != next { snapshot = next }
    }
}

private protocol ProfileBrowserHosting {
    var profileState: ProfileBrowserState { get }
}

private final class ProfileHostingController<Content: View>: UIHostingController<Content>, ProfileBrowserHosting {
    let profileState: ProfileBrowserState

    init(state: ProfileBrowserState, content: Content) {
        profileState = state
        super.init(rootView: content)
    }

    @MainActor required dynamic init?(coder: NSCoder) { nil }
}

@objc(AMProfileBrowser)
final class ProfileBrowser: NSObject {
    @objc(makeWithRows:selected:isolated:allowsInstanceSettings:settings:jitStatus:accountImage:downloadSnapshot:prepareDirectory:blockTexture:blockTextures:saveJava:action:)
    static func make(rows: [[String: String]], selected: String?, isolated: Bool, allowsInstanceSettings: Bool,
                     settings: @escaping (String) -> UIViewController,
                     jitStatus: @escaping () -> Bool,
                     accountImage: @escaping () -> UIImage?,
                     downloadSnapshot: @escaping () -> [String: Any],
                     prepareDirectory: @escaping (String) -> String?,
                     blockTexture: @escaping (String, String) -> UIImage?,
                     blockTextures: @escaping (String) -> [String],
                     saveJava: @escaping (String, [String: String]) -> Bool,
                     action: @escaping (String, String) -> Void) -> UIViewController {
        let state = ProfileBrowserState(rows: rows, selected: selected)
        if #available(iOS 17.0, *) {
            return ProfileHostingController(state: state, content: LauncherWorkspace(profiles: state,
                                                                    settings: settings, jitStatus: jitStatus,
                                                                    accountImage: accountImage, downloadSnapshot: downloadSnapshot,
                                                                    prepareDirectory: prepareDirectory, blockTexture: blockTexture, blockTextures: blockTextures, saveJava: saveJava, action: action))
        }
        return ProfileHostingController(state: state, content: ProfileLibrary(profiles: state, action: action, allowsInstanceSettings: allowsInstanceSettings, isolated: isolated))
    }

    @objc(updateController:rows:selected:)
    static func update(controller: UIViewController, rows: [[String: String]], selected: String?) {
        (controller as? ProfileBrowserHosting)?.profileState.update(rows: rows, selected: selected)
    }
}

private struct ProfileLibrary: View {
    @ObservedObject var profiles: ProfileBrowserState
    let action: (String, String) -> Void
    let allowsInstanceSettings: Bool

    @State private var search = ""
    @State private var selection: String?

    private var rows: [[String: String]] { profiles.snapshot.rows }
    private var selected: String? { selection ?? profiles.snapshot.selected }
    private var visibleRows: [[String: String]] {
        rows.filter {
            search.isEmpty || ($0["name"] ?? "").localizedCaseInsensitiveContains(search)
                || ($0["version"] ?? "").localizedCaseInsensitiveContains(search)
        }
    }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Text("Minecraft").font(.largeTitle.bold()).accessibilityAddTraits(.isHeader)
                TextField("Search profiles", text: $search)
                    .textFieldStyle(RoundedBorderTextFieldStyle())
                    .accessibilityLabel("Search profiles")
                if visibleRows.isEmpty {
                    Text(rows.isEmpty ? "No profiles" : "No matching profiles")
                        .foregroundColor(.secondary)
                }
                LazyVGrid(columns: [GridItem(.adaptive(minimum: 175), spacing: 12)], spacing: 12) {
                    ForEach(visibleRows, id: \.self) { row in
                        let id = row["id"] ?? ""
                        Button {
                            selection = id
                            action("select", id)
                        } label: {
                            VStack(alignment: .leading, spacing: 8) {
                                HStack {
                                    Image(systemName: "cube.fill").foregroundColor(.accentColor)
                                    Spacer()
                                    if selected == id {
                                        Image(systemName: "checkmark.circle.fill").foregroundColor(.accentColor)
                                    }
                                }
                                Text(row["name"] ?? id).font(.headline)
                                Text(row["version"] ?? "").font(.subheadline).foregroundColor(.secondary)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding()
                            .background(Color(UIColor.secondarySystemGroupedBackground))
                            .clipShape(RoundedRectangle(cornerRadius: 14))
                        }
                        .buttonStyle(PlainButtonStyle())
                        .accessibilityAddTraits(selected == id ? .isSelected : [])
                    }
                }
                if let id = selected, rows.contains(where: { $0["id"] == id }) {
                    HStack(spacing: 20) {
                        Button { action("play", id) } label: { Label("Play", systemImage: "play.fill") }
                        Button { action("edit", id) } label: { Label("Edit", systemImage: "slider.horizontal.3") }
                        Spacer()
                        if rows.count > 1 {
                            Button { action("delete", id) } label: { Label("Delete", systemImage: "trash") }
                        }
                    }
                    .padding(.vertical, 8)
                }
                Button { action("directory", "") } label: { Label("Game Directory", systemImage: "folder") }
                    .disabled(!allowsInstanceSettings)
                Toggle("Separate preferences", isOn: Binding(
                    get: { isolated }, set: { isolated = $0; action("isolation", $0 ? "1" : "0") }
                ))
                .disabled(!allowsInstanceSettings)
            }
            .padding()
        }
        .background(Color(UIColor.systemGroupedBackground))
    }

    @State var isolated = false
}
