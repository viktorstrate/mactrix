import Models
import SwiftUI

public struct CreateRoomScreen: View {
    @State private var params = CreateRoomParams()
    @State private var submitting = false
    @State private var errorMsg: Error? = nil

    let onSubmit: (_ params: CreateRoomParams) async throws -> Void

    public init(onSubmit: @escaping (_ params: CreateRoomParams) async throws -> Void) {
        self.onSubmit = onSubmit
    }

    @ViewBuilder
    var header: some View {
        VStack(spacing: 10) {
            Image(systemName: "number")
                .font(.largeTitle)
            Text("Create Room")
                .font(.largeTitle)

            Text("Create a new chat room to start a conversation.")
        }
    }

    @ViewBuilder
    var form: some View {
        Form {
            TextField("Name", text: $params.name)
                .textFieldStyle(.roundedBorder)
                .padding(.bottom, 8)

            LabeledContent("Topic") {
                TextEditor(text: $params.topic)
                    .textEditorStyle(.plain)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 6)
                            .foregroundStyle(Color.white)
                    )
                    .frame(height: 80)
            }
            .padding(.bottom, 30)

            Picker("Access", selection: $params.access) {
                VStack(alignment: .leading) {
                    Label("Private", systemImage: "lock")
                        .font(.title3)
                    Text("Only invited people can join.")
                        .font(.subheadline)
                }
                .tag(RoomAccess.privateRoom)
                .padding(.bottom, 8)

                VStack(alignment: .leading) {
                    Label("Public", systemImage: "lock.open")
                        .font(.title3)
                    Text("Everyone can join.")
                        .font(.subheadline)
                }
                .tag(RoomAccess.publicRoom)
                .padding(.bottom, 8)
            }
            .pickerStyle(.radioGroup)
            .padding(.bottom, 20)

            Picker("Visibility", selection: $params.visibility) {
                VStack(alignment: .leading) {
                    Label("Unpublished", systemImage: "eye.slash.circle")
                        .font(.title3)
                    Text("The room will not be shown in the published room list.")
                        .font(.subheadline)
                }
                .tag(RoomVisibility.unpublished)
                .padding(.bottom, 8)

                VStack(alignment: .leading) {
                    Label("Published", systemImage: "globe")
                        .font(.title3)
                    Text("The room will be shown in the published room list.")
                        .font(.subheadline)
                }
                .tag(RoomVisibility.published)
                .padding(.bottom, 8)
            }
            .pickerStyle(.radioGroup)
            .padding(.bottom, 20)

            Toggle("End to End Encryption", systemImage: "lock", isOn: $params.enableEncryption)
            Text("Once encryption is enabled, it can not be turned off again.")
                .font(.subheadline)
                .padding(.bottom, 8)

            HStack {
                Button(action: submitForm) {
                    Text("Create")
                }
                .buttonStyle(.borderedProminent)

                HStack(spacing: 0) {
                    ProgressView()
                        .scaleEffect(0.5)
                    Text("Creating room...")
                        .foregroundStyle(.secondary)
                }
                .opacity(submitting ? 1 : 0)
            }

            if let errorMsg {
                Text("Failed to create room: \(errorMsg.localizedDescription)")
                    .foregroundStyle(.red)
                    .textSelection(.enabled)
            }
        }
        .disabled(submitting)
        .frame(minWidth: 300, maxWidth: 450)
        .padding()
        .onSubmit { submitForm() }
    }

    public var body: some View {
        ScrollView {
            HStack {
                Spacer()
                VStack(spacing: 40) {
                    Spacer()
                    header
                    form
                    Spacer()
                }
                Spacer()
            }
        }
        .scrollBounceBehavior(.basedOnSize)
        .navigationTitle("Create Room")
    }

    func submitForm() {
        guard !submitting else { return }
        let paramsCopy = params
        Task {
            submitting = true
            defer { submitting = false }

            do {
                try await onSubmit(paramsCopy)
            } catch {
                errorMsg = error
            }
        }
    }
}

#Preview {
    CreateRoomScreen { _ in
        try await Task.sleep(for: .seconds(3))
    }
}
