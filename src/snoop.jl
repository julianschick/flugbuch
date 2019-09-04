import Flugbuch
using Dates

Flugbuch.createFb("snoop.db")
Flugbuch.importFb("examples/import.csv")
Flugbuch.printFb()
Flugbuch.printFb(beginNr=2, endNr=2)
Flugbuch.printFb(beginDate=Date(2018,1,1), endDate=Date(2019,1,1))
