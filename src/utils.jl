rsd(v) = std(v) / mean(v)
rsd_pct(v) = 100 * rsd(v)

apply(fs, x...) = [f(x...) for f in fs]
apply(f::Function, x...) = f(x...)

f_var_inter(var_bet, var_intra, inv_n) = max(var_bet - var_intra * inv_n, 0)
f_var_sum_rsd(var1, var2, means) = sqrt(var1 + var2) / means
f_var_sum_rsd_pct(var1, var2, means) = f_var_sum_rsd(var1, var2, means) * 100
ratio_pct(x, y) = x / y * 100
f_rsd_sum_std(x, y, m) = sqrt(x ^ 2 + y ^ 2) * m
f_rsd_sum_std_pct(x, y, m) = f_rsd_sum_std(x, y, m) * 100

"""
    pivot(df::DataFrame, col; rows = [], prefix = true, notsort = ["Stats", "File"], drop = [])
    pivot(df::DataFrame, cols::AbstractVector; rows = [], prefix = true, notsort = ["Stats", "File"], drop = [])

Transform `DataFrame` into wide format.

# Arguments
* `df`: target `DataFrame`.
* `col`: the column (Symbol or String) holding the column names in wide format.
* `cols`: the column(s) (Vector) holding the column names in wide format.

# Keyword Arguments
* `rows`: the column(s) (Symbol, String, or Vector) preserving as row keys in wide format.
* `prefix`: whether preserving `col` or `cols` in column names.
* `notsort`: columns (Vector); do not sort by these columns.
* `drop`: columns (Vector); drop these columns.
"""
function pivot(df::DataFrame, cols; rows = [], prefix = true, notsort = ["Stats", "File"], drop = [])
    df = _pivot(df, cols; rows, prefix, drop)
    ord = filter(!startswith("Data"), names(df))
    filter!(x -> !in(x, notsort), ord)
    sort!(df, ord)
end
function _pivot(df::DataFrame, col; rows = [], prefix = true, drop = [])
    cols = names(df)
    value_id = findall(startswith("Data"), cols)
    row_id = setdiff(eachindex(cols), value_id)
    col_id = findfirst(==(String(col)), cols)
    setdiff!(row_id, col_id)
    dfs = prefix ? [unstack(df, row_id, col_id, v, renamecols = x -> Symbol(cols[v], :|, cols[col_id], :(=), x)) for v in value_id] : 
                    [unstack(df, row_id, col_id, v, renamecols = x -> Symbol(cols[v], :|, x)) for v in value_id]
    df = length(dfs) == 1 ? only(dfs) : outerjoin(dfs...; on = cols[row_id])
    select!(df, rows, Not(drop))
end

function _pivot(df::DataFrame, cols::AbstractVector; rows = [], prefix = true, drop = [])
    length(cols) == 1 && return _pivot(df, only(cols); rows, prefix)
    dfs = [df]
    row_id = Int[]
    colss = names(df)
    for col in cols
        df = first(dfs)
        colss = names(df)
        value_id = findall(startswith("Data"), colss)
        row_id = setdiff(eachindex(colss), value_id)
        col_id = findfirst(==(String(col)), colss)
        setdiff!(row_id, col_id)
        dfs = mapreduce(append!, dfs) do df
                colss = names(df)
                prefix ? [unstack(df, row_id, col_id, v, renamecols = x -> Symbol(colss[v], :|, colss[col_id], :(=), x)) for v in value_id] : 
                        [unstack(df, row_id, col_id, v, renamecols = x -> Symbol(colss[v], :|, x)) for v in value_id]
            end
    end
    df = length(dfs) == 1 ? only(dfs) : outerjoin(dfs...; on = colss[row_id])
    select!(df, rows, Not(drop))
end

"""
    unpivot(df::DataFrame, col; rows = [], notsort = ["Stats", "File"], drop = [])
    unpivot(df::DataFrame, cols::AbstractVector; rows = [], notsort = ["Stats", "File"], drop = [])

Transform `DataFrame` into wide format.

# Arguments
* `df`: target `DataFrame`.
* `col`: the column name (Symbol or String) in long format.
* `cols`: the column(s) (Vector) in long format.

# Keyword Arguments
* `rows`: the column(s) (Symbol, String, or Vector) preserving as row keys in long format.
* `notsort`: columns (Vector); do not sort by these columns.
* `drop`: columns (Vector); drop these columns.
"""
function unpivot(df::DataFrame, col; rows = [], notsort = ["Stats", "File"], drop = [])
    df = _unpivot(df, col)
    select!(df, rows, Not(drop))
    ord = filter(!startswith("Data"), names(df))
    filter!(x -> !in(x, notsort), ord)
    sort!(df, ord)
end

function unpivot(df::DataFrame, cols::AbstractVector; rows = [], notsort = ["Stats", "File"], drop = [])
    for col in cols
        df = _unpivot(df, col)
    end
    select!(df, rows, Not(drop))
    ord = filter(!startswith("Data"), names(df))
    filter!(x -> !in(x, notsort), ord)
    sort!(df, ord)
end

function _unpivot(df::DataFrame, col)
    col = string(col)
    cols = names(df)
    value_id = findall(startswith("Data"), cols)
    row_id = setdiff(eachindex(cols), value_id)
    valuecols = map(value_id) do i
        replace(cols[i], Regex("\\|" * col * "=[^\\|]*") => "")
    end
    newcols = map(value_id) do i
        only(match(Regex("\\|" * col * "=([^\\|]*)"), cols[i]))
    end
    colmap = Dictionary{String, Vector{Int}}()
    for (i, v) in enumerate(valuecols)
        push!(get!(colmap, v, Int[]), i)
    end
    dfs = [stack(select(df, row_id, value_id[v] .=> identity .=> newcols[v]), newcols[v]; variable_name = col, value_name = k) for (k, v) in pairs(colmap)]
    df = length(dfs) == 1 ? only(dfs) : outerjoin(dfs...; on = vcat(cols[row_id], col))
end

"""
    mean_plus_minus_std(m, s; digits = 2)

Round and merge mean values and standard deviations with "±".

# Arguments
* `m`: mean values.
* `s`: standard deviations.
* `digits`: rounds to the specified number of digits after the decimal place.
"""
mean_plus_minus_std(m, s; digits = 2) = @. string(round(m; digits), "±", round(s; digits))

"""
    add_percentage(s; ispct = false, digits = 2)

Add "%" to `s`.

# Arguments
* `s`: numbers.
* `ispct`: whether the orinal data is percentage; if not, the value will time 100.
* `digits`: rounds to the specified number of digits after the decimal place.
"""
add_percentage(s; ispct = false, digits = 2) = ispct ? (@. string(round(s; digits), "%")) : (@. string(round(s * 100; digits), "%"))

"""
    merge_stats(df::DataFrame, col_pairs...; colstats = :Stats, kwargs...)

Merge spcific statistics.

# Arguments
* `df`: target `DataFrame`.
* `col_pairs`: `DataFrames.jl` syntax to manipulate columns. They will be put in internal `select!` function.
* `colstats`: column name of statistics.
* `kwargs`: keyword arguments for internal `select!` function.
"""
function merge_stats(df::DataFrame, col_pairs...; colstats = :Stats, kwargs...)
    cols = propertynames(df)
    value_id = findfirst(==(:Data), cols)
    row_id = setdiff(eachindex(cols), value_id)
    col_id = findfirst(==(colstats), cols)
    setdiff!(row_id, col_id)
    df = unstack(df, row_id, col_id, value_id)
    select!(df, row_id, col_pairs...; kwargs...)
    cols2 = propertynames(df)
    row_id2 = findall(in(cols[row_id]), cols2)
    col_id2 = setdiff(eachindex(cols2), row_id2)
    df = stack(df, col_id2, row_id2; variable_name = colstats, value_name = :Data)
    sort!(df, row_id2)
end

"""
    normalize(df::DataFrame, normalizer::DataFrame; id = [:Analyte, :L], stats = (All(), "Accuracy"), colstats = :Stats)

Normalize `DataFrame` by the given normalizer.

# Arguments
* `normalizer`: the `DataFrame` to normalize `df`.
* `df`: the `DataFrame` to be normalized.
* `id`: the column(s) (Symbol, string or integer) with a unique key for each row.
* `stats`: a `Tuple` represented as statistics involved in normalization. The first argument applies to `df`, and the second applies to `normalizer`. `All()` indicates including all statistics.
* `colstats`: column name of statistics.
"""
function normalize(df::DataFrame, normalizer::DataFrame; id = [:Analyte, :Level], stats = (All(), "Accuracy"), colstats = :Stats)
    normalizer = filter(colstats => ==(stats[1]), normalizer)
    df = deepcopy(df)
    ngdf = groupby(normalizer, id)
    tgdf = groupby(df, id)
    if stats[1] isa All
        stats = (unique(getproperty(df, colstats)), stats[2])
    end
    for (i, j) in zip(eachindex(ngdf), eachindex(tgdf))                                                                                 
        tgdf[j].Data[in.(getproperty(tgdf[j], colstats), Ref(stats[1]))] ./= ngdf[i].Data ./ 100                                                                        
    end
    df
end

"""
    qualify(df::DataFrame; kwargs...)

Replace data out of acceptable range. See `qualify!` for details.
"""
qualify(df::DataFrame; kwargs...) = qualify!(deepcopy(df); kwargs...)

"""
    qualify!(df::DataFrame; 
            lod = nothing, 
            loq = nothing, 
            lloq = nothing, 
            uloq = nothing, 
            lodsub = "<LOD", 
            loqsub = "<LOQ", 
            lloqsub = "<LLOQ", 
            uloqsub = ">ULOQ")

Replace data out of acceptable range.

* `lod`: limit of detection; values are promoted to match columns whose name starts with "Data".
* `loq`: limit of quantification; values are promoted to match columns whose name starts with "Data".
* `lloq`: lower limit of quantification; values are promoted to match columns whose name starts with "Data".
* `uloq`: upper limit of quantification; values are promoted to match columns whose name starts with "Data".
* `lodsub`: substitution for value smaller than LOD.
* `loqsub`: substitution for value smaller than LOQ.
* `lloqsub`: substitution for value smaller than LLOQ.
* `uloqsub`: substitution for value larger than ULOQ.
"""
function qualify!(df::DataFrame; 
                    lod = nothing, 
                    loq = nothing, 
                    lloq = nothing, 
                    uloq = nothing, 
                    lodsub = "<LOD", 
                    loqsub = "<LOQ", 
                    lloqsub = "<LLOQ", 
                    uloqsub = ">ULOQ")
    th = [lod, loq, lloq, uloq]
    p = findall(!isnothing, th)
    isempty(p) && return df
    th = th[p]
    sub = [lodsub, loqsub, lloqsub, uloqsub][p]
    comp = [<, <, <, >][p]
    cols = filter!(startswith("Data"), names(df))
    bk = zeros(length(cols))
    fb = [identity for i in cols]
    th = mapreduce(hcat, th) do t
        bk .+ t
    end
    sub = mapreduce(hcat, sub) do s
        apply.(fb, s)
    end
    for (col, ts, ss) in zip(cols, eachrow(th), eachrow(sub))
        df[!, col] = map(df[!, col]) do x
            for (t, s, c) in zip(ts, ss, comp)
                c(x, t) && return s
            end
            x
        end
    end
    df
end

