module Validation
using DataPipes, Statistics, CSV, DataFrames
export read_data, qc_report, sample_report, ap_report, me_report, recovery_report, stability_report, flat, mean_plus_minus_std, merge_stats, normalize

include("utils.jl")

"""
    read_data(file)

Read csv data from Agilent MassHunter Quantitative analysis. The table needs to be flat.
"""
function read_data(file)
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
    tbl_id = CSV.read(file, DataFrame; select = [2], skipto = 3)
    mapreduce(vcat, 0:n_datatype) do i
        tbl = CSV.read(file, DataFrame; select = ic .+ i, skipto = 3)
        DataFrame(t[2][2] => tbl_id.Column2, "Data Type" => repeat([dname[i + 1]], size(tbl_id, 1)), (cname .=> eachcol(tbl))...)
    end
end

include("report.jl")

end