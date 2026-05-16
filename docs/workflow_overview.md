# Workflow overview

This workflow is for survey projects where several binary questionnaire items are combined into a respondent-level index before modelling.

## 1. Survey input validation

The first component reads a local survey file and checks whether the fields required for the later steps are present. These can include respondent or household identifiers, weights, cluster or sampling-unit fields, strata, region, and candidate index items.

Candidate binary items are audited for observed values, missingness, usable response variation, and compatibility with the configured `0 / 1 / NA` recoding scheme. The output is a structured validation object used by the index-construction step.

## 2. Index construction

The second component recodes selected binary items into a common `0 / 1 / NA` format and keeps an item-level audit of yes, no, missing, and unexpected values.

After recoding, the workflow keeps items with usable variation and builds a complete-case item matrix. Two index-construction options are available:

- PCA on the recoded item matrix;
- a tetrachoric one-factor approach for binary items, if the `psych` package is available and the item structure is suitable.

The score direction is checked against the respondent-level item mean so that the orientation of the index is explicit.

## 3. Model fitting

The third component merges the index scores back into the modelling data and fits regression models. The survey branch uses the `survey` package and can use weights, primary sampling units, and strata where these are available.

A mixed-effects branch is available for checking clustering or hierarchical structure. This branch uses `lme4` and requires the random-effects structure to be supplied explicitly.

The modelling step can export coefficient tables, sample-flow summaries, and variable-typing messages.

## Files

- `R/01_validate_survey_input.R` — input reading, schema checks, and candidate item audit.
- `R/02_construct_survey_index.R` — binary item recoding and index construction.
- `R/03_fit_survey_index_models.R` — survey-weighted and mixed-effects model fitting.
- `examples/example_workflow.R` — placeholder workflow showing how the components are run together.