# Prompts pour avancer sur Pinpoint

## 1. Prompt pour Claude Code (continuer le dev)

> Copie-colle ceci dans Claude Code, à la racine du dépôt `Pinpoint/`.

```
Tu travailles sur Pinpoint, une app macOS native (Swift / SwiftUI + ScreenCaptureKit)
qui vit dans la barre de menus. Le but : capturer l'écran, poser des repères numérotés
sur les éléments importants, et copier dans le presse-papier une image annotée + un
texte d'instructions référençant chaque repère, prêt à coller dans un agent IA.

Le projet est déjà scaffoldé avec XcodeGen (voir project.yml et README.md). Lis
d'abord README.md et tous les fichiers de Pinpoint/Pinpoint/ pour comprendre
l'architecture existante avant de coder.

Cible : macOS 15+. Dépendance : KeyboardShortcuts (Sindre Sorhus).

Première priorité — remplacer la capture plein écran par une SÉLECTION DE RÉGION
façon capture système :
1. À l'appui sur ⌘⇧1, afficher un overlay plein écran (un NSWindow .screenSaver level,
   transparent, sur tous les écrans) qui assombrit l'écran.
2. L'utilisateur trace un rectangle à la souris ; afficher le rectangle clair + les
   dimensions en live ; Échap annule.
3. Capturer uniquement cette région via ScreenCaptureKit (SCContentFilter sur le bon
   display + sourceRect dans SCStreamConfiguration, ou recadrage du CGImage), à la
   résolution native, puis ouvrir l'éditeur existant avec cette image.

Contraintes :
- Garde le code organisé comme l'existant (un fichier par responsabilité).
- Gère le multi-écran et le Retina (backingScaleFactor) correctement.
- Ne casse pas le flow actuel : la capture plein écran peut rester en fallback
  (ex. clic droit sur l'icône de la barre de menus).

Après ça, propose-moi un plan court pour les itérations suivantes :
flèches/rectangles d'annotation en plus des pins, réglage du style des repères,
historique des captures, et amélioration du format de texte généré pour les agents.

Build avec `xcodegen generate && xcodebuild -scheme Pinpoint build` pour vérifier
que ça compile avant de me rendre la main. Travaille par petits commits.
```

## 2. Prompt pour Claude Design (identité visuelle & UI)

> À utiliser dans Claude Design / l'outil de design pour produire l'icône, l'identité
> et les maquettes d'écran.

```
Crée l'identité visuelle et les maquettes d'une app macOS native nommée « Pinpoint ».

Concept : un utilitaire de barre de menus qui sert à capturer l'écran et à POSER DES
REPÈRES NUMÉROTÉS sur les éléments précis qu'on veut désigner, pour ensuite copier le
tout (image annotée + instructions) dans un agent IA. Mot-clé : précision, « pointer
exactement ce que je veux dire ».

Public : développeurs et power users macOS qui utilisent des agents type Claude Code /
Codex. Ton : pro, sobre, moderne, esprit outil indépendant macOS de qualité (pense
aux apps de la trempe de Raycast, CleanShot X, Things).

Livrables souhaités :
1. APP ICON macOS (grille et coins arrondis style Big Sur/Sonoma). Idée directrice :
   une punaise / un réticule de visée / un repère numéroté « 1 ». Décline en plusieurs
   pistes. Fournis les rendus à 1024px et la déclinaison sur fond clair et sombre.
2. PALETTE & TYPO : une couleur d'accent forte (c'est la couleur des repères, doit
   ressortir sur n'importe quelle capture — éviter le bleu système banal), neutres,
   et police système (SF Pro). Donne les valeurs hex et l'usage.
3. STYLE DES REPÈRES : le pastille numérotée posée sur la capture — forme, contour,
   ombre, contraste sur fond clair ET sombre, états (par défaut / sélectionné).
   Propose 2-3 variantes.
4. MAQUETTES D'ÉCRAN :
   - l'icône dans la barre de menus + son menu déroulant ;
   - l'overlay de sélection de région (écran assombri, rectangle clair, dimensions) ;
   - la fenêtre d'éditeur : capture à gauche avec repères numérotés, panneau latéral
     droit listant les repères (note par repère) + champ « instructions pour l'agent »
     + bouton « Copier pour l'agent ».

Contraintes : respecter les conventions macOS (HIG), mode clair et sombre, layout
adaptable au redimensionnement de fenêtre. Pas de copie d'apps existantes — identité
originale.
```
