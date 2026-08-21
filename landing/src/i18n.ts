export type Lang = 'en' | 'fr';

export const GITHUB_URL = 'https://github.com/croustibat/Pinpoint';
export const DOWNLOAD_URL = 'https://github.com/croustibat/Pinpoint/releases/latest';

export const languageNames: Record<Lang, string> = {
  en: 'EN',
  fr: 'FR',
};

/** Path to the other language's page, for the toggle. */
export const otherLang: Record<Lang, { code: Lang; href: string }> = {
  en: { code: 'fr', href: '/fr/' },
  fr: { code: 'en', href: '/' },
};

type Content = {
  meta: { title: string; description: string };
  nav: { features: string; how: string; agents: string; changelog: string; github: string; download: string };
  hero: {
    eyebrow: string;
    titleA: string;
    titleB: string;
    subtitle: string;
    download: string;
    github: string;
    req: string;
  };
  mockup: { caption: string };
  steps: { title: string; subtitle: string; items: { n: string; t: string; d: string }[] };
  features: { title: string; subtitle: string; items: { t: string; d: string }[] };
  tour: { title: string; subtitle: string; shelf: string; settings: string };
  agents: { eyebrow: string; title: string; body: string; sample: string; access: string };
  download: { title: string; body: string; cta: string; req: string; source: string; brew: string };
  footer: { tagline: string; rights: string; os: string };
};

export const content: Record<Lang, Content> = {
  en: {
    meta: {
      title: 'Pinpoint — point at exactly what you mean',
      description:
        'A macOS menu-bar app that captures your screen, drops numbered markers on what matters, and copies a ready-to-paste prompt for your AI agent. Free & open source.',
    },
    nav: { features: 'Features', how: 'How it works', agents: 'For agents', changelog: 'Changelog', github: 'GitHub', download: 'Download' },
    hero: {
      eyebrow: 'macOS menu-bar app — free & open source',
      titleA: 'Point at exactly',
      titleB: 'what you mean.',
      subtitle:
        'Capture your screen, drop numbered markers on what matters, and copy a ready-to-paste prompt for your AI agent — an annotated image plus instructions that reference every marker.',
      download: 'Download for macOS',
      github: 'View on GitHub',
      req: 'macOS 15+ · Apple Silicon & Intel',
    },
    mockup: {
      caption: 'Editor — drop markers, write a note, copy for your agent',
    },
    steps: {
      title: 'From screen to prompt in three steps',
      subtitle: 'No round-trips, no describing pixels in words.',
      items: [
        { n: '1', t: 'Capture a region', d: 'Press ⌘⇧1 and drag a rectangle. Native resolution, multi-display and Retina aware.' },
        { n: '2', t: 'Drop numbered markers', d: 'Click to place pins and add a note to each. Add arrows and rectangles for emphasis.' },
        { n: '3', t: 'Copy for your agent', d: '⌘C copies the annotated image and a structured text that references every marker — and drops the same three files at a stable path your agent can read on its own.' },
      ],
    },
    features: {
      title: 'Built to be precise',
      subtitle: 'Everything you need to point an agent at the right pixel.',
      items: [
        { t: 'Accessibility context', d: 'Each marker also carries what macOS knows about the element under it — role, label, owning app and its frame.' },
        { t: 'On-device text reading', d: 'Vision reads the text under each marker — errors, class names, log lines — and it travels with the capture.' },
        { t: 'Redaction', d: 'Drag over a token or a secret before it ships. Hidden in the image, the text and the accessibility context alike.' },
        { t: 'Undo, redo, still editable', d: '⌘Z through any change. Markers, arrows and rectangles stay selectable, movable and resizable after you drop them.' },
        { t: 'Window capture', d: 'Hold Space while dragging to snap the selection to a window instead of drawing it freehand.' },
        { t: 'Markers, arrows & rectangles', d: 'Ringed, numbered pins in three styles, plus arrows and rectangles for emphasis, drawn straight on the capture.' },
        { t: 'Legend baked in', d: 'Optionally embed the marker descriptions and instructions into the image, so a single paste carries everything.' },
        { t: 'The shelf', d: 'Browse, search, favorite and reopen your screenshots from a built-in library.' },
        { t: 'Native & private', d: 'SwiftUI + ScreenCaptureKit, living in your menu bar. Captures, OCR reads and accessibility context stay on your Mac.' },
      ],
    },
    tour: {
      title: 'A closer look',
      subtitle: 'A native menu-bar companion — capture, organize, and tune it to the way you work.',
      shelf: 'The shelf — every screenshot in one browsable library you can favorite, sort and reopen.',
      settings: 'Settings — rebind the global shortcuts, pick one of three marker styles, and bake the legend into the image.',
    },
    agents: {
      eyebrow: 'Made for AI agents',
      title: 'The file your agent reads directly',
      body: 'Every copy also writes capture.png, capture.md and capture.json to a stable path — because Claude Code and most MCP clients don’t render inline images (the upstream bug was closed “not planned”), so a file an agent opens itself is the channel that actually works. capture.md lists each marker’s position in pixels and percent, the accessibility element found under it — role, label, owning app — and whatever text was read there on device. None of it depends on a page’s DOM, so it reads the same in any app.',
      sample: `# Annotated capture — 1720×1046 px

An image is attached. Numbered (ringed) badges point to specific elements.
Positions are given in pixels from the top-left corner (0, 0), then as a percentage of the image size.

## Markers
M1, M2… are the numbers drawn on the image; the code in brackets is a stable ID for that marker.
“UI” lines name the interface element found under the marker in the macOS accessibility tree at capture time — its role, its label, the app owning it, and its box in this image. “Path” is the chain of containers around it.
“Text” lines are what Pinpoint read in the pixels under the marker, on this Mac. A marker’s description may have been pre-filled from such a read and then edited by the user.

- M1 [5a5421] · overflows its card at this width — (1264, 127) px · (74 %, 12 %)
  - UI: AXButton “Export CSV” · id=export-csv · com.apple.Safari · box (1178, 99) 162×52 px
  - Path: AXWindow “Orders — Admin” › AXButton “Export CSV”
- M2 [010661] · error stays after a valid range is picked — (249, 254) px · (14 %, 24 %)
  - UI: AXWindow “Orders — Admin” · com.apple.Safari · box (0, 0) 1720×1046 px
  - Path: AXWindow “Orders — Admin”
  - Text: “Invalid date range: end must be after start”

## Task — Bug
The markers point at a defect. Find its cause before proposing anything: locate the code that produces what is marked, explain why it behaves this way, then propose the smallest change that addresses the cause rather than the symptom. If the capture isn’t enough to be sure, say what you would need to look at.

## Instructions
The Export CSV button overflows its card at this width, and the date-range error stays on screen after picking a valid range.`,
      access: 'Reachable without the editor too: `pinpoint capture` from a script or a hook, or `pinpoint mcp` as a stdio MCP server exposing capture_region, get_last_capture and list_recent.',
    },
    download: {
      title: 'Get Pinpoint',
      body: 'Free and open source. Notarized and signed with a Developer ID.',
      cta: 'Download for macOS',
      req: 'macOS 15 or later · Apple Silicon & Intel',
      source: 'Browse the source on GitHub',
      brew: 'Or install with Homebrew',
    },
    footer: { tagline: 'Capture. Mark. Prompt.', rights: '© 2026 Baptiste Bouillot', os: 'Open source' },
  },

  fr: {
    meta: {
      title: 'Pinpoint — désigne exactement ce que tu veux dire',
      description:
        'Une app de barre de menus macOS qui capture ton écran, pose des repères numérotés sur ce qui compte, et copie un prompt prêt à coller pour ton agent IA. Gratuite & open source.',
    },
    nav: { features: 'Fonctions', how: 'Comment ça marche', agents: 'Pour les agents', changelog: 'Changelog', github: 'GitHub', download: 'Télécharger' },
    hero: {
      eyebrow: 'App de barre de menus macOS — gratuite & open source',
      titleA: 'Désigne exactement',
      titleB: 'ce que tu veux dire.',
      subtitle:
        'Capture ton écran, pose des repères numérotés sur ce qui compte, et copie un prompt prêt à coller pour ton agent IA — une image annotée et des instructions qui référencent chaque repère.',
      download: 'Télécharger pour macOS',
      github: 'Voir sur GitHub',
      req: 'macOS 15+ · Apple Silicon & Intel',
    },
    mockup: {
      caption: 'Éditeur — pose des repères, écris une note, copie pour ton agent',
    },
    steps: {
      title: 'De l’écran au prompt en trois étapes',
      subtitle: 'Pas d’allers-retours, pas besoin de décrire des pixels avec des mots.',
      items: [
        { n: '1', t: 'Capture une région', d: 'Appuie sur ⌘⇧1 et trace un rectangle. Résolution native, multi-écran et Retina.' },
        { n: '2', t: 'Pose des repères numérotés', d: 'Clique pour placer des repères et ajoute une note à chacun. Flèches et rectangles pour appuyer.' },
        { n: '3', t: 'Copie pour ton agent', d: '⌘C copie l’image annotée et un texte structuré qui référence chaque repère — et dépose les mêmes fichiers à un chemin stable que ton agent peut lire seul.' },
      ],
    },
    features: {
      title: 'Conçu pour la précision',
      subtitle: 'Tout ce qu’il faut pour pointer un agent sur le bon pixel.',
      items: [
        { t: 'Contexte d’accessibilité', d: 'Chaque repère porte aussi ce que macOS sait de l’élément dessous — rôle, libellé, app propriétaire et son cadre.' },
        { t: 'Lecture de texte sur l’appareil', d: 'Vision lit le texte sous chaque repère — erreurs, noms de classes, lignes de log — et il voyage avec la capture.' },
        { t: 'Rédaction', d: 'Glisse sur un jeton ou un secret avant qu’il ne parte. Masqué dans l’image, le texte et le contexte d’accessibilité à la fois.' },
        { t: 'Annuler, rétablir, toujours modifiable', d: '⌘Z pour revenir sur tout changement. Repères, flèches et rectangles restent sélectionnables, déplaçables et redimensionnables après coup.' },
        { t: 'Capture de fenêtre', d: 'Maintiens Espace en traçant pour aimanter la sélection à une fenêtre plutôt que de la dessiner à main levée.' },
        { t: 'Repères, flèches & rectangles', d: 'Des pastilles numérotées et cerclées en trois styles, plus des flèches et des rectangles pour appuyer, dessinés sur la capture.' },
        { t: 'Légende incrustée', d: 'Incruste si tu veux les descriptions et les instructions dans l’image, pour qu’un seul collage transmette tout.' },
        { t: 'L’étagère', d: 'Parcours, recherche, mets en favori et rouvre tes captures depuis une bibliothèque intégrée.' },
        { t: 'Natif & privé', d: 'SwiftUI + ScreenCaptureKit, dans ta barre de menus. Captures, lectures OCR et contexte d’accessibilité restent sur ton Mac.' },
      ],
    },
    tour: {
      title: 'Le tour du propriétaire',
      subtitle: 'Un compagnon natif dans la barre de menus — capture, range et règle-le à ta main.',
      shelf: 'L’étagère — toutes tes captures dans une bibliothèque à parcourir, mettre en favori, trier et rouvrir.',
      settings: 'Réglages — reconfigure les raccourcis globaux, choisis l’un des trois styles de repère et incruste la légende dans l’image.',
    },
    agents: {
      eyebrow: 'Pensé pour les agents IA',
      title: 'Le fichier que ton agent lit directement',
      body: 'Chaque copie écrit aussi capture.png, capture.md et capture.json à un chemin stable — parce que Claude Code et la plupart des clients MCP ne rendent pas les images renvoyées en ligne (le bug amont a été fermé « not planned »), donc un fichier que l’agent ouvre lui-même est le seul canal qui marche vraiment. capture.md liste la position de chaque repère en pixels et en pourcentage, l’élément d’accessibilité trouvé dessous — rôle, libellé, app propriétaire — et le texte éventuellement lu à cet endroit, sur l’appareil. Rien de tout ça ne dépend du DOM d’une page : ça marche pareil dans n’importe quelle app.',
      sample: `# Capture annotée — 1720×1046 px

Une image est jointe. Des pastilles numérotées (cerclées) pointent des éléments précis.
Les positions sont données en pixels depuis le coin haut-gauche (0, 0), puis en pourcentage de la taille de l’image.

## Repères
M1, M2… correspondent aux numéros dessinés sur l’image ; le code entre crochets est un identifiant stable de ce repère.
Les lignes « UI » nomment l’élément d’interface trouvé sous le repère dans l’arbre d’accessibilité macOS au moment de la capture — son rôle, son libellé, l’app qui le possède et sa boîte dans cette image. « Path » est la chaîne de conteneurs qui l’entoure.
Les lignes « Text » sont ce que Pinpoint a lu dans les pixels sous le repère, sur ce Mac. La description d’un repère a pu être pré-remplie à partir d’une telle lecture, puis modifiée par l’utilisateur.

- M1 [4ecd13] · déborde de sa carte à cette largeur — (1264, 127) px · (74 %, 12 %)
  - UI: AXButton “Export CSV” · id=export-csv · com.apple.Safari · box (1178, 99) 162×52 px
  - Path: AXWindow “Orders — Admin” › AXButton “Export CSV”
- M2 [6f42cb] · l’erreur reste affichée après une plage valide — (249, 254) px · (14 %, 24 %)
  - UI: AXWindow “Orders — Admin” · com.apple.Safari · box (0, 0) 1720×1046 px
  - Path: AXWindow “Orders — Admin”
  - Text: “Invalid date range: end must be after start”

## Tâche — Bug
Les repères désignent un défaut. Cherchez-en la cause avant de proposer quoi que ce soit : localisez le code qui produit ce qui est marqué, expliquez pourquoi il se comporte ainsi, puis proposez la plus petite modification qui traite la cause plutôt que le symptôme. Si la capture ne suffit pas à en être sûr, dites ce qu’il faudrait aller regarder.

## Instructions
Le bouton Exporter en CSV déborde de sa carte à cette largeur, et l’erreur de plage de dates reste affichée après avoir choisi une plage valide.`,
      access: 'Accessible aussi sans passer par l’éditeur : `pinpoint capture` depuis un script ou un hook, ou `pinpoint mcp` comme serveur MCP en stdio, qui expose capture_region, get_last_capture et list_recent.',
    },
    download: {
      title: 'Obtiens Pinpoint',
      body: 'Gratuit et open source. Notarisé et signé avec un Developer ID.',
      cta: 'Télécharger pour macOS',
      req: 'macOS 15 ou ultérieur · Apple Silicon & Intel',
      source: 'Voir le code source sur GitHub',
      brew: 'Ou installe avec Homebrew',
    },
    footer: { tagline: 'Capture. Marque. Prompt.', rights: '© 2026 Baptiste Bouillot', os: 'Open source' },
  },
};
