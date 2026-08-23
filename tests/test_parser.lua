local Parser = require("parser")

print("Running unit tests for Tabata parser...")

-- Test reading workouts/tabata.csv
local workouts, err = Parser.readCSV("workouts/tabata.csv")

assert(workouts ~= nil, "Test failed: Could not read file (" .. tostring(err) .. ")")
assert(#workouts > 3, "Test failed: Too few rows parsed.")
assert(workouts[1].name == "Plank", "Test failed: First exercise should be Plank.")
assert(workouts[1].seconds == 30, "Test failed: Plank duration should be 30 seconds.")

-- Test reading workouts/example.csv
local example_workouts, example_err = Parser.readCSV("workouts/example.csv")
assert(#example_workouts > 0, "Test failed: example.csv is empty")

-- Test reading a CSV with blank lines, comments, and whitespace
local tmp_path = "workouts/test_blank_lines_temp.csv"
local tmp_file = io.open(tmp_path, "w")
tmp_file:write("\n\n# Header comment\nPlank, 30\n   \n\t\nRest, 10\n\n\nPush-ups,45\n\n")
tmp_file:close()

local blank_test_workouts, blank_test_err = Parser.readCSV(tmp_path)
os.remove(tmp_path)

assert(blank_test_workouts ~= nil, "Test failed: Could not read blank lines test CSV (" .. tostring(blank_test_err) .. ")")
assert(#blank_test_workouts == 3, "Test failed: Expected exactly 3 exercises, got " .. tostring(#blank_test_workouts))
assert(blank_test_workouts[1].name == "Plank" and blank_test_workouts[1].seconds == 30, "Test failed: Plank parsed incorrectly")
assert(blank_test_workouts[2].name == "Rest" and blank_test_workouts[2].seconds == 10, "Test failed: Rest parsed incorrectly")
assert(blank_test_workouts[3].name == "Push-ups" and blank_test_workouts[3].seconds == 45, "Test failed: Push-ups parsed incorrectly")

print("All tests passed! Parsed intervals from workouts/tabata.csv:")
for i, item in ipairs(workouts) do
    print(string.format("  %d. %s - %d seconds", i, item.name, item.seconds))
end
