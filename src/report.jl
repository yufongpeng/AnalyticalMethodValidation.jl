"""
    APData(tbls::Table...; id = r"Pre.*_(.*)_.*", type = "Accuracy")

Create `APData` from multiple tables.

# Arguments
* `tbls`: each table should contain data of one day.
* `id`: `Regex` identifier for the AP experiment samples. The concentration level is captured in the identifier.
* `type`: quantification value type.
"""
function APData(tbls::Table...; id = r"Pre.*_(.*)_.*", type = "Accuracy")
    gtbls = map(tbls) do tbl
        cols = propertynames(tbl)
        ap = @p tbl filter(occursin(id, getproperty(_, cols[1]))) filter(==(type, getproperty(_, cols[2]))) Table
        level = cols[1]
        getproperty(ap, level) .= getindex.(match.(id, getproperty(ap, level)), 1)
        ap = @p ap group(getproperty(level)) map(getproperties(_, propertynames(ap)[3:end])) map(columns)
    end
    ns = @p gtbls mapreduce(map(x -> map(y -> 1 / length(y), x), _), fmap(vcat)) map(Table) map(map(mean, columns(_)))
    accuracies = @p gtbls mapreduce(map(x -> map(mean, x), _), fmap(vcat)) map(Table)
    vars = @p gtbls mapreduce(map(x -> map(var, x), _), fmap(vcat)) map(Table)
    accuracy = @p accuracies map(map(mean, columns(_)))
    var_intra = @p vars map(map(mean, columns(_)))
    std_intra = @p var_intra map(map(sqrt, _))
    rsds = fmap(Table ∘ (fmap ∘ fmap)(f_rsd))(vars, accuracies)
    stds = fmap(Table ∘ (fmap ∘ fmap)(f_std))(vars)
    var_bet = @p accuracies map(map(var, columns(_)))
    std_bet = @p var_bet map(map(sqrt, _))
    var_inter = (fmap ∘ fmap)(f_var_inter)(var_bet, var_intra, ns)
    std_inter = @p var_inter map(map(sqrt, _))
    repeatability = (fmap ∘ fmap)(f_rsd)(var_intra, accuracy)
    reproducibility = (fmap ∘ fmap)(f_rsd)(var_inter, var_intra, accuracy)
    stats = ["Accuracy", "Intraday standard deviation", "Intraday variance", "\"Betweenday\" standard deviation", "\"Betweenday\" variance", "Interday standard deviation", "Interday variance", "Repeatability", "Reproducibility"]
    APData(
        (accuracy = accuracies, std = stds, rsd = rsds, var = vars), 
        fmap((x -> Table((Stats = stats, ), x)) ∘ fmap(vcat))(accuracy, std_intra, var_intra, std_bet, var_bet, std_inter, var_inter, repeatability, reproducibility)
    )
end

"""
    MEData(tbl::Table; matrix = r"Post.*_(.*)_.*", stds = r"STD.*_(.*)_.*", type = "Area")

Create `MEData` from a table.

# Arguments
* `tbl`: a `Table`.
* `matrix`: `Regex` identifier for samples with matrix. The concentration level is captured in the identifier.
* `stds`: `Regex` identifier for standard solution. The concentration level is captured in the identifier.
* `type`: quantification value type.
"""
MEData(tbl::Table; matrix = r"Post.*_(.*)_.*", stds = r"STD.*_(.*)_.*", type = "Area") = ratio_data(tbl; type, pre = matrix, post = stds) |> MEData

"""
    RecoveryData(tbl::Table; pre = r"Pre.*_(.*)_.*", post = r"Post.*_(.*)_.*", type = "Final Conc.")

Create `RecoveryData` from a table.

# Arguments
* `tbl`: a `Table`.
* `pre`: `Regex` identifier for prespiked samples. The concentration level is captured in the identifier.
* `post`: `Regex` identifier for postspiked samples. The concentration level is captured in the identifier.
* `type`: quantification value type.
"""
RecoveryData(tbl::Table; pre = r"Pre.*_(.*)_.*", post = r"Post.*_(.*)_.*", type = "Final Conc.") = ratio_data(tbl; type, pre, post) |> RecoveryData

function ratio_data(tbl::Table; pre = r"Pre.*_(.*)_.*", post = r"Post.*_(.*)_.*", type = "Final Conc.")
    cols = propertynames(tbl)
    df = @p tbl filter(==(type, getproperty(_, cols[2]))) 
    pre_tbl = @p df filter(occursin(pre, getproperty(_, cols[1]))) Table
    post_tbl = @p df filter(occursin(post, getproperty(_, cols[1]))) Table
    level = cols[1]
    getproperty(pre_tbl, level) .= getindex.(match.(pre, getproperty(pre_tbl, level)), 1)
    getproperty(post_tbl, level) .= getindex.(match.(post, getproperty(post_tbl, level)), 1)
    pre_tbls = @p pre_tbl group(getproperty(level)) map(getproperties(_, propertynames(pre_tbl)[3:end])) map(columns)
    post_tbls = @p post_tbl group(getproperty(level)) map(getproperties(_, propertynames(post_tbl)[3:end])) map(columns)
    pre_report = @p pre_tbls map(Table ∘ fmap(x -> apply([mean, rsd], x)))
    post_report = @p post_tbls map(Table ∘ fmap(x -> apply([mean, rsd], x)))
    report = map((x, y) -> Table((Stats = ["Recovery", "RSD"], ), Table(fmap(map)([pct_ratio, std_sum], x, y))), pre_report, post_report)
    for level in report
        drugs = @p level propertynames collect
        insert!(getproperty(level, drugs[1]), 2, "standard deviation")
        popfirst!(drugs)
        for drug in drugs
            dt = getproperty(level, drug)
            insert!(dt, 2, dt[1] * dt[2])
        end
    end
    report
end

"""
    StabilityData(tbl::Table; d0 = r"S.*_(.*)_.*", days = r"S.*_(.*)_(.*)_(.*)_.*", order = "TDL", type = "Accuracy")

Create `StabilityData` from a table.

# Arguments
* `tbl`: a `Table`.
* `d0`: `Regex` identifier for day0 samples. The concentration level is captured in the identifier.
* `days`: `Regex` identifier for the stability samples. The storage condition, concentration level, and storage days are captured in the identifier; the order can be set by `order`.
* `order`: a string for setting the order of captured values from `days`; T is temperature (storage condition); D is storage days; L is concentration level
* `type`: quantification value type.
"""
function StabilityData(tbl::Table; d0 = r"S.*_(.*)_.*", days = r"S.*_(.*)_(.*)_(.*)_.*", order = "TDL", type = "Accuracy")
    cols = propertynames(tbl)
    df = @p tbl filter(==(type, getproperty(_, cols[2])))
    d0_tbl = @p df filter(occursin(d0, getproperty(_, cols[1]))) Table
    level = cols[1]
    getproperty(d0_tbl, level) .= getindex.(match.(d0, getproperty(d0_tbl, level)), 1)
    stability_tbl = @p df filter(occursin(days, getproperty(_, cols[1]))) Table
    stability_tbl = Table(stability_tbl; (Symbol.(split(order, "")) .=> map(1:length(order)) do i 
        getindex.(match.(days, getproperty(stability_tbl, level)), i)
    end
    )...)
    stability_tbl = Table(stability_tbl; D = (@p stability_tbl.D map(parse(Int, replace(_, "D" => "")))))
    stability_tbl = sort(stability_tbl, :D)
    ls = @p stability_tbl.L unique
    ndays = @p stability_tbl.D unique
    pushfirst!(ndays, 0)
    d0_gtbl = @p d0_tbl filter(in(getproperty(_, level), ls)) group(getproperty(level)) map((columns ∘ getproperties)(_, cols[3:end]))
    gtbl = @p stability_tbl group(getproperty(:T)) map(group(getproperty(:L), _)) map(map(x -> group(getproperty(:D), x), _)) map((fmap ∘ fmap)(getproperties(propertynames(stability_tbl)[3:end - 3])))
    d0_accuracy = @p d0_gtbl map(fmap(mean))
    d0_std = @p d0_gtbl map(fmap(std))
    accuracy = @p gtbl map(fmap((x -> Table((Days = ndays, ), x)) ∘ vcat_fmap2_table_skip1(mean))(d0_accuracy , _))
    stds = @p gtbl map(fmap((x -> Table((Days = ndays, ), x)) ∘ vcat_fmap2_table_skip1(std))(d0_std , _))
    StabilityData(accuracy, stds)
end

"""
    Report(::Data)

Create `Report` from `Data`
"""
function Report(data::StabilityData)
    nt = map((accuracy = data.accuracy, std = data.std)) do dt
        mapreduce(vcat, pairs(dt)) do (temp, tbl)
            levels = @p tbl keys collect
            new = Pair{Symbol, Any}[:Days => getindex(tbl, levels[1]).Days]
            drugs = @p getindex(tbl, levels[1]) propertynames collect
            popfirst!(drugs)
            for drug in drugs
                for level in levels
                    push!(new, Symbol(string(drug) * "_" * level) => getproperty(getindex(tbl, level), drug))
                end
            end
            Table((Temp = repeat([temp], length(new[1][2])), ); new...)
        end
    end
    cols = @p nt.accuracy propertynames collect
    new = Pair{Symbol, Any}[:Temp => nt.accuracy.Temp, :Days => nt.accuracy.Days]
    cols = cols[3:end]
    for col in cols
        push!(new, Symbol(string(col) * "_" * "acc") => getproperty(nt.accuracy, col))
        push!(new, Symbol(string(col) * "_" * "std") => getproperty(nt.std, col))
    end
    Report(data, Table(; new...))
end

function Report(data::APData)
    levels = @p data.summary keys collect
    ndays = size(getindex(data.daily.accuracy, levels[1]), 1)
    stats = vcat([["Accuracy($i)", "standard deviation($i)", "RSD($i)"] for i in 1:ndays]..., getindex(data.summary, levels[1]).Stats)
    new = Pair{Symbol, Any}[:Stats => stats]
    drugs = @p getindex(data.summary, levels[1]) propertynames collect
    popfirst!(drugs)
    for drug in drugs
        for level in levels
            daily_acc = getproperty(data.daily.accuracy[level], drug)
            daily_std = getproperty(data.daily.std[level], drug)
            daily_rsd = getproperty(data.daily.rsd[level], drug)
            stat = vcat([[daily_acc[i], daily_std[i], daily_rsd[i]] for i in 1:ndays]..., getproperty(getindex(data.summary, level), drug))
            push!(new, Symbol(string(drug) * "_" * level) => stat)
        end
    end
    Report(data, Table(; new...))
end

Report(data::RecoveryData) = Report(data, ratio_report(data.data))
Report(data::MEData) = Report(data, ratio_report(data.data))

function ratio_report(data::TypedTables.Dictionary)
    levels = @p data keys collect
    new = Pair{Symbol, Any}[:Stats => getindex(data, levels[1]).Stats]
    drugs = @p getindex(data, levels[1]) propertynames collect
    popfirst!(drugs)
    for drug in drugs
        for level in levels
            push!(new, Symbol(string(drug) * "_" * level) => getproperty(getindex(data, level), drug))
        end
    end
    Table(; new...)
end

