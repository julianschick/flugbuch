
struct FlightAccumulator
    count::Int
    totalTime::Dates.Minute
    picTime::Dates.Minute
    dualTime::Dates.Minute
    instrTime::Dates.Minute
end

FlightAccumulator() = FlightAccumulator(0, Dates.Minute(0), Dates.Minute(0), Dates.Minute(0), Dates.Minute(0))
FlightAccumulator(flights::Vector{<:Flighty}) = sum([FlightAccumulator(); flights])

function toPrettyTableRow(acc::FlightAccumulator, comment)
	return [
		"",
		"", "", "", "", "", "", "", "", "", "", acc.count,
		asString(acc.totalTime),
		"",
		asString(acc.picTime), asString(acc.dualTime), asString(acc.instrTime),
		comment
	]
end

function Base.:+(acc::FlightAccumulator, f::Flighty)
    c = acc.count + numberOfLandings(f)
    totalTime = acc.totalTime + minutes(f)
    dualTime = acc.dualTime
    picTime = acc.picTime
    instrTime = acc.instrTime

    if !dual(f)
        picTime = acc.picTime + minutes(f)
    else
        dualTime = acc.dualTime + minutes(f)
    end

    if instr(f)
        instrTime = acc.instrTime + minutes(f)
    end

    FlightAccumulator(c, totalTime, picTime, dualTime, instrTime)
end

function Base.:+(f1::Flighty, f2::Flighty)::FlightAccumulator
    acc = FlightAccumulator()
    acc + f1 + f2
end
