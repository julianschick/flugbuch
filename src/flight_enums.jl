
@enum Launch begin
	Aerotow
    Winch
end

function Launch(str::AbstractString)
	if str == "W"
		Winch
	elseif str == "F"
		Aerotow
	else
		ArgumentError(str, "Invalid launch method string") |> throw
	end
end

function Base.convert(::Type{String}, l::Launch)
	if l == Winch
		return "W"
	else
		return "F"
	end
end

Base.convert(::Type{Launch}, str::AbstractString) = Launch(str)
