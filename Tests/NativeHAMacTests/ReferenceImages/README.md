# Approved visual references

The GUI smoke tests always write current PNGs to `.build/render-artifacts`.

After comparing those artifacts with the corresponding Home Assistant frontend
card and approving a NativeHA result, copy the PNG here with the same filename.
Future test runs will perform a tolerant pixel comparison automatically.

Expected filenames:

- `entities-card.png`
- `history-graph.png`
- `climate-dial-frame-0.png`
- `climate-dial-frame-1.png`
- `climate-dial-frame-2.png`

Set `NATIVEHA_REQUIRE_VISUAL_REFERENCES=1` in CI after all references have been
approved to make a missing reference fail instead of being treated as optional.
