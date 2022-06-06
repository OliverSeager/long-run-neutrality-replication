/*

Oliver Seager
o.j.seager@lse.ac.uk
SE 17

The idea of this script is to produce a gvkey-ecq level dataset with patent counts weighted by Kogan et al. (2017) valuations, for the given quarter and summations over horizons of up to 19 quarters ahead. Since Kogan et al. (2017) use their own mapping to CRSP (an adaptation of the NBER algorithm), I circumvent my Compustat-PatentsView match here and instead refer to the WRDS CRSP-Compustat linking table.

Created: 24/05/2022
Last Modified: 24/05/2022

Infiles:
- kogan_patent_data.dta (Patent-level data from Kogan et al. (2017), with estimated dollar value and number of forward citations.)
- 001b_monthly_cpi.dta (The Organisation for Economic Cooperation and Development's CPI Price Index at the monthly frequency, with Stata %tm time format.)
- crsp_cstat_link.dta (WRDS' link of CRSP Permno and Permco to Compustat gvkey, with link start and end dates.)
- 001c_cstat_jan1961_jan2022_ow_controls.dta (S&P Compustat Quarterly Fundamentals data, with all Ottonello and Winberry (2020) control variables)

Out&Infiles:

Outfiles:
- 003c_database_c.dta (A gvkey-ecq level dataset of summative patent values, as determined by Kogan et al. (2017), for the current ecq through 19 ecqs ahead.)

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

log using "./code/003b_patent_database_c.log", replace


***********************
* BUILDING DATABASE C *
***********************

* Import Kogan Data *

use "./data/kogan_patent_data.dta", clear // Data are comprehensive to the end of 2017m2 (for filings)


* Drop Extraneous Variables *

keep patent_id xi_nominal permno filing_date issue_date // We keep only the nominal value of patents here, as we wish to deflate it to 2012 dollars (rather than the 1982 dollars used by Kogan et al. (2017))


* Populate Missing Values for Filing Date * // For this, we simply take the median time a patent takes to grant

gen waiting_period = filing_date - issue_date // Length of time (days) between application and granting

quietly summarize waiting_period, detail // Gets median waiting_period into `=r(p50)'

replace filing_date = issue_date - `=r(p50)' if missing(filing_date)

drop waiting_period // No longer needed


* Deflate Nominal Patent Value to 2012 Dollars *

// Since nominal value is measured at time of granting, we use the month of the granting date to merge to CPI

gen observation_date = mofd(issue_date) // Granting month. This variable name is necessary to merge to the CPI data

merge m:1 observation_date using "./outputs/001b_monthly_cpi.dta"

drop if _merge == 2 // All master observations merge. We don't need unused CPI months.

gen xi_real = xi_nominal/cpi_index

label var xi_real "Patent Value, 2012 Dollars"

drop xi_nominal observation_date cpi_index _merge issue_date // No longer needed


* Merge to WRDS Compustat-CRSP Linking Table *

rename permno LPERMNO // Facilatates merge

joinby LPERMNO using "./data/crsp_cstat_link.dta", unmatched(both)

rename LPERMNO permno
rename LINKDT linkdt
rename LINKENDDT linkenddt

tabulate _merge // The vast majority of observations merge

keep if _merge == 3 // We can only use merged data

drop _merge LINKPRIM LIID LINKTYPE LPERMCO


* Drop Temporally Erroneous Patent-gvkey Matches *

drop if filing_date < linkdt | filing_date > linkenddt // Observations are now unique at the patent_id-gvkey level


* Get Fractional Share of Patent per gvkey *

bysort patent_id: gen fractional_share = 1/_N

label var fractional_share "gvkey's fractional share of patent"


* Get Fractional Patent Value *

gen frac_xi_real = xi_real*fractional_share

label var frac_xi_real "Fractional Value of Patent, 2012 Dollars"

drop xi_real // No longer needed


* Collapse to gvkey-month Level *

gen ecq_start_month = mofd(filing_date)

format ecq_start_month %tm

label var ecq_start_month "Starting month of exact calendar quarter"

drop patent_id fractional_share permno filing_date linkdt linkenddt // No longer needed

collapse (sum) frac_xi_real, by(gvkey ecq_start_month)


* Set Panel *

encode gvkey, gen(gvkey_enc) // We need a numeric for setting the panel

xtset gvkey_enc ecq_start_month


* Fill Panel *

// We do this to calculate sums for each gvkey

tsfill, full // Fill in gaps, creating a strongly balanced panel


* Populate Empty Panel Observations *

bysort gvkey_enc (gvkey): replace gvkey = gvkey[_N] // Here we populate the gvkey for the new observations; for string variables, missing values go to the *start* of an ordering

drop gvkey_enc // No longer needed

replace frac_xi_real = 0 if missing(frac_xi_real)


* Get *Quarterly* Value of Patent Counts *

bysort gvkey (ecq_start_month): gen ecq_patent_count = frac_xi_real + frac_xi_real[_n+1] + frac_xi_real[_n+2]

drop if missing(ecq_patent_count) // We don't need these last two months - we don't have full data on the last two quarters that they are the starting month of


* Get Winsorised Quarterly Value of Patent Counts, Based on "Active Patenting Period" for Firms *

/* For winsorisation, we... 
(1) ...only count normal calendar quarters (Jan-Mar, Apr-Jun, etc.) as to not triple-count firm patenting
(2) ...only count quarters when the firm is "actively patenting" - the period from the firm's first patenting to last patenting
*/

bysort gvkey (ecq_start_month): egen first_patenting_ecqStartMonth = min((frac_xi_real > 0)*ecq_start_month) // First ecq_start month for which firm patents (essentially two months before first patenting month)

bysort gvkey (ecq_start_month): egen last_patenting_ecqStartMonth = max((frac_xi_real > 0)*ecq_start_month) // Last ecq_start month for which firm patents (essentially last patenting month)

gen active_patenting_ecq = (ecq_start_month >= first_patenting_ecqStartMonth & ecq_start_month <= last_patenting_ecqStartMonth) // Marks quarters as "active patenting" or not (note citationless patents don't count here). 

drop first_patenting_ecqStartMonth last_patenting_ecqStartMonth // No longer needed

_pctile ecq_patent_count if mod(ecq_start_month, 3) == 0 & active_patenting_ecq == 1, percentiles(1 99) // The mod Boolean checks the ecq corresponds to a standard quarter. Stores 1st percentile in `r(r1)' and 99th percentile in `r(r2)'

gen wins_ecq_patent_count = `r(r1)'*(ecq_patent_count < `r(r1)') + ecq_patent_count*(ecq_patent_count >= `r(r1)' & ecq_patent_count <= `r(r2)') + `r(r2)'*(ecq_patent_count > `r(r2)')  // Gets winsorised value

drop active_patenting_ecq frac_xi_real // No longer needed


* Get 0th Horizon (Current ecq) Log Patent Count *

gen log_1PlusPatents_h0 = log(1 + ecq_patent_count)

gen log_1PlusWinsPatents_h0 = log(1 + wins_ecq_patent_count)


// Note that our data are monthly, by starting month of exact calendar quarter. We want the *quarterly* sums of frac_weighted_forward_citations for patents for the current and 19 succeeding quarters.

forvalues q_horizon = 1/19{ // The q horizon is the number of quarters incorporated in the sum
	
	gen patents_h`q_horizon' = ecq_patent_count if ecq_start_month <= 633 // We initiate the variable with the number of patents for the current month. We stop at October 2012 (2012Q4b) inclusive.
	
	gen wins_patents_h`q_horizon' = wins_ecq_patent_count if ecq_start_month <= 633
	
	local m_horizon = `q_horizon'*3 // This is the number of months ahead that we sum quarters over (in steps of 3)
	
	forvalues m = 3(3)`m_horizon'{
		
		bysort gvkey (ecq_start_month): replace patents_h`q_horizon' = patents_h`q_horizon' + ecq_patent_count[_n + `m'] if ecq_start_month <= 633
		
		bysort gvkey (ecq_start_month): replace wins_patents_h`q_horizon' = wins_patents_h`q_horizon' + wins_ecq_patent_count[_n + `m'] if ecq_start_month <= 633
		
	}
	
	gen log_1PlusPatents_h`q_horizon' = log(1 + patents_h`q_horizon') // We calculate the log value here
	
	gen log_1PlusWinsPatents_h`q_horizon' = log(1 + wins_patents_h`q_horizon') // We calculate the log value here
	
	drop patents_h`q_horizon' wins_patents_h`q_horizon' // We're only actually interested in the log value
	
}


* Drop Non-log ecq Patent Counts *

drop ecq_patent_count wins_ecq_patent_count


* Drop ecqs After 2012Q4b *

drop if ecq_start_month > 633


* Translate Exact Calendar Quarter Start Month to Exact Calendar Quarter *

gen m_of_year = mod(ecq_start_month, 12) + 1 // 1-12. Month of the year for ecq_start_month

gen ecq_year = yofd(dofm(ecq_start_month)) + (m_of_year == 12) // Year to which ecq is attached. If the exact calendar quarter starts in December, this maps to Q1a of the following year

tostring ecq_year, replace // We store ecq as a string, so we need this component as a string.

gen ecq = ecq_year + "Q1a" if m_of_year == 12 
replace ecq = ecq_year + "Q1b" if m_of_year == 1
replace ecq = ecq_year + "Q1c" if m_of_year == 2 
replace ecq = ecq_year + "Q2a" if m_of_year == 3 
replace ecq = ecq_year + "Q2b" if m_of_year == 4 
replace ecq = ecq_year + "Q2c" if m_of_year == 5 
replace ecq = ecq_year + "Q3a" if m_of_year == 6 
replace ecq = ecq_year + "Q3b" if m_of_year == 7 
replace ecq = ecq_year + "Q3c" if m_of_year == 8 
replace ecq = ecq_year + "Q4a" if m_of_year == 9
replace ecq = ecq_year + "Q4b" if m_of_year == 10
replace ecq = ecq_year + "Q4c" if m_of_year == 11

drop ecq_start_month m_of_year ecq_year


* Re-order Variables *

order gvkey ecq


* Merge to Compustat Data, Drop Unneeded Observations *

// We have data on gvkeys for *every possible ecq* for our data period (i.e. 12 observations a year). Typically, we only need 4 observations a year. We merge to gvkey-ecq in our Compustat data and drop everything that doesn't merge in order to rectify this.

merge 1:1 gvkey ecq using "./outputs/001c_cstat_jan1961_jan2022_ow_controls.dta", keepusing(gvkey ecq) // We don't actually retain any variables from the dataset we merge to; we just want _merge numbers

drop if _merge != 3

drop _merge


* Export *

compress

save "./outputs/003c_database_c.dta", replace


*************
* POSTAMBLE *
*************

log close

exit