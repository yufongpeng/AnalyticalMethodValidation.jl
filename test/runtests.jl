using AnalyticalMethodValidation, ChemistryQuantitativeAnalysis, DataFrames, Statistics, Chain
using Test
const AMA = AnalyticalMethodValidation
const CQA = ChemistryQuantitativeAnalysis

@testset "AnalyticalMethodValidation.jl" begin
    df1 = AMA.read(joinpath("data", "D1.csv"))
    df2 = AMA.read(joinpath("data", "D2S0S7.csv"))
    dfs = AMA.read(joinpath.("data", ["D1.csv", "D2S0S7.csv", "D3.csv"]))
    qc_t = filter("File" => Base.Fix1(occursin, r"PooledQC"), CQA.table(df1.estimated_concentration))
    qc = qc_report(df1; pct = false)
    @test isapprox(qc.Data[1], mean(qc_t.A))
    ap = ap_report(dfs)
    re = recovery_report(df1)
    me = me_report(df1; matrix = r"Pre.*_(.*)_.*", stds = r"Post.*_(.*)_.*")
    st = stability_report(df2; d0 = r"Pre.*_(.*)_.*", id = r"S.*_(.*)_D(.*)_(.*)_.*")
    @test isapprox(std(ap.daily.Data[1:2:5]), ap.summary.Data[3])
    @test isapprox(ap.summary.Data[3] ^ 2 - ap.summary.Data[1] ^ 2 / 5, ap.summary.Data[4] ^ 2)
    @test isapprox(sqrt(ap.summary.Data[4] ^ 2 + ap.summary.Data[1] ^ 2) * 100 / ap.summary.Data[2], ap.summary.Data[6])
    sample = AMA.read(joinpath("data", "sample.csv"))
    sp = @chain sample begin
        sample_report
        pivot(:Analyte)
        qualify(; lod = [1.5, 0.03, 0.3], loq = [5, 0.1, 1], lodsub = missing, loqsub = [1.5, 0.03, 0.3])
    end
    @test collect(sp[1, [2, 4]]) == [1.5, 0.3]
    @test ismissing(sp[4, 4])
    m = merge_stats(st.result, ["Accuracy(%)", "Standard Deviation(%)"] => mean_plus_minus_std)
    pv = pivot(m, [:Analyte, :Level]; drop = :Stats)
    @test m[all.(zip(m.Analyte .== "A", m.Condition .== "4C", m.Level .== "0-2")), "Data"][begin] == pv[pv.Condition .== "4C", "Data|Analyte=A|Level=0-2"][begin]
    # @test unpivot(pv, "Level") == pivot(m, "Analyte"; drop = :Stats)
    @test m.Data == unpivot(pv, ["Level", "Analyte"]; rows = :Analyte).Data
    mqc = @chain qc begin
        merge_stats(["Mean", "Standard Deviation"] => mean_plus_minus_std => "Mean", "Relative Standard Deviation" => add_percentage => "RSD")
        pivot(:Stats; prefix = false)
    end
    @test mqc[1, "Data|RSD"] == "4.37%"
end