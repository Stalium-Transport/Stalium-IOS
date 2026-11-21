import SwiftUI

struct LoginView: View {
    enum Step: Equatable { case credentials, twoFactor(setup: Bool, secret: String, uri: String) }

    @State private var step: Step = .credentials
    @State private var username = ""
    @State private var password = ""
    @State private var code = ""
    @State private var busy = false
    @State private var error: String?
    @FocusState private var codeFocused: Bool

    var body: some View {
        ZStack {
            St.bg.ignoresSafeArea()
            ScrollView {
                VStack(spacing: 14) {
                    Image("Logo").resizable().scaledToFit().frame(width: 88, height: 88)
                        .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
                        .padding(.top, 60)
                    Text("STALIUM").font(.system(size: 32, weight: .black)).tracking(3)
                    Text("Espace conducteurs & staff").foregroundColor(St.muted)
                        .padding(.bottom, 24)

                    switch step {
                    case .credentials: credentials
                    case let .twoFactor(setup, secret, uri): twoFactor(setup: setup, secret: secret, uri: uri)
                    }
                }
                .padding(24)
                .animation(.easeInOut, value: step)
            }
        }
    }

    // MARK: Identifiants
    private var credentials: some View {
        VStack(spacing: 12) {
            Field(icon: "person.fill") {
                TextField("Identifiant ou e-mail", text: $username)
                    .textInputAutocapitalization(.never).autocorrectionDisabled()
                    .textContentType(.username)
            }
            Field(icon: "lock.fill") {
                SecureField("Mot de passe", text: $password)
                    .textContentType(.password)
                    .onSubmit { Task { await submitCredentials() } }
            }
            errorText
            Button { Task { await submitCredentials() } } label: {
                Group { if busy { ProgressView().tint(.white) } else { Text("Se connecter").bold() } }
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent).clipShape(RoundedRectangle(cornerRadius: 14))
            .disabled(busy || username.isEmpty || password.isEmpty)
        }
    }

    // MARK: 2FA
    private func twoFactor(setup: Bool, secret: String, uri: String) -> some View {
        VStack(spacing: 14) {
            Text("🔐 Double authentification").font(.title3.bold())
            if setup {
                Text("Première connexion : ajoutez votre compte dans Google Authenticator (ou Authy), puis entrez le code à 6 chiffres.")
                    .foregroundColor(St.muted).multilineTextAlignment(.center)
                if let u = URL(string: uri), !uri.isEmpty {
                    Link(destination: u) {
                        Label("Ajouter dans l'appli d'authentification", systemImage: "arrow.up.forward.app")
                            .bold().frame(maxWidth: .infinity, minHeight: 50)
                    }
                    .buttonStyle(.borderedProminent).clipShape(RoundedRectangle(cornerRadius: 14))
                }
                if !secret.isEmpty {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("Ou saisissez la clé à la main :").font(.footnote).foregroundColor(St.muted)
                        Text(secret).font(.system(.body, design: .monospaced)).foregroundColor(St.cyan).textSelection(.enabled)
                        Button { UIPasteboard.general.string = secret } label: { Label("Copier la clé", systemImage: "doc.on.doc") }
                    }
                    .padding(14).card()
                }
            } else {
                Text("Entrez le code à 6 chiffres de votre application d'authentification.")
                    .foregroundColor(St.muted).multilineTextAlignment(.center)
            }
            TextField("000000", text: $code)
                .keyboardType(.numberPad).textContentType(.oneTimeCode)
                .font(.system(size: 30, weight: .bold, design: .rounded)).multilineTextAlignment(.center).tracking(8)
                .padding(14).background(St.surfaceHigh).clipShape(RoundedRectangle(cornerRadius: 14))
                .focused($codeFocused)
                .onChange(of: code) { v in
                    let digits = String(v.filter(\.isNumber).prefix(6))
                    if digits != v { code = digits }
                    if digits.count == 6 { Task { await submitCode() } }
                }
                .onAppear { codeFocused = true }
            errorText
            Button { Task { await submitCode() } } label: {
                Group { if busy { ProgressView().tint(.white) } else { Text("Valider").bold() } }
                    .frame(maxWidth: .infinity, minHeight: 52)
            }
            .buttonStyle(.borderedProminent).clipShape(RoundedRectangle(cornerRadius: 14))
            .disabled(busy || code.count != 6)
            Button("Retour") { step = .credentials; code = ""; error = nil }.foregroundColor(St.muted)
        }
    }

    @ViewBuilder private var errorText: some View {
        if let e = error { Text(e).foregroundColor(St.red).multilineTextAlignment(.center).font(.subheadline) }
    }

    // MARK: Actions
    private func submitCredentials() async {
        guard !busy, !username.isEmpty, !password.isEmpty else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            let r = try await Api.login(username.trimmingCharacters(in: .whitespaces), password)
            if r["setup"].bool {
                let s = try? await Api.get("mobile.php?action=2fa_setup")
                step = .twoFactor(setup: true, secret: s?["secret"].string ?? "", uri: s?["uri"].string ?? "")
            } else {
                step = .twoFactor(setup: false, secret: "", uri: "")
            }
        } catch {
            self.error = error.localizedDescription
        }
    }

    private func submitCode() async {
        guard !busy, code.count == 6 else { return }
        busy = true; error = nil
        defer { busy = false }
        do {
            try await Api.verify2fa(code)
            Session.shared.loggedIn = true
        } catch {
            self.error = error.localizedDescription
            code = ""
        }
    }
}

private struct Field<Content: View>: View {
    let icon: String
    @ViewBuilder let content: () -> Content
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: icon).foregroundColor(St.muted).frame(width: 20)
            content()
        }
        .padding(16)
        .background(St.surfaceHigh)
        .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
    }
}
