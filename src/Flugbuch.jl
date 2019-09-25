module Flugbuch

import CSV
import SQLite
using LightGraphs: Graph, connected_components, add_edge!
using PrettyTables
using Dates
using ArgParse
using IniFile

abstract type Flighty end
const NumberedOld{T} = Tuple{Int, T}

struct Numbered{T}
	nr::Int
	value::T
end

include("flight.jl")
include("flight_group.jl")
include("flight_accumulator.jl")
include("util.jl")

export create, load, unload, prt, csv, help, n, p, expand, deadlines
export Date	# re-export

dbFilename = missing 		#::String
db = missing				#::SQLite.DB
selfNames = missing 		#::Vector{String}
bufferedFlighties = missing #::Vector{Numbered{<:Flighty}}

lastFrameBegin = missing
lastFrameEnd = missing

cErr = crayon"red"
cWarn = crayon"yellow"
cSucc = crayon"green"

function loadConfig(configFilename::String)
	if !isfile(configFilename)
		println(cWarn, "Konfigurationsdatei ~/.flugbuchrc nicht vorhanden.")
		return
	end

	conf = read(Inifile(), configFilename)

	s = get(conf, "", "mynames", "default")
	global selfNames = filter(x -> x != "", strip.(split(s, ";")))

	global dbFilename = get(conf, "", "defaultdb", missing)
end

function loadConfig()
	loadConfig(joinpath(homedir(), ".flugbuchrc"))
end

loadConfig()

function help()
	println()
	println("""Kommandos:
--------------------------------------------------------------------------------

 > create("foo.db")              Erstellt ein neues Flugbuch in der Datei
                                'foo.db' und öffnet es
 > load("foo.db")                Öffnet das Flugbuch in der Datei 'foo.db'
 > load()                        Öffnet das Standard-Flugbuch, das in der
                                 Konfigurationsdatei festgelegt ist
 > unload()                      Schließt das geöffnete Flugbuch
 > prt()                         Gibt das komplette Flugbuch aus
 > prt(10, 20)                   Gibt die Zeilen 10 bis 20 des Flugbuchs aus
 > prt(11)                       Gibt die Zeile 11 des Flugbuchs aus
 > csv("foo.csv")                Liest Flüge aus der CSV-Datei 'foo.csv' ein
 > help()                        Gibt diese Hilfe aus
 > n()                           Zeigt den nächsten Flug an
 > p()                           Zeigt den vorherigen Flug an
 > expand(34)                    Zeigt die in der Zeile 34 gruppierten Flüge
                                 einzeln an
 > deadlines()                   Zeigt an, ob die gesetzlichen Fristen zur Zeit
                                 erfüllt sind, und wann sie ablaufen werden


Zusatzparameter, die den meisten Funktionen mitgegeben werden können:
--------------------------------------------------------------------------------

 - beginNr = 10                  Beginne die Ausgabe mit Zeile 10
 - endNr = 50                    Beende die Ausgabe mit Zeile 50
 - beginDate = Date(2017,1,1)    Zeige nur Flüge am und nach dem 01.01.2017
 - endDate = Date(2019,2,1)      Zeige nur Flüge am und bis zum 01.02.2019
 - limitAircraft = 10            Kürze die Flugzeugtypen auf 10 Zeichen
 - limitPilots = 10              Kürze Pilot und Copilot auf 10 Zeichen
 - limitLocations = 10           Kürze Start- und Landeort auf 10 Zeichen
 - limitComments = 20            Kürze die Bemerkungen auf 10 Zeichen
 - frameGroups = true            Umrahme gruppierte Flüge
 - printSums= true               Gebe die Summen in der Fußzeile aus
""")
end

function deadlines()

end

function create(filename::String)
	if isdir(filename)
		println("Der angegebene Pfad '$filename' ist ein Verzeichnis.")
		return
	end
	if isfile(filename)
		println("Die Datei '$filename' ist bereits vorhanden.")
		return
	end

	global db = SQLite.DB(filename)

	SQLite.Query(db, "CREATE TABLE IF NOT EXISTS flights (
						id INTEGER PRIMARY KEY,
						nr INTEGER NOT NULL,
						callsign TEXT NULL,
						aircraftType TEXT NULL,
						pilot TEXT NOT NULL,
						copilot TEXT NULL,
						launch TEXT NOT NULL,
						date TEXT NOT NULL,
						departureTime TEXT NOT NULL,
						arrivalTime TEXT NOT NULL,
						numberOfLandings INTEGER NOT NULL default 1,
						departureLocation TEXT NULL,
						arrivalLocation TEXT NULL,
						dual BOOLEAN NOT NULL,
						instr BOOLEAN NOT NULL default false,
						comments TEXT NULL
						);")

	println(cSucc, "Flugbuch '$filename' erstellt und geöffnet.")
end

function load(filename::AbstractString)
	if !isfile(filename)
		println(cErr, "Datei '$filename' existiert nicht.")
		return
	end

	global db = SQLite.DB(filename)

	try
		SQLite.Query(db, "SELECT * FROM flights LIMIT 1");
	catch e
		println(cErr, "Fehler beim Lesen aus dem Flugbuch: $e")
		throw(e)
		db = missing
		return
	end

	println(cSucc, "Flugbuch '$filename' geöffnet.")
end

function load()
	if !ismissing(dbFilename)
		load(dbFilename)
	else
		println(cWarn, "Kein Standard-Flugbuch in der Konfigurationsdatei festgelegt.")
	end
end

function unload()
	if ismissing(db)
		println(cWarn, "Es war kein Flugbuch geladen.")
		return
	end

	global db = missing
	global lastFrameBegin = missing
	global lastFrameEnd = missing
	global bufferedFlighties = missing
	println(cSucc, "Flugbuch geschlossen.")
end

function prt(;
		beginDate = missing,
		endDate = missing,
		beginNr = missing,
		endNr = missing,
		kwargs...
	)

	if ismissing(bufferedFlighties)
		if !loadBuffer()
			return
		end
	end

	filteredFlighties = filter(bufferedFlighties) do f
		(ismissing(beginNr) || f.nr >= beginNr) &&
		(ismissing(endNr) || f.nr <= endNr) &&
		(ismissing(endDate) || date(f.value) <= endDate) &&
		(ismissing(beginDate) || date(f.value) >= beginDate)
	end

	if isempty(filteredFlighties)
	 	println("\nKeine Flüge entsprechen dem Filter.")
		global lastFrameBegin = missing
		global lastFrameEnd = missing
	 	return
	end

	last = filteredFlighties[end]
	allUpToLast = filter(f -> f.nr <= last.nr, bufferedFlighties)

	filteredAcc = FlightAccumulator([f.value for f in filteredFlighties])
	totalAcc = FlightAccumulator([f.value for f in allUpToLast])

	global lastFrameBegin = filteredFlighties[1].nr
	global lastFrameEnd = filteredFlighties[end].nr

	pretty_table(filteredFlighties, sums = [(filteredAcc, "Σ"), (totalAcc, "Σ (total)")]; kwargs...)
	nothing
end

function prt(beginNr::Int, endNr::Int; kwargs...)
	prt(beginNr=beginNr, endNr=endNr; kwargs...)
end

function prt(nr::Int; kwargs...)
	prt(beginNr=nr, endNr=nr; kwargs...)
end

function n(; kwargs...)
	if ismissing(lastFrameEnd)
		println(cWarn, "\nKein vorheriger Flug, dessen Nachfolger angezeigt werden kann.")
		return
	end
	prt(beginNr = lastFrameEnd+1, endNr = lastFrameEnd+1; kwargs...)
end

function p(; kwargs...)
	if ismissing(lastFrameBegin)
		println(cWarn, "\nKein vorheriger Flug, dessen Vorgänger angezeigt werden kann.")
		return
	end
	prt(beginNr = lastFrameBegin-1, endNr = lastFrameBegin-1; kwargs...)
end

function expand(nr::Int)

	if ismissing(bufferedFlighties)
		loadBuffer()
	end

	if nr < 1 || nr > length(bufferedFlighties)
		println(cErr, "\nUngültige Flugnummer $nr.")
		return
	end

	f = bufferedFlighties[nr]

	if isa(f.value, Flight)
		pretty_table(Numbered{<:Flighty}[f])
	else
		flights = f.value.flights
		numbered = Numbered{<:Flighty}[Numbered(i, flights[i]) for i in eachindex(flights)]
		acc = FlightAccumulator([flt for flt in flights])
		pretty_table(numbered, sums=[(acc, "Σ")])
	end
end

function loadBuffer()

	if ismissing(db)
		println(cErr, "Kein Flugbuch geladen.")
		return false
	end

	flights = fetchAllFlights(db)

	flightsByDate = Dict{Date, Vector{Flight}}()
	for f in flights
		if !haskey(flightsByDate, f.date)
			flightsByDate[f.date] = [f]
		else
			push!(flightsByDate[f.date], f)
		end
	end

	flighties = Flighty[]
	for (date, flights) in flightsByDate
		g = Graph(length(flights))

		for i in 1:length(flights)
			for j in i+1:length(flights)
				!groupable(flights[i], flights[j]) || add_edge!(g, i, j)
			end
		end

		for component in connected_components(g)
			groupedFlights = flights[component]

			if length(groupedFlights) == 1
				push!(flighties, groupedFlights[1])
			else
				push!(flighties, FlightGroup(groupedFlights))
			end
		end
	end

	sort!(flighties)
	flighties = Numbered{<:Flighty}[Numbered(i, flighties[i]) for i in eachindex(flighties)]

	global bufferedFlighties = flighties
	return true
end

function csv(fileName::String; autoconfirm = false, kwargs...)

	if ismissing(db)
		println(cErr, "Kein Flugbuch geladen.")
		return
	end

	if ismissing(selfNames)
		println(cErr, "Eigener Name nicht festgelegt.")
		return
	end

	csv = CSV.File(fileName, footerskip=1, normalizenames=true, silencewarnings=true, delim = ";")

	flights = Flight[]
	ignoredFlights = Flight[]
	overlappingFlights = Flight[]
	i = 1

	for row in csv
		try
			(f, forMe) = Flight(row)
			if forMe
				if  sum(overlap.(Ref(f), flights)) > 0
					push!(overlappingFlights, f)
				else
					f.nr = i
					i += 1
					push!(flights, f)
				end
			else
				push!(ignoredFlights, f)
			end
		catch e
			println("error: ", e)
			println("aborting!")
			throw(e)
			return
		end
	end

	if !isempty(ignoredFlights)
		println("\n$(length(ignoredFlights)) ignorierte Flüge (nicht für mein Flugbuch): ")
		pretty_table(ignoredFlights; kwargs...)
	end

	if !isempty(overlappingFlights)
		println("\n$(length(overlappingFlights)) ignorierte Flüge (in den Importdaten überlappend): ")
		pretty_table(overlappingFlights; kwargs...)
	end

	presentFlights = fetchAllFlights(db)

	overlappingFlights = Flight[]
	insertableFlights = Flight[]

	for f in flights
		if sum(overlap.(Ref(f), presentFlights)) > 0
			push!(overlappingFlights, f)
		else
			push!(insertableFlights, f)
		end
	end

	if !isempty(overlappingFlights)
		println("\n$(length(overlappingFlights)) ignorierte Flüge (mit bestehenden Flügen überlappend): ")
		pretty_table(overlappingFlights; kwargs...)
	else
		println("\nKeine Flüge überlappen mit bestehenden Flügen.")
	end

	if !isempty(insertableFlights)
		println("\n$(length(insertableFlights)) Flüge für den Import:")
		pretty_table(insertableFlights; kwargs...)
	else
		println("\nKeine Flüge zu importieren.")
		return
	end

	if !autoconfirm
		println("\nÜberprüfen Sie die obigen Angaben und geben Sie 'ja' ein, wenn der Import durchgeführt werden soll.")
		userInput = readline()

		if userInput != "ja"
			println("Vorgang abgebrochen.")
			return
		end
	end

	#invalidate buffer
	global bufferedFlighties = missing

	stmt = SQLite.Stmt(db, "INSERT INTO flights (nr, callsign, aircraftType, pilot, copilot, launch, date, departureTime, arrivalTime, departureLocation, arrivalLocation, dual, instr, comments) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14)")

	for f in insertableFlights
		SQLite.bind!(stmt, 1, string(f.nr))
		SQLite.bind!(stmt, 2, f.callsign)
		SQLite.bind!(stmt, 3, f.aircraftType)
		SQLite.bind!(stmt, 4, f.pilot)
		SQLite.bind!(stmt, 5, f.copilot)
		SQLite.bind!(stmt, 6, convert(String, f.launch))
		SQLite.bind!(stmt, 7, Dates.format(f.date, "dd.mm.yyyy"))
		SQLite.bind!(stmt, 8, Dates.format(f.departureTime, "HH:MM"))
		SQLite.bind!(stmt, 9, Dates.format(f.arrivalTime, "HH:MM"))
		SQLite.bind!(stmt, 10, f.departureLocation)
		SQLite.bind!(stmt, 11, f.arrivalLocation)
		SQLite.bind!(stmt, 12, f.dual ? "1" : "0")
		SQLite.bind!(stmt, 13, f.instr ? "1" : "0")
		SQLite.bind!(stmt, 14, f.comments)
		SQLite.execute!(stmt)
	end

	println("\nFlüge importiert.")
	nothing
end

function pretty_table(flights::Vector{<:Flighty}; kwargs...)
	tuples = Numbered{<:Flighty}[Numbered(i, flights[i]) for i in eachindex(flights)]
	pretty_table(tuples; kwargs...)
end

function pretty_table(
	flights::Vector{Numbered{T} where T <: Flighty};
	sums::Vector{Tuple{FlightAccumulator, String}} = Tuple{FlightAccumulator, String}[],
	limitAircraft::Int = -1,
	limitPilots::Int = -1,
	limitLocations::Int = -1,
	limitComments::Int = -1,
	frameGroups::Bool = true,
	printSums::Bool = true)

	tabRows = [toPrettyTableRow(f) for f in flights]

	hlines = isempty(sums) ? Int[] : [length(tabRows)]
	if frameGroups
		for i in eachindex(flights)
			if isa(flights[i].value, FlightGroup)
				push!(hlines, i)
				push!(hlines, i-1)
			end
		end
	end

	if printSums
		sumRows = collect(length(tabRows)+1:length(tabRows) + length(sums))
		for (acc, name) in sums
			push!(tabRows, toPrettyTableRow(acc,  name))
		end
	else
		sumRows = []
	end

	tab = permutedims(hcat(tabRows...))

	sumCrayon = crayon"negative bold"
	dualCrayon = crayon"light_blue"
	picCrayon = crayon"light_green"
	instrCrayon = crayon"magenta"
	groupCrayon = crayon"yellow negative"

	columnFilter = (data, i) ->
		!(i in 3:4 && limitAircraft == 0) &&
		!(i in 5:6 && limitPilots == 0) &&
		!(i in 8:9 && limitLocations == 0) &&
		!(i == 18 && limitComments == 0)

	formatter = Dict(
		4 => (value, i) -> ellipsis(value, limitAircraft),
		5 => (value, i) -> ellipsis(value, limitPilots),
		6 => (value, i) -> ellipsis(value, limitPilots),
		8 => (value, i) -> ellipsis(value, limitLocations),
		9 => (value, i) -> ellipsis(value, limitLocations),
		18 => (value, i) -> ellipsis(value, limitComments),
	)

	sumHighlighter = Highlighter(
		f = (data, i, j) -> i in [sumRows] && j in [1,13,18],
		crayon = sumCrayon
	)

	dualHighlighter = Highlighter(
		f = (data, i, j) -> (j in 13:14 && i <= length(flights) && dual(flights[i].value)) || j == 16,
		crayon = dualCrayon
	)

	picHighlighter = Highlighter(
		f = (data, i, j) -> (j in 13:14 && i <= length(flights) && !dual(flights[i].value)) || j == 15,
		crayon = picCrayon
	)

	instrHighlighter = Highlighter(
		f = (data, i, j) -> j == 17,
		crayon = instrCrayon
	)

	picSumHighlighter = Highlighter(
		f = (data, i, j) -> j == 14 && i in sumRows,
		crayon = sumCrayon * picCrayon
	)

	dualSumHighlighter = Highlighter(
		f = (data, i, j) -> j == 15 && i in sumRows,
		crayon = sumCrayon * dualCrayon
	)

	instrSumHighlighter = Highlighter(
		f = (data, i, j) -> j == 16 && i in sumRows,
		crayon = sumCrayon * instrCrayon
	)

	groupHighlighter = Highlighter(
		f = (data, i, j) -> j == 1 && i <= length(flights) && isa(flights[i].value, FlightGroup),
		crayon = groupCrayon
	)

	println()
	PrettyTables.pretty_table(
		tab,
		toPrettyTableHeader(),
		unicode_rounded,
		crop = :horizontal,
		hlines = hlines,
		formatter = formatter,
		alignment = :l,
		linebreaks = true,
		highlighters = (
			sumHighlighter,
			dualSumHighlighter,
			dualHighlighter,
			instrSumHighlighter,
			instrHighlighter,
			picSumHighlighter,
			picHighlighter,
			groupHighlighter
		),
		filters_col = (columnFilter,)
	)
end

#
# main
#

# Base.@ccallable function julia_main(ARGS::Vector{String})::Cint
#     main(join(ARGS, " "))
#     return 0
# end
#
# function main(argstr)
# 	args = split(argstr)
#
# 	s = ArgParseSettings("Flugbuch",
#                          version = "Version 1.0",
#                          add_version = true,
# 						 prog = "Flugbuch.jl")
#
# 	@add_arg_table s begin
#         "--from", "-f"
# 			help = "Sichtbare Flüge einschränken anhand Datum oder Flugnr. (beides inklusive) für den Beginn des sichtbaren Bereichs"
#         "--to", "-t"
# 			help = "Sichtbare Flüge einschränken anhand Datum oder Flugnr. (beides inklusive) für das Ende des sichtbaren Bereichs"
#     end
#
#     parsed_args = parse_args(args, s)
# 	function_args = Dict()
#
# 	from_fail, to_fail = false, false
#
# 	if haskey(parsed_args, "from") && parsed_args["from"] != nothing
# 		from = parsed_args["from"]
# 		from_fail = false
#
# 		if tryparse(Int, from) != nothing
# 			function_args[:beginNr] = parse(Int, from)
# 		else
# 			if occursin(r"^[0-9]{1,2}\.[0-9]{1,2}\.[0-9]{1,4}$", parsed_args["from"])
# 				try
# 					function_args[:beginDate] = Date(parsed_args["from"], DateFormat("d.m.Y"))
# 				catch
# 					from_fail = true
# 				end
# 			else
# 				from_fail = true
# 			end
# 		end
# 	end
#
# 	if haskey(parsed_args, "to") && parsed_args["to"] != nothing
# 		to = parsed_args["to"]
# 		to_fail = false
#
# 		if tryparse(Int, to) != nothing
# 			function_args[:endNr] = parse(Int, to)
# 		else
# 			if occursin(r"^[0-9]{1,2}\.[0-9]{1,2}\.[0-9]{1,4}$", parsed_args["to"])
# 				try
# 					function_args[:endDate] = Date(parsed_args["to"], DateFormat("d.m.Y"))
# 				catch
# 					to_fail = true
# 				end
# 			else
# 				to_fail = true
# 			end
# 		end
#
# 	end
#
#
# 	!from_fail || print("Das Argument --from ist im falschen Format (es wird eine Zahl oder ein Datum erwartet) und wird ignoriert.")
# 	!to_fail || print("Das Argument --to ist im falschen Format (es wird eine Zahl oder ein Datum erwartet) und wird ignoriert.")
#
# 	println("helo")
# end

end
