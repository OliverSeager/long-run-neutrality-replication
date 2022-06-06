/*

Oliver Seager
o.j.seager@lse.ac.uk
SE 17

!!! SHELVED !!!

The idea here is to see if I can replicate Ottonello and Winberry (2020) with leverage (basically just to check that everything is as it should be). This doesn't run with distance to default as, at the time of writing, Google Cloud is still working out distance to default for me. Hence, it pulls from 001c_data_processing rather than 001e_data_processing.

Created: 02/04/2022
Last Modified: 04/04/2022

Infiles:
- 001c_cstat_jan1961_jan2022_ow_controls.dta (S&P Compustat Quarterly Fundamentals data, with all Ottonello and Winberry (2020) control variables except distance to default.)
- 001b_cstat_shocks.dta (Data on monetary policy shocks aggregated to the firm-quarter level following Gertler and Karadi (2015)
- 001b_ecq_gdp.dta (Exact Calendar Quarters mapped to their respective Koop et al. (2022) estimate of annualised quarter-on-quarter GDP growth in the United States)

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

log using "./code/002_replicate_ow.log", replace


*************************************
* DE-SELECTING FIRMS FOR REGRESSION *
*************************************

/*
OW de-select
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
  ...*and* the following firm-quarter
- *after* making these adjustments Winsorize leverage (and distance to default) at p0.5 and p99.5
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

bysort gvkey gvkey_run (datadate): gen to_regress = (uncensored_obs[_n-2] == 1 & uncensored_obs[_n-1] == 1 & uncensored_obs == 1 & !missing(investment) & !missing(lvrg[_n-2]) & !missing(size[_n-2]) & !missing(real_sales_growth[_n-2]) & !missing(liquidity_ii[_n-2]) & !missing(fqtr))

label var to_regress "Firm-quarter used in Ottonello & Winberry (2020) regression"

/*
We have...
- 507,675 (26.9% of) firm-quarters with regressable information
- 413,598 (21.9% of) firm-quarters with regressable information for both itself and its first two lags
- 225,902 (12.0% of) firm-quarters with regressable information for both itself and its first two lags *and* a Monetary Policy Shock. These firm quarters will be regressed.
*/


* Winsorise Leverage *

_pctile lvrg if uncensored_obs == 1, percentiles(0.5 99.5) // Get 0.5th and 99.5th percentiles into r(r1) and r(r2) respectively

local pct_lb = `=r(r1)' // The lower bound beyond which winsorisation takes place

local pct_ub = `=r(r2)' // The upper bound beyond which winsorisation takes place

replace lvrg = `pct_lb' if lvrg < `pct_lb' & uncensored_obs == 1 & !missing(lvrg)

replace lvrg = `pct_ub' if lvrg > `pct_ub' & uncensored_obs == 1 & !missing(lvrg)


*********************************
* BUILDING REGRESSION VARIABLES *
*********************************

// We do this *after* winsorising leverage

/*
The variables OW actually use are...
- Demeaned Leverage (demeaned_lvrg, built below) multiplied by the FFR shock (dependent variable of interest, lvrg_shock below)
- Leverage Ratio (lvrg)
- Total Assets (size)
- Sales Growth (real_sales_growth)
- Current Assets as a share of Total Assets (liquidity)
- Fiscal Quarter Dummy (fqtr)
- Interaction of Leverage Ratio with previous quarter's GDP Growth (lvrg_gdp, built below)

They use fixed effects on...
- Firm (gvkey)
- Sector-by-quarter (sector_q)
*/


* Demeaned Leverage *

bysort gvkey: egen mean_lvrg = mean(lvrg) if uncensored_obs == 1 // Mean leverage at the firm level, including only observations with regressable information.

gen demeaned_lvrg = lvrg - mean_lvrg

drop mean_lvrg // No longer needed


* Interaction of Leverage Ratio with Quarter's GDP Growth: Merge to Koop et al. (2022) Estimates *

// Since we need monthly quarter-on-quarter growth (as we use datadate as the endpoint of the quarter, rather than the reported fiscal or calendar quarter), we use monthly Bayesian MF-VAR estimates of U.S. GDP from Koop et al. (2022)

merge m:1 ecq using "./outputs/001b_ecq_gdp.dta", keepusing(kmmp_gdp)

drop if _merge == 2 // We don't need unused estimates from Koop et al. (2022)

drop _merge

label var kmmp_gdp "Quarter-on-quarter GDP growth estimated by Koop et al. (2022)"


* Interaction of Leverage Ratio with Quarter's GDP Growth: Generate Variable *

gen lvrg_gdp = lvrg*kmmp_gdp

label var lvrg_gdp "Leverage ratio interacted with previous quarter's GDP growth"


* Interaction of Demeaned Leverage Ratio with the FFR Shock: Merge to Shock Data *

merge 1:1 gvkey datadate using "./outputs/001b_cstat_shocks.dta" // Only observations for the shock period will merge here.

drop if _merge == 2 // Should be no observations

drop _merge


* Interaction of Demeaned Leverage Ratio with the FFR Shock: Reverse Shock Sign *

// Following Ottonello & Winberry, I reverse the direction of the shock such that a positive value corresponds to an equivalent *decrease* in interest rates

replace tw_shock = -1*tw_shock


* Interaction of Demeaned Leverage Ratio with the FFR Shock: Adjust Shock from Basis Points to Percentage Points *

replace tw_shock = tw_shock/100


**************
* REGRESSION *
**************

* Get Time-correct Values for Control Variables * // These all have to be uncorrelated with the MP shock, which is a weighted aggregation of all MP shocks in the current and previous quarter

bysort gvkey gvkey_run (datadate): gen lvrg_tLess2 = lvrg[_n-2]

bysort gvkey gvkey_run (datadate): gen size_tLess2 = size[_n-2]

bysort gvkey gvkey_run (datadate): gen real_sales_growth_tLess2 = real_sales_growth[_n-2]

bysort gvkey gvkey_run (datadate): gen liquidity_ii_tLess2 = liquidity_ii[_n-2]

bysort gvkey gvkey_run (datadate): gen lvrg_gdp_tLess2 = lvrg_gdp[_n-2]

bysort gvkey gvkey_run (datadate): gen gdp_tLess2 = kmmp_gdp[_n-2]


* Get Time-correct Value for Variable of Interest: Interaction Between Demeaned Leverage and Monetary Policy Shock *

bysort gvkey gvkey_run (datadate): gen lvrg_shock = demeaned_lvrg[_n-2]*tw_shock

label var lvrg_shock "Interaction between demeaned leverage and tight-window FFR shock"


* Encode Fixed Effect and Clustering Variables*

// Absorption in reghdfe only accepts numeric variables

encode gvkey, gen(gvkey_enc)

gen gvkey_gvkeyrun_enc = 100*gvkey_enc + gvkey_run

encode sector_q, gen(sector_q_enc)

encode ecq, gen(ecq_enc)


* Regressions *

reghdfe investment lvrg_shock tw_shock lvrg_tLess2 size_tLess2 real_sales_growth_tLess2 liquidity_ii_tLess2 lvrg_gdp_tLess2 i.fqtr if to_regress == 1, absorb(gvkey_gvkeyrun_enc sector_q_enc) vce(cluster gvkey_gvkeyrun_enc ecq_enc)

reghdfe investment lvrg_shock tw_shock lvrg_tLess2 size_tLess2 real_sales_growth_tLess2 liquidity_ii_tLess2 lvrg_gdp_tLess2 i.fqtr if to_regress == 1, absorb(gvkey_gvkeyrun_enc) vce(cluster gvkey_gvkeyrun_enc)


*************
* POSTAMBLE *
*************

log close

exit