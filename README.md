# Survey index construction and modelling examples in R

This repository contains a small methodological example for building an index from binary survey items and using that index in survey-weighted and mixed-effects models.

It is not tied to a particular survey or substantive research project. The purpose is to keep a clear, reusable example of the modelling steps and the checks needed before combining questionnaire items into an analytical score.

## Components

1. `R/01_validate_survey_input.R` — checks identifiers, weights, candidate items, missing values and simple coding problems.
2. `R/02_construct_survey_index.R` — recodes selected binary items and estimates an index using PCA or a one-factor tetrachoric approach.
3. `R/03_fit_survey_index_models.R` — fits survey-weighted regression and optional mixed-effects sensitivity models.

A minimal example is provided in `examples/example_workflow.R`.

## Data

No respondent-level data are included. The scripts expect a local survey file and should only be used with data that can legally and ethically be analysed for the intended purpose.

## Scope

This is a methodological coding example rather than evidence of a substantive survey-research programme. The main value is the transparent handling of recoding, missingness, item selection, weighting and model checks.

**Author:** Ali Moayedi  
University of St Andrews
