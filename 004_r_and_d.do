/*

Oliver Seager
o.j.seager@lse.ac.uk
SE 17

The idea of this script is to get the relationship between monetary policy shocks and firm-level research and development.

Created: 10/04/2022
Last Modified: 31/05/2022

Infiles:
- 001c_cstat_jan1961_jan2022_ow_controls.dta (S&P Compustat Quarterly Fundamentals data, with all Ottonello and Winberry (2020) control variables except distance to default.)
- 001c_cstat_shocks.dta (Data on monetary policy shocks aggregated to the firm-quarter level following Gertler and Karadi (2015) and Wong (2021), with missing values where shocks are incalculable.)
- 001b_ecq_gdp.dta (Exact Calendar Quarters mapped to their respective Koop et al. (2022) estimate of annualised quarter-on-quarter GDP growth in the United States.)
- 001b_ecq_ffr.dta (Exact Calendar Quarters mapped to the Federal Funds Target Rate for the final day of the quarter, obtained from FRED at the Federal Reserve Bank of St. Louis.)
- 001b_ecq_unemp.dta (Exact Calendar Quarters mapped to their respective Bureau of Labor Statistics estimate of the unemployment rate in the United States.)

Out&Infiles:

Outfiles:

External Packages:

*/

************
* PREAMBLE *
************

clear all
set more off
macro drop _all
set rmsg on, permanently
capture log close
graph drop _all
set scheme modern, permanently

cd "C:/Users/Ollie/Dropbox/Monetary Policy and Innovation"

log using "./code/004_r_and_d.log", replace


**************************************************
* DE-SELECTING FIRMS FOR ANALYSIS AND REGRESSION *
**************************************************

/*
Following O&W, we de-select
- Financial firms (sic in [6000,6799])
- Utilities firms (sic in [4900,4999])
- Non-operative firms (sic 9995)
- Industrial conglomerates (sic 9997)
- Firms not incorporated in the United States
- Firm-quarters with...
  - Negative capital or negative assets
  - Acquisitions (based on Compustat Variable aqcy) larger than 5% of total assets.
  - Investment in the top or bottom 0.5% of the distribution
  - Firms without a 40-observation run of investment
  - Net current assets as a share of total assets > 10 or < -10
  - Leverage > 10 or Leverage < 0
  - Quarterly real sales growth > 1 or < -1
  - Sales < 0
  - Liquidity < 0
*/

* Import Compustat with O&W Controls *

use "./outputs/001c_cstat_jan1961_jan2022_ow_controls.dta", clear


* Generate a Censorship Variable *

gen uncensored_obs = 1

label var uncensored_obs "Firm-quarter information used in Ottonello & Winberry (2020) regression"


* Censor Firms by SIC *

replace uncensored_obs = 0 if (sic >= 6000 & sic < 6800) | (sic >= 4900) & (sic < 5000) | sic == 9995 | sic == 9997 // Censors 32.1% of firm-quarters


* Censor Firms not Incorporated in the US *

replace uncensored_obs = 0 if fic != "USA" // Censors 13.6% of firm-quarters


* Censor Firm-quarters with Negative Capital or Negative Assets (and the following quarter) *

bysort gvkey gvkey_run (datadate): replace uncensored_obs = 0 if capital_stock < 0 | atq < 0 // Censors 0.04% of firm-quarters


* Censor Firm-quarters with Acquisitions Greater than 5% of Total Assets *

bysort gvkey gvkey_run (datadate): replace uncensored_obs = 0 if (aqcy > 0.05*atq & !missing(aqcy)) // Censors 2.6% of firm-quarters

/*
* Censor Firm-quarters where Investment is in the Bottom or Top 0.5% of the Distribution *

_pctile investment if uncensored_obs == 1, percentiles(0.5 99.5) // Get 0.5th and 99.5th percentiles into r(r1) and r(r2) respectively

local pct_lb = `=r(r1)' // The lower bound beyond which censorship takes place

local pct_ub = `=r(r2)' // The upper bound beyond which censorship takes place

replace uncensored_obs = 0 if investment < `pct_lb' & uncensored_obs == 1 & !missing(investment) // Censors 0.2% of firm-quarters

replace uncensored_obs = 0 if investment > `pct_ub' & uncensored_obs == 1 & !missing(investment) // Censorts 0.2% of firm-quarters


* Censor Firm-quarters without a 40-quarter Run-count of Investment *

gen investment_run_count = 0 // Start with all values as 0

bysort gvkey gvkey_run (datadate): replace investment_run_count = 1 if missing(investment[_n-1]) & !missing(investment) // Get the first value as 1

bysort gvkey gvkey_run (datadate): replace investment_run_count = investment_run_count[_n-1] + 1 if !missing(investment[_n-1]) & !missing(investment) // Get all successive values as their number in order of appearance in the investment run

gsort gvkey gvkey_run -datadate // Reverse the date order (so Stata can work iteratively and we don't have to loop anything)

by gvkey gvkey_run: replace investment_run_count = investment_run_count[_n-1] if !missing(investment[_n-1]) & !missing(investment) // Get all values in the run to the total run_count

replace uncensored_obs = 0 if investment_run_count < 40 // Censors 23.7% of firm-quarters
*/

* Censor Firm-quarters where R&D is in the Bottom or Top 0.5% of the distribution * // It might seem strange to censor the *bottom* of the distribution, but we do have 720 negative values for research and development.

_pctile xrdq if uncensored_obs == 1, percentiles(0.5 99.5) // Get 0.5th and 99.5th percentiles into r(r1) and r(r2) respectively

local pct_lb = `=r(r1)' // The lower bound beyond which censorship takes place

local pct_ub = `=r(r2)' // The upper bound beyond which censorship takes place

replace uncensored_obs = 0 if xrdq < `pct_lb' & uncensored_obs == 1 & !missing(xrdq) // Censors 0.009% of firm-quarters (since the 0.5th percentile is 0, many firms below this threshold in terms of percentile are still equal to it)

replace uncensored_obs = 0 if xrdq > `pct_ub' & uncensored_obs == 1 & !missing(xrdq) // Censorts 0.05% of firm-quarters


* Censor Firm-quarters without a 40-quarter Run-count of R&D *

gen xrdq_run_count = 0 // Start with all values as 0

bysort gvkey gvkey_run (datadate): replace xrdq_run_count = 1 if missing(xrdq[_n-1]) & !missing(xrdq) // Get the first value as 1

bysort gvkey gvkey_run (datadate): replace xrdq_run_count = xrdq_run_count[_n-1] + 1 if !missing(xrdq[_n-1]) & !missing(xrdq) // Get all successive values as their number in order of appearance in the R&D run

gsort gvkey gvkey_run -datadate // Reverse the date order (so Stata can work iteratively and we don't have to loop anything)

by gvkey gvkey_run: replace xrdq_run_count = xrdq_run_count[_n-1] if !missing(xrdq[_n-1]) & !missing(xrdq) // Get all values in the run to the total run_count

replace uncensored_obs = 0 if xrdq_run_count < 40 // Censors 19.0% of firm-quarters


* Censor Firm-quarters with Net Current Assets as a Share of Total Assets < -10 or > 10 *

replace uncensored_obs = 0 if actq/atq < - 10 | (actq/atq > 10 & !missing(actq) & !missing(atq)) // Censors 0 firm-quarters


* Censor Firm-quarters with Log Real Sales Growth < -1 or > 1 *

replace uncensored_obs = 0 if real_sales_growth < -1 | (real_sales_growth > 1 & !missing(real_sales_growth)) // Censors 0.6% of firm-quarters


* Generate alternatively-defined Liquidity *

// O&W, in the published version of their paper, define liquidity to be the ratio of current assets (rather than cash and short-term investments) to total assets

gen liquidity_ii = actq/atq

label var liquidity_ii "Current assets as a proportion of total assets"


* Censor Firms with Negative Sales or Negative Liquidity *

replace uncensored_obs = 0 if real_sales < 0 | liquidity_ii < 0 // Censors 0.009% of firm-quarters


* Get Firm-quarters to Regress *

// The regression variables stretch over 3 periods to ensure the controls are exogenous from the monetary policy shock.

bysort gvkey gvkey_run (datadate): gen to_regress = (uncensored_obs[_n-2] == 1 & uncensored_obs[_n-1] == 1 & uncensored_obs == 1 & xrdq >= 0 & !missing(xrdq) & !missing(lvrg[_n-2]) & !missing(size[_n-2]) & !missing(real_sales_growth[_n-2]) & !missing(liquidity_ii[_n-2]) & !missing(fqtr))

label var to_regress "Firm-quarter usable in first quarter regression"

/*
We have...
- 153,947 (8.2% of) firm-quarters with regressable information
- 124,012 (6.57% of) firm-quarters with regressable information for both itself and its first two lags
- 83,642 (4.4% of) firm-quarters with regressable information for both itself and its first two lags *and* a Monetary Policy Shock. These firm quarters will be regressed.
*/

*********************************
* BUILDING REGRESSION VARIABLES *
*********************************

/*
The control variables we use here are...
- Leverage Ratio (lvrg)
- Total Assets (size)
- Sales Growth (real_sales_growth)
- Current Assets as a share of Total Assets (liquidity)
- Fiscal Quarter Dummy (fqtr)

They use fixed effects on...
- Firm (gvkey)
- Year
*/


* Interaction of Leverage Ratio with Quarter's GDP Growth: Merge to Koop et al. (2022) Estimates *

// Since we need monthly quarter-on-quarter growth (as we use datadate as the endpoint of the quarter, rather than the reported fiscal or calendar quarter), we use monthly Bayesian MF-VAR estimates of U.S. GDP from Koop et al. (2022)

merge m:1 ecq using "./outputs/001b_ecq_gdp.dta", keepusing(kmmp_gdp)

drop if _merge == 2 // We don't need unused estimates from Koop et al. (2022)

drop _merge

label var kmmp_gdp "Quarter-on-quarter GDP growth estimated by Koop et al. (2022)"


* Interaction of Leverage Ratio with Quarter's GDP Growth: Generate Variable *

gen lvrg_gdp = lvrg*kmmp_gdp

label var lvrg_gdp "Leverage ratio interacted with previous quarter's GDP growth"


* Merge to End-of-Quarter FFR Target Data *

merge m:1 ecq using "./outputs/001b_ecq_ffr.dta", keepusing(ffr_target)

drop if _merge == 2 // We only need firm-level observations, not unused FFR targets

drop _merge

label var ffr_target "End-of-quarter FFR Target"


* Merge to BLS Unemployment Data *

merge m:1 ecq using "./outputs/001b_ecq_unemp.dta", keepusing(unemp)

drop if _merge == 2 // We only need firm-level observations, not unused unemployment rates

drop _merge

rename unemp bls_unemp // Renamed to indicate source

label var bls_unemp "Unemployment Rate estimated by the Bureau of Labor Statistics"


* FFR Shock: Merge to Shock Data *

merge 1:1 gvkey datadate using "./outputs/001c_cstat_shocks.dta" // Only observations for the shock period will merge here.

drop if _merge == 2 // Should be no observations

drop _merge


* Deflate Research and Development *

gen rxrdq = xrdq/cpi

label var rxrdq "Real R&D Expense, 2012 Dollars"


* Get List of Shocks *

local shocks `" "tw_ma_shock_gk"  "ns_ma_shock_gk" "ww_ma_shock_gk" "tw_shock_gk" "ns_shock_gk" "tw_ma_bic_shock_gk" "ns_ma_bic_shock_gk" "tw_ma_shock_w" "ns_ma_shock_w" "'


* FFR Shock: Adjust Shock Such that 1 Reflects a 0.1% Expansionary Shock *

foreach shock in `shocks'{
	
	gen pos_`shock' = `shock'*(`shock' > 0)
	
	gen neg_`shock' = `shock'*(`shock' < 0)
	
}


**********************
* CENTRAL REGRESSION *
**********************

* Get Time-correct Values for Control Variables * // These all have to be uncorrelated with the MP shock, which is an aggregation of FOMC meeting day shocks from the previous quarter.

bysort gvkey gvkey_run (datadate): gen lvrg_tLess2 = lvrg[_n-2]

bysort gvkey gvkey_run (datadate): gen size_tLess2 = size[_n-2]

bysort gvkey gvkey_run (datadate): gen real_sales_growth_tLess2 = real_sales_growth[_n-2] 

bysort gvkey gvkey_run (datadate): gen liquidity_ii_tLess2 = liquidity_ii[_n-2]

bysort gvkey gvkey_run (datadate): gen lvrg_gdp_tLess2 = lvrg_gdp[_n-2]

bysort gvkey gvkey_run (datadate): gen gdp_tLess2 = kmmp_gdp[_n-2]

bysort gvkey gvkey_run (datadate): gen inflation_tLess2 = cpi_inflation[_n-2]

bysort gvkey gvkey_run (datadate): gen unemp_tLess2 = bls_unemp[_n-2]

bysort gvkey gvkey_run (datadate): gen ffr_tLess2 = ffr_target[_n-2]


* Get "To Locally Project" Indicator *

gen to_lp = to_regress

forvalues lead = 1/7{
	
	replace to_lp = 0 if missing(rxrdq[_n + `lead']) | rxrdq[_n + `lead'] < 0
	
}


* Get 8 Cumulative Leads for R&D * // Essentially here, if we characterise R&D as the first difference in the stock of intellectual capital (dicey), we give meaning to cmltv R&D.

gen log_1_plus_cmltv_rxrdq_tPlus0 = log(1 + rxrdq) if to_lp == 1 // First cmltv value is just the contemporaneous value

forvalues horizon = 1/7{
	
	gen cmltv_rxrdq_tPlus`horizon' = rxrdq if to_lp == 1
	
	forvalues lead = 1/`horizon'{
		
		replace cmltv_rxrdq_tPlus`horizon' = cmltv_rxrdq_tPlus`horizon' + rxrdq[_n + `lead'] if to_lp == 1
		
	}
	
	gen log_1_plus_cmltv_rxrdq_tPlus`horizon' = log(1 + cmltv_rxrdq_tPlus`horizon')
	
	drop cmltv_rxrdq_tPlus`horizon' // No longer needed
	
}


* Encode Fixed Effect and Clustering Variables*

// Absorption in reghdfe only accepts numeric variables

encode gvkey, gen(gvkey_enc)

gen gvkey_gvkeyrun_enc = 100*gvkey_enc + gvkey_run // We use this as a (nominal) fixed effect variable and a clustering variable

gen year = yofd(dofm(mofd(datadate) - 1)) // We take the middle month of the quarter to be representative of its year


* Run Cumulative Local Projection Regressions - Miranda-Agrippino Shocks *

forvalues h = 0/7{
	
	reghdfe log_1_plus_cmltv_rxrdq_tPlus`h' pos_tw_ma_shock_gk neg_tw_ma_shock_gk lvrg_tLess2 size_tLess2 real_sales_growth_tLess2 liquidity_ii_tLess2 lvrg_gdp_tLess2 gdp_tLess2 inflation_tLess2 unemp_tLess2 ffr_tLess2 i.fqtr if to_lp == 1, absorb(gvkey_enc) vce(cluster gvkey_enc year)
	
}

forvalues h = 0/7{
	
	reghdfe log_1_plus_cmltv_rxrdq_tPlus`h' pos_ns_ma_shock_gk neg_ns_ma_shock_gk lvrg_tLess2 size_tLess2 real_sales_growth_tLess2 liquidity_ii_tLess2 lvrg_gdp_tLess2 gdp_tLess2 inflation_tLess2 unemp_tLess2 ffr_tLess2 i.fqtr if to_lp == 1, absorb(gvkey_enc) vce(cluster gvkey_enc year)
	
}


***********************************
* WINSORISATION ROBUSTNESS CHECKS *
***********************************

* Winsorise Research and Development *

_pctile rxrdq if to_lp == 1, percentiles(1 99) // Gets 1st and 99th percentiles into r(r1) and r(r2) respectively

gen winsrxrdq = `r(r1)'*(rxrdq < `r(r1)') + rxrdq*(rxrdq >= `r(r1)' & rxrdq <= `r(r2)') + `r(r2)'*(rxrdq > `r(r2)') // Gets winsorised value


* Get 7 Cumulative Winsorised Leads for Research and Development *

forvalues horizon = 0/7{
	
	gen wins_cmltv_rxrdq_tPlus`horizon' = winsrxrdq if to_lp == 1
	
	if(`horizon' > 0){
		
		forvalues lead = 1/`horizon'{
		
			replace wins_cmltv_rxrdq_tPlus`horizon' = wins_cmltv_rxrdq_tPlus`horizon' + winsrxrdq[_n + `lead'] if to_lp == 1
			
		}
		
	}
	
	gen log1PlusCmltvWinsrxrdqtPlus`horizon' = log(1 + wins_cmltv_rxrdq_tPlus`horizon')
	
	drop wins_cmltv_rxrdq_tPlus`horizon' // No longer needed
	
}


* Winsorise Firm-level Control Variables *

local firm_level_vars `" "lvrg_tLess2" "size_tLess2" "real_sales_growth_tLess2" "liquidity_ii_tLess2" "lvrg_gdp_tLess2" "' 

foreach var in `firm_level_vars'{
	
	_pctile `var' if to_lp == 1, percentiles(1 99) // Gets 1st and 99th percentiles into r(r1) and r(r2) respectively

	gen wins_`var' = `r(r1)'*(`var' < `r(r1)') + `var'*(`var' >= `r(r1)' & `var' <= `r(r2)') + `r(r2)'*(`var' > `r(r2)') // Gets winsorised value
	
} 


* Run Cumulative Regressions - Winsorised *

forvalues h = 0/7{
	
	if(`h' <= 1 | `h' == 3 | `h' == 7){
	
	reghdfe log1PlusCmltvWinsrxrdqtPlus`h' pos_tw_ma_shock_gk neg_tw_ma_shock_gk wins_lvrg_tLess2 wins_size_tLess2 wins_real_sales_growth_tLess2 wins_liquidity_ii_tLess2 wins_lvrg_gdp_tLess2 gdp_tLess2 inflation_tLess2 unemp_tLess2 ffr_tLess2 i.fqtr if to_lp == 1, absorb(gvkey_gvkeyrun_enc) vce(cluster gvkey_enc year)
		
	}
	
}

forvalues h = 0/7{
	
	if(`h' <= 1 | `h' == 3 | `h' == 7){
	
	reghdfe log1PlusCmltvWinsrxrdqtPlus`h' pos_ns_ma_shock_gk neg_ns_ma_shock_gk wins_lvrg_tLess2 wins_size_tLess2 wins_real_sales_growth_tLess2 wins_liquidity_ii_tLess2 wins_lvrg_gdp_tLess2 gdp_tLess2 inflation_tLess2 unemp_tLess2 ffr_tLess2 i.fqtr if to_lp == 1, absorb(gvkey_gvkeyrun_enc) vce(cluster gvkey_enc year)
	
	}
	
}


***************************************
* ALTERNATIVE SHOCK ROBUSTNESS CHECKS *
***************************************

* Run Cumulative Regressions - Observed Shock Series *

forvalues h = 0/7{
	
	if(`h' <= 1 | `h' == 3 | `h' == 7){
	
	reghdfe log_1_plus_cmltv_rxrdq_tPlus`h' pos_tw_shock_gk neg_tw_shock_gk lvrg_tLess2 size_tLess2 real_sales_growth_tLess2 liquidity_ii_tLess2 lvrg_gdp_tLess2 gdp_tLess2 inflation_tLess2 unemp_tLess2 ffr_tLess2 i.fqtr if to_lp == 1, absorb(gvkey_enc) vce(cluster gvkey_enc year)
		
	}
	
}

forvalues h = 0/7{   
	
	if(`h' <= 1 | `h' == 3 | `h' == 7){
	
	reghdfe log_1_plus_cmltv_rxrdq_tPlus`h' pos_ns_shock_gk neg_ns_shock_gk lvrg_tLess2 size_tLess2 real_sales_growth_tLess2 liquidity_ii_tLess2 lvrg_gdp_tLess2 gdp_tLess2 inflation_tLess2 unemp_tLess2 ffr_tLess2 i.fqtr if to_lp == 1, absorb(gvkey_enc) vce(cluster gvkey_enc year)
	
	}
	
}

* Run Cumulative Regressions - BIC-purged Series *

forvalues h = 0/7{
	
	if(`h' <= 1 | `h' == 3 | `h' == 7){
	
	reghdfe log_1_plus_cmltv_rxrdq_tPlus`h' pos_tw_ma_bic_shock_gk neg_tw_ma_bic_shock_gk lvrg_tLess2 size_tLess2 real_sales_growth_tLess2 liquidity_ii_tLess2 lvrg_gdp_tLess2 gdp_tLess2 inflation_tLess2 unemp_tLess2 ffr_tLess2 i.fqtr if to_lp == 1, absorb(gvkey_enc) vce(cluster gvkey_enc year)
		
	}
	
}

forvalues h = 0/7{   
	
	if(`h' <= 1 | `h' == 3 | `h' == 7){
	
	reghdfe log_1_plus_cmltv_rxrdq_tPlus`h' pos_ns_ma_bic_shock_gk neg_ns_ma_bic_shock_gk lvrg_tLess2 size_tLess2 real_sales_growth_tLess2 liquidity_ii_tLess2 lvrg_gdp_tLess2 gdp_tLess2 inflation_tLess2 unemp_tLess2 ffr_tLess2 i.fqtr if to_lp == 1, absorb(gvkey_enc) vce(cluster gvkey_enc year)
	
	}
	
}


* Run Cumulative Regressions - Wong-aggregated Series *

forvalues h = 0/7{
	
	if(`h' <= 1 | `h' == 3 | `h' == 7){
	
	reghdfe log_1_plus_cmltv_rxrdq_tPlus`h' pos_tw_ma_shock_w neg_tw_ma_shock_w lvrg_tLess2 size_tLess2 real_sales_growth_tLess2 liquidity_ii_tLess2 lvrg_gdp_tLess2 gdp_tLess2 inflation_tLess2 unemp_tLess2 ffr_tLess2 i.fqtr if to_lp == 1, absorb(gvkey_enc) vce(cluster gvkey_enc year)
		
	}
	
}

forvalues h = 0/7{   
	
	if(`h' <= 1 | `h' == 3 | `h' == 7){
	
	reghdfe log_1_plus_cmltv_rxrdq_tPlus`h' pos_ns_ma_shock_w neg_ns_ma_shock_w lvrg_tLess2 size_tLess2 real_sales_growth_tLess2 liquidity_ii_tLess2 lvrg_gdp_tLess2 gdp_tLess2 inflation_tLess2 unemp_tLess2 ffr_tLess2 i.fqtr if to_lp == 1, absorb(gvkey_enc) vce(cluster gvkey_enc year)
	
	}
	
}


* Run Cumulative Regressions - Wide-window Series *

forvalues h = 0/7{
	
	if(`h' <= 1 | `h' == 3 | `h' == 7){
	
	reghdfe log_1_plus_cmltv_rxrdq_tPlus`h' pos_ww_ma_shock_gk neg_ww_ma_shock_gk lvrg_tLess2 size_tLess2 real_sales_growth_tLess2 liquidity_ii_tLess2 lvrg_gdp_tLess2 gdp_tLess2 inflation_tLess2 unemp_tLess2 ffr_tLess2 i.fqtr if to_lp == 1, absorb(gvkey_enc) vce(cluster gvkey_enc year)
		
	}
	
}


**********************
* SUMMARY STATISTICS *
**********************

* Age of Firm *

bysort gvkey: egen datamonth_min = min(mofd(datadate))

gen datamonth = mofd(datadate)

gen age_months = datamonth - datamonth_min

gen age_qs = floor(age_months/3)


* Observation One: FFR-Surprises *

gen eligible_ffr = to_lp*!missing(tw_ma_shock_gk)

bysort gvkey eligible_ffr (datadate): gen count_ffr = (_n == 1) if eligible_ffr == 1


* Observation One: PCA-Surprises *

gen eligible_pca = to_lp*!missing(ns_ma_shock_gk)

bysort gvkey eligible_pca (datadate): gen count_pca = (_n == 1) if eligible_pca == 1


* FFR-Surprises *

count if to_lp == 1 & !missing(tw_ma_shock_gk)

count if to_lp == 1 & !missing(tw_ma_shock_gk) & count_ffr == 1

summarize log_1_plus_cmltv_rxrdq_tPlus0 if to_lp == 1 & !missing(tw_ma_shock_gk), detail 

summarize age_qs if to_lp == 1 & !missing(tw_ma_shock_gk), detail

summarize lvrg if to_lp == 1 & !missing(tw_ma_shock_gk), detail

summarize size if to_lp == 1 & !missing(tw_ma_shock_gk), detail

summarize real_sales_growth if to_lp == 1 & !missing(tw_ma_shock_gk), detail

summarize liquidity_ii if to_lp == 1 & !missing(tw_ma_shock_gk), detail


* PCA-Surprises *

count if to_lp == 1 & !missing(ns_ma_shock_gk)

count if to_lp == 1 & !missing(ns_ma_shock_gk) & count_pca == 1

summarize log_1_plus_cmltv_rxrdq_tPlus0 if to_lp == 1 & !missing(ns_ma_shock_gk), detail 

summarize age_qs if to_lp == 1 & !missing(ns_ma_shock_gk), detail

summarize lvrg if to_lp == 1 & !missing(ns_ma_shock_gk), detail

summarize size if to_lp == 1 & !missing(ns_ma_shock_gk), detail

summarize real_sales_growth if to_lp == 1 & !missing(ns_ma_shock_gk), detail

summarize liquidity_ii if to_lp == 1 & !missing(ns_ma_shock_gk), detail


*************
* POSTAMBLE *
*************

log close

exit