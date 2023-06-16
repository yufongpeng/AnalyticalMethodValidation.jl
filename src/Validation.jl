module Validation
using DataPipes, SplitApplyCombine, TypedTables, Statistics, CSV
import Base: sort, show
export read_data, Report, Data, QCReport, SampleReport, APData, MEData, RecoveryData, StabilityData

include("utils.jl")

"""
    Data

Abstract type for data.
"""
abstract type Data end

"""
    Report{T}

Report type.

# Fields
* `data`: `Data` object.
* `report`: `Table` object.
"""
mutable struct Report{T}
    data::T
    report::Table
end

"""
    QCReport

A wrapper of `Table` containing QC results.

# Fields
* `report`: QC table.
"""
struct QCReport
    report::Table
    function QCReport(tbl::Table; id = r"PooledQC", type = "Final Conc.", stats = [mean, std, rsd])
        cols = propertynames(tbl)
        qc = @p tbl filter(occursin(id, getproperty(_, cols[1]))) filter(==(type, getproperty(_, cols[2]))) Table
        cols = propertynames(qc)[3:end]
        report = @p getproperties(qc, cols) columns map(apply(stats, _))
        new(Table((Stats = stats, ), report))
    end
end

"""
    SampleReport

A wrapper of `Table` containing sample results.

# Fields
* `report`: sample table.
"""
struct SampleReport
    report::Table
    function SampleReport(tbl::Table; id = r"Sample_(\d*).*", type = "Final Conc.")
        cols = propertynames(tbl)
        sample = @p tbl filter(occursin(id, getproperty(_, cols[1]))) filter(==(type, getproperty(_, cols[2]))) Table
        getproperty(sample, cols[1]) .= map(x -> match(id, x)[1], getproperty(sample, cols[1]))
        @p sample group(getproperty(cols[1])) map(getproperties(_, cols[3:end])) map(map(mean, columns(_))) reduce(vcat) Table Table((sample = unique(getproperty(sample, cols[1])),); (cols[3:end] .=> collect(columns(__)))...) new
    end
end

"""
    APData <: Data

A type for accuracy and precision results.

# Fields
* `daily`: a `Table` containing daily accuracy, standard deviation, and relative standard deviation.
* `summary`: a `Table` containing overall accuracy, intraday variation, interday variation, repeatability, and reproducalbility. 
"""
struct APData <: Data
    daily::NamedTuple
    summary::TypedTables.Dictionary
end

"""
    MEData <: Data

A type for matrix effect results.

# Fields
* `data`: a `Dictionary`. The keys are concentration levels, and the values are `Table`s.
"""
struct MEData <: Data
    data::TypedTables.Dictionary
end

"""
    RecoveryData <: Data

A type for recovery results.

# Fields
* `data`: a `Dictionary`. The keys are concentration levels, and the values are `Table`s.
"""
struct RecoveryData <: Data
    data::TypedTables.Dictionary
end

"""
    StabilityData <: Data

A type for stability results.

# Fields
* `accuracy`: a `Dictionary`. The keys are storage conditions, and the values are `Dictionary`s whose keys are concentration levels, and values are `Table`s.
* `rsd`: a `Dictionary`. The keys are storage conditions, and the values are `Dictionary`s whose keys are concentration levels, and values are `Table`s.
"""
struct StabilityData <: Data
    accuracy::TypedTables.Dictionary
    rsd::TypedTables.Dictionary
end

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
    cname = @p ic map(Symbol(replace(t[1][_], " Results" => "")))
    n_datatype = round(Int, (length(t[1]) - ic[1] + 1) / length(ic)) - 1
    dname = t[2][ic[1]:ic[1] + n_datatype]
    tbl_id = CSV.read(file, Table; select = [2], skipto = 3)
    mapreduce(vcat, 0:n_datatype) do i
        tbl = CSV.read(file, Table; select = ic .+ i, skipto = 3)
        Table(; Symbol(t[2][2]) => tbl_id.Column2, var"Data Type" = repeat([dname[i + 1]], size(tbl_id, 1)), (cname .=> collect(columns(tbl)))...)
    end
end

include("report.jl")

function show(io::IO, ::MIME"text/plain", report::Report{T}) where T
    println(io, "Report of ", replace(repr(T), "Data" => ""))
    show(io, MIME("text/plain"), report.report)
end

function show(io::IO, ::MIME"text/plain", report::QCReport)
    print(io, "QC Report\n")
    show(io, MIME("text/plain"), report.report)
end

function show(io::IO, ::MIME"text/plain",report::SampleReport)
    print(io, "Sample Report\n")
    show(io, MIME("text/plain"), report.report)
end

end