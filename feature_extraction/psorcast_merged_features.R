########################################################################
#' Psoriasis Validation
#' 
#' Purpose: 
#' This script is used to merge all of the .tsv files
#' used for analysis of psorcast, it will clean redundant record by taking
#' the most recent record of a given day (assuming one day per test). 
#' 
#' It will also output a fully row-binded tables containing each 
#' participant_id, date of test, and source table info 
#' for future debugging purposes.
#'
#' Author: Aryton Tediarjo
#' email: aryton.tediarjo@sagebase.org
########################################################################
rm(list=ls())
gc()

# import libraries
library(synapser)
library(data.table)
library(tidyverse)
library(githubr)
library(config)
source("utils/feature_extraction_utils.R")
source('utils/processing_log_utils.R')
synLogin()

############################
# Global Vars
############################
OUTPUT_REF <- list(
    merged_file = "psorcast_merged_features.tsv",
    removed_records = "error_log_psorcast_merged_features.tsv")
PARENT_REF <- list(
    merged_file = "syn22346256",
    removed_records = "syn25832341")
PPACMAN_TBL_ID <- "syn22337133"
PARENT_SYN_ID <- "syn22346256"
FEATURES_ID <- list(
    djo = "syn26158358",
    dig_jc = "syn25830490",
    gs_jc = "syn25832772",
    gs_swell = "syn25832774",
    pso_draw = "syn22341657",
    walk = "syn25832106"
)

############################
# Git Reference
############################
SCRIPT_PATH <- file.path('feature_extraction', "psorcast_merged_features.R")
GIT_TOKEN_PATH <- config::get("git")$token_path
GIT_REPO <- config::get("git")$repo
githubr::setGithubToken(readLines(GIT_TOKEN_PATH))
GIT_URL <- getPermlink(
    repository = getRepo(
        repository = GIT_REPO, 
        ref="branch", 
        refName='main'), 
    repositoryPath = SCRIPT_PATH)

main <- function(){
    #' get ppacman
    ppacman <- synGet(PPACMAN_TBL_ID)$path %>% fread()
    
    #' get entirety of feature set
    all_data_list <- 
        purrr::map(FEATURES_ID, function(syn_id){
            entity <- synGet(syn_id)
            feature_tbl_id <- entity$properties$id
            feature_tbl_name <- entity$properties$name
            features <- entity$path %>% 
                fread() %>%
                dplyr::mutate(source = feature_tbl_name,
                              id = feature_tbl_id) %>%
                dplyr::select(-createdOn)})
        
    #' merge all features using reduce operation, and right-join PPACMAN
    #' table to keep all users with ppacman information
    merged_features <- 
        all_data_list %>% 
        purrr::reduce(dplyr::full_join, 
                      by = c("participantId", "visit_num")) %>%
        tibble::as_tibble() %>%
        dplyr::right_join(ppacman, 
                          by = c("participantId", "visit_num")) %>%
        dplyr::group_by(participantId, createdOn, visit_num) %>%
        dplyr::summarise_all(last) %>%
        dplyr::select(-starts_with("recordId"),
                      -starts_with("source"),
                      -starts_with("id")) %>%
        dplyr::select(participantId, 
                      createdOn, 
                      visit_num, 
                      everything()) %>% 
        dplyr::arrange(desc(createdOn))
    
    #' save merged file to synapse
    save_to_synapse(data = merged_features,
                    output_filename = OUTPUT_REF$merged_file, 
                    parent = PARENT_REF$merged_file,
                    name = "get merged file",
                    executed = GIT_URL,
                    used = c(FEATURES_ID %>% purrr::reduce(c), 
                             PPACMAN_TBL_ID))
}

log_process(main(), SCRIPT_PATH)


