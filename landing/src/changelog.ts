// Hand-maintained changelog shown on /changelog.
// Add a new entry at the TOP for each release (mark it `latest: true` and drop
// `latest` from the previous one). Keep it in sync with the GitHub release notes.

export type ChangeType = 'added' | 'fixed' | 'changed';

export interface ChangelogEntry {
  version: string;
  /** ISO date (YYYY-MM-DD) of the release. */
  date: string;
  latest?: boolean;
  changes: { type: ChangeType; text: string }[];
  /** Optional credit line (e.g. an external contributor), linked to `href`. */
  credit?: { text: string; href: string };
}

export const changelog: ChangelogEntry[] = [
  {
    version: '0.6.0',
    date: '2026-07-14',
    latest: true,
    changes: [
      { type: 'added', text: 'Crop tool in the editor — trim a capture with eight handles and a rule-of-thirds grid; existing markers and arrows are remapped into the cropped frame.' },
      { type: 'added', text: 'Optional capture timer — a 3, 5, or 10-second countdown before the shot so you can arrange your UI or open a menu; press Esc to cancel.' },
      { type: 'added', text: 'A “What’s New…” item in the menu bar opens this changelog, so you can always see what each release added.' },
    ],
    credit: {
      text: 'Crop tool and capture timer contributed by @ganuong11 — thank you! 🙏',
      href: 'https://github.com/ganuong11',
    },
  },
  {
    version: '0.5.0',
    date: '2026-07-09',
    changes: [
      { type: 'fixed', text: 'Markers placed near an edge are no longer clipped in the exported image — the badge is kept fully inside the picture.' },
      { type: 'added', text: 'Shelf: ⌘A selects all screenshots and Esc exits selection mode.' },
      { type: 'fixed', text: 'The editor’s tool picker no longer shifts around in narrow windows.' },
    ],
  },
  {
    version: '0.4.0',
    date: '2026-07-06',
    changes: [
      { type: 'added', text: 'Automatic updates — a new “Check for updates…” menu item plus background checks, so new releases install in one click.' },
      { type: 'fixed', text: 'Multi-monitor capture: the selection overlay now dims and works on every display, not just the primary one.' },
      { type: 'fixed', text: 'Copied images always paste — the “Copy for the agent” image is capped so it reliably pastes into Claude, GitHub, and other targets.' },
      { type: 'added', text: '“Save image…” (⌘S) exports the full-resolution annotated PNG.' },
      { type: 'added', text: 'The installed version is now shown in Settings.' },
    ],
  },
  {
    version: '0.3.0',
    date: '2026-07-02',
    changes: [
      { type: 'added', text: 'Edit in Pinpoint from the Shelf — reopen any screenshot, including a native ⌘⇧4 capture, as an annotation session.' },
      { type: 'added', text: 'Custom Shelf titles — rename a capture in the Shelf without touching the file on disk.' },
      { type: 'fixed', text: 'Pasting a capture into a terminal now keeps the image instead of dropping it for the text.' },
    ],
  },
  {
    version: '0.2.0',
    date: '2026-06-23',
    changes: [
      { type: 'added', text: 'First public release — capture a region, drop numbered markers, and copy a ready-to-paste prompt for your AI agent.' },
    ],
  },
];
