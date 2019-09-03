include("flight_enums.jl")

using Dates
using CSV
using Printf
import SQLite

mutable struct Flight
	id::UInt
	nr::UInt
	callsign::String
	aircraftType::String
	pilot::String
	copilot::Union{Missing, String}
	launch::Launch
	date::Date
	departureTime::Time
	arrivalTime::Time
	numberOfLandings::UInt
	departureLocation::String
	arrivalLocation::String

	comments::Union{Missing, String}

	dual::Bool
	instr::Bool
end

function toPrettyTableRow(f::Flight)

	flags = (f.dual ? "D" : "P") * (f.instr ? "I" : "")
	timeString = asString(minutes(f))

	return [
		f.nr,
		Dates.format(f.date, "dd.mm.yyyy"),
		f.callsign,
		f.aircraftType,
		f.pilot,
		!ismissing(f.copilot) ? f.copilot : "-",
		convert(String, f.launch),
		f.departureLocation,
		f.arrivalLocation,
		Dates.format(f.departureTime, "HH:MM"),
		Dates.format(f.departureTime, "HH:MM"),
		timeString,
		flags,
		f.dual ? "" : timeString,
		f.dual ? timeString : "",
		f.instr ? timeString : "",
		!ismissing(f.comments) ? f.comments : ""
	]
end

function toPrettyTableHeader()
	return [
		"Nr.", "Datum", "Reg.", "Typ",
		"Pilot", "Co", "S",
		"Von", "Nach", "Start", "Land",
		"Zeit", "~", "PIC", "DUAL", "INSTR",
		"Bemerkungen"
	]
end


getNr(f::Flight) = f.nr
getCallsign(f::Flight) = f.callsign
getAircraftType(f::Flight) = f.aircraftType
getPilot(f::Flight) = f.pilot
getCopilot(f::Flight) = f.copilot
getLaunch(f::Flight) = f.launch
getDate(f::Flight) = f.date
getDepartureTime(f::Flight) = f.departureTime
getArrivalTime(f::Flight) = f.arrivalTime
getNumberOfLanding(f::Flight) = f.numberOfLandings
getDepartureLocation(f::Flight) = f.departureLocation
getArrivalLocation(f::Flight) = f.arrivalLocation
getComments(f::Flight) = f.comments
isDual(f::Flight) = f.dual
isInstr(f::Flight) = f.instr

function Flight(row::NamedTuple)
	Flight(
		row.id,
		0,
		row.callsign,
		row.aircraftType,
		row.pilot,
		row.copilot,
		row.launch,
		Date(row.date, DateFormat("d.m.y")),
		Time(row.departureTime),
		Time(row.arrivalTime),
		row.numberOfLandings,
		row.departureLocation,
		row.arrivalLocation,
		row.comments,
		row.dual,
		row.instr
	)
end

pm(fun::Function, x) = !ismissing(x) ? fun(x) : missing

function Flight(row::CSV.Row, selfName::String)
	inMyFlightbook = true
	!ismissing(row.Datum)		|| throw(ArgumentError("Datum nicht gegeben."))
	!ismissing(row.Lfz_) 		|| throw(ArgumentError("Kennzeichen nicht gegeben."))
	!ismissing(row.Lfz_Muster) 	|| throw(ArgumentError("Flugzeugtyp nicht gegeben."))
	!ismissing(row.Pilot)		|| throw(ArgumentError("Pilot nicht gegeben."))
	!ismissing(row.S_Art)		|| throw(ArgumentError("Startart nicht gegeben."))
	!ismissing(row.Start)		|| throw(ArgumentError("Startzeit nicht gegeben."))
	!ismissing(row.Landung)		|| throw(ArgumentError("Landezeit nicht gegeben."))
	!ismissing(row.Landungen)	|| throw(ArgumentError("Anzahl Landungen nicht gegeben."))
	!ismissing(row.Startort)	|| throw(ArgumentError("Startort nicht gegeben."))
	!ismissing(row.Landeort)	|| throw(ArgumentError("Landeort nicht gegeben."))
	!ismissing(row.Flugart)		|| throw(ArgumentError("Flugart nicht gegeben."))

	flightType = 	pm(strip, row.Flugart)
	pilotName = 	strip(row.Pilot)
	copilotName =	pm(strip, row.Begleiter_FI)

	aircraftType = 	strip(row.Lfz_Muster)
	typeNormalizations = [
		("GROB G 103 \"TWIN II\"", "Twin II"),
		("GROB G 103 C \"TWIN III\"", "Twin III"),
		("TWIN ASTIR TRAINER", "Twin I")
	]
	for (oldType, newType) in typeNormalizations
		if occursin(oldType, aircraftType)
			aircraftType = newType
		end
	end

	if isequal(pilotName, selfName)
		pilot = true
	elseif isequal(copilotName, selfName)
		pilot = false
	else
		throw(ArgumentError("Eigener Name weder im Feld 'Pilot' noch im Feld 'Copilot' gefunden."))
	end

	!ismissing(flightType) || throw(ArgumentError("Flugart nicht gegeben."))
	if !in(flightType, ["S", "N", "X", "G"])
		throw(ArgumentError("Ungültige Flugart '$flightType' vorgefunden."))
	end

	if !pilot
		# If copilot and training flight, then I was flight instructor
		if flightType == "S"
			instr = true
			dual = false
		# If copilot and no training flight, then not for my flightbook
		else
			instr = false
			dual = false
			inMyFlightbook = false
		end
	end

	if pilot
		# If pilot, then I was PIC or, if it is a training flight,
		# dual pilot (being instructed)
		instr = false
		dual = flightType == "S"
	end

	# If I was flight instructor or I was dual pilot (being instructed),
	# then pilot an copilot have to be swapped (compared to the usual
	# records made for the airfield)
	if (dual && pilot) || instr
		pilotName, copilotName = copilotName, pilotName
	end

	(
		Flight(
			0,
			0,
			row.Lfz_,
			aircraftType,
			pilotName,
			copilotName,
			Launch(row.S_Art),
			Date(row.Datum, DateFormat("d.m.y")),
			Time(row.Start),
			Time(row.Landung),
			row.Landungen,
			row.Startort,
			row.Landeort,
			row.Bemerkung,
			dual,
			instr
		), inMyFlightbook
	)

end

function Base.isless(a::Flight, b::Flight)
 	if a.date < b.date
		return true
	elseif a.date > b.date
		return false
	else
		return a.departureTime < b.departureTime
	end
end

function overlap(a::Flight, b::Flight)
	a.date == b.date &&
	a.arrivalTime > b.departureTime &&
	b.arrivalTime > a.departureTime
end

function fetchAllFlights(db::SQLite.DB)
	q = SQLite.Query(db, "SELECT * FROM flights")
	flights = [Flight(row) for row in q]

	sort!(flights)
	for i in 1:length(flights)
		flights[i].nr = i
	end

	return flights
end

minutes(f::Flight)::Dates.Minute = convert(Dates.Minute, f.arrivalTime - f.departureTime)

function asString(m::Dates.Minute)
	minutes = m.value % 60
	hours = m.value ÷ 60
	@sprintf("%02d:%02d", hours, minutes)
end

# function printFlightHeader(aa::AutoAlign; showLocation=true, showComment=true)
# 	print(aa, "Nr.")
# 	print(aa, " ", "Datum")
# 	print(aa, "  ", "Reg.")
# 	print(aa, " ", "Typ")
# 	print(aa, " ", "S")
#
# 	print(aa, "  ", "Pilot")
# 	print(aa, "  ", "Co")
#
# 	if showLocation
# 		print(aa, "  ", "Von")
# 		print(aa, " ", "Nach")
# 	end
#
# 	print(aa, "  ", "Start")
# 	print(aa, "\u2E17", "Land.")
#
# 	print(aa, "  ", "Zeit")
#
# 	print(aa, " ", " ")
# 	print(aa, " ", "PIC")
# 	print(aa, " ", "DUAL")
# 	print(aa, " ", "INSTR")
#
# 	!showComment || print(aa, "  ", "Bemerkungen")
# 	println(aa)
# end

# function Base.print(aa::AutoAlign, f::Flight; showLocation=true, showComment=true)
# 	print(aa, f.nr)
# 	print(aa, " ", Dates.format(f.date, "dd.mm.yyyy"))
# 	print(aa, " ", f.callsign)
# 	print(aa, " ", f.aircraftType)
# 	print(aa, " ", convert(String, f.launch))
#
# 	print(aa, "  ", f.pilot)
# 	if ismissing(f.copilot)
# 		print(aa, "  ", "-")
# 	else
# 		print(aa, "  ", f.copilot)
# 	end
#
# 	if showLocation
# 		print(aa, "  ", f.departureLocation)
# 		print(aa, " ", f.arrivalLocation)
# 	end
#
# 	print(aa, "  ", Dates.format(f.departureTime, "HH:MM"))
# 	print(aa, "\u2E17", Dates.format(f.arrivalTime, "HH:MM"))
#
# 	timeString = asString(minutes(f))
# 	print(aa, "  ", timeString)
#
# 	flags = f.dual ? "D" : "P"
# 	flags *= f.instr ? "I" : ""
# 	print(aa, " ", flags)
#
# 	if f.dual
# 		print(aa, " ", " ")
# 		print(aa, " ", timeString)
# 	else
# 		print(aa, " ", timeString)
# 		print(aa, " ", " ")
# 	end
#
# 	if (f.instr)
# 		print(aa, " ", timeString)
# 	else
# 		print(aa, " ", " ")
# 	end
#
# 	if showComment
# 		print(aa, "  ", !ismissing(f.comments) ? f.comments : "")
# 	end
#
# 	println(aa)
# end
