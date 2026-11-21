# Stalium — application iOS

Application native SwiftUI (iOS 16+) de Stalium Transport : accueil, planning, feuilles de route
(validation / refus), notifications, annonces, absences. Elle utilise la même API que le site et l'appli Android.

## Construire sur GitHub
Chaque `git push` sur `main` lance **Actions → Build iOS** (Mac dans le cloud, dernier Xcode) qui vérifie que l'appli compile.

## Construire sur un Mac
```bash
brew install xcodegen
xcodegen generate
open Stalium.xcodeproj
```
Dans Xcode : cible *Stalium* → *Signing & Capabilities* → choisir son équipe (Team), brancher l'iPhone, ▶︎.

## Notifications push
1. Firebase → Paramètres du projet → ajouter une appli **iOS** (bundle `fr.stalium.transport`) → télécharger `GoogleService-Info.plist` et le placer dans `Stalium/` (il est ignoré par git).
2. Apple Developer → Keys → créer une clé **APNs** (.p8) → la téléverser dans Firebase → Cloud Messaging → Configuration des applications Apple.
3. Pour GitHub Actions : secret `GOOGLE_SERVICE_INFO_PLIST` = `base64 -i Stalium/GoogleService-Info.plist`.
