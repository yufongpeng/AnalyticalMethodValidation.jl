using Validation, DataFrames, DataPipes, Statistics
using Test

@testset "Validation.jl" begin
    dfs = read_data.(["data/D1.csv", "data/D2S0S7.csv", "data/D3.csv", "data/S30.csv"])
    qc_t = @p dfs[1] filter("File" => Base.Fix1(occursin, r"PooledQC")) filter("Data Type" => ==("Final Conc."))
    qc = qc_report(dfs[1])
    @test isapprox(qc.Data[1], mean(qc_t.A))
    ap = ap_report(vcat(dfs[1:3]...))
    re = recovery_report(dfs[1])
    me = me_report(dfs[1]; matrix = r"Pre.*_(.*)_.*", stds = r"Post.*_(.*)_.*", type = "Area")
    st = stability_report(dfs[2]; d0 = r"Pre.*_(.*)_.*", id = r"S.*_(.*)_D(.*)_(.*)_.*")
    @test isapprox(std(ap.daily.Data[1:2:5]), ap.summary.Data[3])
    @test isapprox(ap.summary.Data[3] ^ 2 - ap.summary.Data[1] ^ 2 / 5, ap.summary.Data[4] ^ 2)
    @test isapprox(sqrt(ap.summary.Data[4] ^ 2 + ap.summary.Data[1] ^ 2) * 100 / ap.summary.Data[2], ap.summary.Data[6])
    sample = read_data("data/sample.csv")
    sp = sample_report(sample)
end