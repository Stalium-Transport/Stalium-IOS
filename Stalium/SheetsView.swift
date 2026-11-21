import SwiftUI

private let sheetApi = "open-omsi-sheet.php"

struct SheetsView: View {
    @State private var isValidator: Bool?
    @State private var canValidate = false
    @State private var canReject = false
    @State private var tab = 0
    @State private var reloadKey = 0
    @State private var detail: Int?
    @State private var acceptId: Int?
    @State private var rejectId: Int?
    @State private var reason = ""
    @State private var toast: String?

    var body: some View {
        VStack(spacing: 0) {
            if let v = isValidator {
                if v {
                    Picker("", selection: $tab) {
                        Text("À valider").tag(0)
                        Text("Mes feuilles").tag(1)
                    }
                    .pickerStyle(.segmented).padding(.horizontal, 16).padding(.vertical, 8)
                }
                let pending = v && tab == 0
                Loader(fetch: { try await Api.get(pending ? "\(sheetApi)?action=pending" : "\(sheetApi)?action=mine") }) { d, reload in
                    let list = d["sheets"].array
                    ScrollView {
                        LazyVStack(spacing: 12) {
                            if list.isEmpty {
                                if pending { EmptyState(emoji: "🎉", text: "Aucune feuille en attente de validation.") }
                                else { EmptyState(emoji: "📝", text: "Vous n'avez pas encore de feuille de route.\nElles sont envoyées depuis OMSI ou le site.") }
                            }
                            ForEach(list.indices, id: \.self) { i in
                                let s = list[i]
                                SheetCard(s: s, pending: pending, canValidate: canValidate, canReject: canReject,
                                          onOpen: { detail = s.id }, onAccept: { acceptId = s.id }, onReject: { reason = ""; rejectId = s.id })
                            }
                        }
                        .padding(16)
                    }
                    .refreshable { await reload() }
                }
                .id("\(tab)-\(reloadKey)")
            } else {
                ProgressView().frame(maxWidth: .infinity, maxHeight: .infinity)
            }
        }
        .background(St.bg)
        .task {
            guard isValidator == nil else { return }
            if let r = try? await Api.get("\(sheetApi)?action=pending") {
                canValidate = r["can_validate"].bool; canReject = r["can_reject"].bool
                isValidator = canValidate || canReject
            } else {
                isValidator = false
            }
            tab = isValidator == true ? 0 : 1
        }
        .sheet(item: Binding(get: { detail.map(IdBox.init) }, set: { detail = $0?.id })) { box in
            SheetDetail(id: box.id, canValidate: canValidate, canReject: canReject,
                        onAccept: { afterClosingDetail { acceptId = box.id } },
                        onReject: { afterClosingDetail { reason = ""; rejectId = box.id } })
                .presentationDetents([.large])
        }
        .alert("Accepter la feuille #\(acceptId ?? 0) ?", isPresented: Binding(get: { acceptId != nil }, set: { if !$0 { acceptId = nil } })) {
            Button("Annuler", role: .cancel) {}
            Button("Accepter") { if let id = acceptId { act(id, ["action": "validate"]) } }
        } message: { Text("Le salaire sera versé au conducteur et le message Discord sera mis à jour.") }
        .alert("Refuser la feuille #\(rejectId ?? 0)", isPresented: Binding(get: { rejectId != nil }, set: { if !$0 { rejectId = nil } })) {
            TextField("Motif (envoyé au conducteur)", text: $reason)
            Button("Annuler", role: .cancel) {}
            Button("Refuser", role: .destructive) {
                if let id = rejectId, !reason.trimmingCharacters(in: .whitespaces).isEmpty { act(id, ["action": "reject", "reason": reason]) }
                else { toast = "Indiquez un motif de refus." }
            }
        } message: { Text("Indiquez le motif du refus.") }
        .alert(toast ?? "", isPresented: Binding(get: { toast != nil }, set: { if !$0 { toast = nil } })) { Button("OK") {} }
    }

    /// Ferme le panneau de détail puis lance l'action (une alerte ne peut pas s'afficher par-dessus).
    private func afterClosingDetail(_ then: @escaping () -> Void) {
        detail = nil
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.45, execute: then)
    }

    private func act(_ id: Int, _ body: [String: Any]) {
        Task {
            var b = body; b["id"] = id
            do {
                let r = try await Api.post(sheetApi, b)
                detail = nil
                toast = r["message"].string(or: "C'est fait.")
                reloadKey += 1
            } catch { toast = error.localizedDescription }
        }
    }
}

private struct IdBox: Identifiable { let id: Int }

private struct SheetCard: View {
    let s: J
    let pending: Bool
    let canValidate: Bool
    let canReject: Bool
    let onOpen: () -> Void
    let onAccept: () -> Void
    let onReject: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Button(action: onOpen) {
                VStack(alignment: .leading, spacing: 6) {
                    HStack(spacing: 12) {
                        if pending { Avatar(url: s["driver_avatar"].string, name: s["driver_name"].string(or: "?"), size: 40) }
                        VStack(alignment: .leading) {
                            Text(pending ? s["driver_name"].string(or: "Conducteur") : "Ligne \(s["line_name"].string)").bold().lineLimit(1)
                            Text("#\(s.id) · \(Fmt.date(s["service_date"].string))").font(.footnote).foregroundColor(St.muted)
                        }
                        Spacer()
                        StatusChip(status: s["status"].string)
                    }
                    Text((pending ? "Ligne \(s["line_name"].string) · " : "") + "Service \(s["service_number"].string) · \(Int(s["km_traveled"].double)) km · \(s["passengers"].int) voy.")
                        .font(.subheadline).padding(.top, 4)
                    Text("\(s["bus_name"].string) — \(s["map_name"].string)").font(.footnote).foregroundColor(St.muted).lineLimit(1)
                    Text("Salaire : \(s["earned_formatted"].string)").font(.subheadline.weight(.semibold)).foregroundColor(St.green)
                    if !pending && s["status"].string == "Refusé" && !s["rejection_reason"].string.isEmpty {
                        Text("Motif : \(s["rejection_reason"].string)").font(.footnote).foregroundColor(St.red)
                    }
                }
                .foregroundColor(.primary)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            if pending && (canValidate || canReject) {
                DecisionButtons(canValidate: canValidate, canReject: canReject, onAccept: onAccept, onReject: onReject).padding(.top, 6)
            }
        }
        .padding(16).card()
    }
}

private struct DecisionButtons: View {
    let canValidate: Bool, canReject: Bool
    let onAccept: () -> Void, onReject: () -> Void
    var body: some View {
        HStack(spacing: 10) {
            if canValidate {
                Button(action: onAccept) { Label("Accepter", systemImage: "checkmark").bold().frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.borderedProminent).tint(St.green)
            }
            if canReject {
                Button(action: onReject) { Label("Refuser", systemImage: "xmark").bold().frame(maxWidth: .infinity, minHeight: 44) }
                    .buttonStyle(.bordered).tint(St.red)
            }
        }
    }
}

private struct SheetDetail: View {
    let id: Int
    let canValidate: Bool, canReject: Bool
    let onAccept: () -> Void, onReject: () -> Void
    @State private var sheet: J?
    @State private var error: String?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 0) {
                if let e = error {
                    Text(e).foregroundColor(St.red).frame(maxWidth: .infinity).padding(24)
                } else if let s = sheet {
                    HStack(spacing: 12) {
                        Avatar(url: s["driver_avatar"].string, name: s["driver_name"].string(or: "?"), size: 48)
                        VStack(alignment: .leading) {
                            Text("Feuille #\(s.id)").font(.title3.weight(.heavy))
                            Text(s["driver_name"].string).font(.footnote).foregroundColor(St.muted)
                        }
                        Spacer()
                        StatusChip(status: s["status"].string)
                    }
                    .padding(.bottom, 14)
                    ForEach(rows(s), id: \.0) { k, v in
                        HStack(alignment: .top) {
                            Text(k).font(.subheadline).foregroundColor(St.muted)
                            Spacer()
                            Text(v).font(.subheadline.weight(.semibold)).multilineTextAlignment(.trailing)
                        }
                        .padding(.vertical, 8)
                        Divider().overlay(St.border)
                    }
                    let photo = s["proof_photo"].string
                    if !photo.isEmpty, let u = URL(string: photo.hasPrefix("http") ? photo : Config.siteURL + photo) {
                        AsyncImage(url: u) { $0.resizable().scaledToFit() } placeholder: { ProgressView() }
                            .clipShape(RoundedRectangle(cornerRadius: 12)).padding(.top, 12)
                    }
                    if s["status"].string(or: "En attente") == "En attente" && (canValidate || canReject) {
                        DecisionButtons(canValidate: canValidate, canReject: canReject, onAccept: onAccept, onReject: onReject).padding(.top, 16)
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity).padding(40)
                }
            }
            .padding(20)
        }
        .background(St.surface)
        .task {
            do { sheet = try await Api.get("\(sheetApi)?id=\(id)")["sheet"] } catch { self.error = error.localizedDescription }
        }
    }

    private func rows(_ s: J) -> [(String, String)] {
        [
            ("Date", s["service_date_formatted"].string),
            ("Ligne / service", "\(s["line_name"].string) / \(s["service_number"].string)"),
            ("Bus", s["bus_name"].string),
            ("Carte", s["map_name"].string),
            ("Horaires", "\(s["departure_time"].string) → \(s["arrival_time"].string) (\(s["duration_formatted"].string))"),
            ("Distance", "\(s["km_traveled"].int) km"),
            ("Voyageurs", "\(s["passengers"].int)"),
            ("Ponctualité", s["punctuality"].string),
            ("Conduite", s["driving_score"].string),
            ("Confort", s["comfort_score"].string),
            ("Billetterie", s["ticket_score"].string),
            ("Note", String(repeating: "★", count: max(0, s["rating"].int))),
            ("Salaire", s["earned_money_formatted"].string),
            ("Traité par", s["validated_by"].string),
            ("Motif du refus", s["rejection_reason"].string),
            ("Notes", s["notes"].string),
        ].filter { !$0.1.isEmpty }
    }
}
