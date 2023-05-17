# Validation

A small package for analyzing method validation data. It only accepts csv data from Agilent MassHunter Quantitative analysis and the table needs to be flat.

## Function
1. `read_data`: read the data with some transformation.
2. `qc_report`: calculate accuracy and rsd of QC samples.
3. `ap_report`: calculate accuracy, repeatability and reproducibility.
4. `recovery_report`: calculate recovery by prespiked/postspiked.
5. `stability_report`: calculate accuracy and rsd of QC samples in different tempearture and restoration days.
6. `flatten_ap`: flatten nested `ap_report` for CSV output.
6. `flatten_recovery`: flatten nested `recovery_report` for CSV output.
7. `flatten_stability`: flatten nested `stability_report` for CSV output.

## Scripts
See "/scipt" for customizable command line interfaces.