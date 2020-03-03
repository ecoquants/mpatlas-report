# libraries ----
library(tidyverse)
library(here)
library(glue)

# variables ----
mpas_csv <- here("data/mpas.csv")

# make MPAs ----
mpas <- read_csv(mpas_csv, col_types=cols()) %>% 
  arrange(mpa_name)

make_mpa <- function(mpa_id, mpa_name, formats=c("html")){
  # mpa_id = mpas$mpa_id[1]
  
  # show message of progress
  i_row <- sprintf("%02d", which(mpa_id == mpas$mpa_id))
  message(glue("{i_row} of {nrow(mpas)} MPAs: {mpa_name} ({mpa_id})"))
  
  # render html
  if ("html" %in% formats)
    rmarkdown::render(
      input       = "mpa.Rmd",
      params      = list(
        mpa_id    = mpa_id),
      output_file = glue("docs/mpa_{mpa_id}.html"))
  
  # render pdf
  if ("pdf" %in% formats)
    rmarkdown::render(
      input       = "mpa.Rmd",
      params      = list(
        mpa_id    = mpa_id),
      output_file = glue("docs/mpa_{mpa_id}.pdf"))
}

# walk through all sites to render html
mpas %>% 
  select(mpa_id, mpa_name) %>% 
  pwalk(make_mpa)
