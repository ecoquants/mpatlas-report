# load libraries
if (!require(librarian)){
  # https://github.com/DesiQuintans/librarian/issues/21
  if (!require(remotes))
    install.packages("remotes")
  remotes::install_github("DesiQuintans/librarian")
  library(librarian)
}
shelf(
  fs, here, glue, 
  DBI, odbc, RPostgres,
  tibble, readr, dplyr, tidyr, purrr, stringr,
  sf, leaflet)

# connection to database

# pwd <- readLines("/share/config/mpatlas4r.org_password.txt")
# con <- DBI::dbConnect(
#   RPostgres::Postgres(),
#   dbname   = "gis",
#   host     = "postgis",
#   port     = 5432,
#   user     = "admin",
#   password = pwd)

con <- dbConnect(
  odbc::odbc(), "mpatlas")

#dbRemoveTable(con, "eez")
#dbListTables(con)
#dbGetQuery(con, "SELECT version();") #12.3

get_mpa <- function(mpa_id){
  flds <- c(
    "mpa_id", "wdpa_id", "name", "long_name", "short_name", 
    "slug", "country", "sub_location", 
    "designation", "designation_eng", "designation_type", 
    "iucn_category", "int_criteria", "marine", "status", 
    "status_year", "no_take", 
    "no_take_area", "rep_m_area", "calc_m_area", "rep_area", "calc_area", 
    "gov_type", "mgmt_auth", "mgmt_plan_type", "mgmt_plan_ref", 
    "contact_id", "conservation_effectiveness", "protection_level", 
    "fishing", "fishing_info", "fishing_citation", 
    "access", "access_citation", "primary_conservation_focus", 
    "secondary_conservation_focus", "tertiary_conservation_focus", 
    "conservation_focus_citation", "protection_focus", "protection_focus_info", 
    "protection_focus_citation", "constancy", "constancy_citation", "permanence", 
    "permanence_citation", "wdpa_notes", "notes", "summary", "is_point", "simple_geom")
  
  st_read(con, query = glue("SELECT {paste(flds, collapse = ',')} FROM mpa_mpa WHERE mpa_id = {mpa_id}"))
}

file2str <- function(path){
  paste(readLines(here(path)), collapse = "\n")
}

