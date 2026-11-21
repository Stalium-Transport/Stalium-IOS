import SwiftUI
import WebKit

struct MoreView: View {
    @EnvironmentObject var router: Router
    @State private var confirmLogout = false
    @State private var showAnnouncements = false
    @State private var showAbsences = false

    var body: some View {
        Loader(fetch: { try await Api.get("mobile.php?action=home") }) { d, reload in
            let u = d["user"], p = d["perms"]
            List {
                Section {
                    NavigationLink { WebPage(path: "/app/profile", title: "Mon profil") } label: {
                        HStack(spacing: 14) {
                            Avatar(url: u["avatar_url"].string, name: u["name"].string, size: 56)
                            VStack(alignment: .leading, spacing: 2) {
                                Text(u["name"].string).font(.title3.weight(.heavy))
                                Text([u["role"].string, u["role2"].string].filter { !$0.isEmpty }.joined(separator: " · ")).font(.footnote).foregroundColor(St.cyan)
                                Text("Voir mon profil complet").font(.footnote).foregroundColor(St.muted)
                            }
                        }
                        .padding(.vertical, 6)
                    }
                }
                Section("Dans l'appli") {
                    Button { showAnnouncements = true } label: { Row(icon: "megaphone.fill", label: "Annonces") }
                    Button { showAbsences = true } label: { Row(icon: "beach.umbrella.fill", label: "Mes absences") }
                }
                Section("Sur le site") {
                    web("/app/chat", "Radio-Dépôt (chat)", "bubble.left.and.bubble.right.fill")
                    web("/app/tickets", "Support & tickets", "lifepreserver.fill")
                    web("/app/training", "Formation", "graduationcap.fill")
                    web("/app/classement", "Classement du mois", "trophy.fill")
                    if p["open_omsi"].bool {
                        web("/app/open-omsi-dashboard", "Tableau de bord OMSI", "chart.bar.fill")
                        web("/app/ibis", "Codes IBIS", "number.square.fill")
                        web("/app/hof", "Base HOF", "map.fill")
                        web("/app/open-omsi-servers", "Nos serveurs", "globe")
                    }
                    web("/app/stalium-file", "Stalium File", "folder.fill")
                }
                if p["staff"].bool {
                    Section("Staff") {
                        if p["exploitation"].bool { web("/app/exploitation", "Exploitation", "slider.horizontal.3") }
                        if p["announcements"].bool { web("/app/admin-announcements", "Publier une annonce", "megaphone") }
                        web("/app/admin-gestion", "Panneau de gestion", "person.3.fill")
                    }
                }
                Section {
                    Button(role: .destructive) { confirmLogout = true } label: { Row(icon: "rectangle.portrait.and.arrow.right", label: "Se déconnecter", tint: St.red) }
                } footer: {
                    Text("Stalium v\(Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "")")
                        .frame(maxWidth: .infinity).padding(.top, 8)
                }
            }
            .scrollContentBackground(.hidden)
            .refreshable { await reload() }
        }
        .background(St.bg)
        .navigationDestination(isPresented: $showAnnouncements) { AnnouncementsView() }
        .navigationDestination(isPresented: $showAbsences) { AbsencesView() }
        .onChange(of: router.pending) { p in openPending(p) }
        .onAppear { openPending(router.pending) }
        .confirmationDialog("Se déconnecter ?", isPresented: $confirmLogout, titleVisibility: .visible) {
            Button("Déconnexion", role: .destructive) { Task { await Api.logout() } }
        } message: { Text("Vous devrez saisir à nouveau votre mot de passe et votre code 2FA.") }
    }

    private func openPending(_ p: String?) {
        guard let p else { return }
        if p == "announcements" { showAnnouncements = true }
        if p == "absences" { showAbsences = true }
        router.pending = nil
    }

    private func web(_ path: String, _ label: String, _ icon: String) -> some View {
        NavigationLink { WebPage(path: path, title: label) } label: { Row(icon: icon, label: label) }
    }
}

private struct Row: View {
    let icon: String, label: String
    var tint: Color = St.cyan
    var body: some View {
        Label { Text(label).foregroundColor(tint == St.red ? St.red : .primary) } icon: { Image(systemName: icon).foregroundColor(tint) }
    }
}

// MARK: - Page du site (rubriques pas encore natives), avec la session de l'appli

struct WebPage: View {
    let path: String
    let title: String
    @State private var progress = 0.0

    var body: some View {
        WebViewRep(path: path, progress: $progress)
            .ignoresSafeArea(edges: .bottom)
            .overlay(alignment: .top) {
                if progress > 0 && progress < 1 { ProgressView(value: progress).tint(St.blue) }
            }
            .navigationTitle(title)
            .navigationBarTitleDisplayMode(.inline)
            .background(St.bg)
    }
}

private struct WebViewRep: UIViewRepresentable {
    let path: String
    @Binding var progress: Double

    func makeCoordinator() -> Coordinator { Coordinator(self) }

    func makeUIView(context: Context) -> WKWebView {
        let cfg = WKWebViewConfiguration()
        cfg.websiteDataStore = .default()
        let wv = WKWebView(frame: .zero, configuration: cfg)
        wv.isOpaque = false
        wv.backgroundColor = UIColor(red: 5 / 255, green: 11 / 255, blue: 20 / 255, alpha: 1)
        wv.scrollView.backgroundColor = wv.backgroundColor
        wv.allowsBackForwardNavigationGestures = true
        wv.customUserAgent = "Mozilla/5.0 (iPhone; CPU iPhone OS 17_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Mobile/15E148 StaliumAndroid/2.0 StaliumNative StaliumiOS"
        wv.navigationDelegate = context.coordinator
        context.coordinator.observe(wv)
        Task { @MainActor in
            await Api.shareSession(with: cfg.websiteDataStore.httpCookieStore)
            if let u = URL(string: Config.siteURL + path) { wv.load(URLRequest(url: u)) }
        }
        return wv
    }

    func updateUIView(_ uiView: WKWebView, context: Context) {}

    final class Coordinator: NSObject, WKNavigationDelegate {
        let parent: WebViewRep
        private var obs: NSKeyValueObservation?
        init(_ p: WebViewRep) { parent = p }

        func observe(_ wv: WKWebView) {
            obs = wv.observe(\.estimatedProgress) { [weak self] w, _ in
                DispatchQueue.main.async { self?.parent.progress = w.estimatedProgress }
            }
        }

        func webView(_ webView: WKWebView, decidePolicyFor action: WKNavigationAction, decisionHandler: @escaping (WKNavigationActionPolicy) -> Void) {
            guard let url = action.request.url else { return decisionHandler(.cancel) }
            let host = url.host ?? ""
            if url.scheme == "about" || host == URL(string: Config.siteURL)?.host || host.hasSuffix("discord.com") {
                decisionHandler(.allow)
            } else {
                UIApplication.shared.open(url)
                decisionHandler(.cancel)
            }
        }
    }
}
