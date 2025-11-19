import AuthenticationServices
import MatrixRustSDK
import SwiftUI

struct WelcomeSheetView: View {
    @Environment(AppState.self) private var appState
    @Environment(\.dismiss) private var dismiss

    @Environment(\.webAuthenticationSession) private var webAuthenticationSession

    @State private var homeserverLogin: HomeserverLogin? = nil

    @State private var homeserverField: String = ""
    @State private var usernameField: String = ""
    @State private var passwordField: String = ""

    @State private var loading: Bool = false
    @State private var showError: Error? = nil

    func loadHomeserver() {
        Task {
            loading = true
            defer { loading = false }

            do {
                homeserverLogin = try await MatrixClient.loginDetails(homeServer: homeserverField)
                showError = nil
            } catch {
                homeserverLogin = nil
                showError = error
            }
        }
    }

    func signInPassword() {
        Task {
            guard let homeserverLogin = homeserverLogin else { return }
            loading = true
            defer { loading = false }

            do {
                let client = try await homeserverLogin.loginPassword(homeServer: homeserverField, username: usernameField, password: passwordField)
                appState.matrixClient = client
                dismiss()
            } catch {
                showError = error
            }
        }
    }

    func signInOidc() {
        Task {
            guard let homeserverLogin = homeserverLogin else { return }
            loading = true
            defer { loading = false }

            do {
                let client = try await homeserverLogin.loginOidc(webAuthSession: webAuthenticationSession)
                appState.matrixClient = client
                dismiss()
            } catch {
                showError = error
            }
        }
    }

    @ViewBuilder
    var passwordLogin: some View {
        TextField("Username", text: $usernameField)
            .disabled(loading)
            .onSubmit { signInPassword() }
        SecureField("Password", text: $passwordField)
            .disabled(loading)
            .onSubmit { signInPassword() }

        HStack {
            Button("Sign in") { signInPassword() }
                .disabled(loading)
            Button("Register account") {}
                .buttonStyle(.link)
                .disabled(loading)
            ProgressView()
                .scaleEffect(0.5)
                .opacity(loading ? 1 : 0)
        }
    }

    @ViewBuilder
    var oidcLogin: some View {
        Button("Sign in with OAuth") {
            signInOidc()
        }
    }

    var body: some View {
        VStack {
            Text("Welcome to Mactrix")
                .font(.headline)
                .padding(.bottom)

            Form {
                TextField("Homeserver", text: $homeserverField, prompt: Text("matrix.org"))
                    .disabled(loading)
                    .onSubmit { loadHomeserver() }

                if homeserverLogin?.loginDetails.supportsOidcLogin() == true {
                    oidcLogin
                }

                if homeserverLogin?.loginDetails.supportsPasswordLogin() == true {
                    passwordLogin
                }
            }
            .frame(maxWidth: 300)

            if let showError = showError {
                Text(showError.localizedDescription)
                    .foregroundStyle(Color.red)
                    .textSelection(.enabled)
            }
        }
        .padding()
    }
}

#Preview {
    WelcomeSheetView()
        .environment(AppState())
}
