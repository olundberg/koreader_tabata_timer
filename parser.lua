local Parser = {}

function Parser.readCSV(filepath)
    -- If no filepath is passed, default to workouts/tabata.csv relative to parser.lua
    if not filepath then
        local str = debug.getinfo(1, "S").source:match("@(.+)")
        local dir = str and str:match("(.*/)") or "./"
        filepath = dir .. "workouts/tabata.csv"
    end
    
    local workouts = {}
    local file, err = io.open(filepath, "r")
    if not file then
        return nil, "Could not find or open file: " .. tostring(filepath) .. " (" .. tostring(err) .. ")"
    end
    
    for line in file:lines() do
        line = line:gsub("^%s*(.-)%s*$", "%1")
        if line ~= "" then
            local exercise, seconds = line:match("^([^,]+),%s*(%d+)$")
            if exercise and seconds then
                table.insert(workouts, {name = exercise, seconds = tonumber(seconds)})
            end
        end
    end
    file:close()
    return workouts
end

return Parser
