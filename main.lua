local Blitbuffer = require("ffi/blitbuffer")
local Button = require("ui/widget/button")
local ButtonDialog = require("ui/widget/buttondialog")
local Device = require("device")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local InfoMessage = require("ui/widget/infomessage")
local InputContainer = require("ui/widget/container/inputcontainer")
local InputDialog = require("ui/widget/inputdialog")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local UIManager = require("ui/uimanager")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local WidgetContainer = require("ui/widget/container/widgetcontainer")
local util = require("util")
local _ = require("gettext")
local Screen = Device.screen

local Parser = require("parser")

local CenterContainer = require("ui/widget/container/centercontainer")
local TopContainer = require("ui/widget/container/topcontainer")
local Geom = require("ui/geometry")

local TabataTimerWidget = InputContainer:extend{
    name = "TabataTimerWidget",
    covers_fullscreen = true,
}

function TabataTimerWidget:init()
    self.width = Screen:getWidth()
    self.height = Screen:getHeight()
    self.dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height }
    self.workouts_dir = self.workouts_dir or (self.plugin_path and (self.plugin_path .. "/workouts")) or "workouts"
    self.currentWorkoutName = self.currentWorkoutName or "tabata"
    self.exercises = self.exercises or { { name = "No exercises", seconds = 0 } }
    self.currentIndex = 1
    self.timeLeft = self.exercises[self.currentIndex].seconds
    self.paused = true
    self.running = true
    self.tick_scheduled = false

    self:buildLayout()
end

function TabataTimerWidget:formatTime(seconds)
    if not seconds or seconds < 0 then seconds = 0 end
    return string.format("%02d:%02d", math.floor(seconds / 60), seconds % 60)
end

function TabataTimerWidget:getTotalTimeLeft()
    local total = self.timeLeft
    for i = self.currentIndex + 1, #self.exercises do
        total = total + (self.exercises[i].seconds or 0)
    end
    return total
end

function TabataTimerWidget:buildLayout()
    local currentEx = self.exercises[self.currentIndex] or { name = "", seconds = 0 }

    self.closeButton = Button:new{
        text = "✕ Close",
        text_font_face = "cfont",
        text_font_size = 24,
        callback = function()
            self:onClose()
        end,
    }

    self.workoutsButton = Button:new{
        text = "Workouts",
        text_font_face = "cfont",
        text_font_size = 24,
        callback = function()
            self:showWorkoutsDialog()
        end,
    }

    self.workoutLabelWidget = TextWidget:new{
        text = "(" .. self.currentWorkoutName .. ")",
        face = Font:getFace("cfont", 22),
    }

    local spacing1 = Screen:scaleBySize(6)
    local spacing2 = Screen:scaleBySize(8)
    local usedWidth = self.closeButton:getSize().w + self.workoutsButton:getSize().w + self.workoutLabelWidget:getSize().w + spacing1 + spacing2
    self.topBarTrailingSpan = HorizontalSpan:new{ width = math.max(0, math.floor(self.width * 0.94) - usedWidth) }

    self.topBar = HorizontalGroup:new{
        align = "center",
        self.closeButton,
        HorizontalSpan:new{ width = spacing1 },
        self.workoutsButton,
        HorizontalSpan:new{ width = spacing2 },
        self.workoutLabelWidget,
        self.topBarTrailingSpan,
    }

    self.titleWidget = TextBoxWidget:new{
        text = string.format("Exercise %d/%d: %s", self.currentIndex, #self.exercises, currentEx.name),
        face = Font:getFace("cfont", 36),
        bold = true,
        alignment = "center",
        width = math.floor(self.width * 0.94),
    }

    self.clockWidget = TextWidget:new{
        text = self:formatTime(self.timeLeft),
        face = Font:getFace("cfont", 130),
        bold = true,
    }

    self.totalClockWidget = TextWidget:new{
        text = "Total left: " .. self:formatTime(self:getTotalTimeLeft()),
        face = Font:getFace("cfont", 26),
    }

    local sampleUpcoming = TextBoxWidget:new{
        text = "Upcoming exercises:\n • Line 1 (30s)\n • Line 2 (30s)\n • Line 3 (30s)\n • Line 4 (30s)\n • (+99 more exercises)\n",
        face = Font:getFace("cfont", 26),
        alignment = "center",
        width = math.floor(self.width * 0.94),
    }
    self.upcomingMaxH = sampleUpcoming:getSize().h
    sampleUpcoming:free()

    self.upcomingTextWidget = TextBoxWidget:new{
        text = self:getUpcomingText(),
        face = Font:getFace("cfont", 26),
        alignment = "center",
        width = math.floor(self.width * 0.94),
    }

    self.upcomingContainer = TopContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = math.floor(self.width * 0.94), h = self.upcomingMaxH },
        self.upcomingTextWidget,
    }

    self.prevButton = Button:new{
        text = "⏮ Prev",
        text_font_face = "cfont",
        text_font_size = 26,
        callback = function()
            self:onPrev()
        end,
    }

    local sampleResume = Button:new{ text = "▶ Resume", text_font_face = "cfont", text_font_size = 26 }
    local samplePause = Button:new{ text = "⏸ Pause", text_font_face = "cfont", text_font_size = 26 }
    local sampleStart = Button:new{ text = "▶ Start", text_font_face = "cfont", text_font_size = 26 }
    self.playPauseButtonWidth = math.max(sampleResume:getSize().w, samplePause:getSize().w, sampleStart:getSize().w)
    sampleResume:free()
    samplePause:free()
    sampleStart:free()

    self.playPauseButton = Button:new{
        text = "▶ Start",
        text_font_face = "cfont",
        text_font_size = 26,
        width = self.playPauseButtonWidth,
        callback = function()
            self:togglePlayPause()
        end,
    }

    self.nextButton = Button:new{
        text = "Next ⏭",
        text_font_face = "cfont",
        text_font_size = 26,
        callback = function()
            self:onNext()
        end,
    }

    self.navButtonGroup = HorizontalGroup:new{
        align = "center",
        self.prevButton,
        HorizontalSpan:new{ width = Screen:scaleBySize(6) },
        self.playPauseButton,
        HorizontalSpan:new{ width = Screen:scaleBySize(6) },
        self.nextButton,
    }

    self.topGroup = VerticalGroup:new{
        align = "center",
        self.topBar,
        VerticalSpan:new{ width = Screen:scaleBySize(2) },
        self.titleWidget,
        VerticalSpan:new{ width = Screen:scaleBySize(2) },
        self.clockWidget,
        self.totalClockWidget,
    }

    self.bottomGroup = VerticalGroup:new{
        align = "center",
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
        self.navButtonGroup,
        VerticalSpan:new{ width = Screen:scaleBySize(4) },
        self.upcomingContainer,
    }

    self.mainGroup = VerticalGroup:new{
        align = "center",
        self.topGroup,
        self.bottomGroup,
    }

    self.centerContainer = CenterContainer:new{
        dimen = Geom:new{ x = 0, y = 0, w = self.width, h = self.height },
        self.mainGroup,
    }

    self.frame = FrameContainer:new{
        width = self.width,
        height = self.height,
        background = Blitbuffer.COLOR_WHITE,
        bordersize = 0,
        margin = 0,
        padding = 0,
        self.centerContainer,
    }

    self[1] = self.frame
end

function TabataTimerWidget:getUpcomingText()
    local text = "Upcoming exercises:\n"
    local count = 0
    for i = self.currentIndex + 1, #self.exercises do
        local ex = self.exercises[i]
        text = text .. " • " .. ex.name .. " (" .. ex.seconds .. "s)\n"
        count = count + 1
        if count >= 4 then
            if #self.exercises > i then
                text = text .. " • (+" .. (#self.exercises - i) .. " more exercises)\n"
            end
            break
        end
    end
    if count == 0 then
        text = text .. " • (Last exercise!)"
    end
    return text
end

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

function TabataTimerWidget:onPrev()
    if self.currentIndex > 1 then
        self.currentIndex = self.currentIndex - 1
    end
    self.timeLeft = self.exercises[self.currentIndex].seconds
    self:updateDisplay()
end

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

function TabataTimerWidget:updateDisplay()
    if not self.running then return end
    local currentEx = self.exercises[self.currentIndex]
    if currentEx then
        self.titleWidget:setText(string.format("Exercise %d/%d: %s", self.currentIndex, #self.exercises, currentEx.name))
    end
    self.clockWidget:setText(self:formatTime(self.timeLeft))
    self.totalClockWidget:setText("Total left: " .. self:formatTime(self:getTotalTimeLeft()))
    self.upcomingTextWidget:setText(self:getUpcomingText())
    self.topGroup:resetLayout()
    self.bottomGroup:resetLayout()
    self.mainGroup:resetLayout()
    UIManager:setDirty(self, "ui")
end

function TabataTimerWidget:scheduleTick()
    if not self.running or self.paused then return end
    self.tick_scheduled = true
    UIManager:scheduleIn(1, function()
        self.tick_scheduled = false
        if not self.running then return end
        if not self.paused then
            self.timeLeft = self.timeLeft - 1
            if self.timeLeft < 0 then
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

function TabataTimerWidget:showWorkoutsDialog()
    local files = self:getAvailableWorkouts()

    local buttons = {}
    for _, file in ipairs(files) do
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
                callback = function()
                    if self.workout_dialog then
                        UIManager:close(self.workout_dialog)
                        self.workout_dialog = nil
                    end
                    self:editWorkout(filepath, display_name)
                end,
            },
        })
    end
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

    local spacing1 = Screen:scaleBySize(6)
    local spacing2 = Screen:scaleBySize(8)
    local usedWidth = self.closeButton:getSize().w + self.workoutsButton:getSize().w + self.workoutLabelWidget:getSize().w + spacing1 + spacing2
    self.topBarTrailingSpan.width = math.max(0, math.floor(self.width * 0.94) - usedWidth)

    self.topBar:resetLayout()
    self.topGroup:resetLayout()
    self:updateDisplay()
end

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
    UIManager:close(self, "ui")
    return true
end

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
        },
    }
end

return TabataTimerPlugin
