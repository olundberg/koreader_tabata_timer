-- ============================================================================
-- KOReader Tabata Timer Plugin
-- Fullscreen countdown and interval timer designed for e-ink devices.
-- ============================================================================

-- KOReader UI and system modules
local Blitbuffer = require("ffi/blitbuffer")             -- Framebuffer color constants
local Button = require("ui/widget/button")                 -- Clickable/tappable button widget
local ButtonDialog = require("ui/widget/buttondialog")     -- Modal dialog containing a list of buttons
local Device = require("device")                           -- Device hardware abstraction (screen, battery, etc.)
local Font = require("ui/font")                             -- FreeType font loader and cache
local FrameContainer = require("ui/widget/container/framecontainer") -- Container with border, padding, and background
local HorizontalGroup = require("ui/widget/horizontalgroup") -- Layout container arranging children horizontally
local HorizontalSpan = require("ui/widget/horizontalspan")   -- Horizontal spacer
local InfoMessage = require("ui/widget/infomessage")       -- Toast notification / message box
local InputContainer = require("ui/widget/container/inputcontainer") -- Root container capable of intercepting touch/key events
local InputDialog = require("ui/widget/inputdialog")       -- Modal text input dialog with on-screen keyboard
local TextBoxWidget = require("ui/widget/textboxwidget")   -- Multi-line wrapped text widget
local TextWidget = require("ui/widget/textwidget")         -- Single-line text widget
local UIManager = require("ui/uimanager")                   -- Main KOReader UI event loop and window manager
local VerticalGroup = require("ui/widget/verticalgroup")     -- Layout container arranging children vertically
local VerticalSpan = require("ui/widget/verticalspan")       -- Vertical spacer
local WidgetContainer = require("ui/widget/container/widgetcontainer") -- Base class for KOReader plugins
local util = require("util")                               -- Utility helpers (file read/write, strings, etc.)
local _ = require("gettext")                               -- Localization / translation function
local Screen = Device.screen                               -- Screen dimensions and DPI scaling helper

-- Plugin-specific modules
local Parser = require("parser")                           -- CSV parser for workout definition files
local Updater = require("updater")                         -- Over-the-air GitHub updater module

local TopContainer = require("ui/widget/container/topcontainer") -- Container aligning children to the top with fixed dimen
local Geom = require("ui/geometry")                         -- Geometry rectangle (x, y, w, h)

-- ----------------------------------------------------------------------------
-- TabataTimerWidget: Fullscreen interactive timer view
-- ----------------------------------------------------------------------------
local TabataTimerWidget = InputContainer:extend{
    name = "TabataTimerWidget",
    covers_fullscreen = true,
}

function TabataTimerWidget:init()
    -- Screen geometry
    self.width = Screen:getWidth()                           -- Full display width in pixels
    self.height = Screen:getHeight()                         -- Full display height in pixels
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height } -- Container bounding box

    -- Path configuration
    self.plugin_path = self.plugin_path or (self.workouts_dir and self.workouts_dir:gsub("/workouts$", "")) or "." -- Root directory of plugin
    self.workouts_dir = self.workouts_dir or (self.plugin_path and (self.plugin_path .. "/workouts")) or "workouts" -- Directory containing workout CSVs

    -- Workout state
    self.currentWorkoutName = self.currentWorkoutName or "tabata" -- Name of current workout routine (without .csv)
    self.exercises = self.exercises or { { name = "No exercises", seconds = 0 } } -- Array of { name = string, seconds = number }
    self.currentIndex = 1                                    -- 1-based index of the currently active exercise
    self.timeLeft = self.exercises[self.currentIndex].seconds -- Remaining seconds for the active exercise

    -- Timer execution flags
    self.paused = true                                       -- Starts in paused state until user presses Start
    self.running = true                                      -- Controls whether timer loop is active (set false on close)
    self.tick_scheduled = false                              -- Flag indicating a 1-second timer tick is queued in UIManager

    -- Build the UI widget tree
    self:buildLayout()
end

-- Converts an integer number of seconds into "MM:SS" format
function TabataTimerWidget:formatTime(seconds)
    if not seconds or seconds < 0 then seconds = 0 end
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

-- Computes total remaining workout time across the current and all remaining exercises
function TabataTimerWidget:getTotalTimeLeft()
    local total = self.timeLeft
    for i = self.currentIndex + 1, #self.exercises do
        total = total + (self.exercises[i].seconds or 0)
    end
    return total
end

-- Constructs the widget tree and calculates vertical spacing
function TabataTimerWidget:buildLayout()
    local currentEx = self.exercises[self.currentIndex] or { name = "", seconds = 0 }

    -- ------------------------------------------------------------------------
    -- Top Navigation Bar
    -- ------------------------------------------------------------------------
    -- Button to exit the timer and return to KOReader
    self.closeButton = Button:new{
        text = "✕ Close",
        text_font_face = "cfont",
        text_font_size = 24,
        callback = function()
            self:onClose()
        end,
    }

    -- Button to open the workout selection / management modal
    self.workoutsButton = Button:new{
        text = "Workouts",
        text_font_face = "cfont",
        text_font_size = 24,
        callback = function()
            self:showWorkoutsDialog()
        end,
    }

    -- Label displaying the current workout name next to the Workouts button (e.g. "(tabata)")
    self.workoutLabelWidget = TextWidget:new{
        text = "(" .. self.currentWorkoutName .. ")",
        face = Font:getFace("cfont", 22),
    }

    -- Top bar layout spacing & horizontal alignment
    local leadPadding = Screen:scaleBySize(10)               -- Left margin padding
    local spacing1 = Screen:scaleBySize(6)                  -- Gap between Close and Workouts button
    local spacing2 = Screen:scaleBySize(8)                  -- Gap between Workouts button and workout label
    self.topBarLeadingSpan = HorizontalSpan:new{ width = leadPadding }

    -- Calculate remaining width so the top bar spans across 94% of screen width cleanly
    local usedWidth = leadPadding + self.closeButton:getSize().w + self.workoutsButton:getSize().w + self.workoutLabelWidget:getSize().w + spacing1 + spacing2
    self.topBarTrailingSpan = HorizontalSpan:new{ width = math.max(0, math.floor(self.width * 0.94) - usedWidth) }

    -- Group holding all top-bar items horizontally
    self.topBar = HorizontalGroup:new{
        align = "center",
        self.topBarLeadingSpan,
        self.closeButton,
        HorizontalSpan:new{ width = spacing1 },
        self.workoutsButton,
        HorizontalSpan:new{ width = spacing2 },
        self.workoutLabelWidget,
        self.topBarTrailingSpan,
    }

    -- ------------------------------------------------------------------------
    -- Middle Section: Exercise Title, Countdown Clocks, Controls
    -- ------------------------------------------------------------------------
    -- Current exercise indicator and name: "(1/10)\nPlank"
    self.titleWidget = TextBoxWidget:new{
        text = string.format("(%d/%d)\n%s", self.currentIndex, #self.exercises, currentEx.name),
        face = Font:getFace("cfont", 44),
        bold = true,
        alignment = "center",
        width = math.floor(self.width * 0.94),
    }

    -- Main countdown timer ("00:30"): Uses custom font height/baseline to eliminate empty FreeType margins
    local clockFace = Font:getFace("cfont", 155)
    local _, clockAscender = clockFace.ftsize:getHeightAndAscender()
    self.clockWidget = TextWidget:new{
        text = self:formatTime(self.timeLeft),
        face = clockFace,
        bold = true,
        padding = 0,
        forced_height = math.floor(clockAscender * 0.84),
        forced_baseline = math.floor(clockAscender * 0.80),
    }

    -- Total remaining workout time ("Total left: 03:40")
    self.totalClockWidget = TextWidget:new{
        text = "Total left: " .. self:formatTime(self:getTotalTimeLeft()),
        face = Font:getFace("cfont", 30),
        padding = 0,
    }

    -- ------------------------------------------------------------------------
    -- Upcoming Exercises Section
    -- ------------------------------------------------------------------------
    -- Pre-calculate maximum height of 8 upcoming lines to lock container height and avoid jitter
    local sampleUpcoming = TextBoxWidget:new{
        text = "Upcoming exercises:\n 99. Line 1 (30s)\n 99. Line 2 (30s)\n 99. Line 3 (30s)\n 99. Line 4 (30s)\n 99. Line 5 (30s)\n 99. Line 6 (30s)\n (+99 more exercises)\n",
        face = Font:getFace("cfont", 30),
        alignment = "center",
        width = math.floor(self.width * 0.94),
    }
    self.upcomingMaxH = sampleUpcoming:getSize().h           -- Locked vertical height for upcoming list
    sampleUpcoming:free()

    -- Live widget displaying next upcoming exercises
    self.upcomingTextWidget = TextBoxWidget:new{
        text = self:getUpcomingText(),
        face = Font:getFace("cfont", 30),
        alignment = "center",
        width = math.floor(self.width * 0.94),
    }

    -- TopContainer locks upcoming text to fixed height, preventing layout jumps when items decrease
    self.upcomingContainer = TopContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = math.floor(self.width * 0.94), h = self.upcomingMaxH },
        self.upcomingTextWidget,
    }

    -- ------------------------------------------------------------------------
    -- Navigation & Playback Controls
    -- ------------------------------------------------------------------------
    -- Previous exercise button
    self.prevButton = Button:new{
        text = "⏮ Prev",
        text_font_face = "cfont",
        text_font_size = 30,
        callback = function()
            self:onPrev()
        end,
    }

    -- Pre-calculate maximum button width for Start/Pause/Resume states so button size remains static
    local sampleResume = Button:new{ text = "▶ Resume", text_font_face = "cfont", text_font_size = 30 }
    local samplePause = Button:new{ text = "⏸ Pause", text_font_face = "cfont", text_font_size = 30 }
    local sampleStart = Button:new{ text = "▶ Start", text_font_face = "cfont", text_font_size = 30 }
    self.playPauseButtonWidth = math.max(sampleResume:getSize().w, samplePause:getSize().w, sampleStart:getSize().w)
    sampleResume:free()
    samplePause:free()
    sampleStart:free()

    -- Start / Pause / Resume toggle button
    self.playPauseButton = Button:new{
        text = "▶ Start",
        text_font_face = "cfont",
        text_font_size = 30,
        width = self.playPauseButtonWidth,
        callback = function()
            self:togglePlayPause()
        end,
    }

    -- Next exercise button
    self.nextButton = Button:new{
        text = "Next ⏭",
        text_font_face = "cfont",
        text_font_size = 30,
        callback = function()
            self:onNext()
        end,
    }

    -- Horizontal group holding Prev, Start/Pause, and Next buttons
    self.navButtonGroup = HorizontalGroup:new{
        align = "center",
        self.prevButton,
        HorizontalSpan:new{ width = Screen:scaleBySize(6) },
        self.playPauseButton,
        HorizontalSpan:new{ width = Screen:scaleBySize(6) },
        self.nextButton,
    }

    -- Vertical group holding title, timer, total clock, and nav buttons
    self.middleGroup = VerticalGroup:new{
        align = "center",
        self.titleWidget,
        VerticalSpan:new{ width = Screen:scaleBySize(2) },
        self.clockWidget,
        self.totalClockWidget,
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
        self.navButtonGroup,
    }

    -- ------------------------------------------------------------------------
    -- Dynamic Spacing and Main Root Layout Assembly
    -- ------------------------------------------------------------------------
    self.topMarginSpan = VerticalSpan:new{ width = Screen:scaleBySize(4) }

    -- Calculate available vertical space and distribute between top and bottom sections
    local usedH = self.topMarginSpan.width + self.topBar:getSize().h + self.middleGroup:getSize().h + self.upcomingContainer:getSize().h
    local remainingH = math.max(0, self.height - usedH)

    self.space1Span = VerticalSpan:new{ width = math.max(Screen:scaleBySize(2), math.floor(remainingH * 0.35)) }
    self.space2Span = VerticalSpan:new{ width = math.max(Screen:scaleBySize(4), math.floor(remainingH * 0.40)) }

    -- Full vertical layout group
    self.mainGroup = VerticalGroup:new{
        align = "center",
        self.topMarginSpan,
        self.topBar,
        self.space1Span,
        self.middleGroup,
        self.space2Span,
        self.upcomingContainer,
    }

    -- Root frame container with white background
    self.frame = FrameContainer:new{
        width = self.width,
        height = self.height,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        margin = 0,
        padding = 0,
        self.mainGroup,
    }

    self[1] = self.frame
end

-- Generates formatted multi-line text listing upcoming exercises (up to 6 items previewed)
function TabataTimerWidget:getUpcomingText()
    local text = "Upcoming exercises:\n"
    local count = 0                                          -- Number of upcoming exercises added to preview
    for i = self.currentIndex + 1, #self.exercises do
        local ex = self.exercises[i]
        text = text .. " " .. i .. ". " .. ex.name .. " (" .. ex.seconds .. "s)\n"
        count = count + 1
        if count >= 6 then
            -- If more exercises exist beyond the 6 preview lines, append count summary
            if #self.exercises > i then
                text = text .. " (+" .. (#self.exercises - i) .. " more exercises)\n"
            end
            break
        end
    end
    if count == 0 then
        text = text .. " (Last exercise!)"
    end
    return text
end

-- Toggles between running and paused states
function TabataTimerWidget:togglePlayPause()
    self.paused = not self.paused
    if not self.paused then
        self.playPauseButton:setText("⏸ Pause", self.playPauseButtonWidth)
        if not self.tick_scheduled then
            self:scheduleTick()
        end
    else
        self.playPauseButton:setText("▶ Resume", self.playPauseButtonWidth)
    end
    self.navButtonGroup:resetLayout()
    self.mainGroup:resetLayout()
    UIManager:setDirty(self, "ui")
end

-- Jumps back to previous exercise interval
function TabataTimerWidget:onPrev()
    if self.currentIndex > 1 then
        self.currentIndex = self.currentIndex - 1
    end
    self.timeLeft = self.exercises[self.currentIndex].seconds
    self:updateDisplay()
end

-- Skips forward to next exercise interval or ends workout if on final exercise
function TabataTimerWidget:onNext()
    if self.currentIndex < #self.exercises then
        self.currentIndex = self.currentIndex + 1
        self.timeLeft = self.exercises[self.currentIndex].seconds
        self:updateDisplay()
    else
        self:onClose()
        UIManager:show(InfoMessage:new{
            text = "Workout completed! Well done!",
            timeout = 5,
        })
    end
end

-- Updates all text widgets (title, countdown, total clock, upcoming list) and marks UI dirty
function TabataTimerWidget:updateDisplay()
    if not self.running then return end
    local currentEx = self.exercises[self.currentIndex]
    if currentEx then
        self.titleWidget:setText(string.format("(%d/%d)\n%s", self.currentIndex, #self.exercises, currentEx.name))
    end
    self.clockWidget:setText(self:formatTime(self.timeLeft))
    self.totalClockWidget:setText("Total left: " .. self:formatTime(self:getTotalTimeLeft()))
    self.upcomingTextWidget:setText(self:getUpcomingText())
    self.middleGroup:resetLayout()
    self.mainGroup:resetLayout()
    UIManager:setDirty(self, "ui")
end

-- Schedules recurring 1-second countdown ticks via UIManager
function TabataTimerWidget:scheduleTick()
    if not self.running or self.paused then return end
    self.tick_scheduled = true
    UIManager:scheduleIn(1, function()
        self.tick_scheduled = false
        if not self.running then return end
        if not self.paused then
            self.timeLeft = self.timeLeft - 1
            if self.timeLeft < 0 then
                -- Move to next exercise when interval reaches 0
                self.currentIndex = self.currentIndex + 1
                if self.currentIndex > #self.exercises then
                    self:onClose()
                    UIManager:show(InfoMessage:new{
                        text = "Workout completed! Well done!",
                        timeout = 5,
                    })
                    return
                else
                    self.timeLeft = self.exercises[self.currentIndex].seconds
                end
            end
            self:updateDisplay()
            self:scheduleTick()
        end
    end)
end

-- Scans workouts_dir for all available .csv workout files
function TabataTimerWidget:getAvailableWorkouts()
    local ok, lfs = pcall(require, "libs/libkoreader-lfs")
    if not ok then
        ok, lfs = pcall(require, "lfs")
    end
    local files = {}
    if ok and lfs and self.workouts_dir then
        pcall(function()
            for file in lfs.dir(self.workouts_dir) do
                if file:match("%.[cC][sS][vV]$") then
                    table.insert(files, file)
                end
            end
        end)
    end
    table.sort(files)
    return files
end

-- Displays the "Select Workout" modal dialog with options to Select, Edit, Rename, Create New, and Check Updates
function TabataTimerWidget:showWorkoutsDialog()
    local files = self:getAvailableWorkouts()                 -- List of *.csv filenames in workouts_dir

    -- Measure button widths for "✏ Edit" and "Rename" to keep columns uniform
    local sampleEdit = Button:new{ text = "✏ Edit" }
    local sampleRename = Button:new{ text = _("Rename") }
    local edit_width = sampleEdit:getSize().w + Screen:scaleBySize(8)
    local rename_width = sampleRename:getSize().w + Screen:scaleBySize(8)
    sampleEdit:free()
    sampleRename:free()

    local buttons = {}
    -- Add a row for each workout routine: [Workout Name] | [✏ Edit] | [Rename]
    for i, file in ipairs(files) do
        local display_name = file:gsub("%.[cC][sS][vV]$", "")
        local filepath = self.workouts_dir .. "/" .. file
        table.insert(buttons, {
            {
                text = display_name,
                callback = function()
                    if self.workout_dialog then
                        UIManager:close(self.workout_dialog)
                        self.workout_dialog = nil
                    end
                    self:loadWorkout(filepath, display_name)
                end,
            },
            {
                text = "✏ Edit",
                width = edit_width,
                callback = function()
                    if self.workout_dialog then
                        UIManager:close(self.workout_dialog)
                        self.workout_dialog = nil
                    end
                    self:editWorkout(filepath, display_name)
                end,
            },
            {
                text = _("Rename"),
                width = rename_width,
                callback = function()
                    if self.workout_dialog then
                        UIManager:close(self.workout_dialog)
                        self.workout_dialog = nil
                    end
                    self:renameWorkout(filepath, display_name)
                end,
            },
        })
    end

    -- Button to create a new workout CSV
    table.insert(buttons, {
        {
            text = _("➕ New workout"),
            callback = function()
                if self.workout_dialog then
                    UIManager:close(self.workout_dialog)
                    self.workout_dialog = nil
                end
                self:newWorkout()
            end,
        }
    })

    -- Button to check GitHub for updates over Wi-Fi
    table.insert(buttons, {
        {
            text = _("Check for updates"),
            callback = function()
                if self.workout_dialog then
                    UIManager:close(self.workout_dialog)
                    self.workout_dialog = nil
                end
                Updater.checkAndUpdate(self.plugin_path, function()
                    self:showWorkoutsDialog()
                end)
            end,
        }
    })

    -- Button to dismiss the dialog
    table.insert(buttons, {
        {
            text = _("Cancel"),
            callback = function()
                if self.workout_dialog then
                    UIManager:close(self.workout_dialog)
                    self.workout_dialog = nil
                end
            end,
        }
    })

    self.workout_dialog = ButtonDialog:new{
        title = _("Select Workout"),
        buttons = buttons,
    }
    UIManager:show(self.workout_dialog)
end

-- Prompts user for a new name and renames the workout .csv file on disk
function TabataTimerWidget:renameWorkout(filepath, old_display_name)
    local rename_dialog
    rename_dialog = InputDialog:new{
        title = _("Rename Workout"),
        input = old_display_name,
        input_hint = _("e.g. hiit"),
        description = string.format(_("Enter new name for '%s':"), old_display_name),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(rename_dialog)
                        self.rename_dialog = nil
                        self:showWorkoutsDialog()
                    end,
                },
                {
                    text = _("Rename"),
                    is_enter_default = true,
                    callback = function()
                        local raw_name = rename_dialog:getInputText() or ""
                        -- Sanitize input: trim whitespace, strip .csv suffix and path separators
                        local clean_name = raw_name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%.[cC][sS][vV]$", "")
                        clean_name = clean_name:gsub("[\\/]", "")
                        if clean_name == "" then
                            UIManager:show(InfoMessage:new{
                                text = _("Please enter a valid workout name."),
                            })
                            return
                        end

                        UIManager:close(rename_dialog)
                        self.rename_dialog = nil

                        if clean_name == old_display_name then
                            self:showWorkoutsDialog()
                            return
                        end

                        local new_filepath = self.workouts_dir .. "/" .. clean_name .. ".csv"
                        local exists = util.readFromFile(new_filepath, "rb")
                        if exists and exists ~= "" then
                            UIManager:show(InfoMessage:new{
                                text = string.format(_("A workout named '%s' already exists."), clean_name),
                            })
                            self:showWorkoutsDialog()
                            return
                        end

                        -- Rename file on filesystem
                        local ok, err = os.rename(filepath, new_filepath)
                        if not ok then
                            UIManager:show(InfoMessage:new{
                                text = string.format(_("Failed to rename file:\n%s"), tostring(err)),
                            })
                            self:showWorkoutsDialog()
                            return
                        end

                        -- If currently active workout was renamed, update top bar label
                        if self.currentWorkoutName == old_display_name then
                            self.currentWorkoutName = clean_name
                            self.workoutLabelWidget:setText("(" .. self.currentWorkoutName .. ")")
                            local leadPadding = self.topBarLeadingSpan and self.topBarLeadingSpan.width or Screen:scaleBySize(10)
                            local spacing1 = Screen:scaleBySize(6)
                            local spacing2 = Screen:scaleBySize(8)
                            local usedWidth = leadPadding + self.closeButton:getSize().w + self.workoutsButton:getSize().w + self.workoutLabelWidget:getSize().w + spacing1 + spacing2
                            self.topBarTrailingSpan.width = math.max(0, math.floor(self.width * 0.94) - usedWidth)
                            self.topBar:resetLayout()
                            self.middleGroup:resetLayout()
                            self.mainGroup:resetLayout()
                            UIManager:setDirty(self, "ui")
                        end

                        UIManager:show(InfoMessage:new{
                            text = string.format(_("Renamed to '%s'"), clean_name),
                            timeout = 2,
                        })
                        self:showWorkoutsDialog()
                    end,
                },
            }
        },
    }
    self.rename_dialog = rename_dialog
    UIManager:show(rename_dialog)
    rename_dialog:onShowKeyboard()
end

-- Prompts for a workout name, generates a starter CSV template, and opens the editor
function TabataTimerWidget:newWorkout()
    local name_dialog
    name_dialog = InputDialog:new{
        title = _("New Workout"),
        input_hint = _("e.g. hiit"),
        description = _("Enter workout name:"),
        buttons = {
            {
                {
                    text = _("Cancel"),
                    id = "close",
                    callback = function()
                        UIManager:close(name_dialog)
                        self.name_dialog = nil
                    end,
                },
                {
                    text = _("Create"),
                    is_enter_default = true,
                    callback = function()
                        local raw_name = name_dialog:getInputText() or ""
                        local clean_name = raw_name:gsub("^%s+", ""):gsub("%s+$", ""):gsub("%.[cC][sS][vV]$", "")
                        clean_name = clean_name:gsub("[\\/]", "")
                        if clean_name == "" then
                            UIManager:show(InfoMessage:new{
                                text = _("Please enter a valid workout name."),
                            })
                            return
                        end
                        UIManager:close(name_dialog)
                        self.name_dialog = nil

                        local filepath = self.workouts_dir .. "/" .. clean_name .. ".csv"
                        local existing = util.readFromFile(filepath, "rb")
                        if not existing or existing == "" then
                            -- Create default template if file does not exist yet
                            local template = "# Exercise,Seconds\nPlank,30\nRest,10\nPush-ups,30\nRest,10\n"
                            util.writeToFile(template, filepath)
                        end
                        self:editWorkout(filepath, clean_name)
                    end,
                },
            }
        },
    }
    self.name_dialog = name_dialog
    UIManager:show(name_dialog)
    name_dialog:onShowKeyboard()
end

-- Opens full-screen text editor to modify a workout CSV directly on-device
function TabataTimerWidget:editWorkout(filepath, display_name)
    local content = util.readFromFile(filepath, "rb") or ""
    self.editor_dialog = InputDialog:new{
        title = string.format("Edit %s.csv", display_name),
        input = content,
        fullscreen = true,
        condensed = true,
        allow_newline = true,
        cursor_at_end = false,
        add_nav_bar = true,
        keyboard_visible = true,
        save_callback = function(new_content, closing)
            local ok, err = util.writeToFile(new_content, filepath)
            if ok then
                self:loadWorkout(filepath, display_name)
                return true, _("File saved")
            else
                return false, tostring(err or "Failed to save file")
            end
        end,
        close_callback = function()
            self.editor_dialog = nil
        end,
    }
    UIManager:show(self.editor_dialog)
end

-- Loads a workout CSV file, resets index/timer, and updates the display
function TabataTimerWidget:loadWorkout(filepath, display_name)
    local workouts, err = Parser.readCSV(filepath)
    if not workouts or #workouts == 0 then
        UIManager:show(InfoMessage:new{
            text = "Error reading CSV:\n" .. tostring(err or "No valid rows found."),
        })
        return
    end

    self.paused = true
    self.playPauseButton:setText("▶ Start", self.playPauseButtonWidth)
    self.exercises = workouts
    self.currentWorkoutName = display_name
    self.workoutLabelWidget:setText("(" .. self.currentWorkoutName .. ")")
    self.currentIndex = 1
    self.timeLeft = self.exercises[self.currentIndex].seconds

    -- Recalculate top bar widths
    local leadPadding = self.topBarLeadingSpan and self.topBarLeadingSpan.width or Screen:scaleBySize(10)
    local spacing1 = Screen:scaleBySize(6)
    local spacing2 = Screen:scaleBySize(8)
    local usedWidth = leadPadding + self.closeButton:getSize().w + self.workoutsButton:getSize().w + self.workoutLabelWidget:getSize().w + spacing1 + spacing2
    self.topBarTrailingSpan.width = math.max(0, math.floor(self.width * 0.94) - usedWidth)

    self.topBar:resetLayout()
    self.middleGroup:resetLayout()
    self.mainGroup:resetLayout()
    self:updateDisplay()
end

-- Closes the timer widget and cleans up all active modal dialogs
function TabataTimerWidget:onClose()
    self.running = false
    self.paused = true
    if self.workout_dialog then
        UIManager:close(self.workout_dialog)
        self.workout_dialog = nil
    end
    if self.editor_dialog then
        UIManager:close(self.editor_dialog)
        self.editor_dialog = nil
    end
    if self.name_dialog then
        UIManager:close(self.name_dialog)
        self.name_dialog = nil
    end
    if self.rename_dialog then
        UIManager:close(self.rename_dialog)
        self.rename_dialog = nil
    end
    UIManager:close(self, "ui")
    return true
end

-- ----------------------------------------------------------------------------
-- TabataTimerPlugin: KOReader Plugin Lifecycle & Menu Registration
-- ----------------------------------------------------------------------------
local TabataTimerPlugin = WidgetContainer:extend{
    name = "tabatatimer",
    is_doc_only = false,
}

function TabataTimerPlugin:init()
    self.ui.menu:registerToMainMenu(self)
end

function TabataTimerPlugin:addToMainMenu(menu_items)
    menu_items.tabata_timer = {
        text = _("Tabata Timer"),
        sorting_hint = "tools",
        sub_item_table = {
            {
                text = _("Start workout from CSV"),
                callback = function()
                    local workouts_dir = self.path and (self.path .. "/workouts") or "workouts"
                    local default_csv = workouts_dir .. "/tabata.csv"
                    local default_name = "tabata"
                    local workouts, err = Parser.readCSV(default_csv)
                    if not workouts or #workouts == 0 then
                        local ok, lfs = pcall(require, "libs/libkoreader-lfs")
                        if not ok then ok, lfs = pcall(require, "lfs") end
                        if ok and lfs then
                            pcall(function()
                                for file in lfs.dir(workouts_dir) do
                                    if file:match("%.[cC][sS][vV]$") then
                                        workouts, err = Parser.readCSV(workouts_dir .. "/" .. file)
                                        if workouts and #workouts > 0 then
                                            default_name = file:gsub("%.[cC][sS][vV]$", "")
                                            break
                                        end
                                    end
                                end
                            end)
                        end
                    end
                    if not workouts or #workouts == 0 then
                        UIManager:show(InfoMessage:new{
                            text = "Error reading workouts:\n" .. tostring(err or "No valid CSV found in " .. workouts_dir),
                        })
                        return
                    end

                    local timerWidget = TabataTimerWidget:new{
                        exercises = workouts,
                        currentWorkoutName = default_name,
                        workouts_dir = workouts_dir,
                        plugin_path = self.path,
                    }
                    UIManager:show(timerWidget, "ui")
                end,
            },
            {
                text = _("Check for updates..."),
                callback = function()
                    local plugin_path = self.path or "."
                    Updater.checkAndUpdate(plugin_path)
                end,
            },
        },
    }
end

return TabataTimerPlugin
