import Flugbuch

using Dates

exampleDir = @__DIR__

# in case last tear down did not work
if isfile(joinpath(exampleDir, "runtest.db"))
    rm(joinpath(exampleDir, "runtest.db"))
end

Flugbuch.loadConfig(joinpath(exampleDir, "examples", "flugbuchrc"))
Flugbuch.create(joinpath(exampleDir, "runtest.db"))
Flugbuch.csv(joinpath(exampleDir, "examples", "import.csv"), autoconfirm = true)
Flugbuch.prt()
Flugbuch.prt(beginNr=2, endNr=2)
Flugbuch.prt(beginDate=Date(2018,1,1), endDate=Date(2019,1,1))
Flugbuch.unload()

rm(joinpath(exampleDir, "runtest.db"))
