using AnalyticalMethodValidation, ChemistryQuantitativeAnalysis, DataFrames, Statistics, Chain
using Test
const AMV = AnalyticalMethodValidation
const CQA = ChemistryQuantitativeAnalysis

@testset "AnalyticalMethodValidation.jl" begin
    df1 = AMV.read(joinpath("data", "D1.csv"))
    df2 = AMV.read(joinpath("data", "D2S0S7.csv"))
    dfs = AMV.read(joinpath.("data", ["D1.csv", "D2S0S7.csv", "D3.csv"]))
    qc_t = filter("File" => Base.Fix1(occursin, r"PooledQC"), CQA.table(df1.estimated_concentration))
    qc = qc_report(df1; pct = false)
    @test isapprox(qc.Data[1], mean(qc_t.A))
    ap = ap_report(dfs)
    re = recovery_report(df1)
    me = me_report(df1; matrix = r"Pre.*_(.*)_.*", stds = r"Post.*_(.*)_.*")
    st = stability_report(df2; day0 = r"Pre.*_(.*)_.*", stored = r"S.*_(.*)_D(.*)_(.*)_.*")
    st2 = stability_report(df2; day0 = nothing, stored = r"S.*_(.*)_D(.*)_(.*)_.*")
    @test isnothing(st2.day0)
    @test isapprox(std(ap.daily.Data[1:2:5]), ap.summary.Data[3])
    @test isapprox(ap.summary.Data[3] ^ 2 - ap.summary.Data[1] ^ 2 / 5, ap.summary.Data[4] ^ 2)
    @test isapprox(sqrt(ap.summary.Data[4] ^ 2 + ap.summary.Data[1] ^ 2) * 100 / ap.summary.Data[2], ap.summary.Data[6])
    pre_t = filter("File" => Base.Fix1(occursin, r"Pre.*_(.*)_.*"), CQA.table(df1.area))
    post_t = filter("File" => Base.Fix1(occursin, r"Post.*_(.*)_.*"), CQA.table(df1.area))
    @test isapprox(mean(pre_t.A[1:5]) / mean(post_t.A[1:3]) * 100, re.Data[1])
    d0_t = filter("File" => Base.Fix1(occursin, r"Pre.*_(.*)_.*"), CQA.table(df2.accuracy))
    d7_t = filter("File" => Base.Fix1(occursin, r"S.*_(.*)_D(.*)_(.*)_.*"), CQA.table(df2.accuracy))
    @test isapprox(mean(d0_t.A[6:10]) * 100, st.day0.Data[1])
    @test isapprox(mean(d7_t.A[1:3]) * 100, st.stored.Data[9])
    @test isapprox(st.stored.Data[9] / st.day0.Data[1] * 100, st.stored_over_day0.Data[9])
    sample = AMV.read(joinpath("data", "sample.csv"))
    sp = @chain sample begin
        sample_report
        selectby(:Stats, "Mean")
        pivot([:Analyte, :Stats])
        qualify(; lod = [1.5, 0.03, 0.3], loq = [5, 0.1, 1], lodsub = missing, loqsub = [1.5, 0.03, 0.3])
    end
    @test collect(sp[1, [2, 4]]) == [1.5, 0.3]
    @test ismissing(sp[4, 4])
    sp2 = sample_report(dfs; id = r"Pre.*_(.*)_.*", type = :accuracy, pct = true)
    @test all(endswith("(%)"), sp2.Stats)
    @test all(>(1), sp2.Data)
    m = selectby(st.stored, :Stats, ["Accuracy(%)", "Standard Deviation(%)"] => mean_plus_minus_std => "Accuracy(%)")
    pv = pivot(m, [:Analyte, :Level]; drop = :Stats)
    @test m[all.(zip(m.Analyte .== "A", m.Condition .== "4C", m.Level .== "0-2")), "Data"][begin] == pv[pv.Condition .== "4C", "Data|Analyte=A|Level=0-2"][begin]
    @test unpivot(pv, "Level") == pivot(m, ["Analyte"]; drop = :Stats)
    @test m.Data == unpivot(pv, ["Level", "Analyte"]; rows = :Analyte).Data
    qc1 = selectby(qc, :Stats, ["Mean", "Standard Deviation"] => mean_plus_minus_std => "Mean", "Relative Standard Deviation" => add_percentage => "RSD"; pivot = true, prefix = false)
    qc2 = @chain qc begin
        pivot(:Stats)
        selectby(:Stats, ["Mean", "Standard Deviation"] => mean_plus_minus_std => "Mean", "Relative Standard Deviation" => add_percentage => "RSD")
    end
    apr = selectby(pivot(ap.daily, :Analyte), :Stats, ["Accuracy(%)", "Standard Deviation(%)"] => mean_plus_minus_std => "Accuracy(%)"; pivot = true, prefix = false)
    @test qc1[1, "Data|RSD"] == "4.37%"
    @test qc2[2, "Data|Stats=RSD"] == "5.06%"
    @test apr[1, "Data|Analyte=A|Accuracy(%)"] == "86.53±6.11"
    @test all(normalize(re, re; stats = (All(), "Recovery(%)")).Data[1:2:end] .== 1.0)
end