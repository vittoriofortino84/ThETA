% Generated by roxygen2: do not edit by hand
% Please edit documentation in R/script_tissue_specific_efficacy_score.R
\name{generate.ora.plots}
\alias{generate.ora.plots}
\title{Generate plots for the visualization of ORA results.}
\usage{
generate.ora.plots(
  ora_data,
  set_plots = c("dotplot", "emapplot", "cnetplot", "upsetplot"),
  showCategory = 20,
  font_size = 8
)
}
\arguments{
\item{ora_data}{a list of ORA results.}

\item{set_plots}{character vector indicating the types of plots to be generated.
Possible values are: dotplot, emapplot, cnetplot and upsetplot.}

\item{showCategory}{number of enriched terms to display.}

\item{font_size}{text size in pts.}
}
\value{
a set of plot for each ORA result.
}
\description{
Annotation plots generated with the R package 'enrichplot'.
}
