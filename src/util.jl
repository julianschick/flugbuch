
function asString(m::Dates.Minute)
	minutes = m.value % 60
	hours = m.value ÷ 60
	@sprintf("%02d:%02d", hours, minutes)
end

pm(fun::Function, x) = !ismissing(x) ? fun(x) : missing

function ellipsis(str::String, limit::Int)
	if limit <= 0 || limit >= length(str)
		return str
	end

	str[1:nextind(str, limit)] * "..."
end

function applyNormalizations(str::AbstractString, norm::Vector{Tuple{String, String}})
	for (oldval, newval) in norm
		if occursin(str, oldval)
			return newval
		end
	end
	return str
end
