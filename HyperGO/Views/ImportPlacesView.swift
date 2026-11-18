import SwiftUI
import SwiftData

/// 粘贴一批「名称 + 地址」批量导入
struct ImportPlacesView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @Environment(LocationManager.self) private var locationManager

    @State private var text = ""
    @State private var groupName = ""
    @State private var running = false
    @State private var progress = (done: 0, total: 0)
    @State private var result: PlaceImporter.Result?

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextEditor(text: $text)
                        .frame(minHeight: 220)
                        .font(.callout)
                        .disabled(running)
                } header: {
                    Text("粘贴名单")
                } footer: {
                    Text("每行一个地点：名称和地址之间用 Tab 隔开（从表格里复制就是这样），或者用两个以上空格隔开。已经存在的同名同地址地点会自动跳过。")
                }
                Section {
                    TextField("不分组", text: $groupName)
                        .disabled(running)
                } header: {
                    Text("导入到分组（可选）")
                }
                if running {
                    Section {
                        ProgressView(value: Double(progress.done), total: Double(max(progress.total, 1))) {
                            Text("正在查找地址 \(progress.done)/\(progress.total)")
                        }
                    }
                }
                if let result {
                    Section("结果") {
                        Text(result.summary)
                    }
                }
            }
            .navigationTitle("批量导入")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button(result == nil ? "取消" : "完成") { dismiss() }
                        .disabled(running)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("导入") { Task { await runImport() } }
                        .disabled(running || PlaceImporter.parse(text).isEmpty)
                }
            }
        }
    }

    private func runImport() async {
        running = true
        result = nil
        let r = await PlaceImporter.importText(text, into: context, near: locationManager.location,
                                               groupName: groupName.trimmingCharacters(in: .whitespaces)) { done, total in
            progress = (done, total)
        }
        result = r
        running = false
        if r.failed.isEmpty { text = "" }
    }
}
