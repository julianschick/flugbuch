
struct FlightGroup <: Flighty
    flights::Vector{Flight}

	function FlightGroup(x::Vector{Flight})
		if isempty(x)
			throw(ArgumentError("Flight group must not be empty"))
		end
		new(x)
	end
end

function groupable_(a::Flight, b::Flight)
    return a.date == b.date &&
           a.pilot == b.pilot &&
           a.instr && !a.dual &&
           b.instr && !b.dual &&
           a.launch == b.launch &&
           a.departureLocation == b.departureLocation &&
           a.arrivalLocation == b.arrivalLocation &&
           a.callsign == b.callsign
end

function groupable(a::Flight, b::Flight)
    groupable_(a, b) &&
    (convert(Minute, abs(a.arrivalTime - b.departureTime)).value <= 30 ||
     convert(Minute, abs(a.departureTime - b.arrivalTime)).value <= 30)
end

function Base.isless(a::Flighty, b::Flighty)
 	if date(a) < date(b)
		return true
	elseif date(a) > date(b)
		return false
	else
		return departureTime(a) < departureTime(b)
	end
end

representingFlight(f::Flight)::Flight = f
representingFlight(g::FlightGroup)::Flight = g.flights[1]

copilot(f::Flight) = f.copilot
function copilot(g::FlightGroup)
	copilots = [f.copilot for f in g.flights] |> skipmissing |> unique
	isempty(copilots) ? missing : join(copilots, "\n")
end

date(f::Flight) = f.date
date(g::FlightGroup) = representingFlight(g).date

departureTime(f::Flight) = f.departureTime
departureTime(g::FlightGroup) = minimum([f.departureTime for f in g.flights])
arrivalTime(f::Flight) = f.arrivalTime
arrivalTime(g::FlightGroup) = maximum([f.arrivalTime for f in g.flights])

minutes(f::Flight)::Dates.Minute = convert(Dates.Minute, f.arrivalTime - f.departureTime)
minutes(g::FlightGroup)::Dates.Minute = sum(minutes.(g.flights))

numberOfLandings(f::Flight) = f.numberOfLandings
numberOfLandings(g::FlightGroup) = sum([f.numberOfLandings for f in g.flights])

dual(f::Flight) = f.dual
dual(g::FlightGroup) = representingFlight(g).dual

instr(f::Flight) = f.instr
instr(g::FlightGroup) = representingFlight(g).instr

comments(f::Flight) = f.comments
comments(g::FlightGroup) = join(skipmissing([f.comments for f in g.flights]), ", ")

function toPrettyTableRow(nfy::Numbered{<:Flighty})
	row = toPrettyTableRow(nfy.value)
	row[1] = nfy.nr
	return row
end

function toPrettyTableRow(fy::Flighty)

	f = representingFlight(fy)

	flags = (f.dual ? "D" : "P") * (f.instr ? "I" : "")
	timeString = asString(minutes(fy))

	return [
		0,
		Dates.format(f.date, "dd.mm.yyyy"),
		f.aircraftType,
		f.callsign,
		f.pilot,
		!ismissing(copilot(fy)) ? copilot(fy) : "-",
		f.departureLocation,
		f.arrivalLocation,
		convert(String, f.launch),
		Dates.format(departureTime(fy), "HH:MM"),
		Dates.format(arrivalTime(fy), "HH:MM"),
		timeString,
		flags,
		f.dual ? "" : timeString,
		f.dual ? timeString : "",
		f.instr ? timeString : "",
		numberOfLandings(fy),
		!ismissing(comments(fy)) ? comments(fy) : ""
	]
end

function toPrettyTableHeader()
	return [
		"Nr.", "Datum", "Muster", "Reg.",
		"Pilot", "Co",
		"Von", "Nach", "S", "Start", "Land",
		"Zeit", "~", "PIC", "DUAL", "INSTR", "#L",
		"Bemerkungen"
	]
end

# function toPrettyTableRow(g::FlightGroup)
# 	f = g.flights[1]
# 	row = toPrettyTableRow(f)
# 	timeString = asString(minutes(g))
#
# 	copilots = [f.copilot for f in g.flights] |> skipmissing |> unique
# 	if isempty(copilots)
# 		row[6] = "-"
# 	else
# 		row[6] = join(copilots, "\n")
# 	end
#
# 	row[10] = Dates.format(minimum([f.departureTime for f in g.flights]), "HH:MM")
# 	row[11] = Dates.format(maximum([f.arrivalTime for f in g.flights]), "HH:MM")
# 	row[12] = sum([f.numberOfLandings for f in g.flights])
# 	row[13] = timeString
# 	row[15] = f.dual ? "" : timeString
# 	row[16] = f.dual ? timeString : ""
# 	row[17] = f.instr ? timeString : ""
#
# 	row[18] = join(skipmissing([f.comments for f in g.flights]), ", ")
#
# 	return row
# end
