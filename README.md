# MathsMaster-ipad

Build-only copies of the MathsMaster app for testing in Swift Playgrounds on the iPad. Nothing personal in here.

**Test instruction:** in Working Copy, clone this repo, open each `MM-test-*.swiftpm` folder in Swift Playgrounds, tap Run, and report for each: did it build (paste any error) and did it launch (crash before or after the first screen).

| Folder | What it is |
|---|---|
| `MM-test-0` | Scaffold only (control) |
| `MM-test-A` | Scaffold + editor |
| `MM-test-B` | Scaffold + cards |
| `MM-test-C` | Full build (PR #8 head) |
| `MM-test-D` | Full build without the bundled MathJax files |
| `MM-test-E` | Full build without the Keyboard test screen |

Each has its own bundle ID, so they install side by side. When an app asks for a library folder, pick a new empty folder (e.g. `MM-test-lib`), not your real MathsMaster library.
