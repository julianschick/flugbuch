module Flugbuch

import CSV
import SQLite
using LightGraphs: Graph, connected_components, add_edge!
using Dates
using ArgParse
using PrettyTables

abstract type Flighty end
const Numbered{T} = Tuple{Int, T}

include("flight.jl")
include("flight_group.jl")
include("flight_accumulator.jl")
include("util.jl")

export flightbook, main, csvImport

Base.@ccallable function julia_main(ARGS::Vector{String})::Cint
	main(join(ARGS, " "))
	return 0
end

function main(argstr)
	args = split(argstr)

	s = ArgParseSettings("Flugbuch",
                         version = "Version 1.0",
                         add_version = true,
						 prog = "flugbuch.jl")

	@add_arg_table s begin
        "--from", "-f"
			help = "Sichtbare Flüge einschränken anhand Datum oder Flugnr. (beides inklusive) für den Beginn des sichtbaren Bereichs"
        "--to", "-t"
			help = "Sichtbare Flüge einschränken anhand Datum oder Flugnr. (beides inklusive) für das Ende des sichtbaren Bereichs"
    end

    parsed_args = parse_args(args, s)
	function_args = Dict()

	from_fail, to_fail = false, false

	if haskey(parsed_args, "from") && parsed_args["from"] != nothing
		from = parsed_args["from"]
		from_fail = false

		if tryparse(Int, from) != nothing
			function_args[:beginNr] = parse(Int, from)
		else
			if occursin(r"^[0-9]{1,2}\.[0-9]{1,2}\.[0-9]{1,4}$", parsed_args["from"])
				try
					function_args[:beginDate] = Date(parsed_args["from"], DateFormat("d.m.Y"))
				catch
					from_fail = true
				end
			else
				from_fail = true
			end
		end
	end

	if haskey(parsed_args, "to") && parsed_args["to"] != nothing
		to = parsed_args["to"]
		to_fail = false

		if tryparse(Int, to) != nothing
			function_args[:endNr] = parse(Int, to)
		else
			if occursin(r"^[0-9]{1,2}\.[0-9]{1,2}\.[0-9]{1,4}$", parsed_args["to"])
				try
					function_args[:endDate] = Date(parsed_args["to"], DateFormat("d.m.Y"))
				catch
					to_fail = true
				end
			else
				to_fail = true
			end
		end

	end


	!from_fail || print("Das Argument --from ist im falschen Format (es wird eine Zahl oder ein Datum erwartet) und wird ignoriert.")
	!to_fail || print("Das Argument --to ist im falschen Format (es wird eine Zahl oder ein Datum erwartet) und wird ignoriert.")

	flightbook(;function_args...)
end

function flightbook(;
		beginDate = missing,
		endDate = missing,
		beginNr = missing,
		endNr = missing,
		kwargs...
	)

	db = SQLite.DB("data.db")
	flights = fetchAllFlights(db)

	# filteredFlights = filter(flights) do f
	#
	# end
	#
	# if isempty(filteredFlights)
	# 	println("\nKeine Flüge entsprechen dem Filter.")
	# 	return
	# end

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

		#pretty_tablee(flights)
		#println(connected_components(g))

		#groupedFlights = FlightGroup[]
		for component in connected_components(g)
			flightsInComponent = flights[component]
			push!(flighties, FlightGroup(flightsInComponent))
		end

		#flighties = [flighties; groupedFlights]
		#acc = FlightAccumulator(groupedFlights)
		#pretty_tablee(groupedFlights, sums = [(acc, "Σ")])
	end



	#pretty_tablee(filteredFlights, sums = [(filteredAcc, "Σ"), (totalAcc, "Σ (total)")]; kwargs...)
	sort!(flighties)
	flighties = [(i, flighties[i]) for i in eachindex(flighties)]

	filteredFlighties = filter(flighties) do (nr, f)
		(ismissing(beginNr) || nr >= beginNr) &&
		(ismissing(endNr) || nr <= endNr) &&
		(ismissing(endDate) || date(f) <= endDate) &&
		(ismissing(beginDate) || date(f) >= beginDate)
	end

	(lastFlightNr, lastFlight) = filteredFlighties[end]
	allUpToLast = filter(t -> t[1] <= lastFlightNr, flighties)

	filteredAcc = FlightAccumulator([t[2] for t in filteredFlighties])
	totalAcc = FlightAccumulator([t[2] for t in allUpToLast])


	pretty_tablee(filteredFlighties, sums = [(filteredAcc, "Σ"), (totalAcc, "Σ (total)")]; kwargs...)
	nothing
end

function csvImport(fileName::String)
	csv = CSV.File(fileName, footerskip=1, normalizenames=true, silencewarnings=true)
	flights = Flight[]
	ignoredFlights = Flight[]
	overlappingFlights = Flight[]
	i = 1

	for row in csv
		try
			(f, forMe) = Flight(row, "Schick, Julian")
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
		pretty_tablee(ignoredFlights)
	end

	if !isempty(overlappingFlights)
		println("\n$(length(overlappingFlights)) ignorierte Flüge (in den Importdaten überlappend): ")
		pretty_tablee(overlappingFlights)
	end

	db = SQLite.DB("data.db")
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
		pretty_tablee(overlappingFlights)
	else
		println("\nKeine Flüge überlappen mit bestehenden Flügen.")
	end

	if !isempty(insertableFlights)
		println("\n$(length(insertableFlights)) Flüge für den Import:")
		pretty_tablee(insertableFlights)
	else
		println("\nKeine Flüge zu importieren.")
	end

	println("\nÜberprüfen Sie die obigen Angaben und geben Sie 'ja' ein, wenn der Import durchgeführt werden soll.")
	userInput = readline()

	if userInput != "ja"
		println("Vorgang abgebrochen.")
		return
	end

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
end

function pretty_tablee(
	flights::Vector{Tuple{Int,T}} where T <: Flighty;
	sums::Vector{Tuple{FlightAccumulator, String}} = Tuple{FlightAccumulator, String}[],
	limitAircraft::Int = -1,
	limitPilots::Int = -1,
	limitLocations::Int = -1,
	limitComments::Int = -1
)

	tabRows = [toPrettyTableRow(f) for f in flights]

	# headerRepeat = max(headerRepeat, 10)
	# for i in 1:length(tabRows)÷headerRepeat
	# 	ii = i*20 + (i-1)
	# 	if length(tabRows) - ii > headerRepeat+3
	# 		insert!(tabRows, ii, toPrettyTableHeader())
	# 	end
	# end


	hlines = isempty(sums) ? Int[] : [length(tabRows)]
	sumRows = collect(length(tabRows)+1:length(tabRows) + length(sums))

	for (acc, name) in sums
		push!(tabRows, toPrettyTableRow(acc,  name))
	end

	tab = permutedims(hcat(tabRows...))

	sumCrayon = crayon"negative bold"
	dualCrayon = crayon"light_blue"
	picCrayon = crayon"light_green"
	instrCrayon = crayon"magenta"

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
		f = (data, i, j) -> (j in 13:14 && i <= length(flights) && dual(flights[i][2])) || j == 16,
		crayon = dualCrayon
	)

	picHighlighter = Highlighter(
		f = (data, i, j) -> (j in 13:14 && i <= length(flights) && !dual(flights[i][2])) || j == 15,
		crayon = picCrayon
	)

	instrHighlighter = Highlighter(
		f = (data, i, j) -> j == 17,
		crayon = instrCrayon
	)

	picSumHighlighter = Highlighter(
		f = (data, i, j) -> j == 15 && i in sumRows,
		crayon = sumCrayon * picCrayon
	)

	dualSumHighlighter = Highlighter(
		f = (data, i, j) -> j == 16 && i in sumRows,
		crayon = sumCrayon * dualCrayon
	)

	instrSumHighlighter = Highlighter(
		f = (data, i, j) -> j == 17 && i in sumRows,
		crayon = sumCrayon * instrCrayon
	)

	println()
	pretty_table(
		tab,
		toPrettyTableHeader(),
		unicode_rounded,
		crop = :horizontal,
		hlines = hlines,
		formatter = formatter,
		alignment = :l,
		linebreaks = true,
		highlighters = (sumHighlighter, dualSumHighlighter, dualHighlighter, instrSumHighlighter, instrHighlighter, picSumHighlighter, picHighlighter),
		filters_col = (columnFilter,)
	)

end


end
