using Validation, TypedTables, DataPipes, Statistics
using Test

@testset "Validation.jl" begin
    tbls = read_data.(["data/D1.csv", "data/D2S0S7.csv", "data/D3.csv", "data/S30.csv"])
    qc_t = @p tbls[1] filter(occursin(r"PooledQC", _.var"Data File")) filter(==("Final Conc.", _.var"Data Type")) Table
    qc = QCReport(tbls[1])
    @test isapprox(qc.report.A[1], mean(qc_t.A))
    ap = APData(tbls[1:3]...)
    re = RecoveryData(tbls[1])
    me = MEData(tbls[1]; matrix = r"Pre.*_(.*)_.*", stds = r"Post.*_(.*)_.*", type = "Area")
    st = StabilityData(reduce(append!, tbls[[2, 4]]))
    rap = Report(ap)
    @test isapprox(var(rap.report.A_01[[1,4,7]]), rap.report.A_01[14])
    @test isapprox(rap.report.A_01[14] - rap.report.A_01[12] / 5, rap.report.A_01[16])
    @test isapprox(rap.report.A_01[16] + rap.report.A_01[12], (rap.report.A_01[18] * rap.report.A_01[10] / 100) ^ 2)
    rre = Report(re)
    rme = Report(me)
    rst = Report(st)
    sample = read_data("data/sample.csv")
    sp = SampleReport(sample)
    @test isapprox(sp.report.A[2], mean(sample.A[270:271]))
end