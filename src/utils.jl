rsd(v) = std(v) / mean(v) * 100

apply(fs, x...) = [f(x...) for f in fs]

f_var_inter(var_bet, var_intra, inv_n) = max(var_bet - var_intra * inv_n, 0)
f_var_sum_pct(var1, var2, means) = sqrt(var1 + var2) / means * 100
ratio_pct(x, y) = x / y * 100
f_rsd_sum_std(x, y, m) = sqrt(x ^ 2 + y ^ 2) * m

"""
    flattable(df::DataFrame, col)
    flattable(df::DataFrame, cols::AbstractVector) 

Turn `DataFrame` into wide format.

# Arguments
* `df`: target `DataFrame`.
* `col`: the column (Symbol or string) holding the column names in wide format.
* `cols`: a vecctor of columns (Symbol or string) holding the column names in wide format.
"""
function flattable(df::DataFrame, col)
    cols = names(df)
    value_id = findall(x -> occursin("Data", x), cols)
    row_id = setdiff(eachindex(cols), value_id)
    col_id = findfirst(==(String(col)), cols)
    setdiff!(row_id, col_id)
    dfs = [unstack(df, row_id, col_id, v, renamecols = x -> Symbol(cols[v], :_, cols[col_id], :(=), x)) for v in value_id]
    length(dfs) == 1 ? dfs[1] : outerjoin(dfs...; on = cols[row_id])
end

function flattable(df::DataFrame, cols::AbstractVector) 
    for col in cols
        df = flat(df, col)
    end
    df
end

"""
    mean_plus_minus_std(m, s; digits = 2)

Round and merge mean values and standard deviations with "±".

# Arguments
* `m`: mean values.
* `s`: standard deviations.
* `digits`: rounds to the specified number of digits after the decimal place.
"""
mean_plus_minus_std(m, s; digits = 2) = string.(round.(m; digits), "±", round.(s; digits))

"""
    add_percentage(s; digits = 2)

Add "%" to `s`.

# Arguments
* `s`: numbers.
* `digits`: rounds to the specified number of digits after the decimal place.
"""
add_percentage(s; digits = 2) = string.(round.(s; digits), Ref("%"))

"""
    merge_stats(df::DataFrame, col_pairs...; kwargs...)

Merge spcific statistics.

# Arguments
* `df`: target `DataFrame`.
* `col_pairs`: `DataFrames.jl` syntax to manipulate columns. They will be put in internal `select!` function.
* `kwargs`: keyword arguments for internal `select!` function.
"""
function merge_stats(df::DataFrame, col_pairs...; kwargs...)
    cols = propertynames(df)
    value_id = findfirst(==(:Data), cols)
    row_id = setdiff(eachindex(cols), value_id)
    col_id = findfirst(==(:Stats), cols)
    setdiff!(row_id, col_id)
    df = unstack(df, row_id, col_id, value_id)
    select!(df, row_id, col_pairs...; kwargs...)
    cols2 = propertynames(df)
    row_id2 = findall(in(cols[row_id]), cols2)
    col_id2 = setdiff(eachindex(cols2), row_id2)
    df = stack(df, col_id2, row_id2; variable_name = :Stats, value_name = :Data)
    sort!(df, row_id2)
end

"""
    normalize(normalizer::DataFrame, df::DataFrame; id = [:Drug, :L], stats = ("Accuracy", All()))

Normalize `DataFrame` by the given normalizer.

# Arguments
* `normalizer`: the `DataFrame` to normalize `df`.
* `df`: the `DataFrame` to be normalized.
* `id`: the column(s) (Symbol, string or integer) with a unique key for each row.
* `stats`: a `Tuple` represented as statistics involved in normalization. The first argument applies to `normalizer`, and the second applies to `df`. `All()` indicates including all statistics.
"""
function normalize(normalizer::DataFrame, df::DataFrame; id = [:Drug, :L], stats = ("Accuracy", All()))
    normalizer = filter(:Stats => ==(stats[1]), normalizer)
    df = deepcopy(df)
    ngdf = groupby(normalizer, id)
    tgdf = groupby(df, id)
    if stats[2] isa All
        stats = (stats[1], unique(df.Stats))
    end
    for (i, j) in zip(eachindex(ngdf), eachindex(tgdf))                                                                                 
        tgdf[j].Data[in.(tgdf[j].Stats, Ref(stats[2]))] ./= ngdf[i].Data ./ 100                                                                        
    end
    df
end