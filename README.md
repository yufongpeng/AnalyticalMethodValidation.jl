# Validation

|CI status|Coverage|
|:-------:|:------:|
[![][ci-img]][ci-url]| [![][codecov-img]][codecov-url]|

[ci-img]: https://github.com/yufongpeng/Validation.jl/actions/workflows/CI.yml/badge.svg?branch=main
[ci-url]: https://github.com/yufongpeng/Validation.jl/actions/workflows/CI.yml?query=branch%3Amain
[codecov-img]: https://codecov.io/gh/yufongpeng/Validation.jl/branch/main/graph/badge.svg
[codecov-url]: https://codecov.io/gh/yufongpeng/Validation.jl

A small package for analyzing method validation data. It only accepts csv data from Agilent MassHunter Quantitative analysis and the table needs to be flat.

## Function
1. `read_data`: read the data with some transformation.
2. `QCReport`: calculate accuracy and rsd of QC samples.
3. `APData`: calculate accuracy, repeatability and reproducibility.
4. `RecoveryData`: calculate recovery by prespiked/postspiked.
5. `MEData`: calculate matrix effect by with_matrix/std_solution.
6. `StabilityData`: calculate accuracy and rsd of QC samples in different tempearture and restoration days.
7. `SampleReport`: average each sample.
8. `Report`: flatten nested `Data` object for CSV output.

## Scripts
See "/scipt" for command line interfaces.

## Computation
### Intra-day

$$\mu_{d} = \sum_{j=1}^{n_d} \dfrac{c_{d, j}}{n_d}$$

$$s_{intra}^2 = \dfrac{1}{p}\sum_{i = 1}^{p}\sum_{j = 1}^{n_i} \dfrac{(c_{i, j} - \mu_i)^2}{n_i - 1}$$

$$accuracy_{intra, d} = \dfrac{\mu_{d}}{conc.}$$

$$rsd_{intra, d} = \dfrac{s_{intra}}{accuracy_{intra, d}}$$

$p$: number of days, $n_i$: number of repeats of $i$ th day, $c_{i, j}$: measured concentration of $i$ th day and $j$ th repeat, $conc.$: reference concentration
### Inter-day
$$\mu = \dfrac{1}{p}\sum_{i = 1}^{p}\sum_{j = 1}^{n_i} \dfrac{c_{i, j}}{n_i}$$

$$accuracy_{inter} = \sum_{i = 1}^{p} \dfrac{accuracy_{intra, i}}{p} = \dfrac{\mu}{conc.}$$

$$repeatability = rsd_{intra} = \dfrac{s_{intra}}{accuracy_{inter}}$$

$$s_{between}^2 = \sum_{i = 1}^{p} \dfrac{(\mu_i - \mu)^2}{n_d - 1}$$

$$s_{inter}^2 = max\ \{0, s_{between}^2 - \dfrac{s_{intra}^2}{\hat{n}}\ \}$$

$$\hat{n}=\dfrac{p}{\sum_{i=1}^p\dfrac{1}{n_i}}$$

$$reproducibility = rsd_{total} = \dfrac{\sqrt{s_{inter}^2+s_{intra}^2}}{accuracy_{inter}}$$