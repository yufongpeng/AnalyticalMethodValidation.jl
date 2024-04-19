# AnalyticalMethodValidation

|CI status|Coverage|
|:-------:|:------:|
[![][ci-img]][ci-url]| [![][codecov-img]][codecov-url]|

[ci-img]: https://github.com/yufongpeng/AnalyticalMethodValidation.jl/actions/workflows/CI.yml/badge.svg?branch=main
[ci-url]: https://github.com/yufongpeng/AnalyticalMethodValidation.jl/actions/workflows/CI.yml?query=branch%3Amain
[codecov-img]: https://codecov.io/gh/yufongpeng/AnalyticalMethodValidation.jl/branch/main/graph/badge.svg
[codecov-url]: https://codecov.io/gh/yufongpeng/AnalyticalMethodValidation.jl

A small package for analytical method validation, and sample analysis.

For command line interfaces, see [`juliaquant`](https://github.com/yufongpeng/juliaquant).

## Function
1. `read`: read csv file(s) into `AnalysisTable` (See [`ChemistryQuantitativeAnalysis.jl`](https://github.com/yufongpeng/ChemistryQuantitativeAnalysis.jl)). Currently, only data from MassHunter Software in wide format is supported.

### Report functions
These function accept `AnalysisTable` or `Batch`.
1. `qc_report`: compute statistics of QC samples.
2. `ap_report`: compute accuracy, repeatability and reproducibility.
3. `recovery_report`: compute recovery by prespiked/postspiked.
4. `me_report`: compute matrix effect by with_matrix/std_solution.
5. `stability_report`: compute stability in different condition and restoration days.
6. `sample_report`: average each sample.

### Util functions
1. `pivot`: transform dataframe into wide format.
2. `unpivot`: transform dataframe into long format. 
3. `selectby`: select values by specific column, and apply `select!` as if the values are columns. This function is useful to merge multiple statistical values into specific formats.
4. `mean_plus_minus_std`: round and merge mean values and standard deviations with "±".
5. `add_percentage`: add "%".
6. `normalize`: normalize dataframe by the given normalizer.
7. `qualify`: replace data out of acceptable range.
8. `qualify!`: replace data out of acceptable range.

## Computation
### Intra-day

$$a_{d,j } = \dfrac{c_{d, j}}{conc.}$$

$$\mu_{d} = \sum_{j=1}^{n_d} \dfrac{a_{d, j}}{n_d}$$

$$s_{intra}^2 = \dfrac{1}{p}\sum_{i = 1}^{p}\sum_{j = 1}^{n_i} \dfrac{(a_{i, j} - \mu_i)^2}{n_i - 1}$$

$$accuracy_{intra, d} = \mu_{d}$$

$$rsd_{intra, d} = \dfrac{s_{intra}}{accuracy_{intra, d}}$$

$p$: number of days, $n_i$: number of repeats of $i$ th day, $c_{i, j}$: measured concentration of $i$ th day and $j$ th repeat, $conc.$: reference concentration
### Inter-day

$$\mu = \dfrac{1}{p}\sum_{i = 1}^{p}\sum_{j = 1}^{n_i} \dfrac{a_{i, j}}{n_i}$$

$$accuracy_{inter} = \sum_{i = 1}^{p} \dfrac{accuracy_{intra, i}}{p} = \mu$$

$$repeatability = rsd_{intra} = \dfrac{s_{intra}}{accuracy_{inter}}$$

$$s_{between}^2 = \sum_{i = 1}^{p} \dfrac{(\mu_i - \mu)^2}{n_d - 1}$$

$$s_{inter}^2 = max\ \{0, s_{between}^2 - \dfrac{s_{intra}^2}{\hat{n}}\ \}$$

$$\hat{n}=\dfrac{p}{\sum_{i=1}^p\dfrac{1}{n_i}}$$

$$reproducibility = rsd_{total} = \dfrac{\sqrt{s_{inter}^2+s_{intra}^2}}{accuracy_{inter}}$$

## Reference
[Guidelines and Recommendations of the GTFCh](https://www.gtfch.org/cms/index.php/en/guidelines)

[Appendix B - Requirements for the validation of analytical methods](https://www.gtfch.org/cms/images/stories/files/Appendix%20B%20GTFCh%2020090601.pdf)
p.21~p.22