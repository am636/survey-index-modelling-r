# Workflow overview

This workflow is intended for survey projects where several binary questionnaire items are combined into a single respondent-level index before modelling.

## 1. Survey input validation

The first component reads a local survey microdata file and checks whether the fields required for the later workflow are present. It records identifier, weight, cluster, strata, region, and candidate item fields according to the configuration supplied by the user.

The validation step also audits candidate binary items. It checks the observed values, missingness, whether the item looks binary after allowing for common special codes, and whether both `0` and `1` responses are present. The output is a structured object used by the index-construction step.

## 2. Index construction

The second component recodes selected binary items into a common `0 / 1 / NA` format. It keeps an item-level audit showing how many values were recoded as yes, no, missing, or unexpected.

After recoding, the workflow keeps items with usable variation and builds a complete-case item matrix. Two index-construction options are available:

- PCA on the recoded item matrix;
- a tetrachoric one-factor approach for binary items, if the `psych` package is available and the item structure is suitable.

The score direction is checked against the respondent-level item mean, so the orientation of the index is explicit rather than left implicit in the fitted object.

## 3. Model fitting

The third component merges the index scores back into the modelling data and fits regression models. The main model branch uses the `survey` package and can use weights, primary sampling units, and strata where these are available.

A mixed-effects branch is also available for sensitivity checks around clustering or hierarchical structure. This branch uses `lme4` and requires the random-effects structure to be supplied explicitly.

The modelling step can export coefficient tables, sample-flow summaries, and variable-typing messages. These outputs are intended to make model runs easier to inspect and compare without relying only on console output.

## Files

- `R/01_validate_survey_input.R` — input reading, schema checks, and candidate item audit.
- `R/02_construct_survey_index.R` — binary item recoding and index construction.
- `R/03_fit_survey_index_models.R` — survey-weighted and mixed-effects model fitting.
- `examples/example_workflow.R` — placeholder workflow showing how the components are run together.
