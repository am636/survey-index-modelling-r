# Example workflow
#
# This file shows the intended order of the three components.
# It uses placeholder variable names and should be adapted to the local survey file.

source("R/01_validate_survey_input.R")
source("R/02_construct_survey_index.R")
source("R/03_fit_survey_index_models.R")

# 1. Validate the input survey file
validation <- validate_survey_input(
  file_path = "path/to/local_survey_file.dta",
  config = survey_validation_config(
    required_ids = c("cluster_id", "household_id", "respondent_id", "weight"),
    optional_vars = c("psu", "strata", "region", "urban_rural"),
    candidate_items = c("item_a", "item_b", "item_c", "item_d")
  )
)

print(validation)
validation_summary_table(validation)

# 2. Recode binary items and construct an index
index_obj <- construct_survey_index(
  validation,
  config = survey_index_config(
    override_items = c("item_a", "item_b", "item_c", "item_d"),
    method = "pca"
  )
)

print(index_obj)
survey_index_summary_table(index_obj)

# Optional alternative, if the required package is installed and the item matrix is suitable:
# index_obj_tetra <- construct_survey_index(
#   validation,
#   config = survey_index_config(
#     override_items = c("item_a", "item_b", "item_c", "item_d"),
#     method = "tetrachoric"
#   )
# )

# 3. Fit a design-aware model using the constructed index
model_obj <- fit_survey_index_model(
  data = validation$data,
  index_obj = index_obj,
  outcome_var = "survey_index",
  predictors = c("age", "education", "wealth", "urban_rural", "region"),
  ids = survey_design_ids(
    weight = "weight",
    psu = "psu",
    strata = "strata"
  ),
  numeric_vars = c("age"),
  factor_vars = c("urban_rural", "region"),
  config = survey_model_config(engine = "survey")
)

print(model_obj)

# 4. Optional mixed-effects sensitivity model
# mixed_model <- fit_survey_index_model(
#   data = validation$data,
#   index_obj = index_obj,
#   outcome_var = "survey_index",
#   predictors = c("age", "education", "wealth", "urban_rural", "region"),
#   ids = survey_design_ids(weight = "weight"),
#   numeric_vars = c("age"),
#   factor_vars = c("urban_rural", "region", "cluster_id"),
#   config = survey_model_config(
#     engine = "mixed",
#     mixed_random = "(1 | cluster_id)"
#   )
# )
