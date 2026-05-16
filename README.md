# Survey index modelling workflow

This repository contains a modular R workflow for working with survey microdata where an analytical index needs to be constructed from multiple binary questionnaire items before modelling. The workflow covers input checks, item recoding, index construction, survey-weighted modelling, mixed-effects sensitivity models, and structured audit outputs.

No raw survey data, derived respondent-level data, or project-specific model outputs are stored in this repository.

## Workflow summary

The workflow is organised into three components.

1. **Survey input validation**
   - Read a local survey microdata file.
   - Standardise variable names where needed.
   - Check required identifier, weight, cluster, and strata fields.
   - Inspect candidate binary survey items and record whether they contain usable response variation.
   - Return a structured validation object for later stages.

2. **Survey index construction**
   - Recode selected binary items into a common `0 / 1 / NA` structure.
   - Audit missing values, unexpected codes, item variation, and complete-case availability.
   - Build an analysis-ready item matrix.
   - Estimate a respondent-level index using either PCA or a tetrachoric one-factor approach.
   - Keep score orientation explicit so that the direction of the index is documented.

3. **Model fitting and reporting**
   - Merge the respondent-level index back into the modelling data using explicit keys.
   - Apply consistent variable typing through a modelling registry.
   - Fit a survey-weighted Gaussian model as the main design-aware model.
   - Fit optional mixed-effects models to examine hierarchical structure and clustering.
   - Export coefficient tables, model summaries, sample-flow checks, warnings, and audit files.

## Repository layout

```text
.
├── R/
│   ├── 01_validate_survey_input.R
│   ├── 02_construct_survey_index.R
│   └── 03_fit_survey_index_models.R
├── examples/
│   └── example_workflow.R
├── docs/
│   └── workflow_overview.md
├── data/
│   └── README.md
├── outputs/
│   └── README.md
├── README.md
├── LICENSE
└── .gitignore
```

## Example use

```r
source("R/01_validate_survey_input.R")
source("R/02_construct_survey_index.R")
source("R/03_fit_survey_index_models.R")

validation <- validate_survey_input(
  file_path = "path/to/local_survey_file.dta",
  config = survey_validation_config(
    required_ids = c("cluster_id", "household_id", "respondent_id", "weight"),
    optional_vars = c("psu", "strata", "region", "urban_rural"),
    candidate_items = c("item_a", "item_b", "item_c", "item_d")
  )
)

index_obj <- construct_survey_index(
  validation,
  config = survey_index_config(
    override_items = c("item_a", "item_b", "item_c", "item_d"),
    method = "pca"
  )
)

model_obj <- fit_survey_index_model(
  data = validation$data,
  index_obj = index_obj,
  outcome_var = "survey_index",
  predictors = c("age", "education", "wealth", "urban_rural", "region"),
  ids = survey_design_ids(
    weight = "weight",
    psu = "psu",
    strata = "strata"
  )
)
```

## Data

The scripts are written for local survey files that the user is allowed to access. Raw data and generated outputs should be kept outside version control unless they are small, anonymised, and explicitly shareable.

The `.gitignore` file excludes common raw-data and output formats such as `.dta`, `.sav`, `.csv`, `.rds`, `.RData`, and generated output folders.

## Requirements

Core packages depend on which parts of the workflow are used:

- `haven` for reading Stata survey files;
- `survey` for design-aware model fitting;
- `lme4` for mixed-effects models;
- `psych` for tetrachoric index construction, if that option is used.

## License

MIT License.