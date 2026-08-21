# Demo script — v0.7.0

`docs/demo.gif` still shows the pre-0.7.0 flow (capture → percentage markers →
copy). This is the shot list to replace it: a script to *play*, not prose to
adapt. It can't be recorded from here — capturing the screen and driving the
Pinpoint UI is interactive and has to happen on your own Mac — so everything
below is written to be followed step by step, key by key.

## The story it has to tell

Pinpoint's whole pitch for v0.7.0 is bet #1 (#55): a marker isn't a percentage
anymore, it's an anchor into the app's own accessibility tree. The demo has to
*show* that, not describe it:

1. A real, visible bug in a real, running app.
2. One capture, one marker, a one-line instruction.
3. An agent that never saw a screenshot pasted into it — it reads
   `capture.md` (and looks at `capture.png` itself) from the fixed path on
   disk, and fixes the right thing because the marker told it *which element*,
   not just *which pixels*.

Resist the urge to add more markers, more shapes, or a tour of the Shelf.
One clean bug, one marker, one fix is more convincing than a feature tour —
and it's what actually happened in the file handoff this whole release is
built around.

## What's already in the repo for this

Both are gitignored (never committed — see `.gitignore`), so they only exist
in a checkout that made them, but they're real and worth knowing about before
you improvise new assets:

- **`.capture-demo/index.html`** — a small, self-contained fake product page
  ("Nimbus"). It stages exactly one bug on purpose: the logo mark carries
  `transform: translateY(5px)` (see the comment right above `.brand .mark` in
  the CSS), so it sits visibly below the "Nimbus" wordmark's baseline.
  **Use this as the bug.** It needs no setup — open the file in a browser —
  and it's already the bug the old (pre-0.7.0) `demo.gif` pointed at, so
  reusing it keeps continuity with the README's copied-prompt example, which
  was regenerated against this same file for this PR.

- **`.demo-remotion/`** — a Remotion project (`npm run studio` / `npm run
  render`, see its `package.json`) that rendered the *current* `demo.gif`.
  Worth knowing what it actually is: **not a screen recording tool** — it's a
  from-scratch React animation (`src/Demo.tsx`) that *redraws* a fake
  Pinpoint window, a fake cursor, and fake clipboard text by hand-tuned
  keyframes. The content it renders (percent-only markers, no accessibility
  line, no OCR, "Copy for the agent" wording) is the exact pre-0.7.0 format
  this task exists to retire. It is reusable *as a rendering pipeline* — it
  could composite a real screen recording into a branded frame, add a
  cursor-click pulse, export a `.gif`/`.mp4` — but not as-is: `Demo.tsx` would
  need a full rewrite of its timeline and its hard-coded UI/text to match
  what v0.7.0 actually shows, and at that point it is doing the same job as
  a real screen recording while being one step further from the truth.
  **Recommendation: record a real screen capture (below) rather than
  rescripting `Demo.tsx`.** The whole point of this refresh is that the tool
  now shows real, verifiable output — a hand-animated recreation is exactly
  the kind of "plausible but not real" artifact the current landing page and
  README examples got flagged for. If a polish pass is wanted later
  (branded intro card, smoother cursor), it should composite on top of a real
  recording, not replace it.

## Before you hit record

- **Permissions.** Screen Recording must already be granted (Pinpoint will
  otherwise interrupt the take with its own permission alert). If you want
  the accessibility line in `capture.md` for the demo marker, grant
  **Accessibility** too, from Pinpoint's own Settings — it deep-links to
  System Settings ▸ Privacy & Security ▸ Accessibility. Do this *before*
  recording; the OS grant dialog is not something you want mid-take.
- **Dry run.** Take one throwaway capture of `.capture-demo/index.html`'s
  header first, drop a marker on the logo mark, and read the result with
  `pinpoint last --format md` in a terminal. Check what you get. Browsers
  vary in what they expose to the accessibility tree, and the mark carries
  `aria-hidden="true"` in the HTML, which can hide it specifically — if the
  marker resolves to nothing more than the enclosing window, try nudging it
  a few pixels toward the "Nimbus" wordmark (OCR only picks up text within
  about 1.5 marker-radii, so it has to be genuinely close) or dropping it on
  the `.brand` container as a whole instead — either still gets you a role
  and a path. Whatever you actually see in the dry run is what should be in
  the take — don't hand-edit `capture.md` to make it look richer than what
  the app produced.
- **Clean `last/` folder.** Delete
  `~/Library/Application Support/Pinpoint/last/` (or just don't worry about
  it — the next copy replaces it atomically) so `pinpoint last` can't
  accidentally show a stale capture from earlier testing while you're
  checking things.
- **Reset the editor's remembered settings** so the recording starts from a
  clean, legible state: Task preset → **Raw** (you'll pick **Bug** on
  camera), marker style → the default filled disc, text format → Markdown
  (Settings ▸ the agent-text-format picker). These are `@AppStorage`, so
  whatever you last used is what a fresh capture opens with.
- **Agent ready.** Have your terminal open with Claude Code (or whichever
  agent) already running — not launching cold on camera. If you've set up
  the MCP server (`claude mcp add pinpoint -- pinpoint mcp`), the short
  version below can lean on it; otherwise the long version's plain
  file-path prompt works with anything that can read a file, no setup
  required.
- **Window sizing.** Resize the browser and the Pinpoint editor to a
  consistent, deliberate size before recording — 1280×800 keeps the numbers
  in `capture.md` round and matches the dimensions already used in the
  README's example. Bump the terminal and browser zoom up a notch: a GIF
  embedded in a README is usually viewed shrunk, and small text disappears
  first.
- **Quiet the rest of the screen.** Turn on Focus/Do Not Disturb so no
  notification banner drifts across the recording — see **Privacy** below,
  this is the easiest way to avoid ever needing a retake for it.
- **Recording tool.** Nothing fancy needed: QuickTime Player ▸ File ▸ New
  Screen Recording, selecting just the window/region you're demoing. Save as
  `.mov`.

## Long take — for the README (~30–40s)

One continuous take. Timings are targets, not a metronome — a beat either way
is fine, but don't let any single step run long enough to feel like dead air
in a README-embedded clip.

| Time | Action | What must be on screen |
| --- | --- | --- |
| 0:00–0:03 | Nothing yet — just sit on the browser window. | `.capture-demo/index.html` open, full page, the misaligned logo mark visible near the top-left. |
| 0:03–0:04 | Press **⌘⇧1**. | Screen dims; crosshair cursor; the hint *"Drag a rectangle · Space to pick a window · Esc to cancel"*. |
| 0:04–0:06 | Drag a rectangle around the header (roughly the logo + nav area). | Live width×height readout following the drag. |
| 0:06–0:08 | Release. Nudge one corner handle a few pixels, to show it's adjustable. Press **Return**. | The 8 resize handles on the rectangle, briefly, before it commits. |
| 0:08–0:09 | — | The editor window opens on the annotated capture; the Marker tool is already active (it's the default). |
| 0:09–0:10 | Click once, directly on the logo mark. | Marker **1** drops (ringed badge animates in). |
| 0:10–0:12 | Type a short note in the marker's field. | e.g. `Icon sits too low` appearing character by character in the Markers list. |
| 0:12–0:14 | Click the **Task:** picker, choose **Bug**. | The picker's value changing; no need to open its tooltip. |
| 0:14–0:16 | Click into "Instructions for the agent", type one line. | e.g. `Fix the icon alignment.` |
| 0:16–0:17 | Press **⌘C**. | The Copy button flashes to **"Copied!"** with a checkmark. |
| 0:17–0:20 | Cut to the terminal. | Claude Code already running, prompt idle. |
| 0:20–0:22 | Type the prompt, press Return. | `Open ~/Library/Application Support/Pinpoint/last/capture.md, look at capture.png, and fix the bug it describes.` (If MCP is configured, `Fix the bug I just captured with Pinpoint.` is the shorter equivalent — the agent calls `get_last_capture` itself instead of being told the path.) |
| 0:22–0:27 | Let the agent's tool calls play out (speed this segment up in editing if it runs long — nobody needs to read every line). | Reads of `capture.md` / `capture.png`, then it opens `.capture-demo/index.html`. |
| 0:27–0:31 | Cut to the diff. | The edit removing (or zeroing) `transform: translateY(5px);` on `.brand .mark`, clearly readable. |
| 0:31–0:35 | Cut back to the browser, reload (**⌘R**). | The logo mark now sits flush with the wordmark baseline — the visible payoff. |

That's the whole story: bug → one marker → one instruction → an agent that
read a file path, not a pasted image, and knew which CSS rule to touch
because the marker carried more than a percentage.

## Short take — for a social post (~10s)

Same beats, compressed to the point where several of them have to happen
off-camera or sped up. Pre-typing the note and instruction (paste them in
rather than typing live) buys back real seconds:

| Time | Action |
| --- | --- |
| 0:00–0:02 | ⌘⇧1, drag the rectangle, Return — sped up 2× is fine here, nobody needs to see the drag in real time. |
| 0:02–0:04 | Click the marker onto the icon; note and instruction already prefilled (pasted, not typed). |
| 0:04–0:05 | ⌘C — the "Copied!" flash is the beat to hold on. |
| 0:05–0:07 | Terminal, prompt already typed, hit Return. Tool calls sped up or cut entirely — jump straight past them. |
| 0:07–0:10 | The fixed page, reloaded, icon aligned. Hold the last frame — this is the payoff people should screenshot. |

If 10 seconds feels impossible to fit honestly, that's a sign to cut the Task
preset step and the visible tool-call scroll first — they're the least
essential beats, not the marker or the fix.

## Privacy — don't film anything real

- Turn on Focus/Do Not Disturb before recording (see above) so Mail, Slack,
  Messages, or calendar notifications can't drift across the shot.
- Close anything with real data in it — your actual browser tabs/bookmarks
  bar, real email in a mail client badge, a real Wi-Fi network name if it's
  identifying. `.capture-demo/index.html` is fake on purpose; keep the rest
  of the screen that way too.
- If something real *does* end up in a take and a retake isn't practical:
  this is exactly what the **Hide** tool (**⌘4**, #50) is for — drag over it,
  and it's removed from the image *and* stripped out of `capture.md` /
  `capture.json`, not just visually covered.

## Bonus: a second demo (redaction)

If a take ever needs the Hide tool for real, that's worth keeping as its own
short clip rather than throwing away — it's a complete demo in its own right
and nobody has scripted it yet:

1. Put something obviously fake but secret-shaped on screen — a terminal
   line like `export API_KEY=sk-fake-1234567890` works well, it reads as a
   real secret at a glance without being one.
2. Capture, press **⌘4**, drag over the value.
3. Show the exported image: a solid bar, not a blur — nothing recoverable
   underneath.
4. Cut to `capture.md` (or `capture.json`): the field reads *"withheld (the
   user painted over this element — its name and its contents were left
   out)"* rather than silently vanishing or leaking the string anyway.

That last beat — the file explicitly saying a value was withheld, not just
omitting it — is the part worth lingering on; it's what stops a redacted
capture from quietly leaking through the text half of the handoff while the
image looks clean.

## Post-production

Trim in QuickTime (⌘T) or `ffmpeg -ss … -to … -i in.mov -c copy trimmed.mov`,
then convert to GIF with a proper palette pass — a direct `.mov` → `.gif`
without one looks banded on the vermillon marker color:

```sh
ffmpeg -i trimmed.mov -vf "fps=15,scale=1280:-1:flags=lanczos,palettegen" palette.png
ffmpeg -i trimmed.mov -i palette.png \
  -filter_complex "fps=15,scale=1280:-1:flags=lanczos[x];[x][1:v]paletteuse" \
  -loop 0 docs/demo.gif
```

Keep the long take as `docs/demo.gif` (what the README embeds) and the short
take as a separate file (`docs/demo-short.gif`) rather than overwriting one
with the other — the social clip is cropped too tight to double as the
README's.
