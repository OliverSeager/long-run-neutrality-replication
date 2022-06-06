/*

Oliver Seager
o.j.seager@lse.ac.uk
SE 16

This script essentially acts as an engine, importing and exporting datasets as is convenient for later code. This particular script calculates the control variables and variable of interest (quarterly investment) from Ottonello & Winberry (2020). This splits into three stages:
- Investment, Leverage, Net Leverage, Liquidity, Cash Flow, a dividend payer dummy variable, sectoral dummies (all direct from Compustat data)
- Real sales growth, Size (use the BLS implicit price deflator)
- Distance to default (Pretty heavy to compute; requires using CRSP data on stock prices)

It also amends calculated quarterly monetary shocks from 001b_cstat_shocks.dta such that quarters for which shocks are incalculable are moved from 0 to missing.

Created: 13/01/2022
Last Modified: 25/05/2022

Infiles:
- 001a_cstat_jan1961_jan2022_clean.dta (S&P Compustat Quarterly Fundamentals data. Fiscal 1961Q1-2022Q2, Calendar jan1961-jan2022. Cleaned in 001a such that gvkey-datadate gives foundation for panel.)
- 001a_cstat_qdates.dta (gvkey-datadate level Computstat data with Stata clock time endpoints of the current and previous fiscal quarter, as well as "expected quarter length".)
- 001b_ecq_cpi.dta (The Organisation for Economic Cooperation and Development's CPI Price Index for exact calendar quarters (1960Q1b-2021Q4c) and CPI quarter-on-quarter annualised inflation (1960Q2b-2021Q4c))
- 001b_ecq_ipd.dta (The Bureau of Labor Statistics' Implicit Price Deflator, linearly interpolated to give a value for a quarter starting in any month of the year.)
- crsp_cstat_link_jan1960_dec2020.dta (Linking between gvkey and CUSIP for each particular datadate on which the gvkey reports accounting data.)
- crsp_19600101_20201231.dta (CRSP Data on Security Prices. 1st January 1960 - 31st December 2020)
- 001b_cstat_shocks.dta (Data on monetary policy shocks aggregated to the firm-quarter level following Gertler and Karadi (2015) and Wong (2021), but with 0s instead of missing values for some quarters where shocks are incalculable.)

Out&Infiles:
- 001c_cstat_jan1961_jan2022_ow_controls.dta (S&P Compustat Quarterly Fundamentals data, with all Ottonello and Winberry (2020) control variables)
- 001c_crsp_dd_may1960_dec2020.dta (Data on equity and past 365-day equity variance for the Ottonello and Winberry (2020) "distance to default" control variable. 24th May 1960 - 31st December 2020. Constructed from CRSP securities data.)

Outfiles:
- 001c_cstat_shocks.dta (Data on monetary policy shocks aggregated to the firm-quarter level following Gertler and Karadi (2015) and Wong (2021), with missing values where shocks are incalculable.)

External Packages:
- rangestat
- carryforward

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

log using "./code/001c_data_processing.log", replace


*********************************************************
* GETTING OTTONELLO & WINBERRY (2020) CONTROL VARIABLES *
*********************************************************

  *********************************
* Calculating "Runs" for Each gvkey * 
  *********************************

// The panel in Compustat does not correspond to calendar years, since firm accounting dates vary. We therefore have as our cross-sectional-level variable a "gvkey run" - a series of financial quarters for a given gvkey that are consistently 3 months apart. For example, if a firm posts observations every three months from January 2000 through October 2005, then posts an observation in December 2005 and again every three months until September 2009, then Jan2000-Oct2005 and Dec2005-Sep2009 will be two separate runs.

* Import Compustat *

use "./outputs/001a_cstat_jan1961_jan2022_clean.dta", clear


* Getting gvkey-specific Observation Number in datadate Order *

bysort gvkey (datadate): gen gvkey_obs_nr = _n

label var gvkey_obs_nr "gvkey-specific observation number. datadate order"


* Getting Implied Length of Quarter for each Observation *

bysort gvkey (datadate): gen implied_q_len = datadate - datadate[_n-1]


* Merging in Expected Quarter Length *

rename datadate td_datadate // Rename to align with using

merge 1:1 gvkey td_datadate using "./outputs/001a_cstat_qdates.dta", keepusing(eql) // Expected quarter length is the anticipated length of the quarter based on the 3-month period concluding with datadate.

rename td_datadate datadate // Re-rename 

drop _merge // All 1,887,102 observations merge.


* Marking the Start of Each Run *

/* 
A new run starts if...
(1) An observation is the first for the given gvkey
(2) The previous observation is not 89-92 days before the current observation.
*/

gen run_start = 0 // Initiate variable

label var run_start "Observation is first in run"

replace run_start = 1 if implied_q_len <= eql - 7 | implied_q_len >= eql + 7 // Note that the first observation for each gvkey is covered here since implied_q_len = . for these observations. In terms of comparison to expected quarter length, note that at most we can expect a firm to change its accounting quarter by 6 days (i.e. less than a week) either way.

drop eql // No longer needed


* Getting the Run Number for Each Observation *

gen gvkey_run = 1 if gvkey_obs_nr == 1 // Initiate variable, marking first observation for each gvkey as run 1

label var gvkey_run "Run number"

summarize gvkey_obs_nr

forvalues i = 2/`=r(max)'{
	
	bysort gvkey (datadate): replace gvkey_run = gvkey_run[_n-1] + run_start if gvkey_obs_nr == `i' // Iteratively calculates run number
	
} // 1,753,823 of 1,887,102 observations (92.94%) are in the first run for their gvkey.


* Drop Extraneous Variables *

drop gvkey_obs_nr run_start


* Export Checkpoint *

save "./outputs/001c_cstat_jan1961_jan2022_ow_controls.dta", replace


  ********************************************
* Variables Directly Calculable with Compustat *
  ********************************************

* Import Checkpoint *

use "./outputs/001c_cstat_jan1961_jan2022_ow_controls.dta", clear

  
* Investment: Interpolation for Net PPE * // Linear interpolation of single-quarter breaks in ppentq observations following Ottonello & Winberry (2020)

bysort gvkey gvkey_run (datadate): replace ppentq = (ppentq[_n-1] + ppentq[_n+1])/2 if ppentq == . & ppentq[_n-1] != . & ppentq[_n+1] != . // 20,091 of 1,881,578 observations changed


* Investment: Get difference (and log-difference) in Net PPE *

bysort gvkey gvkey_run (datadate): gen raw_investment = ppentq - ppentq[_n-1] // 1,353,997 observations have non-missing values for raw_investment. We use this later in calculating capital stock.

label var raw_investment "Difference in net PPE"

bysort gvkey gvkey_run (datadate): gen investment = log(ppentq) - log(ppentq[_n-1])

label var investment "Log-difference in net PPE"


* R&D: Interpolation for Research and Development Expenses * // Linear interpolation of single-quarter breaks in xrdq in the spirit of Ottonello & Winberry (2020)

bysort gvkey gvkey_run (datadate): replace xrdq = (xrdq[_n-1] + xrdq[_n+1])/2 if missing(xrdq) & !missing(xrdq[_n-1]) & !missing(xrdq[_n+1]) // 4,268 of 1,881,578 observations changed


* Leverage *

gen lvrg = (dlcq + dlttq)/atq

label var lvrg "Leverage"


* Net Leverage *

gen net_lvrg = (dlcq + dlttq - (actq - lctq))/atq

label var net_lvrg "Net leverage"


* Liquidity *

gen liquidity = cheq/atq

label var liquidity "Liquidity"


* Capital Stock * (This isn't a control variable, but is the denominator in cash_flow)

/* This is calculated iteratively through gvkey-runs.
  (a) We start with capital stock as a missing value.
  (b) The first time we have a non-missing value for ppegtq (gross PPE), we make this capital stock, after which...
    (c1) If a period has a non-missing value for the difference in ppentq (net PPE), we add this to the previous period's capital stock to get this period's capital stock.
	(c2) If a period has missing value for the difference in ppentq (net PPE), we return to step (a).
*/

bysort gvkey gvkey_run (datadate): gen gvkey_run_obs_nr = _n

label var gvkey_run_obs_nr "Observation number within gvkey run"

gen capital_stock = . // Initiate variable

label var capital_stock "Capital stock"

summarize gvkey_run_obs_nr

forvalues i = 1/`=r(max)'{
	
	bysort gvkey gvkey_run (datadate): replace capital_stock = capital_stock[_n-1] + raw_investment if gvkey_run_obs_nr == `i' & capital_stock[_n-1] != . & raw_investment != .
	
	bysort gvkey gvkey_run (datadate): replace capital_stock = ppegtq if gvkey_run_obs_nr == `i' & capital_stock == . & ppegtq != .
	
}


* Cash Flow *

// Naturally, cash flow can only be properly scaled by capital stock if capital stock is a positive value, so we disregard nonpositive values for capital stock in our calculation here. Furthermore, Ottonello & Winberry do not give a definition of EBIT (the numerator) in terms of compustat variables, so I use the definition of EBITDA from https://www.issgovernance.com/file/files/CompanyFinancials_DataDefinitions.pdf (which doesn't actually mention DA at all).

gen cash_flow = (saleq - cogsq - xsgaq)/capital_stock if capital_stock > 0

label var cash_flow "Cash flow"


* Pays Dividends *

gen paid_dividends = . // Initiate variable

replace paid_dividends = 0 if dvpq <= 0

replace paid_dividends = 1 if dvpq > 0 & dvpq != .

label var paid_dividends "Paid dividends this quarter. Indicator"


* Sector * // We don't use this itself, but it provides one part of the sector-by-quarter fixed effect

destring sic, replace

gen sector = ""

replace sector = "Agriculture, Forestry, Fishing" if sic < 1000

replace sector = "Mining" if sic >= 1000 & sic < 1500

replace sector = "Construction" if sic >= 1500 & sic < 1800

replace sector = "Manufacturing" if sic >= 2000 & sic < 4000

replace sector = "Transport, Communications, Infrastructure" if sic >= 4000 & sic < 5000

replace sector = "Wholesale Trade" if sic >= 5000 & sic < 5200

replace sector = "Retail Trade" if sic >= 5200 & sic < 6000

replace sector = "Services" if sic >= 7000 & sic < 9000


* Get "Exact Calendar Quarter" for each Observation *

// Note that datadate gives the last day of the last month of the quarter reported on.

gen datamonth = mod(mofd(datadate), 12) + 1 // Range 1-12. Last month of the quarter.

label var datamonth "1-12. Month of last day of quarter"

gen datayear = yofd(datadate) // Year of datadate.

replace datayear = datayear - 1 if datamonth == 1 // Quarters ending in January (datamonth = 1) need be listed as Q4c of the year before.

label var datayear "Year in which majority of quarter takes place"

tostring datayear, replace // Exact calendar quarter will be a string of the form "1960Q1". Note that datamonth remains numeric.

gen ecq = "" // Initiate exact calendar quarter variable

replace ecq = datayear + "Q" + "4c" if datamonth == 1
replace ecq = datayear + "Q" + "1a" if datamonth == 2
replace ecq = datayear + "Q" + "1b" if datamonth == 3
replace ecq = datayear + "Q" + "1c" if datamonth == 4
replace ecq = datayear + "Q" + "2a" if datamonth == 5
replace ecq = datayear + "Q" + "2b" if datamonth == 6
replace ecq = datayear + "Q" + "2c" if datamonth == 7
replace ecq = datayear + "Q" + "3a" if datamonth == 8
replace ecq = datayear + "Q" + "3b" if datamonth == 9
replace ecq = datayear + "Q" + "3c" if datamonth == 10
replace ecq = datayear + "Q" + "4a" if datamonth == 11
replace ecq = datayear + "Q" + "4b" if datamonth == 12

label var ecq "Exact calendar quarter"


* Drop Extraneous Variables *

drop datamonth datayear


* Get "Sector by Quarter" *

gen sector_q = ecq + " " + sector


* Export Checkpoint *

save "./outputs/001c_cstat_jan1961_jan2022_ow_controls.dta", replace


  ************************
* Variables Using OECD CPI *
  ************************

/*
Below I use the following definitions for quarters...

Dec (previous year) to Feb: Q1a
Jan to Mar: Q1b
Feb to Apr: Q1c

Mar to May: Q2a
Apr to Jun: Q2b
May to Jul: Q2c

Jun to Aug: Q3a
Jul to Sep: Q3b
Aug to Oct: Q3c

Sep to Nov: Q4a
Oct to Dec: Q4b
Nov to Jan (following year): Q4c

Since the Bureau for Labor Statistics publishes calendar-quarter implicit price deflator values, I calculate the price deflator for each quarter defined above as follows

Q(x)a = (1/3)*Q(x-1) + (2/3)*Q(x)
Q(x)b = Q(x)
Q(x)c = (2/3)*Q(x) + (1/3)*Q(x+1)
*/


* Import Checkpoint *

use "./outputs/001c_cstat_jan1961_jan2022_ow_controls.dta", clear


* Merge to OECD CPI *

merge m:1 ecq using "./outputs/001b_ecq_cpi.dta"

drop if _merge == 2 // We do not keep unmerged quarters from the consumer price index data (i.e. those before 1961Q1b)

drop _merge

label var cpi "OECD's Consumer Price Index"


* Size *

gen size = log(atq/cpi) // Ottonello and Winberry (2020) define size to be the log of real assets.

label var size "Log of Real Assets"


* Real Sales Growth *

sort gvkey gvkey_run datadate

gen real_sales = saleq/cpi // Get real sales for quarter.

label var real_sales "Real Sales"

by gvkey gvkey_run: gen real_sales_growth = log(real_sales) - log(real_sales[_n-1])

label var real_sales_growth "Log-difference in real sales"


* Export Checkpoint *

save "./outputs/001c_cstat_jan1961_jan2022_ow_controls.dta", replace


  ************************************************************
* Robustness Check Variables Using BLS Implicit Price Deflator *
  ************************************************************
  
* Import Checkpoint *

use "./outputs/001c_cstat_jan1961_jan2022_ow_controls.dta", clear


* Merge to BLS Implicit Price Deflator *

merge m:1 ecq using "./outputs/001b_ecq_ipd.dta"

drop if _merge == 2 // We do not keep unmerged quarters from the Implicit Price Deflator data (i.e. those before 1961Q1b)

drop _merge

label var ipd "BLS' Implicit Price Deflator, linearly interpolated"


* Size *

gen size_ipd = log(atq/ipd) // Ottonello and Winberry (2020) define size to be the log of real assets.

label var size_ipd "Log of Real Assets (using BLS IPD)"


* Real Sales Growth *

sort gvkey gvkey_run datadate

gen real_sales_ipd = saleq/ipd // Get real sales for quarter.

label var real_sales_ipd "Real Sales (using BLS IPD)"

by gvkey gvkey_run: gen real_sales_growth_ipd = log(real_sales_ipd) - log(real_sales_ipd[_n-1])

label var real_sales_growth_ipd "Log-difference in real sales (using BLS IPD)"


* Export Checkpoint *

save "./outputs/001c_cstat_jan1961_jan2022_ow_controls.dta", replace


  ****************************************************
* Distance to Default: CRSP Data, Initial Calculations *
  ****************************************************
  
/* 
For distance to default following Gilchrist and Zakrajsek (2012) and Vassalou and Xing (2004), we need observe...

(1) Firm equity (calculated as stock price multiplied by number of shares outstanding for all share classes on the Compustat datadate)
(2) Firm equity variance (calculated as sample variance of difference in firm equity in a 365-day window ending on the Compustat datadate)
(3) The one-year U.S. treasury yield
(4) Firm level debt

We use CRSP data to obtain (1) and (2), and merge in Federal Reserve data for (3).
*/


* Import CRSP Stock Returns Data *

use "./data/crsp_19600101_20201231.dta", clear


* Get Lower-case Variable Names*

rename PERMNO permno
rename PERMCO permco
rename CUSIP cusip
rename PRC prc
rename SHROUT shrout


* Adjust Stock Prices to Account for CRSP Imputation Indicator *

// When no trade of the stock took place on the day, CRSP takes the midpoint of the bid/ask spread and *precedes the imputed price with a minus sign*. Thus...

replace prc = -prc if prc < 0


* Calculate Equity Value *

generate equity = prc*shrout

label var equity "Share price multiplied by number of shares on date"


* Drop Extraneous Variables *

drop permno permco prc shrout // No longer needed


* Fill in Panel *

// Many datadates in Compustat fall on trading holidays (including weekends). We use tsfill here to accomodate for this possibility. 

encode cusip, gen(cusip_enc) // Takes about 5 minutes.

xtset cusip_enc date

tsfill // Takes about 5 minutes.

decode cusip_enc, gen(cusip_dec)

replace cusip = cusip_dec if missing(cusip) // Since I tsfill on cusip_dec, values of cusip for the new observations are initially empty. These are filled here

drop cusip_enc cusip_dec // No longer needed


* Merge in Market Yield on 1-year U.S. Treasuries *

merge m:1 date using "./outputs/001a_dgs1_19620101_20220120.dta"

drop if _merge == 2 // Drops non-overlapping dates

drop _merge


* Scale Treasury Yield * // The 1-year treasury yield (from The Fed) is given in %, and is given in annual terms. We remove the percentage and change to a daily rate here. Since we use 253 trading days in our annual time horizon and r needs to be commensurable with daily volatility, we use...

replace dgs1 = dgs1/100

replace dgs1 = (1 + dgs1)^(1/253) - 1


* Get Number of Equity Values in 365-day Window * // Following Gilchrist and Zakrajsek (2012), I use the Black-Scholes-Merton Model to estimate distance to default on a one-year horizon, with a 365-day window to estimate the variance of value.

rangestat (count) no_365 = equity, interval(date -364 0) by(cusip) // Counts number of non-missing equity values. Roughly 12 minutes.

label var no_365 "Number of non-missing equity values in 365-day window"


* Flag Observations with Insufficiently Large Sample of Equity in 365-day Window *

// I use only cusip-datadates in which half of the assumed trading days (253 days) are covered: no_365 >= 127 = ceiling(253*(1/2)).

gen viable_obs = 1

label var viable_obs "Observation can be used in calculating distance to default"

replace viable_obs = 0 if no_365 < 127

drop no_365 // No longer needed


* Export *

save "./outputs/001c_crsp_dd_may1960_dec2020.dta", replace


  *******************************************************
* Distance to Default: Integrating Compustat Data on Debt *
  *******************************************************
  
* Import CRSP-Compustat Merge Table *

// This table gives the appropriate CRSP-Compustat linkages for reporting dates of each gvkey.

use "./data/crsp_cstat_link_jan1960_dec2020.dta", clear


* Get Lower-case Variable Names *

rename GVKEY gvkey


* Drop Extraneous Variables *
  
keep gvkey datadate cusip


* Change CUSIP to 8-digits for later Merge into CRSP *

replace cusip = substr(cusip, 1, 8) // Compustat keeps 9-digit CUSIPs, which contain an extra indicator digit which is superfluous in CRSP.


* Drop Duplicates *

duplicates drop // 11,507 observations are duplicates in terms of gvkey, datadate and *8-digit* CUSIPS (but are unique in terms of 9-digit CUSIPs). Since we merge to Compustat on *gvkey* and not CUSIP, there are no duplicate Compustat entries whereby one Compustat gvkey maps onto multiple CRSP CUSIPs (8-digits). If we were mapping from Compustat to 9-digit CUSIPs, this would be a problem. As things are, there is not.


* Merge into Compustat *

merge 1:1 gvkey datadate using "./outputs/001c_cstat_jan1961_jan2022_ow_controls.dta" // Again, a 1:1 merge as gvkey-datadate is a unique identifier in the master dataset too.

keep if _merge == 3 // All observations from the master match. We keep only observations for which we can both calculate and merge a value for debt.

drop _merge


* Keep Only Necessary Variables * // This will be fine as we merge back into compustat eventually anywat

keep cusip datadate dlcq dlttq


* Get Debt Variable *

// Glichrist and Zakrajsek, operating on a 1-year horizon, consider firm debt to be all current liabilities in addition to one half of all long-term liabilities

gen debt = dlcq + 0.5*dlttq

drop dlcq dlttq // No longer necessary


* Rename Date Variable for Merge to CRSP *

rename datadate date


* Merge into CRSP Distance to Default Data *

merge 1:1 cusip date using "./outputs/001c_crsp_dd_may1960_dec2020.dta" // This is a 1:1 merge as cusip-(data)date is a unique identifier in the master dataset

drop if _merge == 1 // Observation is of no use if it doesn't merge into the CRSP data


* Flag Compustat Observations * // We flag the cusip-datadate pairings that feature in the compustat dataset

gen cstat_obs = 0

replace cstat_obs = 1 if _merge == 3 // Merged observations feature in both CRSP and Compustat

drop _merge // No longer needed


* Flag viable Compustat Observations * // We exclude here observations with an insufficiently large sample of equity values in the preceding 365-day window

gen viable_cstat_obs = cstat_obs*viable_obs

label var viable_cstat_obs "gvkey-datadate pair appears in Compustat, and sufficient number of non-missing equity values"


* Drop Observations from CUSIPs that do not Appear in Compustat (or for which Debt, and therefore distance to default, is not Calculable) *

bysort cusip: egen cusip_max_debt = max(debt) // Get the maximal (non-missing) value of debt for each individual CUSIP time series

drop if cusip_max_debt == . // Drop observations whose CUSIP does not correspond to any non-missing values for debt on any date. Drops 35,387,391 of 131,167,494 observations 24/01/22

drop cusip_max_debt


* Linearly Interpolate Debt Figures *

bysort cusip: ipolate debt date, gen(debt_interpolated) // Takes about 15 minutes.


* Flag Compustat Data for which Debt is Interpolated * // Since there's no figure for debt for the Compustat datadate, we do not calculate distance to default for this data (it would be absurd to conjecture distance to default if we don't, at the least, know the true value of the firm's debt.)

gen cstat_interpolated_debt = 0

replace cstat_interpolated_debt = 1 if debt != debt_interpolated & cstat_obs == 1 // 76,662 observations altered.

drop viable_obs cstat_obs // These are different criteria that serve the same purpose, so their product is sufficient.


* Fill in Debt Variable with Interpolations *

replace debt = debt_interpolated if debt == . 

drop debt_interpolated // No longer needed


* Replace Negative Debt Values * // For the purposes of distance to default, negative debt is the same as zero debt - distance to default is infinite. Thus, we replace negative debt with zero here.

replace debt = 0 if debt < 0 // 162 observations changed


* Rescale Debt * // Equity, since calculated from CRSP, is given exactly. Debt (from Compustat) is given in 1000s.

replace debt = debt*1000


* Save to be Merged Back into Below *

save "./outputs/001c_crsp_dd_may1960_dec2020.dta", replace


  **************************************
* Distance to Default: Final Calculation *
  **************************************
  
* Import CRSP *

use "./outputs/001c_crsp_dd_may1960_dec2020.dta", clear


* Rename Date to datadate for Nominal Clarity * 

// Below, I construct a dataset in which date refers to the date that the data are from, and datadate refers to the date of whose 365-day window the observation is a part.

rename date datadate


* Keep only Compustat datadate Observations *

keep if viable_cstat_obs == 1 // Leaves 917,480 observations.


* Keep only Observations for which Distance to Default is Calculable *

keep if debt != . & cstat_interpolated_debt == 0 // Without these two variables, we cannot calculate distance to default. This leaves 788,641 observations.


* Drop Extraneous Variables * // What we do below is create a dataset where each datadate for which distance to default is calculable has 365 observations corresponding to it, which make up the 365-day window which provides the sample estimates of volatility. This initially means we just construct a dataset at only the cusip-datadate-date level, which we then m:1 merge into 001c_crsp_dd_may1960_dec2020.dta.

keep cusip datadate


* Generate (Wide Version) Window Dataset *

forvalues i= 1/365{
    
	gen date`i' = datadate - 365 + `i'
	
}


* Reshape *

reshape long date, i(cusip datadate) j(day_of_window) // Expands dataset to 197,160,250 observations. This takes about 40-70 minutes.

drop day_of_window // The new time variable is unnecessary


* Format Date *

format date %td


* Merge back into Distance to Default Data *

merge m:1 cusip date using "./outputs/001c_crsp_dd_may1960_dec2020.dta" // Takes about 8 minutes.

keep if _merge == 3 | date == datadate // Drop unused data from using dataset.

drop _merge


* Drop Extraneous Variables *

drop viable_cstat_obs cstat_interpolated_debt // Since datadate indicates the Compustat datadate to which each observation pertains, we no longer need these.


* Drop Observations from Which V Uncalculable *

drop if date != datadate & (dgs1 == . | equity == . | debt == .) // We *always* preserve the date that features in the Compustat data (i.e. the 365th day of each window), and carry forward the most recent value for equity to it *later* to prevent double-counting in variance calculation. We lose some finite values for equity here, but recall that the variance of equity is merely a starting value for iteration until we find sigma_v; we don't actually need the "correct" value of sigma_equity, merely something close to it. We also ultimately do not care about equity and carry forward the most recent value of v forward to the compustat date if empty. Leaves 190,986,807 observations.


* Drop All but Last Consistent Run of Calculable V values * // If a firm has calculable values of V for March-July and then September-February only, for example, the variance of the stock price will likely be overestimated due the absence of the intermeditating values between the bunched values in March-July and the bunched values in September-February. In this example, I would drop the data from March-July.

bysort cusip datadate (date): gen lead_gap = date[_n+1] - date // Days between today's calculable V and next calculable V

gen gap_flag = 0 

replace gap_flag = 1 if lead_gap > 7 & lead_gap != . // I drop any observations that occur before a calendar week of incalculable Vs

drop lead_gap

bysort cusip datadate: egen cd_nr_obs = sum(1) // Number of dates for each cusip-datadate

summarize cd_nr_obs // Get max value for iterative loop

sort cusip datadate date

forvalues i = `=r(max)'(-1)1{
	
	by cusip datadate: replace gap_flag = 1 if _n == `i' & gap_flag[_n+1] == 1
	
}

drop if gap_flag == 1

drop gap_flag


* Drop Cusip-datadates with too Small Sample Size * // Again, we apply the 87-day lower bound to acceptable sample sizes for the calculation of volatility.

bysort cusip datadate (date): gen datadate_equity = equity[_N] // If the datadate has an empty value for equity, then we have one loss workable observation than indicated by cd_nr_obs.

bysort cusip datadate: replace cd_nr_obs = _N // We've dropped some stuff since the last count, so we have to replace this.

drop if cd_nr_obs < 127 | (cd_nr_obs == 127 & datadate_equity == .)

drop cd_nr_obs datadate_equity


* Compress * // Since this dataset is very large, we compress here

compress


* Save Entire Dataset *

save "./outputs/001c_dd_all.dta", replace


* Partition Dataset into 20 for Google Cloud Distance to Default Calculation *

bysort cusip datadate: gen obs_nr = _n

keep if obs_nr == 1

keep cusip datadate

gen random = runiform()

sort random

drop random

gen order_random = _n/_N

forvalues i = 1/20{
	
	preserve
	
	keep if order_random <= `i'/20 & order_random > (`i' - 1)/20
	
	drop order_random // Not really necessary to save
	
	merge 1:m cusip datadate using "./outputs/001c_dd_all.dta", keep(match)
	
	drop _merge
	
	save "./outputs/google_cloud/001_c_dd_tranche`i'.dta", replace
	
	restore
	
}


************************************************************************
* MOVE 0s TO MISSING FOR INCALCULABLE QUARTERLY MONETARY POLICY SHOCKS *
************************************************************************

* Import Shock Data Merged to Compustat *

use "./outputs/001b_cstat_shocks.dta", clear


* Get Month of Datadate *

gen tm_month = mofd(datadate)


* Move to Missing Incalculable Classical Shock Gertler and Karadi (2015) Values *
     
replace tw_shock_gk = . if tm_month < mofd(date("1990-06-01", "YMD")) | tm_month > mofd(date("2009-12-01", "YMD"))
replace ww_shock_gk = . if tm_month < mofd(date("1990-06-01", "YMD")) | tm_month > mofd(date("2009-12-01", "YMD"))
replace tw_ma_shock_gk = . if tm_month < mofd(date("1990-06-01", "YMD")) | tm_month > mofd(date("2009-12-01", "YMD"))
replace tw_ma_bic_shock_gk = . if tm_month < mofd(date("1990-06-01", "YMD")) | tm_month > mofd(date("2009-12-01", "YMD"))
replace ww_ma_shock_gk = . if tm_month < mofd(date("1990-06-01", "YMD")) | tm_month > mofd(date("2009-12-01", "YMD"))


* Move to Missing Incalculable Classical Shock Wong (2021) Values *

replace tw_shock_w = . if tm_month < mofd(date("1990-06-01", "YMD")) | tm_month > mofd(date("2010-03-01", "YMD"))
replace ww_shock_w = . if tm_month < mofd(date("1990-06-01", "YMD")) | tm_month > mofd(date("2010-03-01", "YMD"))
replace tw_ma_shock_w = . if tm_month < mofd(date("1990-06-01", "YMD")) | tm_month > mofd(date("2010-03-01", "YMD"))
replace tw_ma_bic_shock_w = . if tm_month < mofd(date("1990-06-01", "YMD")) | tm_month > mofd(date("2010-03-01", "YMD"))
replace ww_ma_shock_w = . if tm_month < mofd(date("1990-06-01", "YMD")) | tm_month > mofd(date("2010-03-01", "YMD"))

* Move to Missing Incalculable Nakamura and Steinsson (2018) Gertler and Karadi (2015) Values *
  
replace ns_shock_gk = . if tm_month < mofd(date("2000-06-01", "YMD")) | tm_month > mofd(date("2019-09-01", "YMD")) | (tm_month > mofd(date("2008-06-01", "YMD")) & tm_month < mofd(date("2009-12-01", "YMD")))
replace ns_ma_shock_gk = . if tm_month < mofd(date("2000-06-01", "YMD")) | tm_month > mofd(date("2016-12-01", "YMD")) | (tm_month > mofd(date("2008-06-01", "YMD")) & tm_month < mofd(date("2009-12-01", "YMD")))
replace ns_ma_bic_shock_gk = . if tm_month < mofd(date("2000-06-01", "YMD")) | tm_month > mofd(date("2016-12-01", "YMD")) | (tm_month > mofd(date("2008-06-01", "YMD")) & tm_month < mofd(date("2009-12-01", "YMD")))


* Move to Missing Incalculable Nakamura and Steinsson (2018) Wong (2021) Values *
  
replace ns_shock_w = . if tm_month < mofd(date("2000-06-01", "YMD")) | tm_month > mofd(date("2019-12-01", "YMD")) | (tm_month > mofd(date("2008-09-01", "YMD")) & tm_month < mofd(date("2009-12-01", "YMD")))
replace ns_ma_shock_w = . if tm_month < mofd(date("2000-06-01", "YMD")) | tm_month > mofd(date("2017-03-01", "YMD")) | (tm_month > mofd(date("2008-09-01", "YMD")) & tm_month < mofd(date("2009-12-01", "YMD")))
replace ns_ma_bic_shock_w = . if tm_month < mofd(date("2000-06-01", "YMD")) | tm_month > mofd(date("2017-03-01", "YMD")) | (tm_month > mofd(date("2008-09-01", "YMD")) & tm_month < mofd(date("2009-12-01", "YMD")))


* Drop Extraneous Variables *

drop tm_month // No longer needed


* Export *

compress

save "./outputs/001c_cstat_shocks.dta", replace


* Get Correlations: Keep Only Unique tm_months *

drop gvkey // Only variable not fixed at the month level

duplicates drop 


* Get Correlations: Keep Only Standard Calendar Quarters *

keep if mod(mofd(datadate), 3) == 2 // Keeps only quarters ending in March, June, September, and December.


* Get Basic Correlations: Common Quarters for Pairs *

count if !missing(tw_shock_gk)

count if !missing(ns_shock_gk)

count if !missing(ns_ma_shock_gk)

count if !missing(tw_shock_gk) & !missing(ns_shock_gk)

count if !missing(tw_shock_gk) & !missing(ns_ma_shock_gk)

count if !missing(ns_shock_gk) & !missing(ns_ma_shock_gk)


* Get Basic Correlations *

correlate tw_shock_gk tw_ma_shock_gk ns_shock_gk ns_ma_shock_gk


* Get BIC Correlations: Common Months for Pairs *

count if !missing(tw_shock_gk)

count if !missing(ns_shock_gk)

count if !missing(ns_ma_shock_gk)

count if !missing(tw_shock_gk) & !missing(ns_shock_gk)

count if !missing(tw_shock_gk) & !missing(ns_ma_shock_gk)

count if !missing(ns_shock_gk) & !missing(ns_ma_shock_gk)


* Get BIC Correlations *

correlate tw_shock_gk tw_ma_shock_gk tw_ma_bic_shock_gk ns_shock_gk ns_ma_shock_gk ns_ma_bic_shock_gk


* Get Wide Correlations: Common Quarters for Pairs *

count if !missing(tw_shock_gk)

count if !missing(ns_shock_gk)

count if !missing(ns_ma_shock_gk)

count if !missing(tw_shock_gk) & !missing(ns_shock_gk)

count if !missing(tw_shock_gk) & !missing(ns_ma_shock_gk)

count if !missing(ns_shock_gk) & !missing(ns_ma_shock_gk)


* Get Wide Correlations *

correlate tw_shock_gk tw_ma_shock_gk ww_shock_gk ww_ma_shock_gk ns_shock_gk ns_ma_shock_gk


* Get Wong Correlations: Common Quarters for Pairs *

count if !missing(tw_shock_gk)

count if !missing(tw_shock_w)

count if !missing(ns_ma_shock_gk)

count if !missing(ns_ma_shock_w)


count if !missing(tw_shock_gk) & !missing(tw_shock_w)

count if !missing(tw_shock_gk) & !missing(ns_ma_shock_gk)

count if !missing(tw_shock_gk) & !missing(ns_ma_shock_w)


count if !missing(tw_shock_w) & !missing(ns_ma_shock_gk)

count if !missing(tw_shock_w) & !missing(ns_ma_shock_w)


count if !missing(ns_ma_shock_gk) & !missing(ns_ma_shock_w)


correlate tw_ma_shock_gk tw_ma_shock_w ns_ma_shock_gk ns_ma_shock_w


/*
Note that...
    
- For the classical monetary policy shock series...		
 
 - The Gertler and Karadi (2015) shocks are calculable for 1990Q2b-2009Q4b (Including MA shocks)
 - The Wong (2019) shocks are calculable for 1990Q2b-2010Q1b (Including MA shocks)

 
- For the Nakamura and Steinsson (2018) monetary policy shock series...

 - The Gertler and Karadi (2015) shocks are calculable for 2000Q2b-2008Q2b; 2009Q4b-2019Q3b (for MA shocks, 2000Q2b-2008Q2b; 2009Q4b-2016Q4b)
 - The Wong (2019) shocks are calculable for 2000Q2b-2008Q3b; 2009Q4b-2019Q4b (for MA shocks, 2000Q2b-2008Q3b; 2009Q4b-2017Q1b)
	
*/

* Import Shock Data Merged to Compustat from 001b_cstat_shocks *



*************
* POSTAMBLE *
*************

log close

exit


/*

Old code for partitioning...

* Import Checkpoint *

use "./outputs/001c_dd_all.dta", clear


* Find Number of ~500MB Partitions *

memory // Stores number of bytes used in memory

local bytes = r(data_data_u) // Gets number of bytes used

local partitions = round((`bytes')/(1024*1024*500)) // There are 1,024 bytes in a KB and 1,024 KB in a MB. We want partitions to be roughly 500MB each.


* Group CUSIP-datadate Observations Together for Partitioning * // If we don't do this, partitioning can split CUSIP-datadate 365-day windows.

sort cusip datadate date // Ordered data is essential for the partitioning below

gen obs_nr = _n // Gets ordered number for each observation

bysort cusip datadate: egen cd_max_n = max(obs_nr) // Get greatest _n within cusip-datadate pair

drop obs_nr // No longer necessary


* Partition into Datasets and Export * // The remainder of calculation takes place in Python, so we export here.

forvalues i = 1/`partitions'{
	
	preserve // Partitioning the data requires preserving it.
	
	drop if cd_max_n <= (`=_N'/`partitions')*(`i' - 1) | cd_max_n > (`=_N'/`partitions')*`i'
	
	drop cd_max_n // No longer necessary
	
	compress
	
	save "./outputs/001c_dd_python_`i'.dta", replace
	
	restore // We restore the data at the end
	
}


* Find Old Unreplaced Files and Remove * // If the dataset shrinks, so may the number of partitions, yet 001c_dd_python_x.dta files from the old code may remain (viz. those with x > partition). We erase those here

local output_files_dta: dir "./outputs/" files "*.dta" // Gets all output files ending in ".dta"

foreach _file in `output_files_dta'{
	
	local filestart = substr("`_file'", 1, 15) // If this is a partition, filestart will be 001c_dd_python_
	
	if("`filestart'" == "001c_dd_python_"){
		
		local number_end = strpos("`_file'", ".") // The number (the x in 001c_dd_python_x.dta) will end here
		
		local filenumber = real(substr("`_file'", 16, `number_end' - 16)) // Gets the file number in string format
		
		if(`filenumber' > `partitions'){ // Executes only for superfluous files
			
			erase "./outputs/`_file'"
			
		}
		
	}
	
}

*/


* Old Code For Carrying Forward Equity * // Probably unnecessary and doable in Python.

/*
* Change Equity to Most Recently Observed Equity * // I carryforward equity values here (for no more than one week). We do this *after* getting the variance to prevent double-counting in its calculation.

gen cf = 1 // Indicator that observation may receive carried forward value of equity

bysort cusip (date): replace cf = 0 if missing(equity[_n-1]) & missing(equity[_n-2]) & missing(equity[_n-3]) & missing(equity[_n-4]) & missing(equity[_n-5]) & missing(equity[_n-6]) & missing(equity[_n-7]) // Ensures value of equity is carried forward (for at most one week.)

bysort cusip (date): carryforward equity if cf == 1, replace

label var equity "Equity, most recent observation"

drop cf // No longer needed
*/