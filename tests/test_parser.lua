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

print("All tests passed! Parsed intervals from workouts/tabata.csv:")
for i, item in ipairs(workouts) do
    print(string.format("  %d. %s - %d seconds", i, item.name, item.seconds))
end
