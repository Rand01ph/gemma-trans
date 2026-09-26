# macOS UI contract — 2.1.1

`ui-contract.json` is the reviewable element inventory: stable ID, purpose, states,
text constraints, visibility, interaction and relative layout. `baseline/` contains
native macOS screenshots and actual rendered element geometry. `annotated/` maps
numbered boxes to IDs. Release layout remains the 2.1.0 design; only bottom-right speed
and segmented progress are intentional changes.

## Run

1. `GEMMATRANS_TEST_RESULT="$PWD/App/build/ui-tests.xcresult" ./script/build_and_run.sh --ui-test`
2. This builds and launches the isolated `.uitest` identity and unregisters it after the run.
3. `python3 script/export_ui_menu.py App/build/ui-tests.xcresult App/build/ui-menu`
4. `python3 script/capture_ui.py --menu-captures App/build/ui-menu --output App/build/ui-current`
5. `python3 script/ui_contract.py --baseline docs/ui/baseline --current App/build/ui-current --output App/build/ui-diff`

Use a fresh output directory/result bundle for each run. For the real-model macOS
service test, prefix the XCTest command with `TEST_RUNNER_GT_SERVICE_TEST=1` on a
machine that already has `hymt2-4bit` installed. The test uses launch arguments and
an isolated preferences suite, passes a named pasteboard through `NSPerformService`,
and verifies the complete text using the card's Copy button. The general clipboard
is restored with all original data types. PopClip itself is a separate manual
integration check.

The comparison requires Python Pillow (`script/requirements-ui.txt`). Normal CI runs identifier and deliberate
regression checks without GUI dependencies. The `macOS UI regression` workflow runs
on a logged-in self-hosted `gemmatrans-ui` Mac with the baseline OS/build, scale and
system font. Missing captures or mismatched environments fail acceptance. A skipped
or unconfigured graphical runner is not evidence of UI acceptance.

Fixtures use a separate test preferences suite and no inference, downloads, API or
global hotkey registration. They use fixed content, state and metrics. Native window
capture requires Screen Recording access; XCTest interactions require UI automation
access. Neither permission is bypassed. Geometry is exported from actual rendered
views, not inferred from the expected contract. Native menu interaction uses XCTest.

## Review rules

- Run comparison for every UI-affecting change, even without a design request.
- Do not regenerate expected images to make a test green.
- Intentional UI changes must name affected IDs and states in the PR, update this
  contract and include before/after/difference images for review.
- Comparison tolerates 1 pt of geometry noise and at most 0.2% of pixels changing
  by more than 16/255. No text or button region is masked. Element/text/state
  checks run independently of pixel tolerance.
- `capture_ui.py` writes only into a new output location and refuses overwrite.
  `ui_contract.py` never writes baselines.
- Long results intentionally scroll: their text frame may exceed the viewport.
  Buttons, direction and rate must remain visible; the speed sits at the right of the bottom action row and shares its vertical center with Copy.
- OS/SDK upgrades require a separately reviewed baseline update, not a wider threshold.

The generation boundary check proves no program-side truncation and avoids accepting
output-limit stops. Model EOS still cannot prove semantic completeness. Real-model
article tests check all 12 reference markers, including the last paragraph.

## Original reference

`reference-2.1.0/` was captured from the tagged `101735f` view implementations in a
separate worktree on the same OS and scale. Only Debug capture/engine fixtures were
injected, and the package link reused the patch's test-settings isolation. Original
view layout and styling were not replaced. These are historical comparison images,
not the acceptance baseline. The accepted location for speed was subsequently
changed to the **bottom right** at the user's request.
