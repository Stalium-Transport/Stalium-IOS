import SwiftUI

struct HomeView: View {
    @EnvironmentObject var router: Router

    var body: some View {
        Loader(fetch: { try await Api.get("mobile.php?action=home") }) { d, reload in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    header(d["user"])
                    balance(d["stats"])
                    todo(d["perms"], d["pending"])

                    SectionTitle("Mes prochains services") {
                        Button("Tout voir") { router.tab = .planning }.font(.subheadline)
                    }
                    let next = d["next_services"].array
                    if next.isEmpty {
                        Text("Aucun service planifié pour le moment.").foregroundColor(St.muted).padding(18).card()
                    } else {
                        ForEach(next.indices, id: \.self) { i in ServiceCard(s: next[i]) }
                    }

                    SectionTitle("Accès rapides")
                    LazyVGrid(columns: Array(repeating: GridItem(.flexible(), spacing: 10), count: 3), spacing: 10) {
                        QuickTile(icon: "doc.text.fill", label: "Feuilles") { router.tab = .sheets }
                        NavigationLink { AbsencesView() } label: { TileLabel(icon: "beach.umbrella.fill", label: "Absences") }
                        NavigationLink { AnnouncementsView() } label: { TileLabel(icon: "megaphone.fill", label: "Annonces") }
                        NavigationLink { WebPage(path: "/app/chat", title: "Radio-Dépôt") } label: { TileLabel(icon: "bubble.left.and.bubble.right.fill", label: "Chat") }
                        NavigationLink { WebPage(path: "/app/tickets", title: "Support & tickets") } label: { TileLabel(icon: "lifepreserver.fill", label: "Tickets") }
                        QuickTile(icon: "bell.fill", label: "Notifs", badge: d["unread_notifications"].int) { router.tab = .notifications }
                    }

                    let ann = d["latest_announcement"]
                    if !ann.isNull {
                        SectionTitle("Dernière annonce")
                        NavigationLink { AnnouncementsView() } label: {
                            HStack(spacing: 12) {
                                Text("📣").font(.title)
                                VStack(alignment: .leading) {
                                    Text(ann["title"].string).bold().lineLimit(2).foregroundColor(.primary)
                                    Text(Fmt.date(ann["created_at"].string, time: true)).font(.footnote).foregroundColor(St.muted)
                                }
                                Spacer()
                                Image(systemName: "chevron.right").foregroundColor(St.muted)
                            }
                            .padding(16).card()
                        }
                    }
                }
                .padding(16)
            }
            .refreshable { await reload() }
        }
        .background(St.bg)
    }

    private func header(_ u: J) -> some View {
        HStack(spacing: 14) {
            Avatar(url: u["avatar_url"].string, name: u["name"].string, size: 54)
            VStack(alignment: .leading, spacing: 2) {
                let h = Calendar.current.component(.hour, from: Date())
                Text(h >= 5 && h < 18 ? "Bonjour 👋" : "Bonsoir 🌙").foregroundColor(St.muted)
                Text(u["name"].string).font(.title2.weight(.heavy)).lineLimit(1)
                Text([u["role"].string, u["role2"].string].filter { !$0.isEmpty }.joined(separator: " · ").isEmpty ? "Conducteur"
                     : [u["role"].string, u["role2"].string].filter { !$0.isEmpty }.joined(separator: " · "))
                    .font(.footnote).foregroundColor(St.cyan).lineLimit(1)
            }
        }
    }

    private func balance(_ s: J) -> some View {
        let byStatus = Dictionary(s["sheets"].array.map { ($0["status"].string(or: "En attente"), $0["n"].int) }, uniquingKeysWith: +)
        return VStack(alignment: .leading, spacing: 4) {
            Text("Mon solde").foregroundColor(.white.opacity(0.8))
            Text(Fmt.euro(s["balance"].double)).font(.system(size: 32, weight: .black)).foregroundColor(.white)
            HStack(spacing: 10) {
                MiniStat(label: "Services", value: "\(s["services"].int)")
                MiniStat(label: "Km ce mois", value: "\(s["km_month"].int)")
                MiniStat(label: "En attente", value: "\(byStatus["En attente"] ?? 0)")
            }
            .padding(.top, 10)
        }
        .padding(20)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(St.gradient)
        .clipShape(RoundedRectangle(cornerRadius: 24, style: .continuous))
    }

    @ViewBuilder
    private func todo(_ p: J, _ pending: J) -> some View {
        let sheets = p["validate_sheets"].bool || p["reject_sheets"].bool
        if sheets || p["absences"].bool {
            SectionTitle("À traiter")
            if sheets {
                let n = pending["sheets"].int
                Button { router.tab = .sheets } label: {
                    ActionRow(icon: "checkmark.seal.fill", title: "Feuilles de route à valider", subtitle: n == 0 ? "Rien en attente 🎉" : "\(n) feuille(s) en attente", count: n, tint: St.yellow)
                }
            }
            if p["absences"].bool {
                let n = pending["absences"].int
                NavigationLink { AbsencesView(startOnManage: true) } label: {
                    ActionRow(icon: "beach.umbrella.fill", title: "Absences à valider", subtitle: n == 0 ? "Aucune demande" : "\(n) demande(s)", count: n, tint: St.cyan)
                }
            }
        }
    }
}

private struct MiniStat: View {
    let label: String
    let value: String
    var body: some View {
        VStack(alignment: .leading) {
            Text(value).font(.headline.weight(.heavy)).foregroundColor(.white)
            Text(label).font(.caption2).foregroundColor(.white.opacity(0.8)).lineLimit(1)
        }
        .padding(10).frame(maxWidth: .infinity, alignment: .leading)
        .background(Color.white.opacity(0.14)).clipShape(RoundedRectangle(cornerRadius: 14))
    }
}

private struct ActionRow: View {
    let icon: String, title: String, subtitle: String, count: Int, tint: Color
    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: icon).foregroundColor(tint).frame(width: 44, height: 44)
                .background(tint.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading) {
                Text(title).bold().foregroundColor(.primary)
                Text(subtitle).font(.footnote).foregroundColor(St.muted)
            }
            Spacer()
            CountBadge(n: count)
            Image(systemName: "chevron.right").foregroundColor(St.muted)
        }
        .padding(16).card()
    }
}

struct ServiceCard: View {
    let s: J
    var body: some View {
        HStack(spacing: 14) {
            VStack {
                Text(String(s["start_time"].string.prefix(5))).font(.headline.weight(.heavy)).foregroundColor(St.blue)
                Text(String(s["end_time"].string.prefix(5))).font(.caption).foregroundColor(St.muted)
            }
            .frame(width: 62).padding(.vertical, 8)
            .background(St.blue.opacity(0.15)).clipShape(RoundedRectangle(cornerRadius: 14))
            VStack(alignment: .leading, spacing: 2) {
                Text(Fmt.date(s["service_date"].string).capitalized).font(.footnote).foregroundColor(St.muted)
                Text("Ligne \(s["line_name"].string) · Service \(s["service_num"].string)").bold().lineLimit(1)
                Label([s["bus_assigned"].string, s["server_name"].string].filter { !$0.isEmpty }.joined(separator: " · "), systemImage: "bus.fill")
                    .font(.footnote).foregroundColor(St.muted).lineLimit(1)
                if !s["driver_name"].string.isEmpty {
                    Text("👤 \(s["driver_name"].string)").font(.footnote).foregroundColor(St.muted)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(16).card()
    }
}

private struct TileLabel: View {
    let icon: String, label: String
    var badge = 0
    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: icon).font(.title2).foregroundColor(St.cyan)
            Text(label).font(.footnote.weight(.semibold)).foregroundColor(.primary)
        }
        .frame(maxWidth: .infinity, minHeight: 78)
        .card()
        .overlay(alignment: .topTrailing) { CountBadge(n: badge).padding(6) }
    }
}

private struct QuickTile: View {
    let icon: String, label: String
    var badge = 0
    let action: () -> Void
    var body: some View {
        Button(action: action) { TileLabel(icon: icon, label: label, badge: badge) }
    }
}
