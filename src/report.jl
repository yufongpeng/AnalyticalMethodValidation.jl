"""
    qc_report(df::DataFrame; id = r"PooledQC", type = "Final Conc.", stats = [mean, std, rsd], names = ["Mean", "Standard Deviation", "Relative Standard Deviation"])

Compute statistics of QC data.

# Arguments
* `df`: a `DataFrame` returned by `read_data`.
* `id`: `Regex` identifier for the QC samples.
* `type`: quantification value type.
* `stats`: statistics functions.
* `names`: names of statistics. When `nothing` is given, `stats` is served as `names`.
"""
function qc_report(df::DataFrame; id = r"PooledQC", type = "Final Conc.", stats = [mean, std, rsd], names = ["Mean", "Standard Deviation", "Relative Standard Deviation"])
    cols = propertynames(df)
    names = isnothing(names) ? stats : names
    @chain df begin
        filter(cols[1] => Base.Fix1(occursin, id), _) 
        filter(cols[2] => ==(type), _)
        stack(cols[3:end], cols[1]; variable_name = :Drug, value_name = :Data)
        select!([:Drug, :Data])
        groupby(:Drug)
        combine(:Data => x -> vcat(apply(stats, x)...); renamecols = false)
        insertcols!(_, 2, :Stats => repeat(repr.(names); outer = size(_, 1) ÷ length(stats)))
        sort!(:Drug)
    end
end

"""
    sample_report(df::DataFrame; id = r"Sample_(\\d*).*", type = "Final Conc.")

Compute mean of sample data.

# Arguments
* `df`: a `DataFrame` returned by `read_data`.
* `id`: `Regex` identifier for the QC samples.
* `type`: quantification value type.
"""
function sample_report(df::DataFrame; id = r"Sample_(\d*).*", type = "Final Conc.")
    cols = propertynames(df)
    sample = @p df filter(cols[1] => Base.Fix1(occursin, id)) filter(cols[2] => ==(type))
    sample[:, cols[1]] = map(x -> match(id, x)[1], sample[!, cols[1]])
    @chain sample begin
        stack(cols[3:end], cols[1]; variable_name = :Drug, value_name = :Data)
        select!([cols[1], :Drug, :Data])
        groupby([cols[1], :Drug])
        combine(:Data => mean; renamecols = false)
    end
end

"""
    ap_report(df::DataFrame; id = r"Pre.*_(.*)_.*", type = "Accuracy")

Compute accuracy and precision. A `NamedTuple` is returned with two elements: `daily` is a `DataFrame` conataing accuracy and standard deviation for each day, and `summary` is a `DataFrame` conataing overall accuracy, repeatability and reproducibility. 

# Arguments
* `df`: a `DataFrame` returned by `read_data`.
* `id`: `Regex` identifier for the AP experiment samples. The day and concentration level is captured in the identifier; the order can be set by `order`.
* `order`: a string for setting the order of captured values from `id`; D is day; L is concentration level.
* `type`: quantification value type.
"""
function ap_report(df::DataFrame; id = r"Pre(.*)_(.*)_.*", order = "DL", type = "Accuracy")
    cols = propertynames(df)
    datatype = cols[2]
    level = cols[1]
    drugs = cols[3:end]
    ap_df = @chain df begin 
        filter(datatype => ==(type), _)
        filter(level => Base.Fix1(occursin, id), _)
        insertcols!(_, 1, (Symbol.(split(order, "")) .=> map(1:length(order)) do i 
            getindex.(match.(id, _[!, level]), i)
        end
        )...)
        select!(Not([datatype, level]))
    end
    ap_df[!, :D] .= @p ap_df.D map(parse(Int, _))
    ap_df = stack(ap_df, drugs, [:L, :D]; variable_name = :Drug, value_name = :Data)
    gdf = groupby(ap_df, [:Drug, :L, :D])
    ns = @chain gdf begin
        combine(:Data .=> inv ∘ length; renamecols = false)
        groupby([:Drug, :L])
        combine(:Data => mean; renamecols = false)
    end 
    accuracies = combine(gdf, :Data => mean; renamecols = false)
    stds = combine(gdf, :Data => std; renamecols = false)
    vars = combine(gdf, :Data => var; renamecols = false)
    accuracy, var_bet = @chain accuracies begin
        groupby([:Drug, :L])
        (combine(_, :Data => mean; renamecols = false), combine(_, :Data => var; renamecols = false))
    end
    var_intra = combine(groupby(vars, [:Drug, :L]), :Data => mean; renamecols = false)
    var_inter = deepcopy(accuracy)
    var_inter[:, :Data] = @. f_var_inter(getproperty([var_bet, var_intra, ns], :Data)...)
    reproducibility = deepcopy(accuracy)
    reproducibility[:, :Data] = @. f_var_sum_pct(getproperty([var_intra, var_inter, reproducibility], :Data)...)
    std_intra = transform!(var_intra, :Data => ByRow(sqrt); renamecols = false)
    std_bet = transform!(var_bet, :Data => ByRow(sqrt); renamecols = false)
    std_inter = transform!(var_inter, :Data => ByRow(sqrt); renamecols = false)
    repeatability = deepcopy(accuracy)
    repeatability[:, :Data] = @. ratio_pct(getproperty([std_intra, repeatability], :Data)...)
    for (st, nm) in zip([accuracies, stds, accuracy, std_intra, std_bet, std_inter, repeatability, reproducibility], 
                        ["Accuracy", "Standard Deviation", "Accuracy", "Intraday Standard Deviation", "Betweenday Standard Deviation", "Interday Standard Deviation", "Repeatability", "Reproducibility"])
        insertcols!(st, :Stats => nm)
    end
    daily = @chain vcat(accuracies, stds) begin
        select!([:Drug, :L, :D, :Stats, :Data])
        sort!([:Drug, :L, :D])
    end
    summary = @chain vcat(std_intra, accuracy, std_bet, std_inter, repeatability, reproducibility) begin
        select!([:Drug, :L, :Stats, :Data])
        sort!([:Drug, :L])
    end
    (; daily, summary)
end

"""
    me_report(df::DataFrame; matrix = r"Post.*_(.*)_.*", stds = r"STD.*_(.*)_.*", type = "Area")

Compute matrix effects.

# Arguments
* `df`: a `DataFrame` returned by `read_data`.
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
* `df`: a `DataFrame` returned by `read_data`.
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
    df = @chain df begin
        filter(datatype => ==(type), _)
        stack(drugs, level; variable_name = :Drug, value_name = :Data)
        rename!(Dict(level => :L))
    end
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
    @chain vcat(ratio, stds) begin
        select!([:Drug, :L, :Stats, :Data])
        sort!([:Drug, :L])
    end
end

"""
    stability_report(df::DataFrame; d0 = r"S.*_(.*)_.*", id = r"S.*_(.*)_(.*)_(.*)_.*", order = "TDL", type = "Accuracy")

Compute stability. A `NamedTuple` is returned with two elements: `day0` is a `DataFrame` conataing day0 data, and `result` is a `DataFrame` conataing data of other days. 

# Arguments
* `df`: a `DataFrame` returned by `read_data`.
* `d0`: `Regex` identifier for day0 samples. The concentration level is captured in the identifier.
* `id`: `Regex` identifier for the stability samples. The storage condition, concentration level, and storage days are captured in the identifier; the order can be set by `order`.
* `order`: a string for setting the order of captured values from `id`; T is temperature (storage condition); D is storage days; L is concentration level
* `type`: quantification value type.
"""
function stability_report(df::DataFrame; d0 = r"S.*_(.*)_.*", id = r"S.*_(.*)_(.*)_(.*)_.*", order = "TDL", type = "Accuracy")
    cols = propertynames(df)
    datatype = cols[2]
    level = cols[1]
    drugs = cols[3:end]
    df = filter(datatype => ==(type), df)
    stability_df = filter(level => Base.Fix1(occursin, d0), df)
    d0_data = Dict(:T => "", :D => 0, :L => getindex.(match.(d0, getproperty(stability_df, level)), 1))
    insertcols!(stability_df, 1, map(Symbol.(split(order, ""))) do p
        p => d0_data[p]
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
    stability_df = @chain stability_df begin
        append!(stability_df2)
        filter!(:L => in(ulevel), _)
        sort!(:D)
        stack(drugs, [:T, :D, :L]; variable_name = :Drug, value_name = :Data) 
    end
    gdf = groupby(stability_df, [:Drug, :T, :D, :L])
    accuracy = combine(gdf, :Data => mean, renamecols = false)
    stds = combine(gdf, :Data => std, renamecols = false)
    insertcols!(accuracy, :Stats => "Accuracy")
    insertcols!(stds, :Stats => "Standard Deviation")
    result = @chain vcat(accuracy, stds) begin
        select!([:Drug, :T, :D, :L, :Stats, :Data])
        sort!([:Drug, :T, :D, :L])
    end
    day0 = filter(:D => ==(0), result)
    filter!(:D => >(0), result)
    (; day0, result)
end