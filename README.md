# Pinpoint

Capture ton écran, pose des repères numérotés sur ce qui compte, et copie un
prompt prêt à coller dans ton agent (Claude Code, Codex…) : image annotée +
instructions texte qui référencent chaque repère.

App macOS native, Swift / SwiftUI + ScreenCaptureKit. Vit dans la barre de menus.

## v0.1 (MVP)

- Raccourci global **⌘⇧1** (réglable) → **overlay de sélection de région** : l’écran
  s’assombrit, trace un rectangle (dimensions affichées en live), `Échap` annule.
  Capture de la seule région choisie, à la résolution native (Retina, multi-écran).
- Fallback **« Capturer tout l’écran »** (⌘⇧3) dans le menu de la barre de menus.
- Éditeur : barre d’outils **Repère / Flèche / Rectangle**. Clic pour poser un
  repère numéroté (glisser pour le déplacer, note par repère) ; glisser pour tracer
  une flèche ou un rectangle. Les flèches/rectangles sont visuels ; seuls les repères
  numérotés sont référencés dans le texte agent.
- Champ « instructions pour l’agent » + texte Markdown structuré (dimensions,
  position de chaque repère en %)
- Option **« légende dans l’image »** (réglable) : descriptions des repères +
  instructions incrustées sous la capture, pour qu’un **seul collage** transmette
  tout à l’agent (la plupart des UI ne collent que l’image, pas le texte)
- Accent **vermillon** `#FF4D2E` + **3 styles de repères** réglables (disque plein,
  pin pointeur, contour léger) appliqués à l’écran **et** à l’export
- **⌘C** / bouton → copie l’image annotée (PNG) **et** le texte dans le presse-papier
- **Historique** : sous-menu « Captures récentes » (15 dernières, persistées dans
  Application Support avec leurs annotations) → rouvre une capture telle qu’elle était

Pistes futures : capture de fenêtre, export fichier, partage. Voir `PROMPTS.md`.

## Build

Le projet utilise [XcodeGen](https://github.com/yonaskolb/XcodeGen) pour générer
le `.xcodeproj` (pas versionné).

```bash
brew install xcodegen        # si pas déjà installé
cd Pinpoint
xcodegen generate            # crée Pinpoint.xcodeproj
open Pinpoint.xcodeproj
```

Dans Xcode :

1. Le *Team* de signature est intégré dans `project.yml` (`DEVELOPMENT_TEAM`), donc
   la signature est stable — pas besoin de le re-régler après chaque `xcodegen generate`.
   (Si tu reprends le projet sur une autre machine, remplace ce `DEVELOPMENT_TEAM`
   par le tien : *Réglages Système ▸ Compte développeur*, ou l'OU de ton certificat
   *Apple Development*.)
2. **⌘R** pour lancer.
3. Au premier déclenchement du raccourci, macOS demande l’autorisation
   **Enregistrement de l’écran** : accorde-la dans *Réglages Système ▸ Confidentialité
   et sécurité ▸ Enregistrement de l’écran*, puis **relance l’app**.
4. Appuie sur **⌘⇧1** → l’écran s’assombrit ; trace un rectangle (ou `Échap` pour
   annuler) → l’éditeur s’ouvre avec la région capturée.

> Astuce : grâce au `DEVELOPMENT_TEAM` fixe + au bundle id stable
> (`app.pinpoint.Pinpoint`), macOS mémorise l’autorisation d’un build à l’autre.
> Si une autorisation reste « bloquée » après un changement d’identité, repars à zéro :
> `tccutil reset ScreenCapture app.pinpoint.Pinpoint`, puis relance et ré-accorde.

## Structure

```
Pinpoint/
  project.yml                  # config XcodeGen (deps, bundle id, LSUIElement…)
  Pinpoint/
    PinpointApp.swift          # @main, scène Réglages, raccourci par défaut
    AppDelegate.swift          # status item barre de menus + flow de capture
    RegionSelectionController.swift # overlay multi-écran + résolution des coordonnées
    RegionSelectionView.swift  # dessin de l’assombrissement + rectangle + dimensions
    CaptureRegion.swift        # modèle : display cible + rect (points, top-left) + scale
    CaptureRecord.swift        # modèle persisté d’une capture (image + annotations + date)
    CaptureHistory.swift       # store des captures récentes (Application Support + index JSON)
    ScreenCapture.swift        # ScreenCaptureKit : capture région (sourceRect) ou plein écran
    Pin.swift                  # modèle d’un repère numéroté
    Markup.swift               # modèle d’une annotation flèche / rectangle
    PinStyle.swift             # styles de repères (disque / pointeur / contour) + clé @AppStorage
    Theme.swift                # palette vermillon (NSColor + Color)
    EditorWindowController.swift  # fenêtre AppKit qui héberge l’éditeur SwiftUI
    EditorView.swift           # canvas d’annotation + panneau latéral
    SettingsWindowController.swift # fenêtre AppKit des réglages (contourne le bug SettingsLink macOS 14+)
    Exporter.swift             # rendu PNG annoté + texte + copie presse-papier
```

## Dépendances

- [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) (Sindre Sorhus) — raccourci global réglable.

## Release (DMG notarisé)

L'icône d'app est **générée** depuis le design system :

```bash
swift scripts/generate_icon.swift Pinpoint/Assets.xcassets/AppIcon.appiconset
```

Build signé Developer ID + notarisé + DMG via `scripts/release.sh`. Pré-requis
une seule fois : stocker les credentials de notarisation dans un profil trousseau

```bash
xcrun notarytool store-credentials pinpoint-notary \
  --apple-id "<ton-apple-id>" --team-id MMJD6CLKNQ \
  --password "<mot-de-passe-d-app>"          # appleid.apple.com ▸ Sécurité ▸ mots de passe pour app
```

puis :

```bash
scripts/release.sh        # → build/dist/Pinpoint.dmg (signé, notarisé, staplé)
```
