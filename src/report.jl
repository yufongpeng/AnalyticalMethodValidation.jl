"""
    qc_report(df::DataFrame; id = r"PooledQC", type = "Final Conc.", stats = [mean, std, rsd], names = ["Mean", "Standard Deviation", "Relative Standard Deviation"])

Compute statistics of QC data.

# Arguments
* `df`: a `DataFrame`.
* `id`: `Regex` identifier for the QC samples.
* `type`: quantification value type.
* `stats`: statistics functions.
* `names`: names of statistics. When `nothing` is given, `stats` is served as `names`.
"""
function qc_report(df::DataFrame; id = r"PooledQC", type = "Final Conc.", stats = [mean, std, rsd], names = ["Mean", "Standard Deviation", "Relative Standard Deviation"])
    cols = propertynames(df)
    qc = @p df filter(cols[1] => Base.Fix1(occursin, id)) filter(cols[2] => ==(type))
    qc = stack(qc, cols[3:end], cols[1]; variable_name = :Drug, value_name = :Data)
    select!(qc, [:Drug, :Data])
    report = combine(groupby(qc, :Drug), :Data => x -> vcat(apply(stats, x)...); renamecols = false)
    names = isnothing(names) ? stats : names
    insertcols!(report, 2, :Stats => repeat(repr.(names); outer = size(report, 1) ÷ length(stats)))
    sort!(report, :Drug)
end

"""
    sample_report(df::DataFrame; id = r"Sample_(\\d*).*", type = "Final Conc.")

Compute mean of sample data.

# Arguments
* `df`: a `DataFrame`.
* `id`: `Regex` identifier for the QC samples.
* `type`: quantification value type.
"""
function sample_report(df::DataFrame; id = r"Sample_(\d*).*", type = "Final Conc.")
    cols = propertynames(df)
    sample = @p df filter(cols[1] => Base.Fix1(occursin, id)) filter(cols[2] => ==(type))
    sample[:, cols[1]] = map(x -> match(id, x)[1], sample[!, cols[1]])
    sample = stack(sample, cols[3:end], cols[1]; variable_name = :Drug, value_name = :Data)
    select!(sample, [cols[1], :Drug, :Data])
    combine(groupby(sample, [cols[1], :Drug]), :Data => mean; renamecols = false)
end

"""
    ap_report(df::DataFrame; id = r"Pre.*_(.*)_.*", type = "Accuracy")

Compute accuracy and precision.

# Arguments
* `df`: a `DataFrame`.
* `id`: `Regex` identifier for the AP experiment samples. The day and concentration level is captured in the identifier; the order can be set by `order`.
* `order`: a string for setting the order of captured values from `id`; D is day; L is concentration level.
* `type`: quantification value type.
"""
function ap_report(df::DataFrame; id = r"Pre(.*)_(.*)_.*", order = "DL", type = "Accuracy")
    cols = propertynames(df)
    datatype = cols[2]
    level = cols[1]
    drugs = cols[3:end]
    df = filter(datatype => ==(type), df)
    ap_df = filter(level => Base.Fix1(occursin, id), df)
    insertcols!(ap_df, 1, (Symbol.(split(order, "")) .=> map(1:length(order)) do i 
        getindex.(match.(id, ap_df[!, level]), i)
    end
    )...)
    select!(ap_df, Not([datatype, level]))
    ap_df[!, :D] .= @p ap_df.D map(parse(Int, _))
    ap_df = stack(ap_df, drugs, [:L, :D]; variable_name = :Drug, value_name = :Data)
    gdf1 = groupby(ap_df, [:Drug, :L, :D])
    gdf2 = groupby(combine(gdf1, :Data .=> length; renamecols = false), [:Drug, :L])
    ns = combine(gdf2, :Data => mean; renamecols = false)
    accuracies = combine(gdf1, :Data => mean; renamecols = false)
    stds = combine(gdf1, :Data => std; renamecols = false)
    vars = combine(gdf1, :Data => var; renamecols = false)
    accuracy = combine(groupby(accuracies, [:Drug, :L]), :Data => mean; renamecols = false)
    var_intra = combine(groupby(vars, [:Drug, :L]), :Data => mean; renamecols = false)
    var_bet = combine(groupby(accuracies, [:Drug, :L]), :Data => var; renamecols = false)
    var_inter = deepcopy(accuracy)
    var_inter[:, :Data] = @. f_var_inter(getproperty([var_bet, var_intra, ns], :Data)...)
    reproducibility = deepcopy(accuracy)
    reproducibility[:, :Data] = @. f_var_sum_pct(getproperty([var_intra, var_inter, reproducibility], :Data)...)
    std_intra = transform!(var_intra, :Data => ByRow(sqrt); renamecols = false)
    std_bet = transform!(var_bet, :Data => ByRow(sqrt); renamecols = false)
    std_inter = transform!(var_inter, :Data => ByRow(sqrt); renamecols = false)
    repeatability = deepcopy(accuracy)
    repeatability[:, :Data] = @. ratio_pct(getproperty([std_intra, repeatability], :Data)...)
    insertcols!(accuracies, :Stats => :Accuracy)
    insertcols!(stds, :Stats => "Standard Deviation")
    insertcols!(accuracy, :Stats => "Accuracy")
    insertcols!(std_intra, :Stats => "Intraday Standard Deviation")
    insertcols!(std_bet, :Stats => "Betweenday Standard Deviation")
    insertcols!(std_inter, :Stats => "Interday Standard Deviation")
    insertcols!(repeatability, :Stats => "Repeatability")
    insertcols!(reproducibility, :Stats => "Reproducibility")

    daily = vcat(accuracies, stds)
    select!(daily, [:Drug, :L, :D, :Stats, :Data])
    sort!(daily, [:Drug, :L, :D])
    summary = vcat(std_intra, accuracy, std_bet, std_inter, repeatability, reproducibility)
    select!(summary, [:Drug, :L, :Stats, :Data])
    sort!(summary, [:Drug, :L])
    (; daily, summary)
end

"""
    me_report(df::DataFrame; matrix = r"Post.*_(.*)_.*", stds = r"STD.*_(.*)_.*", type = "Area")

Compute matrix effects.

# Arguments
* `df`: a `DataFrame`.
* `matrix`: `Regex` identifier for samples with matrix. The concentration level is captured in the identifier.
* `stds`: `Regex` identifier for standard solution. The concentration level is captured in the identifier.
* `type`: quantification value type.
"""
function me_report(df::DataFrame; matrix = r"Post.*_(.*)_.*", stds = r"STD.*_(.*)_.*", type = "Area")
    df = ratio_data(df; type, pre = matrix, post = stds)
    replace!(df.Stats, "Ratio" => "Matrix Effect")
    df
end

"""
    recovery_report(df::DataFrame; pre = r"Pre.*_(.*)_.*", post = r"Post.*_(.*)_.*", type = "Final Conc.")

Compute recovery.

# Arguments
* `df`: a `DataFrame`.
* `pre`: `Regex` identifier for prespiked samples. The concentration level is captured in the identifier.
* `post`: `Regex` identifier for postspiked samples. The concentration level is captured in the identifier.
* `type`: quantification value type.
"""
function recovery_report(df::DataFrame; pre = r"Pre.*_(.*)_.*", post = r"Post.*_(.*)_.*", type = "Final Conc.")
    df = ratio_data(df; type, pre, post)
    replace!(df.Stats, "Ratio" => "Recovery")
    df
end

function ratio_data(df::DataFrame; pre = r"Pre.*_(.*)_.*", post = r"Post.*_(.*)_.*", type = "Final Conc.")
    cols = propertynames(df)
    datatype = cols[2]
    level = cols[1]
    drugs = cols[3:end]
    df = filter(datatype => ==(type), df)
    df = stack(df, drugs, level; variable_name = :Drug, value_name = :Data)
    rename!(df, Dict(level => :L))
    pre_df = filter(:L => Base.Fix1(occursin, pre), df)
    post_df = filter(:L => Base.Fix1(occursin, post), df)
    pre_df[:, :L] = getindex.(match.(pre, pre_df[!, :L]), 1)
    post_df[:, :L] = getindex.(match.(post, post_df[!, :L]), 1)
    sort!(pre_df, :L)
    sort!(post_df, :L)
    pre_gdf = groupby(pre_df, [:Drug, :L])
    post_gdf = groupby(post_df, [:Drug, :L])
    ratio = combine(pre_gdf, :Data => mean; renamecols = false)
    stds = combine(pre_gdf, :Data => rsd; renamecols = false)
    post_ratio = combine(post_gdf, :Data => mean; renamecols = false)
    post_rsd = combine(post_gdf, :Data => rsd; renamecols = false)
    ratio[:, :Data] = @. ratio_pct(ratio[!, :Data], post_ratio[!, :Data])
    stds[:, :Data] = @. f_rsd_sum_std(stds[!, :Data], post_rsd[!, :Data], ratio[!, :Data])
    insertcols!(ratio, :Stats => "Ratio")
    insertcols!(stds, :Stats => "Standard Deviation")
    result = vcat(ratio, stds)
    select!(result, [:Drug, :L, :Stats, :Data])
    sort!(result, [:Drug, :L])
end

"""
    stability_report(df::DataFrame; i0 = r"S.*_(.*)_.*", id = r"S.*_(.*)_(.*)_(.*)_.*", order = "TDL", type = "Accuracy")

Compute stability.

# Arguments
* `df`: a `DataFrame`.
* `i0`: `Regex` identifier for day0 samples. The concentration level is captured in the identifier.
* `id`: `Regex` identifier for the stability samples. The storage condition, concentration level, and storage days are captured in the identifier; the order can be set by `order`.
* `order`: a string for setting the order of captured values from `id`; T is temperature (storage condition); D is storage days; L is concentration level
* `type`: quantification value type.
"""
function stability_report(df::DataFrame; i0 = r"S.*_(.*)_.*", id = r"S.*_(.*)_(.*)_(.*)_.*", order = "TDL", type = "Accuracy")
    cols = propertynames(df)
    datatype = cols[2]
    level = cols[1]
    drugs = cols[3:end]
    df = filter(datatype => ==(type), df)
    stability_df = filter(level => Base.Fix1(occursin, i0), df)
    i0_data = Dict(:T => "", :D => 0, :L => getindex.(match.(i0, getproperty(stability_df, level)), 1))
    insertcols!(stability_df, 1, map(Symbol.(split(order, ""))) do p
        p => i0_data[p]
    end...)
    select!(stability_df, Not([datatype, level]))
    ulevel = unique(stability_df.L)
    stability_df2 = filter(level => Base.Fix1(occursin, id), df)
    insertcols!(stability_df2, 1, (Symbol.(split(order, "")) .=> map(1:length(order)) do i 
        getindex.(match.(id, stability_df2[!, level]), i)
    end
    )...)
    select!(stability_df2, Not([datatype, level]))
    stability_df2[!, :D] .= @p stability_df2.D map(parse(Int, _))
    intersect!(ulevel, unique(stability_df2.L))
    append!(stability_df, stability_df2)
    filter!(:L => in(ulevel), stability_df)
    sort!(stability_df, :D)
    stability_df = stack(stability_df, drugs, [:T, :D, :L]; variable_name = :Drug, value_name = :Data)
    gdf = groupby(stability_df, [:Drug, :T, :D, :L])
    accuracy = combine(gdf, :Data => mean, renamecols = false)
    stds = combine(gdf, :Data => std, renamecols = false)
    insertcols!(accuracy, :Stats => "Accuracy")
    insertcols!(stds, :Stats => "Standard Deviation")
    result = vcat(accuracy, stds)
    select!(result, [:Drug, :T, :D, :L, :Stats, :Data])
    sort!(result, [:Drug, :T, :D, :L])
    day0 = filter(:D => ==(0), result)
    filter!(:D => >(0), result)
    (; day0, result)
end