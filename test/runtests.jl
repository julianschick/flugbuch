import Flugbuch

using Dates

# in case last tear down did not work
if isfile("runtest.db")
    rum("runtest.db")
end

Flugbuch.loadConfig("examples/flugbuchrc")
Flugbuch.create("runtest.db")
Flugbuch.csv("examples/import.csv", autoconfirm = true)
Flugbuch.prt()
Flugbuch.prt(beginNr=2, endNr=2)
Flugbuch.prt(beginDate=Date(2018,1,1), endDate=Date(2019,1,1))
Flugbuch.unload()

rm("runtest.db")
