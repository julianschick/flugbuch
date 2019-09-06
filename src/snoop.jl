import Flugbuch
using Dates

Flugbuch.create("snoop.db")
Flugbuch.csv("examples/import.csv")
Flugbuch.prt()
Flugbuch.prt(beginNr=2, endNr=2)
Flugbuch.prt(beginDate=Date(2018,1,1), endDate=Date(2019,1,1))
rm("snoop.db")
