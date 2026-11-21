import SwiftUI

enum St {
    static let bg = Color(red: 5 / 255, green: 11 / 255, blue: 20 / 255)
    static let surface = Color(red: 13 / 255, green: 22 / 255, blue: 38 / 255)
    static let surfaceHigh = Color(red: 20 / 255, green: 32 / 255, blue: 58 / 255)
    static let border = Color.white.opacity(0.08)
    static let blue = Color(red: 59 / 255, green: 130 / 255, blue: 246 / 255)
    static let cyan = Color(red: 0, green: 210 / 255, blue: 1)
    static let green = Color(red: 34 / 255, green: 197 / 255, blue: 94 / 255)
    static let red = Color(red: 239 / 255, green: 68 / 255, blue: 68 / 255)
    static let yellow = Color(red: 234 / 255, green: 179 / 255, blue: 8 / 255)
    static let muted = Color(red: 148 / 255, green: 163 / 255, blue: 184 / 255)
    static let gradient = LinearGradient(colors: [Color(red: 29 / 255, green: 78 / 255, blue: 216 / 255), Color(red: 8 / 255, green: 145 / 255, blue: 178 / 255)],
                                         startPoint: .topLeading, endPoint: .bottomTrailing)
}

// MARK: - Formats

enum Fmt {
    static func euro(_ v: Double) -> String {
        let f = NumberFormatter()
        f.numberStyle = .currency
        f.locale = Locale(identifier: "fr_FR")
        return f.string(from: NSNumber(value: v)) ?? "\(v) €"
    }

    /// "2026-11-21" ou "2026-11-21 10:05:00" (UTC) → texte court en français.
    static func date(_ s: String, time: Bool = false) -> String {
        guard !s.isEmpty else { return "" }
        let out = DateFormatter()
        out.locale = Locale(identifier: "fr_FR")
        out.timeZone = TimeZone(identifier: "Europe/Paris")
        let inp = DateFormatter()
        inp.locale = Locale(identifier: "en_US_POSIX")
        if s.count <= 10 {
            inp.dateFormat = "yyyy-MM-dd"
            inp.timeZone = TimeZone(identifier: "Europe/Paris")
            out.dateFormat = "EEE d MMM"
        } else {
            inp.dateFormat = "yyyy-MM-dd HH:mm:ss"
            inp.timeZone = TimeZone(identifier: "UTC")
            out.dateFormat = time ? "d MMM 'à' HH:mm" : "d MMM"
        }
        let clean = String(s.replacingOccurrences(of: "T", with: " ").prefix(s.count <= 10 ? 10 : 19))
        guard let d = inp.date(from: clean) else { return s }
        return out.string(from: d)
    }

    static func day(_ s: String) -> Date? {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        return f.date(from: String(s.prefix(10)))
    }

    static func iso(_ d: Date) -> String {
        let f = DateFormatter()
        f.locale = Locale(identifier: "en_US_POSIX")
        f.dateFormat = "yyyy-MM-dd"
        f.timeZone = TimeZone(identifier: "Europe/Paris")
        return f.string(from: d)
    }

    static func stripHtml(_ s: String) -> String {
        var t = s.replacingOccurrences(of: "<br\\s*/?>", with: "\n", options: [.regularExpression, .caseInsensitive])
        t = t.replacingOccurrences(of: "</p>", with: "\n", options: .caseInsensitive)
        t = t.replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
        for (a, b) in [("&nbsp;", " "), ("&amp;", "&"), ("&lt;", "<"), ("&gt;", ">"), ("&quot;", "\""), ("&#39;", "'")] {
            t = t.replacingOccurrences(of: a, with: b)
        }
        return t.replacingOccurrences(of: "\n{3,}", with: "\n\n", options: .regularExpression).trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

// MARK: - Composants

struct CardStyle: ViewModifier {
    func body(content: Content) -> some View {
        content
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(St.surface)
            .clipShape(RoundedRectangle(cornerRadius: 20, style: .continuous))
            .overlay(RoundedRectangle(cornerRadius: 20, style: .continuous).stroke(St.border, lineWidth: 1))
    }
}

extension View {
    func card() -> some View { modifier(CardStyle()) }
}

struct StatusChip: View {
    let status: String
    var body: some View {
        let s = status.isEmpty ? "En attente" : status
        let c: Color = ["Validé", "Validée", "Confirmé"].contains(s) ? St.green : (["Refusé", "Refusée", "Annulé", "Annulée"].contains(s) ? St.red : St.yellow)
        Text(s)
            .font(.caption.bold())
            .foregroundColor(c)
            .padding(.horizontal, 10).padding(.vertical, 4)
            .background(c.opacity(0.15))
            .clipShape(Capsule())
    }
}

struct CountBadge: View {
    let n: Int
    var body: some View {
        if n > 0 {
            Text(n > 99 ? "99+" : "\(n)")
                .font(.caption.bold()).foregroundColor(.white)
                .padding(.horizontal, 8).padding(.vertical, 2)
                .background(St.red).clipShape(Capsule())
        }
    }
}

struct Avatar: View {
    let url: String
    let name: String
    var size: CGFloat = 48

    var body: some View {
        ZStack {
            St.gradient
            Text(String(name.prefix(2)).uppercased()).font(.system(size: size / 2.6, weight: .bold)).foregroundColor(.white)
            if let u = fullURL {
                AsyncImage(url: u) { img in img.resizable().scaledToFill() } placeholder: { Color.clear }
            }
        }
        .frame(width: size, height: size)
        .clipShape(Circle())
    }

    private var fullURL: URL? {
        guard !url.isEmpty else { return nil }
        return URL(string: url.hasPrefix("http") ? url : Config.siteURL + url)
    }
}

struct EmptyState: View {
    let emoji: String
    let text: String
    var body: some View {
        VStack(spacing: 10) {
            Text(emoji).font(.system(size: 44))
            Text(text).foregroundColor(St.muted).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity).padding(.vertical, 40)
    }
}

struct SectionTitle<Trailing: View>: View {
    let text: String
    var trailing: () -> Trailing

    init(_ text: String, @ViewBuilder trailing: @escaping () -> Trailing) {
        self.text = text
        self.trailing = trailing
    }

    var body: some View {
        HStack {
            Text(text).font(.headline)
            Spacer()
            trailing()
        }
        .padding(.top, 8)
    }
}

extension SectionTitle where Trailing == EmptyView {
    init(_ text: String) { self.text = text; self.trailing = { EmptyView() } }
}

/// Chargement + erreur + « tirer pour rafraîchir ».
struct Loader<Content: View>: View {
    let fetch: () async throws -> J
    @ViewBuilder let content: (J, @escaping () async -> Void) -> Content
    @State private var data: J?
    @State private var error: String?

    var body: some View {
        Group {
            if let d = data {
                content(d, { await load() })
            } else if let e = error {
                ScrollView {
                    VStack(spacing: 16) {
                        Image(systemName: "wifi.exclamationmark").font(.system(size: 44)).foregroundColor(St.muted)
                        Text(e).foregroundColor(St.muted).multilineTextAlignment(.center)
                        Button("Réessayer") { Task { await load() } }.buttonStyle(.borderedProminent)
                    }
                    .frame(maxWidth: .infinity).padding(.top, 80).padding(.horizontal, 32)
                }
                .refreshable { await load() }
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .task { if data == nil { await load() } }
    }

    private func load() async {
        do {
            data = try await fetch()
            error = nil
        } catch {
            if data == nil { self.error = error.localizedDescription }
        }
    }
}
