
groupable(a::Flight, b::Flight)
    return a.date == b.date &&
           a.callsign == b.callsign &&
           (
                convert(Minute, abs(a.arrivalTime - b.departureTime)) <= 30 ||
                convert(Minute, abs(a.departureTime - b.arrivalTime)) <= 30
           )
end
