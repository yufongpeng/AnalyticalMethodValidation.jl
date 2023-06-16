# Validation

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
See "/scipt" for customizable command line interfaces.