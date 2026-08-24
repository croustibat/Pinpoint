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
    version: '0.7.2',
    date: '2026-08-24',
    latest: true,
    changes: [
      { type: 'added', text: 'Every shape can carry its own description now — rectangles, arrows and redacted areas each get a field beside them, so circling a misaligned button finally has somewhere to say why. Until now only a numbered marker could hold a note, and describing a shape meant dropping a marker on top of it or pushing the explanation into the general instructions.' },
      { type: 'added', text: 'Those descriptions travel wherever the capture goes: into capture.md, into an optional note on each shape in capture.json, and into a new ANNOTATIONS section of the baked-in legend. It matters most on a redacted area — “what I hid, and why” is exactly what an agent needs to know, and it was the one part of the handoff that had no way to say it.' },
    ],
  },
  {
    version: '0.7.1',
    date: '2026-08-21',
    changes: [
      { type: 'added', text: 'Install the pinpoint command from the app — Settings ▸ Capture now has a “Command line tool” section that puts pinpoint on your PATH in one click, asking for permission once. It was already there if you installed with Homebrew; this is for everyone who downloaded the DMG and would otherwise have had to symlink it by hand.' },
    ],
  },
  {
    version: '0.7.0',
    date: '2026-08-21',
    changes: [
      { type: 'added', text: 'Pinpoint now hands your capture to an AI agent as files. Every copy also writes capture.png, capture.md and capture.json to a stable folder, so an agent opens the real image with its own Read tool instead of choking on an inline one.' },
      { type: 'added', text: 'Accessibility context under every marker — a pin is no longer just a percentage but “AXButton ‘Login’ in Safari”, turning a spot on your screen into an anchor an agent can act on. Optional, and off until you grant the permission.' },
      { type: 'added', text: 'On-device OCR reads the text under each marker — error messages, logs, class names — and sends it along with the capture. Nothing is uploaded anywhere.' },
      { type: 'added', text: 'A pinpoint command line, an MCP server (pinpoint mcp) and a pinpoint:// URL scheme, so agents, scripts and shell hooks can drive Pinpoint. The MCP server hands over file paths, never inline images.' },
      { type: 'added', text: 'Redaction tool (⌘4) — drag over a token or an API key and it is painted out of the picture, the text, the JSON and the accessibility context alike, before anything is shared.' },
      { type: 'added', text: 'Undo and Redo (⌘Z / ⇧⌘Z) throughout the editor — and arrows and rectangles can finally be selected, moved and resized after you have drawn them.' },
      { type: 'added', text: 'Window capture — hold Space while selecting to highlight a single window and grab it cleanly, rounded corners included.' },
      { type: 'added', text: 'The selection rectangle is now adjustable before you commit it: drag it around, resize it by its handles, nudge it with the arrow keys, Enter to confirm.' },
      { type: 'added', text: 'Task presets (Bug, Review, Implement) prefill the framing you keep retyping, and a structured JSON export documents every capture against a published schema.' },
      { type: 'added', text: 'Shelf: search your library, contextual empty states, and a confirmation before deleting several screenshots at once. Editor: delete the selected marker with ⌫, tool shortcuts ⌘1/⌘2/⌘3, and tooltips everywhere.' },
      { type: 'added', text: 'VoiceOver labels, Dynamic Type and reduce-motion support across the editor and the shelf.' },
      { type: 'fixed', text: 'What you see is now what you export: on-screen marker and stroke sizes follow the same formula as the exported image, so a small capture no longer ships with oversized annotations.' },
      { type: 'fixed', text: 'Exported images were silently rendered at twice the requested size on Retina, which made every pixel coordinate in the copied text describe a grid half the size of the image it shipped with. Files are smaller and the numbers now match.' },
      { type: 'fixed', text: 'A failed copy or save is reported instead of quietly showing “Copied!”, and the Screen Recording permission is checked before a capture, with a button that opens the right System Settings pane.' },
    ],
  },
  {
    version: '0.6.0',
    date: '2026-07-14',
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
