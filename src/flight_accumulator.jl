
struct FlightAccumulator
    count::Int
    totalTime::Dates.Minute
    picTime::Dates.Minute
    dualTime::Dates.Minute
    instrTime::Dates.Minute
end

getNr(f::FlightAccumulator) = f.count
getCallsign(f::FlightAccumulator) = ""
getAircraftType(f::FlightAccumulator) = ""
getPilot(f::FlightAccumulator) = ""
getCopilot(f::FlightAccumulator) = ""
getLaunch(f::FlightAccumulator) = ""
getDate(f::FlightAccumulator) = ""
getDepartureTime(f::FlightAccumulator) = ""
getArrivalTime(f::FlightAccumulator) = ""
getNumberOfLanding(f::FlightAccumulator) = ""
getDepartureLocation(f::FlightAccumulator) = ""
getArrivalLocation(f::FlightAccumulator) = ""
getComments(f::FlightAccumulator) = ""
isDual(f::FlightAccumulator) = f.dual
isInstr(f::FlightAccumulator) = f.instr

FlightAccumulator() = FlightAccumulator(0, Dates.Minute(0), Dates.Minute(0), Dates.Minute(0), Dates.Minute(0))

function toPrettyTableRow(acc::FlightAccumulator, comment)
	return [
		acc.count,
		"", "", "", "", "", "", "", "", "", "",
		asString(acc.totalTime),
		"",
		asString(acc.picTime), asString(acc.dualTime), asString(acc.instrTime),
		comment
	]
end

function Base.:+(acc::FlightAccumulator, f::Flight)
    c = acc.count + 1
    totalTime = acc.totalTime + minutes(f)
    dualTime = acc.dualTime
    picTime = acc.picTime
    instrTime = acc.instrTime

    if !f.dual
        picTime = acc.picTime + minutes(f)
    else
        dualTime = acc.dualTime + minutes(f)
    end

    if f.instr
        instrTime = acc.instrTime + minutes(f)
    end

    FlightAccumulator(c, totalTime, picTime, dualTime, instrTime)
end

function Base.:+(f1::Flight, f2::Flight)::FlightAccumulator
    acc = FlightAccumulator()
    acc + f1 + f2
end
