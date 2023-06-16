rsd(v) = std(v) / mean(v) * 100

apply(fs, x...) = [f(x...) for f in fs]
vcat_fmap2_table_skip1(f) = (x, y) -> vcat([x], (collect ∘ fmap(fmap(f) ∘ columns))(y))

#islessD(x, y) = isless(parse(Int, replace(x, "D" => "")), parse(Int, replace(y, "D" => "")))
function sort(tbl::Table, sym::Symbol; kwargs...)
    ord = sortperm(getproperty(tbl, sym); kwargs...)
    Table(; (propertynames(tbl) .=> getindex.(collect(columns(tbl)), Ref(ord)))...)
end

reducer(f) = (x...) -> reduce(f, x)
applyer(f) = (x...) -> f(x)
fmap(f) = (x...) -> map(f, x...)

f_var_inter(var_bet, var_intra, inv_n) = max(var_bet - var_intra * inv_n, 0)
f_std(vars) = sqrt(vars)
f_rsd(vars, means) = sqrt(vars) / means * 100
f_rsd(var1, var2, means) = sqrt(var1 + var2) / means * 100
std_sum(x, y) = sqrt(x^2 + y^2)