import SwiftUI

struct ServerSetupView: View {
    @EnvironmentObject var settings: AppSettings
    @State private var input: String = ""
    @State private var error: String?
    @FocusState private var focused: Bool

    var body: some View {
        NavigationView {
            Form {
                Section {
                    VStack(spacing: 12) {
                        Image(systemName: "note.text")
                            .font(.system(size: 56))
                            .foregroundColor(.accentColor)
                        Text("Memos")
                            .font(.largeTitle).bold()
                        Text("连接到你的自托管 Memos 服务器")
                            .font(.subheadline)
                            .foregroundColor(.secondary)
                    }
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                }
                .listRowBackground(Color.clear)

                Section(header: Text("服务器地址"),
                        footer: Text("例如 https://memos.example.com 或 http://192.168.1.10:5230。未填写协议时默认使用 https://。")) {
                    TextField("https://memos.example.com", text: $input)
                        .keyboardType(.URL)
                        .textContentType(.URL)
                        .autocapitalization(.none)
                        .disableAutocorrection(true)
                        .focused($focused)
                        .submitLabel(.go)
                        .onSubmit(connect)
                    if let error = error {
                        Text(error).foregroundColor(.red).font(.footnote)
                    }
                }

                Section {
                    Button(action: connect) {
                        Text("连接").frame(maxWidth: .infinity).font(.headline)
                    }
                    .disabled(input.trimmingCharacters(in: .whitespaces).isEmpty)
                }

                Section(footer: Text("还没有服务器？Memos 是开源的轻量笔记服务，可以通过 Docker 部署：docker run -d -p 5230:5230 -v ~/.memos:/var/opt/memos neosmemo/memos:stable")) {
                    Link("访问 Memos 官网", destination: URL(string: "https://usememos.com")!)
                }
            }
            .navigationBarHidden(true)
        }
        .navigationViewStyle(.stack)
        .onAppear {
            if input.isEmpty, let current = settings.serverURL { input = current.absoluteString }
            focused = input.isEmpty
        }
    }

    private func connect() {
        guard let url = AppSettings.normalize(input) else {
            error = "地址无效，请检查后重试"
            return
        }
        error = nil
        settings.serverURL = url
    }
}
