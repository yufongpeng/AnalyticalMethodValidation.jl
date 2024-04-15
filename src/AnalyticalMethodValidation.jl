module AnalyticalMethodValidation
using DataPipes, Statistics, CSV, DataFrames, Chain, ChemistryQuantitativeAnalysis, Dictionaries
export read_masshunter, qc_report, sample_report, ap_report, me_report, recovery_report, stability_report, 
        pivot, unpivot,
        mean_plus_minus_std, add_percentage, selectby, normalize, qualify!, qualify
const CQA = ChemistryQuantitativeAnalysis

include("utils.jl")

"""
    read(file, source = :mh)

Read data into `AnalysisTable` from various sourece.

Currently, only data from Agilent MassHunter Quantitative analysis is implemented. The table needs to be flat. There must be a column whose name contains \"Data File\" as id for each file.

The returned `AnalysisTable` contains multiple `SampleDataTable` to repressent different data types which `samplecol` is `:File`.
"""
function read(file, source = :mh; datatype = Dictionary{String,  Symbol}(), numtype = Float64)
    if source == :mh || source == :MassHunter
        read_masshunter(file; datatype, numtype)
    end
end

function read_masshunter(file; datatype = Dictionary{String, Symbol}(), numtype)
    get!(datatype, "Area", :area)
    get!(datatype, "Height", :height)
    get!(datatype, "ISTD Resp. Ratio", :relative_signal)
    get!(datatype, "Final Conc.", :estimated_concentration)
    get!(datatype, "Accuracy", :accuracy)
    t = Vector{Vector{String}}(undef, 2)
    for (i, l) in enumerate(eachline(file))
        i > 2 && break
        t[i] = split(l, ",")
    end    
    #t[2] = replace.(t[2], r".*Con.*" => "Concentration")
    ic = @p t[1] findall(occursin("Results", _)) 
    #id_info = @p t[1] findfirst(occursin("Results", _))
    cname = @p ic map(replace(t[1][_], " Results" => ""))
    n_datatype = round(Int, (length(t[1]) - ic[1] + 1) / length(ic)) - 1
    dname = t[2][ic[1]:ic[1] + n_datatype]
    datafile = findfirst(x -> occursin("Data File", string(x)), t[2])
    tbl_id = CSV.read(file, DataFrame; select = [datafile], skipto = 3)
    at = analysistable(get(datatype, dname[i + 1], Symbol(dname[i + 1])) => begin
        tbl = CSV.read(file, DataFrame; select = ic .+ i, skipto = 3)
        for col in eachcol(tbl)
            replace!(col, missing => 0.0)
        end
        SampleDataTable(:File, DataFrame("File" => getproperty(tbl_id, propertynames(tbl_id)[1]), (cname .=> convert.(Vector{numtype}, eachcol(tbl)))...))
    end for i in 0:n_datatype)
    if "Accuracy" in dname
        dt = getproperty(at, get(datatype, "Accuracy", :accuracy))
        for a in eachanalyte(dt)
            a ./= 100
        end
    end
    at
end 

function read_masshunter(files::AbstractVector; datatype = Dictionary{String, Symbol}(), numtype)
    get!(datatype, "Area", :area)
    get!(datatype, "Height", :height)
    get!(datatype, "ISTD Resp. Ratio", :relative_signal)
    get!(datatype, "Final Conc.", :estimated_concentration)
    get!(datatype, "Accuracy", :accuracy)
    dict = map(files) do file
        t = Vector{Vector{String}}(undef, 2)
        for (i, l) in enumerate(eachline(file))
            i > 2 && break
            t[i] = split(l, ",")
        end    
        #t[2] = replace.(t[2], r".*Con.*" => "Concentration")
        ic = @p t[1] findall(occursin("Results", _)) 
        #id_info = @p t[1] findfirst(occursin("Results", _))
        cname = @p ic map(replace(t[1][_], " Results" => ""))
        n_datatype = round(Int, (length(t[1]) - ic[1] + 1) / length(ic)) - 1
        dname = t[2][ic[1]:ic[1] + n_datatype]
        datafile = findfirst(x -> occursin("Data File", string(x)), t[2])
        tbl_id = CSV.read(file, DataFrame; select = [datafile], skipto = 3)
        dictionary(get(datatype, dname[i + 1], Symbol(dname[i + 1])) => begin
            tbl = CSV.read(file, DataFrame; select = ic .+ i, skipto = 3)
            for col in eachcol(tbl)
                replace!(col, missing => 0.0)
            end
            DataFrame("File" => getproperty(tbl_id, propertynames(tbl_id)[1]), (cname .=> convert.(Vector{numtype}, eachcol(tbl)))...)
        end for i in 0:n_datatype)
    end
    datatype = reduce(intersect!, map(keys, dict))
    at = analysistable(dt => begin
        SampleDataTable(:File, vcat(get.(dict, dt, nothing)...))
    end for dt in datatype)
    acc = get(datatype, "Accuracy", :accuracy)
    if acc in propertynames(at)
        dt = getproperty(at, get(datatype, "Accuracy", :accuracy))
        for a in eachanalyte(dt)
            a ./= 100
        end
    end
    at
end 

include("report.jl")

end