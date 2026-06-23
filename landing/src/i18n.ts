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
  nav: { features: string; how: string; agents: string; github: string; download: string };
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
  agents: { eyebrow: string; title: string; body: string; sample: string };
  download: { title: string; body: string; cta: string; req: string; source: string };
  footer: { tagline: string; rights: string; os: string };
};

export const content: Record<Lang, Content> = {
  en: {
    meta: {
      title: 'Pinpoint — point at exactly what you mean',
      description:
        'A macOS menu-bar app that captures your screen, drops numbered markers on what matters, and copies a ready-to-paste prompt for your AI agent. Free & open source.',
    },
    nav: { features: 'Features', how: 'How it works', agents: 'For agents', github: 'GitHub', download: 'Download' },
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
        { n: '3', t: 'Copy for your agent', d: '⌘C copies the annotated image and a structured text that references every marker.' },
      ],
    },
    features: {
      title: 'Built to be precise',
      subtitle: 'Everything you need to point an agent at the right pixel.',
      items: [
        { t: 'Numbered markers', d: 'Ringed, numbered pins that stay legible on any background — in three styles.' },
        { t: 'Arrows & rectangles', d: 'Add visual emphasis right on top of your capture.' },
        { t: 'Legend baked in', d: 'Optionally embed the marker descriptions and instructions into the image, so a single paste carries everything.' },
        { t: 'The shelf', d: 'Browse, favorite and reopen your screenshots from a built-in library.' },
        { t: 'Global shortcuts', d: 'Capture or open the shelf from anywhere — fully rebindable.' },
        { t: 'Native & private', d: 'SwiftUI + ScreenCaptureKit, living in your menu bar. Your captures never leave your Mac.' },
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
      title: 'A prompt your agent can actually read',
      body: 'Most chat UIs paste only the image and drop the clipboard text. Pinpoint can bake the legend into the picture — and always copies a structured prompt that an agent like Claude Code or Codex can parse: image size, each marker’s description and position, then your instructions.',
      sample: `# Annotated capture — 1280×800 px

An image is attached. Numbered (ringed) badges point to specific elements.
Markers (position in % of the image, top-left origin):

1. Primary CTA button · ~62 % × 48 %
2. Misaligned icon · ~12 % × 22 %

## Instructions
Make the CTA full-width on mobile and fix the icon alignment.`,
    },
    download: {
      title: 'Get Pinpoint',
      body: 'Free and open source. Notarized and signed with a Developer ID.',
      cta: 'Download for macOS',
      req: 'macOS 15 or later · Apple Silicon & Intel',
      source: 'Browse the source on GitHub',
    },
    footer: { tagline: 'Capture. Mark. Prompt.', rights: '© 2026 Baptiste Bouillot', os: 'Open source' },
  },

  fr: {
    meta: {
      title: 'Pinpoint — désigne exactement ce que tu veux dire',
      description:
        'Une app de barre de menus macOS qui capture ton écran, pose des repères numérotés sur ce qui compte, et copie un prompt prêt à coller pour ton agent IA. Gratuite & open source.',
    },
    nav: { features: 'Fonctions', how: 'Comment ça marche', agents: 'Pour les agents', github: 'GitHub', download: 'Télécharger' },
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
        { n: '3', t: 'Copie pour ton agent', d: '⌘C copie l’image annotée et un texte structuré qui référence chaque repère.' },
      ],
    },
    features: {
      title: 'Conçu pour la précision',
      subtitle: 'Tout ce qu’il faut pour pointer un agent sur le bon pixel.',
      items: [
        { t: 'Repères numérotés', d: 'Des pastilles numérotées et cerclées, lisibles sur n’importe quel fond — en trois styles.' },
        { t: 'Flèches & rectangles', d: 'Ajoute de l’emphase visuelle directement sur ta capture.' },
        { t: 'Légende incrustée', d: 'Incruste si tu veux les descriptions et les instructions dans l’image, pour qu’un seul collage transmette tout.' },
        { t: 'L’étagère', d: 'Parcours, mets en favori et rouvre tes captures depuis une bibliothèque intégrée.' },
        { t: 'Raccourcis globaux', d: 'Capture ou ouvre l’étagère depuis n’importe où — entièrement reconfigurables.' },
        { t: 'Natif & privé', d: 'SwiftUI + ScreenCaptureKit, dans ta barre de menus. Tes captures ne quittent jamais ton Mac.' },
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
      title: 'Un prompt que ton agent sait vraiment lire',
      body: 'La plupart des interfaces de chat ne collent que l’image et perdent le texte. Pinpoint peut incruster la légende dans l’image — et copie toujours un prompt structuré qu’un agent comme Claude Code ou Codex sait analyser : taille de l’image, description et position de chaque repère, puis tes instructions.',
      sample: `# Capture annotée — 1280×800 px

Une image est jointe. Des pastilles numérotées (cerclées) pointent des éléments précis.
Repères (position en % de l’image, origine haut-gauche) :

1. Bouton d’action principal · ~62 % × 48 %
2. Icône mal alignée · ~12 % × 22 %

## Instructions
Passe le bouton en pleine largeur sur mobile et corrige l’alignement de l’icône.`,
    },
    download: {
      title: 'Obtiens Pinpoint',
      body: 'Gratuit et open source. Notarisé et signé avec un Developer ID.',
      cta: 'Télécharger pour macOS',
      req: 'macOS 15 ou ultérieur · Apple Silicon & Intel',
      source: 'Voir le code source sur GitHub',
    },
    footer: { tagline: 'Capture. Marque. Prompt.', rights: '© 2026 Baptiste Bouillot', os: 'Open source' },
  },
};
