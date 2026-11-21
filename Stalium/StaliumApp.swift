import SwiftUI
import UserNotifications
import FirebaseCore
import FirebaseMessaging

/// Écran demandé par une notification touchée.
@MainActor
final class Router: ObservableObject {
    static let shared = Router()
    @Published var tab: AppTab = .home
    @Published var pending: String?

    /// "/app/mobile#sheets" (donnée de la notification) → onglet / écran de l'appli.
    func open(url: String) {
        if url.contains("#sheets") || url.contains("feuille") { tab = .sheets }
        else if url.contains("planning") { tab = .planning }
        else if url.contains("absences") { tab = .more; pending = "absences" }
        else if url.contains("announcements") { tab = .more; pending = "announcements" }
        else if url.contains("/app/mobile") { tab = .home }
        else { tab = .notifications }
    }
}

final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate, MessagingDelegate {
    /// Firebase actif seulement si GoogleService-Info.plist est présent dans l'appli.
    static var hasFirebase = Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil

    func application(_ application: UIApplication, didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        if Self.hasFirebase {
            FirebaseApp.configure()
            Messaging.messaging().delegate = self
        }
        return true
    }

    static func requestPush() {
        guard hasFirebase else { return }
        UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound]) { granted, _ in
            guard granted else { return }
            DispatchQueue.main.async { UIApplication.shared.registerForRemoteNotifications() }
        }
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        Messaging.messaging().apnsToken = deviceToken
    }

    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let t = fcmToken, !t.isEmpty else { return }
        UserDefaults.standard.set(t, forKey: "fcm_token")
        Task { await Api.registerPushToken(t) }
    }

    // Notification reçue appli ouverte : on l'affiche quand même.
    func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound, .list]
    }

    // Notification touchée : ouvre le bon écran.
    func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let url = response.notification.request.content.userInfo["url"] as? String ?? ""
        await MainActor.run { Router.shared.open(url: url) }
    }
}

@main
struct StaliumApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) var delegate
    @StateObject private var session = Session.shared
    @StateObject private var router = Router.shared

    var body: some Scene {
        WindowGroup {
            Group {
                if session.loggedIn {
                    MainTabs()
                        .task {
                            _ = try? await Api.get("mobile.php?action=me")
                            AppDelegate.requestPush()
                            if let t = UserDefaults.standard.string(forKey: "fcm_token") { await Api.registerPushToken(t) }
                        }
                } else {
                    LoginView()
                }
            }
            .environmentObject(router)
            .preferredColorScheme(.dark)
            .tint(St.blue)
        }
    }
}

enum AppTab: Hashable { case home, planning, sheets, notifications, more }

struct MainTabs: View {
    @EnvironmentObject var router: Router

    var body: some View {
        TabView(selection: $router.tab) {
            NavigationStack { HomeView().navigationTitle("Stalium") }
                .tabItem { Label("Accueil", systemImage: "house.fill") }.tag(AppTab.home)
            NavigationStack { PlanningView().navigationTitle("Planning") }
                .tabItem { Label("Planning", systemImage: "calendar") }.tag(AppTab.planning)
            NavigationStack { SheetsView().navigationTitle("Feuilles de route") }
                .tabItem { Label("Feuilles", systemImage: "doc.text.fill") }.tag(AppTab.sheets)
            NavigationStack { NotificationsView().navigationTitle("Notifications") }
                .tabItem { Label("Notifs", systemImage: "bell.fill") }.tag(AppTab.notifications)
            NavigationStack { MoreView().navigationTitle("Plus") }
                .tabItem { Label("Plus", systemImage: "line.3.horizontal") }.tag(AppTab.more)
        }
    }
}
