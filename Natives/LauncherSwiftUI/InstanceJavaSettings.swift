import SwiftUI

@available(iOS 17.0, *)
struct InstanceJavaSettings: View {
    private enum MemoryMode: String, CaseIterable, Identifiable {
        case inherit, auto, manual
        var id: String { rawValue }
        var title: String {
            switch self {
            case .inherit: "全体設定に従う"
            case .auto: "自動"
            case .manual: "手動"
            }
        }
    }

    let onSave: ([String: String]) -> Bool
    private let versions: [String]
    private let maxMemory: Int
    @State private var java: String
    @State private var overrideArgs: Bool
    @State private var args: String
    @State private var memoryMode: MemoryMode
    @State private var memory: String
    @State private var message: String?

    init(row: [String: String], onSave: @escaping ([String: String]) -> Bool) {
        self.onSave = onSave
        let version = row["javaVersion"] ?? row["java"] ?? "0"
        versions = (row["javaVersions"] ?? "").split(separator: ",").map(String.init)
        maxMemory = Int(row["maxMemory"] ?? "") ?? 250
        let existingArgs = row["javaArgs"] ?? ""
        _java = State(initialValue: version.isEmpty || version == "(default)" ? "0" : version)
        _args = State(initialValue: existingArgs)
        _overrideArgs = State(initialValue: row["javaArgsOverride"] == "1" || !existingArgs.isEmpty)
        _memoryMode = State(initialValue: MemoryMode(rawValue: row["memoryMode"] ?? "") ?? .inherit)
        _memory = State(initialValue: row["memoryMB"] ?? "")
    }

    var body: some View {
        Form {
            Section("Javaランタイム") {
                Picker("Javaの指定", selection: $java) {
                    Text("全体設定に従う").tag("0")
                    ForEach(versions, id: \.self) { Text("Java \($0)").tag($0) }
                    if java != "0" && !versions.contains(java) {
                        Text("Java \(java)（利用不可）").tag(java)
                    }
                }
            }
            Section {
                Toggle("JVM起動引数を上書き", isOn: $overrideArgs)
                if overrideArgs {
                    TextField("JVM起動引数", text: $args, axis: .vertical)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                }
            } footer: {
                Text("上書きを有効にすると、空欄の場合も全体設定の引数は使われません。")
            }
            Section("最大メモリ") {
                Picker("割り当て", selection: $memoryMode) {
                    ForEach(MemoryMode.allCases) { Text($0.title).tag($0) }
                }
                if memoryMode == .manual {
                    TextField("メモリ（MB）", text: $memory)
                        .keyboardType(.numberPad)
                    Text("250〜\(maxMemory) MB").font(.caption).foregroundStyle(.secondary)
                }
            }
            Section {
                Button("Java設定を保存", systemImage: "checkmark", action: save)
                    .disabled(memoryMode == .manual && !(250...maxMemory).contains(Int(memory) ?? 0))
                if let message { Text(message).font(.footnote).foregroundStyle(.secondary) }
            }
        }
    }

    private func save() {
        let saved = onSave([
            "javaVersion": java,
            "javaArgsOverride": overrideArgs ? "1" : "0",
            "javaArgs": overrideArgs ? args : "",
            "memoryMode": memoryMode.rawValue,
            "memoryMB": memory
        ])
        message = saved ? "保存しました。" : "Java設定を保存できませんでした。"
    }
}
