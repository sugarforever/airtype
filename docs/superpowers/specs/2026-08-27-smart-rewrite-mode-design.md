# Smart Rewrite Mode Design

## Goal

Add a thought-aware Enhancement mode that turns disfluent speech into ready-to-use writing while keeping the existing conservative proofreading behavior available.

## User experience

- Enhancement exposes two plainly named modes: `Proofread` and `Smart Rewrite`.
- Settings explains the difference beside the mode control. The selected mode persists.
- The menu bar shows the active mode and lets the user switch modes without opening Settings.
- A configurable global shortcut switches between the two modes and reports the new mode in Airtype's notice UI.
- Selecting or invoking Smart Rewrite requires a complete Enhancement configuration: provider, model, valid base URL, and an API key when the provider requires one.
- If Smart Rewrite is requested without that configuration, Airtype does not start recording or silently fall back. It shows a clear notice with an `Open Enhancement Settings` action that opens the main window at the Enhancement section.
- Proofread retains the current conservative correction contract. Smart Rewrite removes filler and false starts, applies spoken revisions, follows editing instructions, and reorganizes thoughts without inventing facts.

## Boundaries

- Reuse the existing OpenAI-compatible Enhancement request path and providers.
- Do not add accounts, storage, networking endpoints, or dependencies.
- Keep macOS 14 as the deployment floor.
- Do not change the default mode for existing users; default to Proofread.

