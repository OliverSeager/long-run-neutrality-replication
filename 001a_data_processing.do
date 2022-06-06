/*

Oliver Seager
o.j.seager@lse.ac.uk
SE 16

This script essentially acts as an engine, importing and exporting datasets as is convenient for later code. It will work as the first of all 001?_data_processing scripts, alternating between Stata and Python as is appropriate.

Created: 02/12/2021
Last Modified: 30/05/2022

Infiles:
- cstat_jan1961_mar2022.dta (S&P Compustat Quarterly Fundamentals data. Fiscal 1961Q1-2022Q2, Calendar jan1961-mar2022)
- ffsurprises_1990_2009.xlsx (From Gürkaynak, Sack and Swanson (2005) via Nakamura and Steinsson (2018) (1990-1993) and Gorodnichenko and Weber (2015) (1994-2009). Data on FOMC-meeting FFF surprises. 1990-2009.)
- dgs1_19620101_20220120.xlsx (Daily constant 1-year maturity U.S. treasury market yield, from the Board of Governors of the Federal Reserve System (via FRED). Jan 2nd 1962 - Jan 20th 2022.)
- application.tsv (PatentsView - data on applications for granted patents.)
- assignee.tsv (PatentsView - data on all patent assignees, with assignee_id.)
- patent.tsv (PatentsView - patent-level data.)
- patent_assignee.tsv (PatentsView - one-to-many mapping of patent_id to assignee_id.)
- cpc_current.tsv (PatentsView - CPC classification of patents.)
- KPSS_2020_public.csv (Patent-level data from Kogan et al. (2017), with estimated dollar value and number of forward citations.)
- uspatentcitation (PatentsView - Observations at the citing patent to cited patent level (patent_id-citation_id pairs).) 

Out&Infiles:
- 001a_cstat_gvkey_datadate_authoratative.dta (Quarterly Compustat Data containing what I declare the correct observation (for a gvkey datadate panel) for each gvkey-datadate pairing which, in the original data, covers two observations.)
- 001a_cstat_jan1961_jan2022_clean.dta (Quarterly Compustat Data where gvkey-datadate is now an id, such that a panel can be declared based on these two variables.)

Outfiles:
- 001a_cstat_qdates.dta (gvkey-datadate level Computstat data with Stata clock time endpoints of the current and previous fiscal quarter)
- 001a_ffsurprises_tctime.dta (Data on Federal Funds Rate surprises with Stata clock time timestamps of the time of the FOMC post-meeting statement release)
- 001a_dgs1_19620101_20220120.dta (.dta version of daily 1-year U.S. treasury market yield with gaps in time series filled using linear interpolation. Jan 2nd 1962 - Jan 20th 2022.)
- application.dta (A .dta version of application.tsv)
- assignee.dta (A .dta version of assignee.tsv)
- patent.dta (A .dta version of patent.tsv)
- patent_assignee.dta (A .dta version of patent_assignee.tsv)
- cpc_classification.dta (A .dta version of cpc_current.tsv)
- kogan_patent_data.dta (A .dta version of KPSS_2020_public.csv)
- 001a_patent_forward_citations.dta (Observations at the patent level, with number of forward citations by patent.)
- cpc_classification.dta

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

log using "./code/001a_data_processing.log", replace


**********************************************
* GETTING ALTERED VERSIONS OF COMPUSTAT DATA *
**********************************************

  ********************************************
* Compustat Clean for gvkey-datadate Panel *
  ********************************************
  
* Import Compustat *
  
use "./data/cstat_jan1961_mar2022.dta", clear


* Drop non-Duplicate Observations *

duplicates tag gvkey datadate, gen(dup) // All 2,910 duplicates (1,460 gvkey-datadate pairs) are between two observations only

drop if dup == 0

drop dup

// Something important to note is that no gvkey-datadate pair differs in terms of costat


* Create a "Dealt with" Variable to Track Cleaning Progress *

gen dealt_with = 0

label var dealt_with "Authoratative observation in pair established"


* Create Numerical Accounting Data Varlist *

local numerical_accounting "actq atq cheq cogsq dlcq dlttq dvpq lctq ppegtq ppentq saleq xsgaq"


* Flag Pairs with Identical Numerical Accounting Data as Dealt With *

duplicates tag gvkey datadate `numerical_accounting', gen(dup)

replace dealt_with = 1 if dup > 0 // 472 of the 1,460 gvkey-datadate pairs are dealt with.

drop dup


* Flag Pairs with Identical Numerical Accounting Data Except for Missing Values *

gen semi_identical = 1 // Initiate indicator for identical observations except for missing values

label var semi_identical "From identical pair except for missing values"

replace semi_identical = 0 if dealt_with == 1 // We don't bother with pairs already dealt with.

foreach v in `numerical_accounting'{ // Here I loop through all numerical variables 
	
	bysort gvkey datadate: replace semi_identical = 0 if !missing(`v'[1]) & !missing(`v'[2]) & `v'[1] != `v'[2] // Only declared not to be semi-identical if two distinct, finite values for v exist for each gvkey-datadate pair.
	
} // All 1,966 remaining observations (983 pairs) which are "semi-identical".


* Combine Semi-identical Observations *

foreach v in `numerical_accounting'{ // Loop through all numerical variables again.
	
	bysort gvkey datadate (`v'): replace `v' = `v'[1] if missing(`v') & semi_identical == 1 // `v'[1] is the lowest value for v within the pair, so is less than missing.
	
} // This makes each semi-identical pair duplicated in terms of gvkey, datadate and numerical accounting variables.


* Flag Semi-identical Pairs as Dealt With *

duplicates tag gvkey datadate `numerical_accounting', gen(dup)

replace dealt_with = 1 if dup > 0 // All of the remaining observations are now dealt with.

drop dup


* Drop Extraneous Variables *

// At this point, all observations have been dealt with

drop dealt_with


* Drop Observations that Don't Match Calendar Quarter *

// I take those whose datadate matches datacqtr to be the authoritative observations. 

* Where both q Values Present, Get Implied Calendar Year, Quarter from datadate *

gen dd_month = mofd(datadate) // January 1960 = 0

label var dd_month "Months since Jan1960 of datadate variable"

gen dd_cal_y = floor((dd_month - 1)/12) + 1960 // Here, January 1960 maps to 1959. February-December 1960 map to 1960. This is the implied calendar year from datadate.

label var dd_cal_y "Calendar year of datadate variable"

gen dd_cal_q = ceil(mod(dd_month - 0.999, 12)/3) // Here, Feb-Apr map to 1, May-Jul map to 2, Aug-Oct map to 3, Nov-Jan map to 4. This is because we deal with end-dates.

label var dd_cal_q "1-4. Calendar quarter of datadate variable"


* Compare Implied Calendar Year-Quarter to datacqtr *

tostring dd_cal_y dd_cal_q, replace

gen dd_cqtr = ""

replace dd_cqtr = dd_cal_y + "Q" + dd_cal_q // Gets implied calendar year-quarter into same format as datacqtr

label var dd_cqtr "Calendar year-quarter of datadate variable"

gen dd_matches_dcq = 0 // Indicator for whether the two match

replace dd_matches_dcq = 1 if dd_cqtr == datacqtr

label var dd_matches_dcq "datadate matches datacqtr"


* Keep Observation in Pair where datadate Matches datacqtr *

bysort gvkey datadate (dd_matches_dcq): gen to_drop = 1 if _n == 1 & dd_matches_dcq[1] < dd_matches_dcq[2]

drop if to_drop == 1

drop to_drop


* Manually Break Remaining Ties *

drop if gvkey == "028924" & datadate == date("2009-07-31", "YMD") & missing(datafqtr) // This observation seems to differ in a semi-identical manner. Perhaps truncation forces non-equivalence here.


* Drop Extraneous Variables *

drop semi_identical dd_month dd_cal_y dd_cal_q dd_cqtr dd_matches_dcq


* Export *

save "./outputs/001a_cstat_gvkey_datadate_authoratative.dta", replace


* Re-import Original Compustat Data *

use "./data/cstat_jan1961_mar2022.dta", clear


* Drop non-Duplicate Observations *

duplicates tag gvkey datadate, gen(dup) 

drop if dup != 0 // Drops 2,920 duplicates

drop dup


* Append Authoratative Observations for each Duplicate *

append using "./outputs/001a_cstat_gvkey_datadate_authoratative.dta" // Adds in 1,460 observations.


* Save *

save "./outputs/001a_cstat_jan1961_jan2022_clean.dta", replace // gvkey-datadate is now an id.


  **********************************
* Compustat Quarterly Endpoints Only *
  **********************************

* Import Compustat *
  
use "./outputs/001a_cstat_jan1961_jan2022_clean.dta", clear


* Drop Extraneous Variables *

keep gvkey datadate fyearq fqtr datacqtr datafqtr


* Get "Datadate Is Leap Year" Indicator *

gen datadate_is_leap_year = 0 // Initiate indicator

replace datadate_is_leap_year = 1 if mod(yofd(datadate),4) == 0 // Replace if leap year

label var datadate_is_leap_year "Indicates Last Day of Quarter During Leap Year"


* Get Date of End of Previous Quarter *

// We note that all datadates are the last day of the month

gen td_prevq_datadate = .

replace td_prevq_datadate = datadate - 89 if datadate_is_leap_year == 0 & mod(mofd(datadate), 12) + 1 == 4

replace td_prevq_datadate = datadate - 90 if (datadate_is_leap_year == 0 & (mod(mofd(datadate), 12) + 1 == 2 | mod(mofd(datadate), 12) + 1 == 3)) | (datadate_is_leap_year == 1 & mod(mofd(datadate), 12) + 1 == 4)

replace td_prevq_datadate = datadate - 91 if mod(mofd(datadate), 12) + 1 == 6 | mod(mofd(datadate), 12) + 1 == 11 | (datadate_is_leap_year == 1 & (mod(mofd(datadate), 12) + 1 == 2 | mod(mofd(datadate), 12) + 1 == 3))

replace td_prevq_datadate = datadate - 92 if mod(mofd(datadate), 12) + 1 == 1 | (mod(mofd(datadate), 12) + 1 > 4 & mod(mofd(datadate), 12) + 1 != 6 & mod(mofd(datadate), 12) + 1 != 11)

drop datadate_is_leap_year // No longer needed


* Get "Prev Quarter datadate Is Leap Year" Indicator *

gen prevq_datadate_is_leap_year = 0 // Initiate indicator

replace prevq_datadate_is_leap_year = 1 if mod(yofd(td_prevq_datadate),4) == 0 // Replace if leap year

label var prevq_datadate_is_leap_year "Indicates Last Day of Previous Quarter During Leap Year"


* Get Date of End of Previous Quarter *

// We note that all datadates are the last day of the month

gen td_2qago_datadate = .

replace td_2qago_datadate = td_prevq_datadate - 89 if prevq_datadate_is_leap_year == 0 & mod(mofd(td_prevq_datadate), 12) + 1 == 4

replace td_2qago_datadate = td_prevq_datadate - 90 if (prevq_datadate_is_leap_year == 0 & (mod(mofd(td_prevq_datadate), 12) + 1 == 2 | mod(mofd(td_prevq_datadate), 12) + 1 == 3)) | (prevq_datadate_is_leap_year == 1 & mod(mofd(td_prevq_datadate), 12) + 1 == 4)

replace td_2qago_datadate = td_prevq_datadate - 91 if mod(mofd(td_prevq_datadate), 12) + 1 == 6 | mod(mofd(td_prevq_datadate), 12) + 1 == 11 | (prevq_datadate_is_leap_year == 1 & (mod(mofd(td_prevq_datadate), 12) + 1 == 2 | mod(mofd(td_prevq_datadate), 12) + 1 == 3))

replace td_2qago_datadate = td_prevq_datadate - 92 if mod(mofd(td_prevq_datadate), 12) + 1 == 1 | (mod(mofd(td_prevq_datadate), 12) + 1 > 4 & mod(mofd(td_prevq_datadate), 12) + 1 != 6 & mod(mofd(td_prevq_datadate), 12) + 1 != 11)

drop prevq_datadate_is_leap_year // No longer needed


* Add Current Quarter Endpoint *

rename datadate td_datadate // datadate comes in Stata's "date" format.

gen tc_current_q_end = cofd(td_datadate + 1) // Compustat lists data date as the last day of a given quarter. Hence, if a quarter ends at the end of december (1st January 00:00:00), we need to add on a day before converting to clock format. "Clock" time conversions are accurate to within a minute or so.

label var tc_current_q_end "Endpoint of Current Quarter in Clock Format"


* Add Lagged Quarter Endpoint *

gen tc_lag1_q_end = cofd(td_prevq_datadate + 1) // Initiate variable

label var tc_lag1_q_end "Endpoint of Previous Quarter in Clock Format"

drop td_prevq_datadate // No longer needed


* Add Second Lagged Quarter Endpoint *

gen tc_lag2_q_end = cofd(td_2qago_datadate + 1) // Initiate variable

label var tc_lag2_q_end "Endpoint of Two Quarters Ago in Clock Format"

drop td_2qago_datadate // No longer needed


* Drop Extraneous Variables *

keep gvkey td_datadate tc_current_q_end tc_lag1_q_end tc_lag2_q_end // We keep gvkey-datadate to merge back in easily


* Export *

compress

save "./outputs/001a_cstat_qdates.dta", replace


*************************************************
* GETTING ALTERED VERSIONS OF FF SURPRISES DATA *
*************************************************

  ***************************************
* FF Surprises with Stata %tc Time Format *
  ***************************************

* Import Data *

import excel "./data/ffsurprises_1990_2009.xlsx", firstrow clear


* Get %tc Format Time *

gen tc_time = cofd(date) + time_milliseconds // Already calculated the number of milliseconds *into the day* in Excel

drop time_milliseconds // No longer needed


* Get Changes into Destringable Format *

// For some reason some of these variables contain an incorrect hyphen, which doesn't register in Stata as a minus sign

replace unexp_tw = subinstr(unexp_tw, "−", "-", .)

replace unexp_ww = subinstr(unexp_ww, "−", "-", .)

replace exp_tw = subinstr(exp_tw, "−", "-", .)

replace exp_ww = subinstr(exp_ww, "−", "-", .)

replace actual = subinstr(actual, "−", "-", .)


* Destring Changes *

destring unexp_tw unexp_ww exp_tw exp_ww actual, replace


* Export Data *

save "./outputs/001a_ffsurprises_tctime.dta", replace


*******************************************************
* GETTING ALTERED VERSION OF 1-YEAR TREASURY YIELD DATA *
*******************************************************

* Import Data *

import excel "./data/dgs1_19620101_20220120.xlsx", firstrow clear


* Rename to Align with CRSP; to Lower-case *

rename observation_date date

rename DGS1 dgs1


* Set and Fill Time Series *

tsset date

tsfill // Adds 6,266 dates, taking total from 15,668 to 21,934.


* Linearly Interpolate Market Yield *

ipolate dgs1 date, gen(dgs1_interpolated)

replace dgs1 = dgs1_interpolated if missing(dgs1) // Fills in missing values with interpolations

drop dgs1_interpolated


* Export to .dta *

save "./outputs/001a_dgs1_19620101_20220120.dta", replace


*********************************************
* GETTING .dta VERSIONS OF PATENTSVIEW DATA *
*********************************************

  ***********
* Application *
  ***********

* Import .tsv File *

import delimited "./orig/PatentsView/application.tsv", varnames(1) clear


* Disambiguate Variable Names * // We want these to only align with other datasets when it's the same variable

rename id uspto_application_id

rename number application_id

rename country application_country

rename series_code application_series_code


* Compress *

compress


* Clean Date Variable: 00 Day of Month *

replace date = substr(date, 1, 8) + "01" if substr(date,9,2) == "00" // All date strings are 10 characters. Some have 00 as the day of month. We replace this with 01.


* Clean Date Variable: mis-OCRed Years * // We generally presume anything outside of 1868-2021 is wrongly OCRed

replace date = "1" + substr(date, 2, .) if substr(date, 1, 1) == "0" | (substr(date, 1, 1) == "2" & substr(date, 1, 2) != "20") | substr(date, 1, 1) == "7" // 0 or 2 or 7 instead of 1 read as first character

replace date = "19" + substr(date, 3, .) if substr(date, 1, 2) == "10" | substr(date, 1, 2) == "12" | substr(date, 1, 2) == "16" // 0 or 2 or 6 instead of 9 read as second character

replace date = "19" + substr(date, 3, .) if substr(date, 1, 2) == "81" | substr(date, 1, 2) == "91" // 81 or 91 instead of 19 as first two characters


* Get Date to Stata td Format *

gen application_date = date(date, "YMD") // Currently date is a string

format application_date %td

drop date


* Label Variables *

label var uspto_application_id "USPTO-assigned Application ID"

label var patent_id "USPTO Patent Publication Number"

label var application_id "Patentsview-assigned Idiosyncratic Application ID"

label var application_country "Country of Application"

label var application_date "Date of Application Filing"

label var application_series_code "Application Series Code"


* Order Variables *

order patent_id application_date application_id uspto_application_id application_series_code application_country


* Export *

save "./data/application.dta", replace


  ********
* Assignee *
  ********
  
* Import .tsv File *

import delimited "./orig/PatentsView/assignee.tsv", varnames(1) clear


* Disambiguate Variable Names *

rename id assignee_id

rename type assignee_type

rename name_first assignee_forename 

rename name_last assignee_surname

rename organization assignee_name


* Label Variables *

label var assignee_id "Patentsview-assigned Idiosyncratic Assignee ID"

label var assignee_type "Patentsview Classification of Assignee"

label var assignee_forename "Forename, if assignee is individual"

label var assignee_surname "Surname, if assignee is individual"

label var assignee_name "Organisation name, if assignee is organisation"


* Order Variables *

order assignee_id assignee_name assignee_forename assignee_surname assignee_type


* Export *

compress

save "./data/assignee.dta", replace


  ******
* Patent *
  ******
  
* Import .tsv File *

import delimited "./orig/PatentsView/patent.tsv", varnames(1) clear


* Disambiguate Variable Names *

rename id patent_id

rename type patent_category

drop number // Identical to ID

rename country granting_country

rename title patent_title

rename kind patent_kind

rename num_claims patent_nr_claims

drop filename // Not information on the patent, merely the source of the information

rename withdrawn patent_withdrawm


* Label Variables *

label var patent_id "USPTO Patent Publication Number"   

label var patent_category "Category of Patent"

label var granting_country "Country in which Patent Granted"

label var abstract "Patent Abstract Text"

label var patent_title "Title of Patent"

label var patent_kind "USPTO Kind Code; Essentially the type of patent"

label var patent_nr_claims "Number of Claims on Patent"

label var patent_withdrawm "Indicator: Whether Patent Withdrawn"


* Compress *

compress


* Get Granting Date in Stata %td Format *

gen granting_date = date(date, "YMD")

format granting_date %td

label var granting_date "Date on which Patent Granted"

drop date


* Order Variables *

order patent_id granting_date patent_title patent_kind patent_category patent_nr_claims patent_withdrawm abstract


* Export *

save "./data/patent.dta", replace


  ***************
* Patent Assignee *
  ***************
  
* Import .tsv File *

import delimited "./orig/PatentsView/patent_assignee.tsv", varnames(1) clear


* Label Variables *

label var patent_id "USPTO Patent Publication Number"

label var assignee_id "PatentsView-assigned Idiosyncratic Assignee ID"

label var location_id "PatentsView-assigned ID for Location of Assignee"


* Export *

compress

save "./data/patent_assignee.dta", replace


  ******************
* CPC Classification *
  ******************
  
* Import .tsv File *

import delimited "./orig/PatentsView/cpc_current.tsv", varnames(1) clear


* String Patent ID *

tostring patent_id, replace // We do this to align with other datasets


* Label Variables *

label var uuid "PatentsView-assigned idiosyncratic classification ID"

label var patent_id "USPTO Patent Publication Number"

label var section_id "CPC Section (Tier 1)"

label var subsection_id "CPC Subsection (Tier 2)"

label var group_id "CPC Group (Tier 3)"

label var subgroup_id "CPC Group (Tier 4)"

label var category "CPC Category"

label var sequence "Order in which CPC Class Appears in Patent File"


* Export *

compress

save "./data/cpc_classification.dta", replace


****************************************
* GET KOGAN ET AL. (2017) DATA TO .dta *
****************************************

* Import .csv File *

import delimited "./orig/Kogan et al/KPSS_2020_public.csv", varnames(1) clear


* Rename Variables *

rename patent_num patent_id // Aligns with PatentsView


* Compress *

compress


* Get Date Variables to %td Format *

gen issue_date_td = date(issue_date, "MDY")

gen filing_date_td = date(filing_date, "MDY")

drop issue_date filing_date // Drop string dates

rename issue_date_td issue_date // Rename to original name

rename filing_date_td filing_date

format issue_date filing_date %td


* Label Variables *

label var patent_id "USPTO Patent Publication Number"

label var xi_real "Patent Value, 1982 Dollars"

label var xi_nominal "Patent Value, Nominal Dollars"

label var permno "CRSP Permno Company Identifier"

label var cites "Forward Citations"

label var issue_date "Date of Patent Granting"

label var filing_date "Date of Patent Application"


* Recast Patent ID to String *

// We do this to enable merging with other datasets

tostring patent_id, replace


* Export *

save "./data/kogan_patent_data.dta", replace


*************************************
* GET PATENT UPSTREAM CITATION DATA *
*************************************

// Since the citation file is so large, we don't export it to .dta; we simply count the number of citations to each patent and export that.

* Import Data *

import delimited "./orig/PatentsView/uspatentcitation.tsv", varnames(1) clear


* Drop Extraneous Variables *

keep patent_id citation_id // Note that here, patent_id is the patent that is *doing the citing*. We clarify this below.


* Rename Variables to Clarify *

rename patent_id citing_patent_id

rename citation_id cited_patent_id


* Drop Duplicates *

duplicates drop // This is just to make sure we're at the citing_patent_id-cited_patent_id level


* Count Number of Citations by Patent *

bysort cited_patent_id: gen nr_forward_citations = _N


* Reduce to Cited Patent Level *

drop citing_patent_id // No longer needed

duplicates drop


* Rename and Label Variables *

rename cited_patent_id patent_id

label var patent_id "USPTO Patent Publication Number"

label var nr_forward_citations "Number of US Patents Citing this Patent"


* Export *

compress

save "./outputs/001a_patent_forward_citations.dta", replace


*************
* POSTAMBLE *
*************

log close

exit


/*
Compustat variables used, 13/01/2022:

Standard Variables
- GVKEY - Unique Compustat firm identifier
- CUSIP - CUSIP identifier for merging with CRSP data
- SIC - Standard Industry Classification code

Time variables
- DATADATE - Last day of quarter to which data applies
- FYEARQ - Firm's idiosyncratic fiscal year
- FQTR - Quarter of firm's idiosyncratic fiscal year. 1-4.
- DATAFQTR - Quarter of firm's idiosyncratic fiscal year. 1960Q1 = 1.
- DATACQTR - *Approximated* calendar quarter to which firm's idiosyncratic fiscal quarter corresponds. 1960Q1 = 1.
- APDEDATEQ - Actual accounting end date. 

Initial Drop Variables
- EXCHG - Stock exchange code (can be used to remove Canadian-listed firms)
- FIC - Foreign Incorporation code (can be used to remove non-US-based firms)
- LOC - Headquartered country (can be used to remove non-US-based firms)
- INDFMT - Industry format (used to remove financial services firms)

Variables for Ottonello & Winberry (2020)
- PPENTQ - Net property, plant and equipment (used to calculate investment, cash_flow)
- DLCQ - Debt in current liabilities (used to calculate leverage, net_leverage, dist_to_default)
- DLTTQ - Long-term debt (used to calculate leverage, net_leverage, dist_to_default)
- ATQ - Total assets (used to calculate leverage, net_leverage, liquidity, size)
- ACTQ - Current assets (used to calculate net_leverage)
- LCTQ - Current liabilities (used to calculate net_leverage)
- SALEQ - Net sales (used to calculate cash_flow, real_sales_growth)
- CHEQ - Cash and short-term investments (used to calculate liquidity)
- PPEGTQ - Gross property, plant and equipment (used to calculate cash_flow)
- COGSQ - Cost of goods sold (used to calculate cash_flow)
- XSGAQ - Selling, general, and administrative expenses (used to calculate cash_flow)
- DVPQ - Dividends (used to calculate paid_dividends)
- AQCY - Acquisitions (used to deselect firm-quarters where acquisitions exceed 5% of total assets)
*/