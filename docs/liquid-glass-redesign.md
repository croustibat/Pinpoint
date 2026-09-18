# Pinpoint — Redesign Liquid Glass

> Objectif : donner à Pinpoint le look translucide « Liquid Glass » (inspiré de
> [Thaw](https://github.com/stonerl/Thaw)) en utilisant les **API natives d'Apple**
> quand elles sont disponibles (macOS 26+), avec un **fallback propre** pour rester
> compatible macOS 15+. Périmètre v1 : **Shelf (galerie)** et **Éditeur**.

## 1. Décision d'architecture

Le look « Liquid Glass » de Thaw n'est pas un style CSS/dessin maison : c'est le
**design system natif d'Apple** introduit avec macOS 26 (Tahoe) / iOS 26. Les vraies
API (`glassEffect`, `GlassEffectContainer`, `buttonStyle(.glass)`) ne compilent que
contre le SDK macOS 26 et ne rendent le vrai matériau verre que sur macOS 26+.

Pinpoint cible aujourd'hui `MACOSX_DEPLOYMENT_TARGET = 15.0`. On garde cette cible.
Stratégie retenue : **API natives + fallback `#available`**.

| Contexte d'exécution | Rendu |
|---|---|
| macOS 26+ | Vrai Liquid Glass (`.glassEffect`, `.buttonStyle(.glass)`, morphing) |
| macOS 15–25 | Fallback translucide équivalent (`.ultraThinMaterial`, bordure, ombre douce) |

Prérequis de build : **compiler avec Xcode 26 / SDK macOS 26** (le code `if #available`
a besoin du SDK 26 pour connaître les symboles). Ça ne change pas la cible de
déploiement — l'app tourne toujours sur macOS 15.

## 2. Couche d'abstraction (le cœur du plan)

On ne saupoudre pas `#available` partout. On centralise dans **un seul fichier**,
`Pinpoint/GlassStyle.swift`, une poignée de modificateurs réutilisables. Toutes les
vues appellent ces helpers ; le jour où on remonte la cible à macOS 26, on supprime
juste les branches de fallback.

### 2.1 Surface en verre (panneaux, barres, cartes)

```swift
import SwiftUI

extension View {
    /// Applique le matériau Liquid Glass natif sur macOS 26+,
    /// sinon un matériau translucide équivalent.
    @ViewBuilder
    func pinpointGlass(
        in shape: some Shape = RoundedRectangle(cornerRadius: 12, style: .continuous),
        interactive: Bool = false
    ) -> some View {
        if #available(macOS 26, *) {
            self.glassEffect(
                interactive ? .regular.interactive() : .regular,
                in: shape
            )
        } else {
            self
                .background(.ultraThinMaterial, in: shape)
                .overlay(shape.stroke(.white.opacity(0.12), lineWidth: 0.5))
                .shadow(color: .black.opacity(0.18), radius: 8, y: 3)
        }
    }
}
```

### 2.2 Boutons en verre

```swift
extension View {
    /// `buttonStyle(.glass)` natif sur macOS 26+, `.bordered` sinon.
    @ViewBuilder
    func pinpointGlassButton(prominent: Bool = false) -> some View {
        if #available(macOS 26, *) {
            if prominent {
                self.buttonStyle(.glassProminent)
            } else {
                self.buttonStyle(.glass)
            }
        } else {
            if prominent {
                self.buttonStyle(.borderedProminent)
            } else {
                self.buttonStyle(.bordered)
            }
        }
    }
}
```

### 2.3 Conteneur de morphing (regroupe plusieurs éléments verre)

`GlassEffectContainer` permet à plusieurs surfaces verre proches de fusionner. Un
verre ne peut pas échantillonner un autre verre : dès qu'on met **plusieurs** boutons
ou pastilles en verre côte à côte (barre d'outils, actions d'une carte), il faut les
envelopper.

```swift
@ViewBuilder
func pinpointGlassContainer<Content: View>(
    spacing: CGFloat = 8,
    @ViewBuilder content: () -> Content
) -> some View {
    if #available(macOS 26, *) {
        GlassEffectContainer(spacing: spacing) { content() }
    } else {
        content()
    }
}
```

## 3. Tokens de design

À ajouter dans `Theme.swift` (aujourd'hui il ne contient que le vermillon).

| Token | Valeur | Usage |
|---|---|---|
| `glassCornerPanel` | 16 pt (continuous) | Panneaux, barres d'outils |
| `glassCornerCard` | 14 pt (continuous) | Cartes du shelf |
| `glassCornerControl` | 10 pt / Capsule | Boutons, pastilles |
| `glassStrokeOpacity` | 0.12 (light) / 0.18 (dark) | Liseré du fallback |
| accent | `.pinpointVermillon` (existant) | Teinte des boutons proéminents |

Le vermillon reste **la seule couleur de marque**. Le verre est neutre ; l'accent ne
sert qu'aux actions primaires (Copier pour l'agent, Done) et aux markers — pour rester
lisible sur n'importe quelle capture (principe §02 du design system existant).

## 4. Fenêtres (AppKit)

Pour que le verre « prenne » (translucidité réelle du fond), il faut que la fenêtre
laisse passer le fond.

**Éditeur** (`EditorWindowController.swift`)
- Passer `window.titlebarAppearsTransparent = true` (aujourd'hui `false`).
- `window.styleMask.insert(.fullSizeContentView)` pour que le contenu glisse sous la
  barre de titre → la toolbar en verre flotte en haut.
- Optionnel : `window.isMovableByWindowBackground = true`.

**Shelf** (`ShelfWindowController.swift`)
- Même traitement titlebar transparent + `fullSizeContentView`.
- Le `.background(.background)` de `ShelfView` devient une base neutre au-dessus de
  laquelle les cartes verre ressortent (voir §6).

Sur macOS 26 la « toolbar » système adopte Liquid Glass automatiquement ; pour nos
barres custom (HStack maison), on applique `pinpointGlass`.

## 5. Refonte — Éditeur

Fichier : `EditorView.swift`.

**Toolbar** (`toolbar`, l.95) — aujourd'hui `HStack` + `Divider`, fond nul.
- Envelopper les contrôles dans `pinpointGlassContainer { … }`.
- Poser `.pinpointGlass(in: Capsule())` sur le bloc `HStack` (barre flottante) au lieu
  du `Divider` sous elle ; supprimer le `Divider`.
- `Crop` : `.pinpointGlassButton()`. `Done` : `.pinpointGlassButton(prominent: true)`
  + `.tint(.pinpointVermillon)` (la teinte marche avec `.glassProminent`).
- Le `Picker(.segmented)` reste natif : il adopte le verre tout seul sur macOS 26.

**Side panel** (`sidePanel`, l.274)
- Poser `.pinpointGlass(in: RoundedRectangle(cornerRadius: 16))` sur le `VStack`
  racine ; retirer/alléger le `Divider` interne (le verre sépare visuellement).
- `Copy for the agent` : `.pinpointGlassButton(prominent: true)` + tint vermillon.
- `Save image…` : `.pinpointGlassButton()`.
- `TextEditor` (Instructions) : garder l'overlay stroke mais `.scrollContentBackground(.hidden)`
  + fond `.ultraThinMaterial` léger pour cohérence.

**Lignes de markers** (`pinRow` l.362, `shapeRow` l.376)
- Le fond de sélection actuel `Color.pinpointVermillon.opacity(0.12)` reste (bon
  contraste). État non-sélectionné : passer de `Color.clear` à un `pinpointGlass`
  très discret pour donner l'aspect « pastille » — à valider visuellement, option.
- La pastille numérotée (cercle vermillon) : inchangée, c'est l'accent de marque.

**Markers sur l'image** (`PinMarker`, l.857) — hors périmètre re-style lourd : garder
le vermillon plein (lisibilité sur capture). Éventuellement un fin halo verre autour
du pointeur, à tester (macOS 26 only).

## 6. Refonte — Shelf

**Header** (`ShelfView.header`, l.44)
- Envelopper la barre d'actions (Select / gear / refresh) dans
  `pinpointGlassContainer` et poser `.pinpointGlass(in: Capsule())` → barre d'outils
  flottante translucide.
- Titre « Shelf » + dossier : inchangés.
- Barre de filtres (Menu date + Favorites) : même traitement, une seconde capsule
  verre.
- Retirer le `Divider` sous le header (l. ~ dans `body`) : le verre marque la
  séparation.

**Cartes** (`ScreenshotCardView`, fond principal l.53 `clipShape` + le style de carte)
- La carte passe sur `.pinpointGlass(in: RoundedRectangle(cornerRadius: 14), interactive: true)`.
  `interactive: true` = réaction au survol/clic sur macOS 26.
- Boutons flottants sur la vignette (favori l.108, actions) : `.pinpointGlassButton()`
  dans un `pinpointGlassContainer` pour qu'ils fusionnent.
- `dragPreview` (l.217) utilise déjà `.regularMaterial` → remplacer par `pinpointGlass`
  pour cohérence.

**Section headers** (`SectionHeaderView`, 19 l.) — léger : titre de section posé sur une
petite capsule verre `pinpointGlass(in: Capsule())`, ou laissé tel quel (à trancher à
la maquette).

**Detail** (`ScreenshotDetailView`) — hors périmètre v1 strict, mais `clipShape` r22 +
boutons se re-stylent trivialement avec les mêmes helpers en v1.1.

## 7. Accessibilité

- Liquid Glass gère nativement **Reduce Transparency** et **Increase Contrast**. Pour
  le fallback macOS 15, ajouter dans `pinpointGlass` une branche
  `@Environment(\.accessibilityReduceTransparency)` → fond opaque
  (`Color(nsColor: .windowBackgroundColor)`) au lieu du matériau.
- Vérifier le contraste texte sur verre (WCAG AA) en clair et sombre, sur une capture
  claire ET sombre (le pire cas pour un fond translucide).

## 8. Découpage en étapes / PRs

1. **Socle** — `GlassStyle.swift` (helpers) + tokens dans `Theme.swift` + réglages
   fenêtres (titlebar transparent, fullSizeContentView). Aucun changement visuel
   radical encore. *Petit PR, testable.*
2. **Éditeur** — toolbar + side panel + boutons. *PR.*
3. **Shelf** — header + cartes + section headers. *PR.*
4. **Polish** — markers, detail view, états de sélection, reduce transparency,
   passes light/dark. *PR.*

Chaque étape compile et tourne sur macOS 15 (fallback) comme sur 26 (verre réel).

## 9. Risques / points de vigilance

- **Build** : nécessite Xcode 26. Vérifier la CI (`.github/workflows`) — bumper l'image
  macOS du runner vers une qui embarque le SDK 26.
- **Verre sur verre** : ne jamais empiler deux `pinpointGlass` sans conteneur → halos
  laiteux. D'où `pinpointGlassContainer` pour les groupes.
- **Lisibilité sur capture** : le contenu principal de l'éditeur est une image
  arbitraire. Le verre reste sur la **couche fonctionnelle** (barres, panneaux), jamais
  par-dessus la zone image utile — conforme aux guidelines Apple.
- **Perf** : le verre interactif + morphing coûte du GPU ; sur une grille de nombreuses
  cartes, tester le scroll. Si besoin, `interactive:` seulement sur la carte survolée.

## 10. Références

- [glassEffect(_:in:) — Apple Developer](https://developer.apple.com/documentation/swiftui/view/glasseffect(_:in:))
- [Glass — Apple Developer](https://developer.apple.com/documentation/swiftui/glass)
- [Liquid Glass Reference (conorluddy)](https://github.com/conorluddy/LiquidGlassReference)
- [Thaw — l'app d'inspiration](https://github.com/stonerl/Thaw)
