"""
    qc_report(at::AnalysisTable;
                id = r"PooledQC", 
                type = :estimated_concentration, 
                pct = true,
                stats = [mean, std, pct ? rsd_pct : rsd], 
                names = ["Mean", "Standard Deviation", "Relative Standard Deviation" * (pct ? "(%)" : "")], 
                colanalyte = :Analyte,
                colstats = :Stats
            )

Compute statistics of QC data.

# Arguments
* `at`: `AnalysisTable`.
* `id`: `Regex` identifier for the QC samples.
* `pct`: whether converting ratio data into percentage (*100).
* `type`: data type for calculation.
* `stats`: statistics functions.
* `names`: names of statistics. When `nothing` is given, `stats` is served as `names`.
* `colanalyte`: column name of analytes.
* `colstats`: column name of statistics.
"""
function qc_report(at::AnalysisTable; 
                    id = r"PooledQC", 
                    type = :estimated_concentration, 
                    pct = true,
                    stats = [mean, std, pct ? rsd_pct : rsd], 
                    names = ["Mean", "Standard Deviation", "Relative Standard Deviation" * (pct ? "(%)" : "")], 
                    colanalyte = :Analyte,
                    colstats = :Stats
                )
    colanalyte = Symbol(colanalyte)
    colstats = Symbol(colstats)
    dt = getproperty(at, Symbol(type))
    df = CQA.table(dt)
    if !isa(df, DataFrame)
        df = DataFrame(df)
    end
    analytes = analytename(at)
    scol = samplecol(dt)
    names = isnothing(names) ? stats : names
    @chain df begin
        filter(scol => Base.Fix1(occursin, id), _) 
        stack(analytes, scol; variable_name = colanalyte, value_name = :Data)
        select!([colanalyte, :Data])
        groupby(colanalyte)
        combine(:Data => x -> vcat(apply(stats, x)...); renamecols = false)
        insertcols!(_, 2, colstats => repeat(string.(names); outer = size(_, 1) ÷ length(stats)))
        sort!(colanalyte)
    end
end

"""
    sample_report(at::AnalysisTable; id = r"Sample_(\\d*).*", type = :estimated_concentration, colanalyte = :Analyte)

Compute mean of sample data.

# Arguments
* `at`: `AnalysisTable`.
* `id`: `Regex` identifier for the QC samples.
* `type`: data type for calculation.
* `colanalyte`: column name of analytes.
"""
function sample_report(at::AnalysisTable; id = r"Sample_(\d*).*", type = :estimated_concentration, colanalyte = :Analyte)
    colanalyte = Symbol(colanalyte)
    dt = getproperty(at, Symbol(type))
    df = CQA.table(dt)
    if !isa(df, DataFrame)
        df = DataFrame(df)
    end
    analytes = analytename(at)
    scol = samplecol(dt)
    sample = filter(scol => Base.Fix1(occursin, id), df)
    sample[:, scol] = map(x -> match(id, x)[1], sample[!, scol])
    @chain sample begin
        stack(analytes, scol; variable_name = colanalyte, value_name = :Data)
        select!([scol, colanalyte, :Data])
        groupby([scol, colanalyte])
        combine(:Data => mean; renamecols = false)
    end
end

"""
    ap_report(at::AnalysisTable; 
                id = r"Pre.*_(.*)_.*", 
                type = :accuracy, 
                pct = true, 
                colanalyte = :Analyte,
                colstats = :Stats,
                colday = :Day,
                collevel = :Level
            )

Compute accuracy and precision. A `NamedTuple` is returned with two elements: `daily` is a `DataFrame` containing accuracy and standard deviation for each day, and `summary` is a `DataFrame` containing overall accuracy, repeatability and reproducibility. 

# Arguments
* `at`: `AnalysisTable`.
* `id`: `Regex` identifier for the AP experiment samples. The day and concentration level is captured in the identifier; the order can be set by `order`.
* `order`: a string for setting the order of captured values from `id`; D is day; L is concentration level.
* `type`: data type for calculation.
* `pct`: whether converting ratio data into percentage (*100).
* `colanalyte`: column name of analytes.
* `colstats`: column name of statistics.
* `colday`: column name of validation day.
* `collevel`: column name of level.
"""
function ap_report(at::AnalysisTable; 
                    id = r"Pre(.*)_(.*)_.*", 
                    order = "DL", 
                    type = :accuracy, 
                    pct = true, 
                    colanalyte = :Analyte,
                    colstats = :Stats,
                    colday = :Day,
                    collevel = :Level
                )
    colanalyte = Symbol(colanalyte)
    colstats = Symbol(colstats)
    colday = Symbol(colday)
    collevel = Symbol(collevel)
    col = ["Accuracy", "Standard Deviation", "Accuracy", "Intraday Standard Deviation", "Betweenday Standard Deviation", "Interday Standard Deviation", "Repeatability", "Reproducibility"]
    if pct
        f_var_sum_rsd_ = f_var_sum_rsd_pct
        ratio_ = ratio_pct
        col .*= "(%)"
    else
        f_var_sum_rsd_ = f_var_sum_rsd
        ratio_ = /
    end
    dt = getproperty(at, Symbol(type))
    df = CQA.table(dt)
    if !isa(df, DataFrame)
        df = DataFrame(df)
    end
    analytes = analytename(at)
    level = samplecol(dt)
    ap_df = @chain df begin 
        filter(level => Base.Fix1(occursin, id), _)
        insertcols!(_, 1, (Symbol.("__", split(order, "")) .=> map(1:length(order)) do i 
            getindex.(match.(id, _[!, level]), i)
        end
        )...)
        select!(Not([level]))
    end
    rename!(ap_df, :__D => colday, :__L => collevel)
    ap_df[!, colday] .= map(x -> parse(Int, x), getproperty(ap_df, colday))
    ap_df = stack(ap_df, analytes, [collevel, colday]; variable_name = colanalyte, value_name = :Data)
    pct && (ap_df[!, :Data] .*= 100)
    gdf = groupby(ap_df, [colanalyte, collevel, colday])
    ns = @chain gdf begin
        combine(:Data .=> inv ∘ length; renamecols = false)
        groupby([colanalyte, collevel])
        combine(:Data => mean; renamecols = false)
    end 
    accuracies = combine(gdf, :Data => mean; renamecols = false)
    stds = combine(gdf, :Data => std; renamecols = false)
    vars = combine(gdf, :Data => var; renamecols = false)
    accuracy, var_bet = @chain accuracies begin
        groupby([colanalyte, collevel])
        (combine(_, :Data => mean; renamecols = false), combine(_, :Data => var; renamecols = false))
    end
    var_intra = combine(groupby(vars, [colanalyte, collevel]), :Data => mean; renamecols = false)
    var_inter = deepcopy(accuracy)
    var_inter[:, :Data] = @. f_var_inter(getproperty([var_bet, var_intra, ns], :Data)...)
    reproducibility = deepcopy(accuracy)
    reproducibility[:, :Data] = @. f_var_sum_rsd_(getproperty([var_intra, var_inter, reproducibility], :Data)...)
    std_intra = transform!(var_intra, :Data => ByRow(sqrt); renamecols = false)
    std_bet = transform!(var_bet, :Data => ByRow(sqrt); renamecols = false)
    std_inter = transform!(var_inter, :Data => ByRow(sqrt); renamecols = false)
    repeatability = deepcopy(accuracy)
    repeatability[:, :Data] = @. ratio_(getproperty([std_intra, repeatability], :Data)...)
    for (st, nm) in zip([accuracies, stds, accuracy, std_intra, std_bet, std_inter, repeatability, reproducibility], col)
        insertcols!(st, colstats => nm)
    end
    daily = @chain vcat(accuracies, stds) begin
        select!([colanalyte, collevel, colday, colstats, :Data])
        sort!([colanalyte, collevel, colday])
    end
    summary = @chain vcat(std_intra, accuracy, std_bet, std_inter, repeatability, reproducibility) begin
        select!([colanalyte, collevel, colstats, :Data])
        sort!([colanalyte, collevel])
    end
    (; daily, summary)
end

"""
    me_report(at::AnalysisTable; 
                matrix = r"Post.*_(.*)_.*", 
                stds = r"STD.*_(.*)_.*", 
                type = :area, 
                pct = true, 
                colanalyte = :Analyte,
                colstats = :Stats,
                collevel = :Level
            )

Compute matrix effects.

# Arguments
* `at`: `AnalysisTable`.
* `matrix`: `Regex` identifier for samples with matrix. The concentration level is captured in the identifier.
* `stds`: `Regex` identifier for standard solution. The concentration level is captured in the identifier.
* `type`: data type for calculation.
* `pct`: whether converting ratio data into percentage (*100).
* `colanalyte`: column name of analytes.
* `colstats`: column name of statistics.
* `collevel`: column name of level.
"""
function me_report(at::AnalysisTable; 
                    matrix = r"Post.*_(.*)_.*", 
                    stds = r"STD.*_(.*)_.*", 
                    type = :area, 
                    pct = true, 
                    colanalyte = :Analyte,
                    colstats = :Stats,
                    collevel = :Level
                )
    df = ratio_data(at; type, pre = matrix, post = stds, pct, colanalyte, colstats, collevel)
    replace!(getproperty(df, colstats), pct ? "Ratio(%)" => "Matrix Effect(%)" : "Ratio" => "Matrix Effect")
    df
end

"""
    recovery_report(at::AnalysisTable; 
                    pre = r"Pre.*_(.*)_.*", 
                    post = r"Post.*_(.*)_.*", 
                    type = :area, 
                    pct = true, 
                    colanalyte = :Analyte,
                    colstats = :Stats,
                    collevel = :Level
                )

Compute recovery.

# Arguments
* `at`: `AnalysisTable`.
* `pre`: `Regex` identifier for prespiked samples. The concentration level is captured in the identifier.
* `post`: `Regex` identifier for postspiked samples. The concentration level is captured in the identifier.
* `type`: data type for calculation.
* `pct`: whether converting ratio data into percentage (*100).
* `colanalyte`: column name of analytes.
* `colstats`: column name of statistics.
* `collevel`: column name of level.
"""
function recovery_report(at::AnalysisTable; 
                            pre = r"Pre.*_(.*)_.*", 
                            post = r"Post.*_(.*)_.*", 
                            type = :area, 
                            pct = true, 
                            colanalyte = :Analyte,
                            colstats = :Stats,
                            collevel = :Level
                        )
    df = ratio_data(at; type, pre, post, pct, colanalyte, colstats, collevel)
    replace!(getproperty(df, colstats), pct ? "Ratio(%)" => "Recovery(%)" : "Ratio" => "Recovery")
    df
end

function ratio_data(at::AnalysisTable; 
                    pre = r"Pre.*_(.*)_.*", 
                    post = r"Post.*_(.*)_.*", 
                    type = :estimated_concentration, 
                    pct = true, 
                    colanalyte = :Analyte,
                    colstats = :Stats,
                    collevel = :Level
                )
    colanalyte = Symbol(colanalyte)
    colstats = Symbol(colstats)
    collevel = Symbol(collevel)
    col = ["Ratio", "Standard Deviation"]
    if pct
        ratio_ = ratio_pct
        col .*= "(%)"
    else
        ratio_ = /
    end
    dt = getproperty(at, Symbol(type))
    df = CQA.table(dt)
    if !isa(df, DataFrame)
        df = DataFrame(df)
    end
    analytes = analytename(at)
    level = samplecol(dt)
    df = @chain df begin
        stack(analytes, level; variable_name = colanalyte, value_name = :Data)
        rename!(Dict(level => collevel))
    end
    pre_df = filter(collevel => Base.Fix1(occursin, pre), df)
    post_df = filter(collevel => Base.Fix1(occursin, post), df)
    pre_df[:, collevel] = getindex.(match.(pre, pre_df[!, collevel]), 1)
    post_df[:, collevel] = getindex.(match.(post, post_df[!, collevel]), 1)
    sort!(pre_df, collevel)
    sort!(post_df, collevel)
    pre_gdf = groupby(pre_df, [colanalyte, collevel])
    post_gdf = groupby(post_df, [colanalyte, collevel])
    ratio = combine(pre_gdf, :Data => mean; renamecols = false)
    stds = combine(pre_gdf, :Data => rsd; renamecols = false)
    post_ratio = combine(post_gdf, :Data => mean; renamecols = false)
    post_rsd = combine(post_gdf, :Data => rsd; renamecols = false)
    ratio[:, :Data] = @. ratio_(ratio[!, :Data], post_ratio[!, :Data])
    stds[:, :Data] = @. f_rsd_sum_std(stds[!, :Data], post_rsd[!, :Data], ratio[!, :Data])
    insertcols!(ratio, colstats => col[1])
    insertcols!(stds, colstats => col[2])
    @chain vcat(ratio, stds) begin
        select!([colanalyte, collevel, colstats, :Data])
        sort!([colanalyte, collevel])
    end
end

"""
    stability_report(at::AnalysisTable; 
                        d0 = r"S.*_(.*)_.*", 
                        id = r"S.*_(.*)_(.*)_(.*)_.*", 
                        order = "CDL", 
                        type = :accuracy, 
                        pct = true,                             
                        colanalyte = :Analyte,
                        colstats = :Stats,
                        colcondition = :Condition,
                        colday = :Day,
                        collevel = :Level,
                        isaccuracy = true
                    )
Compute stability. A `NamedTuple` is returned with two elements: `day0` is a `DataFrame` conataing day0 data, and `result` is a `DataFrame` conataing data of other days. 

# Arguments
* `at`: `AnalysisTable`.
* `d0`: `Regex` identifier for day0 samples. The concentration level is captured in the identifier.
* `id`: `Regex` identifier for the stability samples. The storage condition, concentration level, and storage days are captured in the identifier; the order can be set by `order`.
* `order`: a string for setting the order of captured values from `id`; C is storage condition; D is storage days; L is concentration level
* `type`: data type for calculation.
* `pct`: whether converting ratio data into percentage (*100).
* `colanalyte`: column name of analytes.
* `colstats`: column name of statistics.
* `colcondition`: column name of storage condition.
* `colday`: column name of validation day.
* `collevel`: column name of level.
* `isaccuracy`: whether the input data is accuracy.
"""
function stability_report(at::AnalysisTable; 
                            d0 = r"S.*_(.*)_.*", 
                            id = r"S.*_(.*)_(.*)_(.*)_.*", 
                            order = "CDL", 
                            type = :accuracy, 
                            pct = true,                             
                            colanalyte = :Analyte,
                            colstats = :Stats,
                            colcondition = :Condition,
                            colday = :Day,
                            collevel = :Level,
                            isaccuracy = true
                        )
    colanalyte = Symbol(colanalyte)
    colstats = Symbol(colstats)
    colcondition = Symbol(colcondition)
    colday = Symbol(colday)
    collevel = Symbol(collevel)
    pct = pct && isaccuracy
    col = [isaccuracy ? "Accuracy" : "Mean", "Standard Deviation"]
    if pct
        col .*= "(%)"
    end
    dt = getproperty(at, Symbol(type))
    df = CQA.table(dt)
    if !isa(df, DataFrame)
        df = DataFrame(df)
    end
    analytes = analytename(at)
    level = samplecol(dt)
    stability_df = filter(level => Base.Fix1(occursin, d0), df)
    d0_data = Dict(:__C => "", :__D => 0, :__L => getindex.(match.(d0, getproperty(stability_df, level)), 1))
    insertcols!(stability_df, 1, map(Symbol.("__", split(order, ""))) do p
        p => d0_data[p]
    end...)
    rename!(stability_df, :__C => colcondition, :__D => colday, :__L => collevel)
    select!(stability_df, Not([level]))
    ulevel = unique(getproperty(stability_df, collevel))
    stability_df2 = filter(level => Base.Fix1(occursin, id), df)
    insertcols!(stability_df2, 1, (Symbol.("__", split(order, "")) .=> map(1:length(order)) do i 
        getindex.(match.(id, stability_df2[!, level]), i)
    end
    )...)
    rename!(stability_df2, :__C => colcondition, :__D => colday, :__L => collevel)
    select!(stability_df2, Not([level]))
    stability_df2[!, colday] .= map(x -> parse(Int, x), getproperty(stability_df2, colday))
    intersect!(ulevel, unique(getproperty(stability_df2, collevel)))
    stability_df = @chain stability_df begin
        append!(stability_df2)
        filter!(collevel => in(ulevel), _)
        sort!(colday)
        stack(analytes, [colcondition, colday, collevel]; variable_name = colanalyte, value_name = :Data) 
    end
    pct && (stability_df.Data .*= 100)
    gdf = groupby(stability_df, [colanalyte, colcondition, colday, collevel])
    accuracy = combine(gdf, :Data => mean, renamecols = false)
    stds = combine(gdf, :Data => std, renamecols = false)
    insertcols!(accuracy, colstats => col[1])
    insertcols!(stds, colstats => col[2])
    result = @chain vcat(accuracy, stds) begin
        select!([colanalyte, colcondition, colday, collevel, colstats, :Data])
        sort!([colanalyte, colcondition, colday, collevel])
    end
    day0 = filter(colday => ==(0), result)
    filter!(colday => >(0), result)
    (; day0, result)
end

"""
    relative_stability_report(at::AnalysisTable; 
                                d0 = r"S.*_(.*)_.*", 
                                id = r"S.*_(.*)_(.*)_(.*)_.*", 
                                order = "CDL", 
                                type = :accuracy, 
                                pct = true,                             
                                colanalyte = :Analyte,
                                colstats = :Stats,
                                colcondition = :Condition,
                                colday = :Day,
                                collevel = :Level,
                                isaccuracy = true
                            )
Compute stability relative to day0 data.

# Arguments
* `at`: `AnalysisTable`.
* `d0`: `Regex` identifier for day0 samples. The concentration level is captured in the identifier.
* `id`: `Regex` identifier for the stability samples. The storage condition, concentration level, and storage days are captured in the identifier; the order can be set by `order`.
* `order`: a string for setting the order of captured values from `id`; C is storage condition; D is storage days; L is concentration level
* `type`: data type for calculation.
* `pct`: whether converting ratio data into percentage (*100).
* `colanalyte`: column name of analytes.
* `colstats`: column name of statistics.
* `colcondition`: column name of storage condition.
* `colday`: column name of validation day.
* `collevel`: column name of level.
* `isaccuracy`: whether the input data is accuracy.
"""
function relative_stability_report(at::AnalysisTable; 
                                    d0 = r"S.*_(.*)_.*", 
                                    id = r"S.*_(.*)_(.*)_(.*)_.*", 
                                    order = "CDL", 
                                    type = :accuracy, 
                                    pct = true,                             
                                    colanalyte = :Analyte,
                                    colstats = :Stats,
                                    colcondition = :Condition,
                                    colday = :Day,
                                    collevel = :Level,
                                    isaccuracy = true
                                )
    st = stability_report(at; d0, id, order, type, pct, colanalyte, colstats, colcondition, colday, collevel, isaccuracy)
    colmean = isaccuracy ? "Accuracy" : "Mean"
    colstd = "Standard Deviation"
    if pct && isaccuracy
        colmean = colmean * "(%)"
        colstd = colstd * "(%)"
    end
    means = normalize(st.result, st.day0; id = [colanalyte, collevel], colstats, stats = (colmean, colmean))
    pct && (means.Data .*= 100)
    pd0 = selectby(st.day0, colstats, [colstd, colmean] => ((x, y) -> map(/, x, y)) => ""; prefix = false, pivot = true)
    pr = selectby(st.result, colstats, [colstd, colmean] => ((x, y) -> map(/, x, y)) => ""; prefix = false, pivot = true)
    ngdf = groupby(pd0, [colanalyte, collevel])
    mgdf = groupby(means, [colanalyte, collevel])
    tgdf = groupby(pr, [colanalyte, collevel])
    for (i, j, k) in zip(eachindex(ngdf), eachindex(tgdf), eachindex(mgdf))                                                                                 
        tgdf[j].Data .= f_rsd_sum_std.(ngdf[i].Data, tgdf[j].Data, mgdf[k].Data)                                                                   
    end
    insertcols!(pr, 5, colstats => repeat([colstd], length(pr.Data)))
    means[!, colstats] .= pct ? "Stability(%)" : "Stability"
    sort!(vcat(means, pr), [colanalyte, colcondition, colday, collevel])
end

for f in [:sample_report, :qc_report, :me_report, :recovery_report, :ap_report, :stability_report, :relative_stability_report]
    @eval $f(batch::Batch; kwargs...) = $f(batch.data; kwargs...)
end