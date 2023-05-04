module Validation
using DataPipes, SplitApplyCombine, TypedTables, Statistics, CSV
import Base: sort
export read_data, qc_report, ap_report, recovery_report, stability_report, flatten_stability, flatten_ap

function read_data(file)
    t = Vector{Vector{String}}(undef, 2)
    for (i, l) in enumerate(eachline(file))
        i > 2 && break
        t[i] = split(l, ",")
    end    
    #t[2] = replace.(t[2], r".*Con.*" => "Concentration")
    ic = @p t[1] findall(occursin("Results", _)) 
    #id_info = @p t[1] findfirst(occursin("Results", _))
    cname = @p ic map(Symbol(replace(t[1][_], " Results" => "")))
    n_datatype = round(Int, (length(t[1]) - ic[1] + 1) / length(ic)) - 1
    dname = t[2][ic[1]:ic[1] + n_datatype]
    
    tbl_id = CSV.read(file, Table; select = [2], skipto = 3)
    mapreduce(vcat, 0:n_datatype) do i
        tbl = CSV.read(file, Table; select = ic .+ i, skipto = 3)
        Table(; Symbol(t[2][2]) => tbl_id.Column2, var"Data Type" = repeat([dname[i + 1]], size(tbl_id, 1)), (cname .=> collect(columns(tbl)))...)
    end
end

rsd(v) = std(v) / mean(v) * 100

apply(fs, x...) = [f(x...) for f in fs]

function qc_report(tbl::Table; id = r"PooledQC", type = "Final Conc.", stats = [mean, rsd])
    cols = propertynames(tbl)
    qc = @p tbl filter(occursin(id, getproperty(_, cols[1]))) filter(==(type, getproperty(_, cols[2]))) Table
    cols = propertynames(qc)[3:end]
    report = @p getproperties(qc, cols) columns map(apply(stats, _))
    Table((Stats = stats, ), report)
end

function ap_report(tbls::Table...; id = r"Pre.*_(.*)_.*", type = "Accuracy")
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
    rsds = fmap(Table ∘ (fmap ^ 2)(f_rsd))(vars, accuracies)
    var_bet = @p accuracies map(map(var, columns(_)))
    var_inter = (fmap ^ 2)(f_var_inter)(var_bet, var_intra, ns)
    repeatability = (fmap ^ 2)(f_rsd)(var_intra, accuracy)
    reproducibility = (fmap ^ 2)(f_rsd)(var_inter, var_intra, accuracy)
    stats = ["Accuracy", "Intraday variance", "\"Betweenday\" variance", "Interday variance", "Repeatability", "Reproducibility"]
    (
        daily = (accuracy = accuracies, rsd = rsds), 
        final = fmap((x -> Table((Stats = stats, ), x)) ∘ fmap(vcat))(accuracy, var_intra, var_bet, var_inter, repeatability, reproducibility)
    )
end

function recovery_report(tbl::Table; pre = r"Pre.*_(.*)_.*", post = r"Post.*_(.*)_.*", type = "Final Conc.", stats = [mean, rsd])
    cols = propertynames(tbl)
    df = @p tbl filter(==(type, getproperty(_, cols[2]))) 
    pre_tbl = @p df filter(occursin(pre, getproperty(_, cols[1]))) Table
    post_tbl = @p df filter(occursin(post, getproperty(_, cols[1]))) Table
    level = cols[1]
    getproperty(pre_tbl, level) .= getindex.(match.(pre, getproperty(pre_tbl, level)), 1)
    getproperty(post_tbl, level) .= getindex.(match.(post, getproperty(post_tbl, level)), 1)
    pre_tbls = @p pre_tbl group(getproperty(level)) map(getproperties(_, propertynames(pre_tbl)[3:end])) map(columns)
    post_tbls = @p post_tbl group(getproperty(level)) map(getproperties(_, propertynames(post_tbl)[3:end])) map(columns)
    pre_report = @p pre_tbls map(Table ∘ fmap(x -> apply(stats, x)))
    post_report = @p post_tbls map(Table ∘ fmap(x -> apply(stats, x)))
    map((x, y) -> Table((Stats = ["recovery", "rsd"], ), Table(fmap(map)([/, std_sum], x, y))), pre_report, post_report)
end

function stability_report(tbl::Table; d0 = r"S.*_(.*)_.*", days = r"S.*_(.*)_(.*)_(.*)_.*", order = "TDL", type = "Accuracy")
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
    gtbl = @p stability_tbl group(getproperty(:T)) map(group(getproperty(:L), _)) map(map(x -> group(getproperty(:D), x), _)) map((fmap ^ 2)(getproperties(propertynames(stability_tbl)[3:end - 3])))
    d0_accuracy = @p d0_gtbl map(fmap(mean))
    d0_rsd = @p d0_gtbl map(fmap(rsd))
    accuracy = @p gtbl map(fmap((x -> Table((Days = ndays, ), x)) ∘ vcat_fmap2_table_skip1(mean))(d0_accuracy , _))
    rsds = @p gtbl map(fmap((x -> Table((Days = ndays, ), x)) ∘ vcat_fmap2_table_skip1(rsd))(d0_rsd , _))
    (accuracy = accuracy, rsd = rsds)
end

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
f_rsd(vars, means) = sqrt(vars) / means * 100
f_rsd(var1, var2, means) = sqrt(var1 + var2) / means * 100
std_sum(x, y) = sqrt(x^2 + y^2)

function flatten_stability(data::NamedTuple)
    data = map(data) do dt
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
    cols = @p data.accuracy propertynames collect
    new = Pair{Symbol, Any}[:Temp => data.accuracy.Temp, :Days => data.accuracy.Days]
    cols = cols[3:end]
    for col in cols
        push!(new, Symbol(string(col) * "_" * "acc") => getproperty(data.accuracy, col))
        push!(new, Symbol(string(col) * "_" * "rsd") => getproperty(data.rsd, col))
    end
    Table(; new...)
end

function flatten_ap(data::TypedTables.Dictionary)
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

end