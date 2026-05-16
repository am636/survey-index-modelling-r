# Survey Index Modelling in R

Reusable R workflow for validating survey microdata, constructing respondent-level indices from binary survey items, and fitting design-aware and multilevel sensitivity models.

This repository is intended as a public portfolio template. It does **not** include raw survey data, derived respondent-level data, or project-specific model outputs.

## Why this repository exists

Many applied research projects use complex individual- or household-level survey data where the analytical outcome is not available directly, but must be constructed from multiple questionnaire items. This workflow demonstrates how to organise that process in a reproducible and auditable way.

The workflow is deliberately general. It can be adapted to survey-based projects in population research, health geography, development studies, environmental social science, policy analysis, and applied quantitative research.

## Workflow

The repository is organised as a three-stage workflow:

1. **Validate survey input**  
   Read a survey microdata file, standardise names, check required identifiers, inspect candidate binary survey items, and return a structured validation object.

2. **Construct a survey index**  
   Recode selected binary items into a consistent `0 / 1 / NA` structure, audit missingness and unexpected codes, build an analysis-ready item matrix, and construct a respondent-level index using PCA or a tetrachoric one-factor approach.

3. **Fit survey index models**  
   Merge the index back into the analysis data, type modelling variables using an explicit registry, fit a survey-weighted model as the primary design-aware analysis, and optionally fit mixed-effects models as exploratory multilevel sensitivity checks.

## Repository structure

```text
survey-index-modelling-r/
├── R/
│   ├── 01_validate_survey_input.R
│   ├── 02_construct_survey_index.R
│   └── 03_fit_survey_index_models.R
├── examples/
│   └── example_workflow.R
├── docs/
│   ├── workflow_overview.md
│   └── portfolio_summary.md
├── data/
│   └── README.md
├── outputs/
│   └── README.md
├── README.md
├── LICENSE
└── .gitignore
```

## Skills demonstrated

- Survey microdata validation
- Defensive data-cleaning workflow design
- Binary item recoding and audit trails
- Respondent-level index construction
- PCA-based dimensionality reduction
- Optional tetrachoric factor-analysis workflow
- Survey-weighted modelling
- Mixed-effects sensitivity analysis
- Explicit handling of clustering, strata, and weights
- Reproducible reporting outputs

## Data policy

No data are included in this repository. The scripts are designed to be reusable with appropriately licensed survey microdata supplied locally by the user.

The `.gitignore` file excludes common raw-data and output formats, including `.dta`, `.sav`, `.csv`, `.rds`, `.RData`, and generated output folders.

## Minimal usage pattern

```r
source("R/01_validate_survey_input.R")
source("R/02_construct_survey_index.R")
source("R/03_fit_survey_index_models.R")

validation <- validate_survey_input(
  file_path = "path/to/local_survey_file.dta",
  config = survey_validation_config(
    required_ids = c("cluster_id", "household_id", "respondent_id", "weight"),
    candidate_items = c("item_a", "item_b", "item_c", "item_d")
  )
)

index_obj <- construct_survey_index(
  validation,
  config = survey_index_config(
    override_items = c("item_a", "item_b", "item_c", "item_d")
  )
)

model_obj <- fit_survey_index_model(
  data = validation$data,
  index_obj = index_obj,
  outcome_var = "survey_index",
  predictors = c("age", "education", "wealth", "urban_rural", "region"),
  ids = survey_design_ids(
    weight = "weight",
    psu = "cluster_id",
    strata = "strata_id"
  )
)
```

## Notes on interpretation

The survey-weighted model is the primary design-aware branch. Mixed-effects models are included as exploratory sensitivity checks for hierarchical structure. They should not be interpreted as a direct replacement for full survey-design inference.

## License

MIT License.
