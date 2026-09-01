# AGENT.md - Developer & AI Agent Guidelines

This repository contains the **KOReader Tabata Timer Plugin**, a customizable interval timer plugin built for [KOReader](https://github.com/koreader/koreader) on e-ink devices (Kobo, Kindle, PocketBook, Android).

---

## 1. Codebase Architecture

```text
.
├── _meta.lua               # Plugin metadata (name, description for KOReader menu)
├── main.lua                # Plugin entry point; sets package.path to ./lua/
├── Makefile                # Test and emulator symlink targets
├── lua/
│   ├── tabata_plugin.lua   # Main UI widget (TabataTimerWidget) & plugin lifecycle (TabataTimerPlugin)
│   ├── parser.lua          # CSV parser for workout routine files
│   └── updater.lua         # GitHub-based OTA updater for routines and plugin code
├── workouts/               # Default workout CSV files (tabata.csv, McGill.csv, mobility.csv, etc.)
├── tests/
│   └── test_parser.lua     # Unit tests for parser.lua
└── screenshots/            # UI screenshots displayed in README.md (timer.png, workouts.png)
```

### Key Modules

- **[`main.lua`](main.lua)**: Injects the `./lua/` folder into `package.path` and returns `tabata_plugin`.
- **[`lua/tabata_plugin.lua`](lua/tabata_plugin.lua)**:
  - `TabataTimerWidget`: Full-screen modal widget extending `InputContainer`. Manages the timer countdown loop, start/pause/resume states, interval indexing, button handling, dialogs, and text editor invocations.
  - `TabataTimerPlugin`: Implements KOReader's `Widget:extend` interface, registers menu entries under **Tools** $\rightarrow$ **Tabata Timer**.
- **[`lua/parser.lua`](lua/parser.lua)**:
  - `Parser.readCSV(filepath)`: Reads exercise lines formatted as `<Exercise Name>,<Duration Seconds>`. Ignores empty lines, `#` comment lines, and trailing `# inline comments`.
- **[`lua/updater.lua`](lua/updater.lua)**:
  - Fetches repository tree from GitHub API over HTTPS, checks for modified/new files, and handles workout conflict resolution.

---

## 2. Development & Testing Workflow

### Running Unit Tests
Always run unit tests after modifying parser logic or workout handling:
```bash
make test
# or
lua tests/test_parser.lua
```

### Running with the KOReader Emulator
KOReader emulator can be run alongside this repo:
1. Symlink this plugin into KOReader's plugin directory:
   ```bash
   make emulator
   # Or manually:
   ln -s "$(pwd)" ../koreader/plugins/tabatatimer.koplugin
   ```
2. Launch the emulator:
   ```bash
   cd ../koreader && ./kodev run
   ```

### Mandatory Screenshot Generation After Each Update
> **IMPORTANT:** After each new update (UI layout changes, feature modifications, or workout routine updates), **new screenshots MUST be generated and updated** in `screenshots/` (`screenshots/timer.png` and `screenshots/workouts.png`).

To generate both screenshots in a headless environment with KOReader's `luajit`:
```bash
cd ../koreader/koreader-emulator-x86_64-linux-gnu-debug/koreader
./luajit -e '
require("setupkoenv")
G_defaults = require("luadefaults"):open()
local DataStorage = require("datastorage")
G_reader_settings = require("luasettings"):open(DataStorage:getDataDir().."/settings.reader.lua")
local Device = require("device")
local CanvasContext = require("document/canvascontext")
CanvasContext:init(Device)
local Screen = Device.screen
local UIManager = require("ui/uimanager")

package.path = "/path/to/koreader_tabata_timer/lua/?.lua;" .. package.path
local TabataPlugin = require("tabata_plugin")

local menu_items = {}
local plugin = TabataPlugin:new{ ui = { menu = { registerToMainMenu = function() end } }, path = "/path/to/koreader_tabata_timer" }
plugin:addToMainMenu(menu_items)

local timerWidget
local orig_show = UIManager.show
UIManager.show = function(self, widget, ...)
    orig_show(self, widget, ...)
    if not timerWidget then timerWidget = widget end
end

-- 1. Generate timer.png
menu_items.tabata_timer.sub_item_table[1].callback()
UIManager:forceRePaint()
Screen:shot("/path/to/koreader_tabata_timer/screenshots/timer.png")

-- 2. Generate workouts.png
timerWidget:showWorkoutsDialog()
UIManager:forceRePaint()
Screen:shot("/path/to/koreader_tabata_timer/screenshots/workouts.png")
'
```

---

## 3. UI Layout & Design Conventions

1. **E-Ink Readability**:
   - Use high-contrast fonts (`"cfont"`), bold styling on critical elements, and clean button borders.
   - Minimize excessive whitespace so information is easily legible from several feet away during exercise.

2. **Screen Scaling & Device Compatibility**:
   - Target resolutions range from 540×720 (standard emulator/older devices) up to 1440×1920 (high-DPI 300 DPI e-readers).
   - Use `Screen:scaleBySize(...)` for pixel-based spacing and borders.

3. **Fixed Upcoming Container Height**:
   - `upcomingContainer` height must be fixed to `sampleUpcoming:getSize().h` (calculated with 8 sample lines). This prevents vertical screen jumping when the remaining number of exercises decreases during a workout.

4. **Digit Metrics on Countdown Timer**:
   - The large timer countdown font (size 155) uses `forced_height` and `forced_baseline` metrics calculated from `clockFace.ftsize:getHeightAndAscender()`. This eliminates unused ascender/descender margins for pure digits.

5. **Screenshot Updates Requirement**:
   - **Always generate and commit updated screenshots (`screenshots/timer.png` and `screenshots/workouts.png`) after each new update or change.**

---

## 4. Workout File Format

Workout files in `workouts/*.csv` follow this standard:
```csv
# Full-line comments are ignored
Plank,30
Rest,10
Push-ups,30 # Inline comments are also ignored
Rest,10
Squats,45
Rest,15
```
- Column 1: Exercise / interval name (trimmed).
- Column 2: Integer duration in seconds.
