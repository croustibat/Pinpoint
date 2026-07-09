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
}

export const changelog: ChangelogEntry[] = [
  {
    version: '0.4.0',
    date: '2026-07-06',
    latest: true,
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
