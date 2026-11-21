import SwiftUI

// MARK: - Planning

struct PlanningView: View {
    @State private var all = false

    var body: some View {
        VStack(spacing: 0) {
            Picker("", selection: $all) {
                Text("Mes services").tag(false)
                Text("Tout le planning").tag(true)
            }
            .pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 8)

            Loader(fetch: {
                let from = Date()
                let to = Calendar.current.date(byAdding: .day, value: all ? 14 : 60, to: from)!
                return try await Api.get("mobile.php?action=planning&from=\(Fmt.iso(from))&to=\(Fmt.iso(to))" + (all ? "&all=1" : ""))
            }) { d, reload in
                let list = d["services"].array
                let days = orderedDays(list)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 10) {
                        if list.isEmpty {
                            EmptyState(emoji: "📆", text: all ? "Aucun service planifié ces 2 prochaines semaines." : "Aucun service à venir pour vous.")
                        }
                        ForEach(days, id: \.self) { day in
                            let services = list.filter { $0["service_date"].string == day }
                            SectionTitle(label(day)) { Text("\(services.count) service(s)").font(.footnote).foregroundColor(St.muted) }
                            ForEach(services.indices, id: \.self) { i in ServiceCard(s: services[i]) }
                        }
                    }
                    .padding(16)
                }
                .refreshable { await reload() }
            }
            .id(all)
        }
        .background(St.bg)
    }

    private func orderedDays(_ list: [J]) -> [String] {
        var seen = Set<String>(), out = [String]()
        for s in list where seen.insert(s["service_date"].string).inserted { out.append(s["service_date"].string) }
        return out
    }

    private func label(_ day: String) -> String {
        guard let d = Fmt.day(day) else { return day }
        if Calendar.current.isDateInToday(d) { return "Aujourd'hui" }
        if Calendar.current.isDateInTomorrow(d) { return "Demain" }
        return Fmt.date(day).capitalized
    }
}

// MARK: - Notifications

struct NotificationsView: View {
    @EnvironmentObject var router: Router
    @State private var key = 0

    var body: some View {
        Loader(fetch: { try await Api.get("notifications.php") }) { d, reload in
            let list = d.array
            List {
                if list.isEmpty {
                    EmptyState(emoji: "🔔", text: "Aucune notification.").listRowBackground(Color.clear)
                }
                ForEach(list.indices, id: \.self) { i in
                    let n = list[i]
                    let unread = n["is_read"].int == 0
                    Button {
                        Task { try? await Api.put("notifications.php?action=read&id=\(n.id)") }
                        router.open(url: route(n))
                    } label: {
                        HStack(alignment: .top, spacing: 12) {
                            Circle().fill(unread ? St.blue : St.border).frame(width: 9, height: 9).padding(.top, 6)
                            VStack(alignment: .leading, spacing: 3) {
                                Text(n["title"].string).fontWeight(unread ? .bold : .medium).foregroundColor(.primary)
                                Text(n["message"].string).font(.subheadline).foregroundColor(St.muted)
                                Text(Fmt.date(n["created_at"].string, time: true)).font(.caption).foregroundColor(St.muted)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .listRowBackground(St.surface)
                    .swipeActions {
                        Button(role: .destructive) {
                            Task { try? await Api.delete("notifications.php?id=\(n.id)"); await reload() }
                        } label: { Label("Supprimer", systemImage: "trash") }
                    }
                }
            }
            .scrollContentBackground(.hidden)
            .refreshable { await reload() }
            .toolbar {
                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Button { Task { try? await Api.put("notifications.php?action=read-all"); await reload() } } label: { Label("Tout marquer lu", systemImage: "checkmark.circle") }
                        Button(role: .destructive) { Task { try? await Api.delete("notifications.php?action=clear-all"); await reload() } } label: { Label("Tout supprimer", systemImage: "trash") }
                    } label: { Image(systemName: "ellipsis.circle") }
                }
            }
        }
        .background(St.bg)
    }

    private func route(_ n: J) -> String {
        let t = n["title"].string.lowercased()
        if t.contains("feuille") { return "#sheets" }
        if n["type"].string == "announcement" { return "announcements" }
        if t.contains("absence") { return "absences" }
        if t.contains("planning") { return "planning" }
        return "notifications"
    }
}

// MARK: - Annonces

struct AnnouncementsView: View {
    var body: some View {
        Loader(fetch: { try await Api.get("announcements.php") }) { d, reload in
            let list = d.array
            ScrollView {
                LazyVStack(spacing: 12) {
                    if list.isEmpty { EmptyState(emoji: "📣", text: "Aucune annonce.") }
                    ForEach(list.indices, id: \.self) { i in AnnouncementCard(a: list[i], startExpanded: i == 0) }
                }
                .padding(16)
            }
            .refreshable { await reload() }
        }
        .background(St.bg)
        .navigationTitle("Annonces")
    }
}

private struct AnnouncementCard: View {
    let a: J
    @State var expanded: Bool
    init(a: J, startExpanded: Bool) { self.a = a; _expanded = State(initialValue: startExpanded) }

    var body: some View {
        let author = a["author_name"].string(or: a["author"].string(or: "Stalium"))
        let text = Fmt.stripHtml(a["content"].string)
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Avatar(url: "", name: author, size: 36)
                VStack(alignment: .leading) {
                    Text(author).font(.subheadline.weight(.semibold))
                    Text(Fmt.date(a["created_at"].string, time: true)).font(.caption).foregroundColor(St.muted)
                }
                Spacer()
                if a["is_staff_only"].int == 1 { Text("STAFF").font(.caption2.bold()).foregroundColor(St.yellow) }
            }
            Text(a["title"].string).font(.headline)
            Text(text).font(.subheadline).foregroundColor(.primary.opacity(0.85)).lineLimit(expanded ? nil : 4)
            if !expanded && text.count > 220 { Text("Lire la suite").font(.subheadline).foregroundColor(St.blue) }
        }
        .padding(16).card()
        .contentShape(Rectangle())
        .onTapGesture { withAnimation { expanded.toggle() } }
    }
}

// MARK: - Absences

private let reasons = ["Personnel", "Vacances", "Technique", "Scolaire / Travail", "Autre"]

struct AbsencesView: View {
    var startOnManage = false
    @State private var isManager = false
    @State private var tab = 0
    @State private var key = 0
    @State private var showForm = false
    @State private var review: J?
    @State private var reviewComment = ""
    @State private var toast: String?

    var body: some View {
        VStack(spacing: 0) {
            if isManager {
                Picker("", selection: $tab) {
                    Text("Mes absences").tag(0)
                    Text("À valider").tag(1)
                }
                .pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 8)
            }
            let manage = isManager && tab == 1
            Loader(fetch: { try await Api.get(manage ? "absences.php?action=admin_list&status=En%20attente" : "absences.php") }) { d, reload in
                let list = d["absences"].array
                ScrollView {
                    LazyVStack(spacing: 10) {
                        if list.isEmpty { EmptyState(emoji: "🌴", text: manage ? "Aucune demande en attente." : "Aucune absence déclarée.") }
                        ForEach(list.indices, id: \.self) { i in
                            let a = list[i]
                            VStack(alignment: .leading, spacing: 4) {
                                HStack(spacing: 10) {
                                    if manage { Avatar(url: a["avatar_url"].string, name: a["username"].string(or: "?"), size: 36) }
                                    VStack(alignment: .leading) {
                                        if manage { Text(a["username"].string).bold() }
                                        Text("Du \(Fmt.date(a["start_date"].string)) au \(Fmt.date(a["end_date"].string))").fontWeight(manage ? .regular : .bold)
                                    }
                                    Spacer()
                                    StatusChip(status: a["status"].string)
                                }
                                Text(a["reason_type"].string).font(.footnote).foregroundColor(St.muted)
                                if !a["comment"].string.isEmpty { Text(a["comment"].string).font(.subheadline) }
                                if !a["review_comment"].string.isEmpty { Text("RH : \(a["review_comment"].string)").font(.footnote).foregroundColor(St.cyan) }
                            }
                            .padding(16).card()
                            .contentShape(Rectangle())
                            .onTapGesture { if manage { reviewComment = ""; review = a } }
                        }
                    }
                    .padding(16).padding(.bottom, 70)
                }
                .refreshable { await reload() }
            }
            .id("\(tab)-\(key)")
        }
        .background(St.bg)
        .navigationTitle("Absences")
        .overlay(alignment: .bottomTrailing) {
            if tab == 0 {
                Button { showForm = true } label: {
                    Label("Déclarer", systemImage: "plus").bold().padding(.horizontal, 20).padding(.vertical, 14)
                        .background(St.blue).foregroundColor(.white).clipShape(Capsule()).shadow(radius: 8)
                }
                .padding(20)
            }
        }
        .task {
            isManager = (try? await Api.get("absences.php?action=admin_list&status=En%20attente")) != nil
            if isManager && startOnManage { tab = 1 }
        }
        .sheet(isPresented: $showForm) {
            AbsenceForm { msg in showForm = false; toast = msg; key += 1 }
                .presentationDetents([.large])
        }
        .alert("Absence de \(review?["username"].string ?? "")", isPresented: Binding(get: { review != nil }, set: { if !$0 { review = nil } })) {
            TextField("Commentaire (facultatif)", text: $reviewComment)
            Button("Valider") { decide("Validée") }
            Button("Refuser", role: .destructive) { decide("Refusée") }
            Button("Annuler", role: .cancel) {}
        } message: {
            if let a = review {
                Text("Du \(Fmt.date(a["start_date"].string)) au \(Fmt.date(a["end_date"].string)) · \(a["reason_type"].string)\n\(a["comment"].string)")
            }
        }
        .alert(toast ?? "", isPresented: Binding(get: { toast != nil }, set: { if !$0 { toast = nil } })) { Button("OK") {} }
    }

    private func decide(_ status: String) {
        guard let a = review else { return }
        Task {
            do {
                try await Api.put("absences.php?action=review&id=\(a.id)", ["status": status, "comment": reviewComment])
                toast = "Absence \(status.lowercased())."
                key += 1
            } catch { toast = error.localizedDescription }
        }
    }
}

private struct AbsenceForm: View {
    let done: (String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var start = Date()
    @State private var end = Date()
    @State private var reason = reasons[0]
    @State private var comment = ""
    @State private var busy = false
    @State private var error: String?

    var body: some View {
        NavigationStack {
            Form {
                DatePicker("Du", selection: $start, in: Calendar.current.startOfDay(for: Date())..., displayedComponents: .date)
                    .onChange(of: start) { v in if end < v { end = v } }
                DatePicker("Au", selection: $end, in: start..., displayedComponents: .date)
                Picker("Motif", selection: $reason) { ForEach(reasons, id: \.self) { Text($0) } }
                Section("Commentaire (facultatif)") {
                    TextEditor(text: $comment).frame(minHeight: 90)
                }
                if let e = error { Text(e).foregroundColor(St.red) }
            }
            .environment(\.locale, Locale(identifier: "fr_FR"))
            .navigationTitle("Déclarer une absence")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Annuler") { dismiss() } }
                ToolbarItem(placement: .confirmationAction) {
                    Button(busy ? "Envoi…" : "Envoyer") { Task { await send() } }.disabled(busy).bold()
                }
            }
        }
    }

    private func send() async {
        busy = true; error = nil
        defer { busy = false }
        do {
            let r = try await Api.post("absences.php", [
                "start_date": Fmt.iso(start), "end_date": Fmt.iso(end), "reason_type": reason, "comment": String(comment.prefix(1000)),
            ])
            done(r["message"].string(or: "Demande envoyée aux RH."))
        } catch { self.error = error.localizedDescription }
    }
}
