/*

Oliver Seager
o.j.seager@lse.ac.uk
SE 17

The idea of this script is to match accounting-side firm names to gvkeys from Compustat.

Created: 17/05/2022
Last Modified: 23/05/2022

Infiles:
- 001c_cstat_jan1961_jan2022_ow_controls.dta (S&P Compustat Quarterly Fundamentals data, with all Ottonello and Winberry (2020) control variables except distance to default.)
- crsp_19600101_20201231.dta (Daily return data on US-listed stocks from CRSP)
- crsp_cstat_link.dta (WRDS' link of CRSP Permno and Permco to Compustat gvkey, with link start and end dates.)

Out&Infiles:

Outfiles:
- 003a_database_a_cstat.dta (List of all compustat gvkeys and the corresponding company names, with dates indicating the duration of the listing.)
- 003a_database_a_comnam_permco.dta (Mapping from CRSP names (comnam) to CRSP permco)
- 003a_database_a_crsp.dta (Mapping from CRSP names (comnam) to Compustat gvkey)
- 003a_database_a_unclean.dta (Concatenated Compustat (conm) and CRSP (comnam) names to Compustat gvkey, with time overlaps removed)
- 003a_database_a_clean_names_messy_times.dta (Cleaned names from 003a_database_a_unclean.dta (except full whitespace removal), with time overlaps)
- 003a_database_a_clean_names_clean_times.dta (Cleaned names from 003a_database_a_unclean.dta (except full whitespace removal), with time overlaps removed)
- 003a_database_a.dta (Concatenated Compustat (conm) and CRSP (comnam) names, cleaned, to Compustat gvkey, with time overlaps removed and wide timings added)

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

log using "./code/003a_patent_database_a.log", replace


***********************************
* GETTING UNCLEAN COMPUSTAT NAMES *
***********************************

* Import Compustat Data *

use "./outputs/001c_cstat_jan1961_jan2022_ow_controls.dta", clear


* Drop Firms by Fundamentals * // To make things a *lot* easier for ourselves, we conduct the fundamental drops we use for our regressions here.

drop if (sic >= 6000 & sic < 6800) | (sic >= 4900) & (sic < 5000) | sic == 9995 | sic == 9997 // Financial firms, utilities firms, Non-operative firms and Industrial Conglomerates

drop if fic != "USA" // Firms not incorporated in the US


* Get First day of Quarter Variable *

gen first_day_q = dofm(mofd(datadate) - 2) // dofm(month) returns the first day of the specified month. datadate occurs on the last day of the last month of the quarter. Therefore dofm(mofd(datadate) - 2) returns the first day of the first month of the quarter. Note that the last day of the quarter is by default the datadate.


* Get Start Point for each gvkey *

// Note that here it's unclear whether we want to start the gvkey-name association for the (patents on RHS: 5 years prior to accounting data to end of accounting data) or (patents on LHS: start of accounting data to 5 years after accounting data). We wait until later to determine this.

bysort gvkey (first_day_q): egen as_date_1 = min(first_day_q) // Earliest day of data coverage

label var as_date_1 "Day of start of name-gvkey link"


* Get End Point for each gvkey *

// See note above

bysort gvkey (datadate): egen as_date_n = max(datadate) // Last day of data coverage

label var as_date_n "Day of end of name-gvkey link"


* Drop Firms not Listed before 1980 *

// Since we have only identifiable FOMC meeting monetary policy shocks from 1990 onwards and patent data from 1980 onwards, we drop every firm that was listed only prior to 1980

drop if datadate < date("1980-01-01", "YMD")


* Drop Extraneous Variables *

keep gvkey conm as_date_1 as_date_n // Observations are now duplicates within gvkeys


* Rename Company Name *

rename conm as_name


* Generate Data Source Variable *

gen as_source = 1 // Source of data on the accounting side.

label var as_source "1 - Compustat, 2 - CRSP" // CRSP- and SDC-sourced names will be appended below


* Drop Duplicates *

duplicates drop // Reduces to 39,253 firms


* Export *

save "./outputs/003a_database_a_cstat.dta", replace 


*************************************
* GETTING UNCLEAN CRSP-LINKED NAMES *
*************************************

  ***********************
* Get comnam-permno Pairs *
  ***********************

* Import Daily CRSP Data * // We start with comnam-permno links
  
use "./data/crsp_19600101_20201231.dta", clear


* Drop Extraneous Variables *

keep PERMNO date COMNAM


* Rename Variables to Lower-case *

rename PERMNO permno
rename COMNAM comnam


* Drop Observations without Company Name *

// If we have no company name, we have nothing on which to base the match.

drop if missing(comnam)


* Get Start and End Dates of Each comnam-permno Link *

bysort permno comnam: egen cp_link_start = min(date)

bysort permno comnam: egen cp_link_end = max(date)

format cp_link_start cp_link_end %td


* Drop pre-1975 Links *

drop if cp_link_end < date("1975-01-01", "YMD")


* Reduce to Link Level *

drop date // Only variable not constant at the comnam-permno level

duplicates drop // Reduces to 42,734 comnam-permno links


* Export *

save "./outputs/003a_database_a_comnam_permco.dta", replace


  *************************
* Get comnam-gvkey Mappings *
  *************************

* Import Data *

use "./outputs/003a_database_a_comnam_permco.dta", clear

  
* Merge to CRSP-Compustat Link *

rename permno LPERMNO

joinby LPERMNO using "./data/crsp_cstat_link.dta", unmatched(both) _merge(_merge) // We have that 6,664 comnam-permno links do not join, and 978 permno-gvkey links do not join. 

drop if _merge != 3

drop _merge


* Merge to Get Compustat Firm Name *

merge m:1 gvkey using "./outputs/003a_database_a_cstat.dta", keepusing(as_name)

drop if _merge != 3 // We don't want leftover using data, or data that does not merge to a gvkey in our sample

drop _merge

rename as_name conm // Mark in the original Compustat format for clarity


* Rename Variables *

rename LPERMNO permno
rename LINKPRIM linkprim
rename LIID liid
rename LINKTYPE linktype
rename LPERMCO lpermco
rename LINKDT linkdt
rename LINKENDDT linkenddt

label var linktype "LC = Research Complete by WRDS, LU = Unresearched"

label var liid "X implies no Compustat data exists. >90 is ADR. Rest are normal."


* Drop Extraneous Variables *

drop linkprim lpermco


* Convert LIID to Categorical *

gen categ_iid = ""

destring liid, gen(liid_num) force // Observations that do not destring (i.e. go to missing) will contain an "X". This indicates that no Compustat data existed at the time of the link.

replace categ_iid = "3 - No Compustat Data" if missing(liid_num)

replace categ_iid = "2 - ADR" if !missing(liid_num) & liid_num >= 90

replace categ_iid = "1 - Standard" if !missing(liid_num) & liid_num < 90

label var categ_iid "Category of Compustat Issue Identification Number"

drop liid liid_num // No longer needed


* Drop if gvkey-permno Link Expires before 1975 *

drop if linkenddt < date("1975-01-01", "YMD")


* Drop If comnam-permno and permno-gvkey Links Do Not Overlap *

drop if cp_link_end < linkdt | cp_link_start > linkenddt


* Replace Current Link End Date Values *

replace linkenddt = date("2022-06-30", "YMD") if linkenddt == .e // .e messes the overlap-checking code up


* Get Start and End Dates for Each Link * // We take the overlap of the comnam-permno link and the permno-gvkey link to be the correct time for the linkage.

gen as_date_1 = cp_link_start*(cp_link_start > linkdt) + linkdt*(linkdt >= cp_link_start) // Gets the maximum of cp_link_start and linkdt

gen as_date_n = cp_link_end*(cp_link_end < linkenddt) + linkenddt*(linkenddt <= cp_link_end) // Gets the minimum of cp_link_end and linkenddt


* Where comnam-to-gvkey Mapping *is not* One-to-Many, Get Start and End Dates *

// If a comnam maps to a single gvkey, we do not concern ourselves with time gaps between the various mappings of this comnam-gvkey pair

bysort comnam: gen nr_mappings_comnam = _N

bysort comnam gvkey: gen nr_mappings_comnam_gvkey = _N

bysort comnam gvkey: egen min_as_date_1 = min(as_date_1)

bysort comnam gvkey: egen max_as_date_n = max(as_date_n)

replace as_date_1 = min_as_date_1 if nr_mappings_comnam == nr_mappings_comnam_gvkey

replace as_date_n = max_as_date_n if nr_mappings_comnam == nr_mappings_comnam_gvkey

drop min_as_date_1 max_as_date_n // No longer needed

format as_date_1 as_date_n %td


* Reduce Each non-One-to-Many comnam-to-gvkey Mapping to a Single Observation *

replace cp_link_start = . if nr_mappings_comnam == nr_mappings_comnam_gvkey // We move all the mapping-specific variables to missing for the non-one-to-many comnam-to-gvkey mappings.
replace cp_link_end = . if nr_mappings_comnam == nr_mappings_comnam_gvkey 
replace linktype = "" if nr_mappings_comnam == nr_mappings_comnam_gvkey
replace linkdt = . if nr_mappings_comnam == nr_mappings_comnam_gvkey
replace linkenddt = . if nr_mappings_comnam == nr_mappings_comnam_gvkey
replace categ_iid = "" if nr_mappings_comnam == nr_mappings_comnam_gvkey

duplicates drop

drop nr_mappings_comnam nr_mappings_comnam_gvkey // Now, every comnam attached to multiple mappings maps to multiple gvkeys.


* Where comnam-to-gvkey Mapping *is* One-to-Many, Iteratively Combine Dates for Overlapping Common comnam-gvkey Mappings *

bysort comnam gvkey: gen cg_link_confirmed_isolated = (_N == 1) // This variable will essentially indicates whether a link has no other overlapping links between the same comnam-gvkey pair.

forvalues i = 1/22{ // We have a comnam mapping to at most 22 gvkeys
	
	local loop_switch = 1
	
	local i2 = 1
	
	while(`loop_switch' == 1){ // Stops looping when changes are no longer being made.
		
		di "`i'.`i2'"
		
		bysort comnam gvkey cg_link_confirmed_isolated (as_date_1 permno): gen to_merge = (as_date_n >= as_date_1[_n+1]) if _n == 1 & cg_link_confirmed_isolated == 0 // We deal with the first link first. Including permno in the ordering allows an arbitary order to be preserved when as_date_1 is the same for multiple observations.
		
		bysort comnam gvkey cg_link_confirmed_isolated (as_date_1 permno): replace to_merge = 1 if to_merge[_n-1] == 1 & _n == 2 & cg_link_confirmed_isolated == 0 // Marks the suceeding observation as to be merged.
		
		replace cg_link_confirmed_isolated = 1 if to_merge == 0 // These are links with *no* overlap with the following link
		
		replace cp_link_start = . if to_merge == 1 // This reminds us we have merged two observations and dropped one arbitrarily, so this information is no longer valid.
		replace cp_link_end = . if to_merge == 1 
		replace linktype = "" if to_merge == 1
		replace linkdt = . if to_merge == 1
		replace linkenddt = . if to_merge == 1
		replace categ_iid = "" if to_merge == 1
		
		bysort comnam gvkey cg_link_confirmed_isolated (as_date_1 permno): replace as_date_n = as_date_n[_n+1] if _n == 1 & to_merge == 1 // Replace the end date of the first observation to match the second
		
		bysort comnam gvkey cg_link_confirmed_isolated (as_date_1 permno): drop if _n == 2 & to_merge == 1 // Drop the second observation
		
		bysort comnam gvkey cg_link_confirmed_isolated (as_date_1 permno): replace cg_link_confirmed_isolated = 1 if to_merge == 1 & as_date_n < as_date_1[_n+1] // Marks newly isolated observations
		
		if(`=r(N_drop)' == 0){
			
			local loop_switch = 0 // Switch off loop
			
		}

		drop to_merge // We start afresh in the next loop
		
		local i2 = `i2' + 1
	
	}
		
}

drop cg_link_confirmed_isolated // No longer needed


* Flag Overlapping Observations *

bysort comnam (as_date_1 gvkey): gen overlap = ((_n == 1 & as_date_n >= as_date_1[_n+1] & !missing(as_date_1[_n+1])) | (_n > 1 & _n < _N & (as_date_1 <= as_date_n[_n-1] | as_date_n >= as_date_1[_n+1])) | (_n == _N & as_date_1 <= as_date_n[_n-1] & !missing(as_date_n[_n-1])))

list comnam permno gvkey conm as_date_1 as_date_n if overlap == 1


* Manual Changes where comnam-gvkey pair is One-to-Many Mappings *

drop if comnam == "A T & T CORP" & (gvkey == "032280" | gvkey == "134845") // We dispense of the transient mappings to AT&T WIRELESS and STARZ in favour of the mapping to AT&T CORP.

drop if comnam == "CABLEVISION SYSTEMS CORP" & gvkey == "143461" // Dispensing of transient mapping

drop if comnam == "CIRCUIT CITY STORES INC" & gvkey == "064410" // Again, remove transient link

drop if comnam == "DISNEY WALT CO" & gvkey == "126814" // Again, remove transient link

drop if comnam == "GENERAL MOTORS CORP" & (gvkey == "012206" | gvkey == "005074") // Keep central mapping to GENERAL MOTORS CO over DIRECTV and ELECTRONIC DATA SYSTEMS CORP

drop if comnam == "GENZYME CORP" & gvkey == "121742" // By sales, GENZYME CORP seems to be main listing over GENZYME SURGICAL PRODUCTS

drop if comnam == "GEORGIA PACIFIC CORP"  & gvkey == "066013" // Keep link to GEORGIA-PACIFIC CORP over GEORGIA-PACIFIC TIMBER CO

drop if comnam == "LIBERTY INTERACTIVE CORP" & gvkey == "013664" // QURATE RETAIL INC has an active costat marker. GCI LIBERTY INC does not.

drop if comnam == "LIBERTY MEDIA CORP 2ND NEW" & gvkey == "183812" // The LIBERTY MEDIA STARZ GROUP link lasts only 2 months. STARZ lasts 2 years.

drop if comnam == "LIBERTY MEDIA CORP 3RD NEW" & (gvkey == "027186" | gvkey == "027187") // Only distinction here is that LIBERTY MEDIA SIRIUSXM GROUP is larger in assets than LIBERTY MEDIA BRAVES GROUP and LIBERTY MEDIA FORMULA ONE. This applies to two time periods.

drop if comnam == "LIBERTY MEDIA CORP NEW" & (gvkey == "032280" | gvkey == "179562" | gvkey == "183812") & as_date_n > date("2006-05-09", "YMD") // This time, QURATE RETAIL INC has an active costat marker. STARZ does not. Liberty media list everything.

drop if comnam == "PITTSTON CO" & gvkey == "028591" // The BRINKS CO listing goes for far longer than the PITTSTON CO-MINERALS GROUP

drop if comnam == "QUANTUM CORP" & gvkey == "124015" // We avoid attributing to the holding company

replace as_date_1 = date("2000-09-28", "YMD") if comnam == "SNYDER COMMUNICATIONS INC" & gvkey == "126836" // We avoid the overlapping, and attribute as much time as possible to SNYDER COMMUNICATIONS INC, giving the remaining time to CIRCLE.COM.

drop if comnam == "SPRINT CORP" & gvkey == "116245" // The link to SPRINT PCS GROUP is transient.

drop if comnam == "TELE COMMUNICATIONS INC NEW" & (gvkey == "065683" | gvkey == "010393") // We opt for the link without the "-SER A" suffix.

drop if comnam == "U S WEST INC" & gvkey == "061464" // We remove the transient link.

// All Overlaps now removed.


* Drop non-Database A Variables *

drop permno cp_link_start cp_link_end linktype linkdt linkenddt conm categ_iid overlap // No longer needed


* Rename and Re-order *

rename comnam as_name // Aligns with the rest of database A

order gvkey as_name as_date_1 as_date_n


* Label Variables *

label var as_date_1 "Day of start of name-gvkey link." // Aligns with rest of database A

label var as_date_n "Day of end of name-gvkey link."


* Generate Source Variable *

gen as_source = 2

label var as_source "1 - Compustat, 2 - CRSP"


* Export *

compress

save "./outputs/003a_database_a_crsp.dta", replace


*******************************
* FINALISE DATABASE A TIMINGS *
*******************************

// This is the central version (with start dates and end dates according to listing and  manual checks). Eventually, we'll switch this to accommodate patents on either side of the regression equation.

* Import Compustat Data *

use "./outputs/003a_database_a_cstat.dta", clear


* Append CRSP Data *

append using "./outputs/003a_database_a_crsp.dta"


* Establish as_name-gvkey Mappings that are One-to-Many *

bysort as_name: gen nr_mappings_as_name = _N

bysort as_name gvkey: gen nr_mappings_as_name_gvkey = _N

gen as_name_one_to_many = (nr_mappings_as_name != nr_mappings_as_name_gvkey)

label var as_name_one_to_many "as_name maps to multiple gvkeys."

drop nr_mappings_as_name nr_mappings_as_name_gvkey // No longer necessary


* Where as_name-gvkey Mapping One-to-One, Extend to Entire Period *

// If the name has a one-to-one mapping, extending it to the furthest period implied all such mappings (from both CRSP and Compustat) is fairly benign.

bysort as_name: egen min_as_date_1 = min(as_date_1) if as_name_one_to_many == 0 // Gets first day of first mapping

bysort as_name: egen max_as_date_n = max(as_date_n) if as_name_one_to_many == 0 // Gets last day of last mapping

replace as_date_1 = min_as_date_1 if !missing(min_as_date_1) // Will only replace for one-to-one mappings

replace as_date_n = max_as_date_n if !missing(max_as_date_n) // Will only replace for one-to-one mappings

drop min_as_date_1 max_as_date_n // No longer needed. Duplicates observations among one-to-one mapping names.

bysort as_name (as_source): drop if _n > 1 & as_name_one_to_many == 0 // Drops now-duplicated listings (except for source), favouring mappings sourced from Compustat.


* Merge to Compustat Name conm, for Overlap Checking *

rename as_name as_name_orig // Helps us not get confused with the merge

merge m:1 gvkey using "./outputs/003a_database_a_cstat.dta", keepusing(as_name) // We simply merge right back into Compustat names to get the original conm, stored as as_name

drop _merge // All observations merge, from both sides. Obviously.

rename as_name conm

label var conm "Original Compustat name"

rename as_name_orig as_name


* Format Date Variables *

format as_date_1 as_date_n %td


* Flag Overlapping Observations *

bysort as_name (as_date_1 gvkey): gen overlap = ((_n == 1 & as_date_n >= as_date_1[_n+1] & !missing(as_date_1[_n+1])) | (_n > 1 & _n < _N & (as_date_1 <= as_date_n[_n-1] | as_date_n >= as_date_1[_n+1])) | (_n == _N & as_date_1 <= as_date_n[_n-1] & !missing(as_date_n[_n-1])))

encode as_name if overlap == 1, gen(n_enc)

gen n = n_enc // This is just to keep my sanity whilst I make manual aterations.

drop n_enc

list as_name gvkey conm as_date_1 as_date_n as_source n if overlap == 1


* Manually Alter/Drop Overlapping Observations *

/* A couple schemes of logic are at play here...
- ...if the name maps both to an "OLD" and a standard listing, we assume the standard listing is the product of an acquisition or merger, in which the "OLD" firm's name is adopted.
- ...if the name maps to two gvkeys, but only at different time periods, and maps twice to one gvkey, we have to resolve the timings of the two listings related to the latter.
*/

// 1-10 (VERIFIED FUNCTIONAL)

drop if as_name == "ABRAXIS BIOSCIENCE INC" & gvkey == "145512" // Drop transient mapping

replace as_date_n = date("1994-05-17", "YMD") if as_name == "ALTA ENERGY CORP" & gvkey == "020063" & as_source == 1 // Extend mapping
drop if as_name == "ALTA ENERGY CORP" & gvkey == "020063" & as_source == 2 // Drop duplicate

drop if as_name == "ALTEX INDUSTRIES INC" & gvkey == "001347" // Mapping only for one day
drop if as_name == "ALTEX INDUSTRIES INC" & gvkey == "012088" & as_source == 2 // Nested within wider mapping

replace as_date_1 = date("1991-08-24", "YMD") if as_name == "AMERICAN LEARNING CORP" & gvkey == "012065" & as_source == 1 // Clarify new mapping dates

replace as_date_1 = date("1993-02-20", "YMD") if as_name == "APPLIED BIOSYSTEMS INC" & gvkey == "008488" // Clarify mapping

replace as_date_1 = date("1990-08-01", "YMD") if as_name == "ATTENTION MEDICAL CO" & gvkey == "023629" & as_source == 1 // Clarify mapping
replace as_date_n = date("1993-06-30", "YMD") if as_name == "ATTENTION MEDICAL CO" & gvkey == "023629" & as_source == 1 // Extend mapping
drop if as_name == "ATTENTION MEDICAL CO" & gvkey == "023629" & as_source == 2 // Drop duplicate

replace as_date_1 = date("1992-10-30", "YMD") if as_name == "AVITAR INC" & gvkey == "025641" // Clarify mapping

drop if as_name == "BAROID CORP" & gvkey == "023420" // We do away with the transitory mapping

drop if as_name == "BIO PLEXUS INC" & gvkey == "144641" // This will merge after cleaning anyway

drop if as_name == "BIOGEN INC" & gvkey == "024468" & as_date_1 == date("24mar2015","DMY") // Nested within other mapping
replace as_date_1 = date("14nov2003", "DMY") if as_name == "BIOGEN INC" & gvkey == "024468" & as_source == 1 // Clarify mapping

// 11-20 (VERIFIED FUNCTIONAL)

drop if as_name == "BLOUNT INC" & gvkey == "002271" // Nested within wider mapping

replace as_date_1 = date("01feb1987", "DMY") if as_name == "BUTLER INTERNATIONAL INC" & gvkey == "013193" // Clarify mapping

drop if as_name == "BROADCAST INTERNATIONAL INC" & gvkey == "014843" // We drop mapping to Vermont listing in favour of main one

replace as_date_n = date("31dec2003", "DMY") if as_name == "CAL DIVE INTERNATIONAL INC" & gvkey == "065006" // Clarify mapping

replace as_date_1 = date("19mar1999", "DMY") if as_name == "CARDIOGENESIS CORP" & gvkey == "062960" // Clarify mapping

replace as_date_1 = date("04jul1990", "DMY") if as_name == "CASUAL MALE CORP" & gvkey == "013292"  // Clarify mapping

drop if as_name == "CERPLEX GROUP INC" & gvkey == "030015" // Drop transient listing

replace as_date_1 = date("28feb1987", "DMY") if as_name == "CIRCUIT SYSTEMS INC" & gvkey == "013891" & as_source == 1 // Extend mapping
drop if as_name == "CIRCUIT SYSTEMS INC" & gvkey == "013891" & as_source == 2 & as_date_1 == date("29apr1988", "DMY") // Drop duplicate
drop if as_name == "CIRCUIT SYSTEMS INC" & gvkey == "013891" & as_source == 2 & as_date_n == date("28apr1988", "DMY") // Drop duplicate

replace as_date_1 = date("29nov2008", "DMY") if as_name == "CLEARWIRE CORP" & gvkey == "181904"  // Clarify mapping

drop if as_name == "COMMODORE RESOURCES CORP" & gvkey == "003254" & as_source == 2 // Nested within broader mapping


// 21-30 (VERIFIED FUNCTIONAL)

replace as_date_n = date("31may1989", "DMY") if as_name == "COMPUSCAN INC" & gvkey == "003298" & as_source == 2 // Extend mapping
drop if as_name == "COMPUSCAN INC" & gvkey == "003298" & as_source == 1 // Drop new duplicate listing
drop if as_name == "COMPUSCAN INC" & gvkey == "022270" // Drop transient listing

replace as_date_1 = date("06feb1988", "DMY") if as_name == "COMPUTERVISION CORP" & gvkey == "025658" // Clarify mapping

replace as_date_1 = date("14aug2018", "DMY") if as_name == "COMSTOCK RESOURCES INC" & gvkey == "034010"  // Clarify mapping
drop if as_name == "COMSTOCK RESOURCES INC" & gvkey == "034010" & as_source == 2 // Drop new duplicate listing

replace as_date_n = date("30aug2002", "DMY") if as_name == "CONOCO INC" & gvkey == "114303" & as_source == 1 // Extend mapping
drop if as_name == "CONOCO INC" & gvkey == "114303" & as_source == 2 // Should drop 2. as_name maps to other gvkey during different time period.

replace as_date_n = date("31dec2014", "DMY") if as_name == "CONSOL ENERGY INC" & gvkey == "120093" // CONSOL ENERGY split and delisted one entity

replace as_date_1 = date("22oct1993", "DMY") if as_name == "COSTCO WHOLESALE CORP" & gvkey == "029028" // Clarify mapping, Costco/Price Club merger

replace as_date_n = date("28oct2004", "DMY") if as_name == "CROWN ANDERSEN INC" & gvkey == "001642" & as_source == 1 // Extend mapping
drop if as_name == "CROWN ANDERSEN INC" & gvkey == "001642" & as_source == 2 // Drop duplicate
drop if as_name == "CROWN ANDERSEN INC" & gvkey == "003626" // Short-lived listing

replace as_date_n = date("22jun2001", "DMY") if as_name == "DATA DIMENSIONS INC" & gvkey == "012730" & as_source == 1 // Extend mapping
drop if as_name == "DATA DIMENSIONS INC" & gvkey == "012730" & as_source == 2 // Drop duplicate

drop if as_name == "DATA TRANSLATION INC" & gvkey == "003776" // Drop short lived MEDIA 100 INC listing.

replace as_date_1 = date("25dec2001", "DMY") if as_name == "DEAN FOODS CO" & gvkey == "062655"  // Clarify mapping

// 31-40 (VERIFIED FUNCTIONAL)

drop if as_name == "DEL TACO RESTAURANTS INC" & gvkey == "019168" & as_source == 2 & as_date_1 == date("01jul2015", "DMY") // Nested within wider mapping

replace as_date_1 = date("01feb2006", "DMY") if as_name == "DEX MEDIA INC" & gvkey == "111631" & as_source == 1 // Clarify mapping
replace as_date_n = date("06jan2016", "DMY") if as_name == "DEX MEDIA INC" & gvkey == "111631" & as_source == 1 // Clarify mapping 
drop if as_name == "DEX MEDIA INC" & gvkey == "111631" & as_source == 2 // Drop duplicate

replace as_date_1 = date("14aug2008", "DMY") if as_name == "DIGIMARC CORP" & gvkey == "181290" // Clarify mapping

replace as_date_1 = date("01aug1989", "DMY") if as_name == "DIGITAL OPTRONICS CORP" & gvkey == "020792" & as_source == 1 // Clarify mapping
replace as_date_n = date("06mar1991", "DMY") if as_name == "DIGITAL OPTRONICS CORP" & gvkey == "020792" & as_source == 1 // Clarify mapping 
drop if as_name == "DIGITAL OPTRONICS CORP" & gvkey == "020792" & as_source == 2 // Drop duplicate

drop if as_name == "DIVERSIFOODS INC" & gvkey == "005199" // Drop Transient GODFATHER'S PIZZA Listing 

replace as_date_1 = date("20dec2014", "DMY") if as_name == "EARTHSTONE ENERGY INC" & gvkey == "022671" & as_source == 1 // Clarify mapping
drop if as_name == "EARTHSTONE ENERGY INC" & gvkey == "022671" & as_source == 2 // Drop duplicate

drop if as_name == "EDMOS CORP" & gvkey == "004221" & as_source == 2 // Should drop 2. Drops duplicates.

replace as_date_1 = date("01jul2015", "DMY") if as_name == "ENERGIZER HOLDINGS INC" & gvkey == "023083" // Clarify mapping. Edgewell/Energizer spin-off

replace as_date_1 = date("14may2011", "DMY") if as_name == "EPICOR SOFTWARE CORP" & gvkey == "117781" // Clarify mapping

drop if as_name == "EXTENDED STAY AMERICA INC" & gvkey == "019163" & as_source == 2


// 41-50 (VERIFIED FUNCTIONAL)

replace as_date_1 = date("10jan1998", "DMY") if as_name == "FEDERAL EXPRESS CORP" & gvkey == "115336" // Clarify mapping, Caliber acquisition

replace as_date_n = date("22dec1997", "DMY") if as_name == "FREEPORT MCMORAN INC" & gvkey == "004895" & as_source == 1 // Extend mapping
drop if as_name == "FREEPORT MCMORAN INC" & gvkey == "004895" & as_source == 2 // Drop duplicate

replace as_date_1 = date("27jun2015", "DMY") if as_name == "GANNETT CO INC" & gvkey == "019574" & as_source == 1 // Clarify mapping. Tegna spun off in 2015
drop if as_name == "GANNETT CO INC" & gvkey == "019574" & as_source == 2 // Drop duplicate

replace as_date_1 = date("01feb2014", "DMY") if as_name == "GASTAR EXPLORATION INC" & gvkey == "178921" // Clarify mapping

drop if as_name == "GENERAL CHEMICAL GROUP INC" & gvkey == "062865" // Drop transient mapping
drop if as_name == "GENERAL CHEMICAL GROUP INC" & gvkey == "121233" & as_source == 2 // Nested within wider mapping

replace as_date_1 = date("30apr2007", "DMY") if as_name == "GEORESOURCES INC" & gvkey == "177206" & as_source == 1 // Clarify mapping - start after old mapping
replace as_date_n = date("31jul2012", "DMY") if as_name == "GEORESOURCES INC" & gvkey == "177206" & as_source == 1 // Extend mapping 
drop if as_name == "GEORESOURCES INC" & gvkey == "177206" & as_source == 2 // Drop new duplicate

drop if as_name == "GOOD TACO CORP" & gvkey == "005222" & as_source == 2 // Drop duplicate
replace as_date_1 = date("01dec1985", "DMY") if as_name == "GOOD TACO CORP" & gvkey == "012364" // Extend mapping

replace as_date_1 = date("29sep1998", "DMY") if as_name == "GROUP 1 SOFTWARE INC" & gvkey == "003277" // Clarify mapping

replace as_date_1 = date("27oct1990", "DMY") if as_name == "HALLWOOD ENERGY CORP" & gvkey == "012044" & as_source == 1 // Extend mapping

replace as_date_n = date("31dec1981", "DMY") if as_name == "HARMONY INC" & gvkey == "005481" & as_source == 1 // Extend mapping
drop if as_name == "HARMONY INC" & gvkey == "005481" & as_source == 2 // Drop duplicate


// 51-60 (VERIFIED FUNCTIONAL)

replace as_date_1 = date("31oct1986", "DMY") if as_name == "HARNISCHFEGER CORP" & gvkey == "005482" // Clarify mapping

drop if as_name == "HEALTHTRONICS INC" & gvkey == "124636" // Surgical services a secondary listing
replace as_date_n = date("13jul2010", "DMY") if as_name == "HEALTHTRONICS INC" & gvkey == "124636" & as_source == 1 // Clarify mapping
drop if as_name == "HEALTHTRONICS INC" & gvkey == "124636" & as_source == 2 // Drop duplicate
replace as_date_n = date("13jul2010", "DMY") if as_name == "HEALTHTRONICS INC" & gvkey == "002589" & as_source == 1 // Clarify mapping
drop if as_name == "HEALTHTRONICS INC" & gvkey == "002589" & as_source == 2 // Drop duplicate

replace as_date_1 = date("29sep2007", "DMY") if as_name == "IBASIS INC" & gvkey == "179459" & as_source == 1 // Clarify mapping
replace as_date_n = date("21dec2009", "DMY") if as_name == "IBASIS INC" & gvkey == "179459" & as_source == 1 // Clarify mapping
drop if as_name == "IBASIS INC" & gvkey == "179459" & as_source == 2 // Drop duplicate

replace as_date_1 = date("03jan1997", "DMY") if as_name == "INFINITY BROADCASTING CORP" & gvkey == "116609" & as_source == 1 // Clarify mapping

replace as_date_1 = date("28feb1990", "DMY") if as_name == "IROQUOIS BRANDS LTD" & gvkey == "020790" & as_source == 1 // Clarify mapping
replace as_date_n = date("20aug1991", "DMY") if as_name == "IROQUOIS BRANDS LTD" & gvkey == "020790" & as_source == 1 // Clarify mapping 
drop if as_name == "IROQUOIS BRANDS LTD" & gvkey == "020790" & as_source == 2 // Drop duplicate

replace as_date_1 = date("12aug1999", "DMY") if as_name == "LABONE INC" & gvkey == "024184" // Clarify mapping

drop if as_name == "LAUREATE EDUCATION INC" & gvkey == "026305" & as_source == 2 // Nested within wider mapping

drop if as_name == "LUMEN TECHNOLOGIES INC" & gvkey == "012846" // Short-lived secondary listing

replace as_date_1 = date("27feb1982", "DMY") if as_name == "MALLINCKRODT INC" & gvkey == "006096"  // Clarify mapping

replace as_date_1 = date("29sep1998", "DMY") if as_name == "MANOR CARE INC" & gvkey == "024607" // Clarify mapping


// 61-70 (VERIFIED FUNCTIONAL)

replace as_date_1 = date("01oct1987", "DMY") if as_name == "MARK CONTROLS CORP" & gvkey == "014469"  // Clarify mapping

replace as_date_1 = date("01jul2020", "DMY") if as_name == "MATCH GROUP INC" & gvkey == "026061"  // Clarify mapping

replace as_date_1 = date("26nov1998", "DMY") if as_name == "MECKLERMEDIA CORP" & gvkey == "121717" & as_source == 1 // Clarify mapping

replace as_date_1 = date("29nov2013", "DMY") if as_name == "MEDIA GENERAL INC" & gvkey == "030950" & as_source == 1 // Extend mapping
drop if as_name == "MEDIA GENERAL INC" & gvkey == "030950" & as_source == 2 // Nested within wider mapping

replace as_date_1 = date("27jul1999", "DMY") if as_name == "MEDICAL MANAGER CORP" & gvkey == "016469" // Clarify mapping

replace as_date_1 = date("30jun1987", "DMY") if as_name == "MESTEK INC" & gvkey == "014064" & as_source == 1 // Clarify mapping
drop if as_name == "MESTEK INC" & gvkey == "014064" & as_source == 2 // Nested within wider mapping

drop if as_name == "MOBOT CORP" & gvkey == "007491" & as_source == 1 // Nested within wider mapping

replace as_date_1 = date("01apr2000", "DMY") if as_name == "MONSANTO CO" & gvkey == "140760" // Clarify mapping

replace as_date_1 = date("09mar1996", "DMY") if as_name == "MORRISON RESTAURANTS INC" & gvkey == "062352" // Clarify mapping

replace as_date_1 = date("20jan1988", "DMY") if as_name == "MOVIE STAR INC" & gvkey == "009402" // Clarify mapping


// 71-80 (VERIFIED FUNCTIONAL)

replace as_date_1 = date("29jun2013", "DMY") if as_name == "NEWS CORP" & gvkey == "018043" // Clarify mapping

replace as_date_n = date("31aug2016", "DMY") if as_name == "NORTEK INC" & gvkey == "260408" & as_source == 1 // Extend mapping
drop if as_name == "NORTEK INC" & gvkey == "260408" & as_source == 2 // Drop duplicate

drop if as_name == "NUCLEAR PHARMACY INC" & gvkey == "008026" // Should drop 3. Nuclear Pharmacy as its own listing (separate from Syncor) is short-lived

replace as_date_1 = date("11dec2003", "DMY") if as_name == "OFFICEMAX INC" & gvkey == "002290" // Clarify mapping

drop if as_name == "PARSONS CORP" & gvkey == "035158" & as_source == 2 // Nested within wider mapping

replace as_date_1 = date("01dec2000", "DMY") if as_name == "PEPSIAMERICAS INC" & gvkey == "005824" // Clarify mapping

replace as_date_1 = date("14may2004", "DMY") if as_name == "PHARMACOPEIA INC" & gvkey == "160237" & as_source == 1 // Extend mapping

replace as_date_n = date("12dec2001", "DMY") if as_name == "RALSTON PURINA CO" & gvkey == "028701" & as_source == 1 // Extend mapping
drop if as_name == "RALSTON PURINA CO" & gvkey == "028701" & as_source == 2 // Drop duplicate
drop if as_name == "RALSTON PURINA CO" & gvkey == "008935" & as_source == 2 // Nested within wider mapping

drop if as_name == "RUSCO INDUSTRIES INC" & gvkey == "009288" & as_source == 2 // Should drop 2 duplicates.

replace as_date_n = date("28apr1989", "DMY") if as_name == "SEQUEL CORP" & gvkey == "013445" & as_source == 1 // Extend mapping
drop if as_name == "SEQUEL CORP" & gvkey == "013445" & as_source == 2 // Drop duplicate


// 81-90 (VERIFIED FUNCTIONAL)

replace as_date_n = date("31may2018", "DMY") if as_name == "SKYLINE CORP" & gvkey == "009761" & as_source == 1 // Extend mapping
drop if as_name == "SKYLINE CORP" & gvkey == "009761" & as_source == 2 // Drop duplicate

replace as_date_n = date("27sep2000", "DMY") if as_name == "SNYDER COMMUNICATIONS INC" & gvkey == "063641" & as_source == 1 // Clarify mapping
drop if as_name == "SNYDER COMMUNICATIONS INC" & gvkey == "063641" & as_source == 2 // Nested within wider mapping

replace as_date_1 = date("07feb2001", "DMY") if as_name == "SPORT SUPPLY GROUP INC" & gvkey == "014490" & as_source == 1 // Clarify mapping

replace as_date_1 = date("06aug2003", "DMY") if as_name == "SPORTS AUTHORITY INC" & gvkey == "066278" // Clarify mapping

replace as_date_1 = date("24jul2018", "DMY") if as_name == "STARTEK INC" & gvkey == "298036" & as_source == 1 // Clarify mapping
drop if as_name == "STARTEK INC" & gvkey == "298036" & as_source == 2 // Nested within wider mapping

drop if as_name == "SUMMIT ENERGY INC" & gvkey == "010143" & as_source == 2 // Nested within wider mapping
replace as_date_n = date("29dec1983", "DMY") if as_name == "SUMMIT ENERGY INC" & gvkey == "010143" & as_source == 1 // Clarify mapping

drop if as_name == "SUNERGY COMMUNITIES INC" & gvkey == "010164" & as_source == 1 // Nested within wider mapping

drop if as_name == "SUNLAND INDUSTRIES INC" & gvkey == "010166" & as_source == 2 // Should drop 2. Nested within wider mapping

replace as_date_n = date("24mar2017", "DMY") if as_name == "SURGICAL CARE AFFILIATES INC" & gvkey == "018841" & as_source == 1 // Extend mapping
drop if as_name == "SURGICAL CARE AFFILIATES INC" & gvkey == "018841" & as_source == 2 // Drop duplicate

drop if as_name == "TECOGEN INC" & gvkey == "018114" & as_source == 2 // Nested within wider mapping


// 91-100 (VERIFIED FUNCTIONAL)

drop if as_name == "TELEPICTURES CORP" & gvkey == "023250" & as_source == 1 // Yield to CRSP mapping

replace as_date_1 = date("11may2001", "DMY") if as_name == "TELIGENT INC" & gvkey == "005888" & as_source == 1 // Clarify mapping
drop if as_name == "TELIGENT INC" & gvkey == "005888" & as_source == 2 // Nested within wider mapping

drop if as_name == "TELLURIAN INC" & gvkey == "030241" & as_source == 2 // Nested within wider mapping

drop if as_name == "TETRA TECH INC" & gvkey == "024783" & as_source == 2 // Nested within wider mapping

replace as_date_n = date("18jun1996", "DMY") if as_name == "TIDE WEST OIL CO" & gvkey == "016491" & as_source == 1 // Extend mapping
drop if as_name == "TIDE WEST OIL CO" & gvkey == "016491" & as_source == 2 // Should drop 2 duplicates.

replace as_date_1 = date("13jan2001", "DMY") if as_name == "TIME WARNER INC" & gvkey == "025056" // Clarify mapping

replace as_date_1 = date("31jul2014", "DMY") if as_name == "TRI POINTE HOMES INC" & gvkey == "258869" & as_source == 1 // Extend mapping
drop if as_name == "TRI POINTE HOMES INC" & gvkey == "258869" & as_source == 2 // Nested within wider mapping

replace as_date_1 = date("09jul1986", "DMY") if as_name == "UNITED STATES STEEL CORP" & gvkey == "023978" & as_source == 1 // Extend mapping

replace as_date_n = date("08apr1984", "DMY") if as_name == "USENCO INC" & gvkey == "011048" // Clarify mapping

replace as_date_1 = date("01jun2000", "DMY") if as_name == "VARCO INTERNATIONAL INC" & gvkey == "020993" // Clarify mapping


// 101-108

replace as_date_1 = date("31dec2005", "DMY") if as_name == "VIACOM INC" & gvkey == "165675" // Clarify mapping

replace as_date_1 = date("24oct2009", "DMY") if as_name == "WEBMD HEALTH CORP" & gvkey == "115404" & as_source == 1 // Clarify mapping
replace as_date_n = date("15sep2017", "DMY") if as_name == "WEBMD HEALTH CORP" & gvkey == "115404" & as_source == 1 // Extend mapping
drop if as_name == "WEBMD HEALTH CORP" & gvkey == "115404" & as_source == 2 // Drop duplicate

replace as_date_1 = date("23may1985", "DMY") if as_name == "WESTERN BEEF INC" & gvkey == "008863" // Clarify mapping

replace as_date_1 = date("24oct2011", "DMY") if as_name == "WESTWOOD ONE INC" & gvkey == "191055" & as_source == 1 // Clarify mapping
drop if as_name == "WESTWOOD ONE INC" & gvkey == "191055" & as_source == 2 // Nested within wider mapping

drop if as_name == "WHEELING PITTSBURGH CORP" & gvkey == "157020" & as_source == 2 // Nested within wider mapping

replace as_date_1 = date("27oct2016", "DMY") if as_name == "YUMA ENERGY INC" & gvkey == "028788" // Clarify mapping

replace as_date_1 = date("19oct2000", "DMY") if as_name == "ZIFF DAVIS INC" & gvkey == "122172" & as_source == 1 // Extend mapping
drop if as_name == "ZIFF DAVIS INC" & gvkey == "066716" & as_source == 2 // Drop duplicate to hyphenated listing

replace as_date_1 = date("30sep2009", "DMY") if as_name == "ZOOM TECHNOLOGIES INC" & gvkey == "183612" & as_source == 1 // Extend mapping
replace as_date_n = date("20aug2014", "DMY") if as_name == "ZOOM TECHNOLOGIES INC" & gvkey == "183612" & as_source == 1
drop if as_name == "ZOOM TECHNOLOGIES INC" & gvkey == "183612" & as_source == 2 // Drop duplicate


* Check Again for Overlap *

drop overlap n // Need to refresh variable

bysort as_name (as_date_1 gvkey): gen overlap = ((_n == 1 & as_date_n >= as_date_1[_n+1] & !missing(as_date_1[_n+1])) | (_n > 1 & _n < _N & (as_date_1 <= as_date_n[_n-1] | as_date_n >= as_date_1[_n+1])) | (_n == _N & as_date_1 <= as_date_n[_n-1] & !missing(as_date_n[_n-1])))

encode as_name if overlap == 1, gen(n_enc)

gen n = n_enc // This is just to keep my sanity whilst I make manual aterations.

drop n_enc

list as_name gvkey conm as_date_1 as_date_n as_source n if overlap == 1 | as_date_1 > as_date_n | missing(as_date_1) | missing(as_date_n) // No overlapping observations.

drop overlap n


* Export *

compress

save "./outputs/003a_database_a_unclean.dta", replace


*************************************
* CLEANING OF ACCOUNTING-SIDE NAMES *
*************************************

* Import Unclean Names *

use "./outputs/003a_database_a_unclean.dta", clear


* Initiate Clean Name Variable *

gen as_name_clean = as_name // This will be altered (often repeatedly) over the course of this script, but we start with the unclean name


  ********************
* Deal with Whitespace *
  ********************

* Replace non-Space Whitespace with Space Whitespace * // An example of non-space whitespace would be tab or newline

replace as_name_clean = regexr(as_name_clean, "[\s]", " ") // \s is all whitespace characters, the space is the space whitespace character.


* Trim Consecutive Whitespace Characters to Single Character *

replace as_name_clean = stritrim(as_name_clean) // Note the difference between functions stritrim and strtrim.


* Get Rid of Leading, Trailing Whitespace *

replace as_name_clean = strtrim(as_name_clean) // Note the difference between functions stritrim and strtrim.


  **********************************
* Remove non-Alphanumeric Characters *
  **********************************

* & *

replace as_name_clean = subinstr(as_name_clean, "&AMP", "AND", .)

replace as_name_clean = subinstr(as_name_clean, "&", "AND", .)


* () *

replace as_name_clean = subinstr(as_name_clean, "(", "", .)

replace as_name_clean = subinstr(as_name_clean, ")", "", .)


* - *

// Here we replace a hyphen with a space, and then use the standard whitespace procedure.

replace as_name_clean = subinstr(as_name_clean, "-", " ", .)

replace as_name_clean = stritrim(as_name_clean)

replace as_name_clean = strtrim(as_name_clean)


* . *

replace as_name_clean = subinstr(as_name_clean, ".", "", .) 

* ' *

replace as_name_clean = subinstr(as_name_clean, "'", "", .)


* / *

// Like with hyphens, here we replace a forward slash with a space, and then use the standard whitespace procedure

replace as_name_clean = subinstr(as_name_clean, "/", " ", .)

replace as_name_clean = stritrim(as_name_clean)

replace as_name_clean = strtrim(as_name_clean)

// This concludes all non-alphanumeric characters for Compustat with the current data I have. There is code after the postamble for flagging non-Alphanumeric Characters.


  *****************
* Condense Acronyms *
  *****************
  
* Leading Acronyms * // Here we clean acronyms that appear at the start of a string, i.e. "D O G   CAT   C O W   FOX   R A T" becomes "DOG   CAT   C O W   FOX   R A T"

gen A_B_ = regexs(0) if regexm(as_name_clean, "^(. (. )+)") // The gappy acronym

gen AB_ = subinstr(A_B_, " ", "", .) + " " // Removes all spaces from acronym, then adds one at the end.

replace as_name_clean = subinstr(as_name_clean, A_B_, AB_, .) if A_B_ != "" // Does the condensing.

drop A_B_ AB_ // No longer needed


* Trailing Acronyms * // Here we clean acronyms that appear at the end of a string, i.e. "D O G   CAT   C O W   FOX   R A T" becomes "D O G   CAT   C O W   FOX   RAT"

gen _Y_Z = regexs(0) if regexm(as_name_clean, "(( .)+ .)$") // The gappy acronym

gen _YZ = " " + subinstr(_Y_Z, " ", "", .) // Removes all spaces from acronym, then adds one at the start.

replace as_name_clean = subinstr(as_name_clean, _Y_Z, _YZ, .) if _Y_Z != "" // Does the condensing. 

drop _Y_Z _YZ  // No longer needed. 


* Mid-string Acronyms * // Here we clean acronyms that appear in the middle of a string, i.e. "D O G   CAT   C O W   FOX   R A T" becomes "D OG   CAT   COW   FOX   RA T". This is why we do leading and trailing acronyms first.

gen _M_N_ = regexs(0) if regexm(as_name_clean, " . (. )+") // The gappy acronym

gen _MN_ = " " + subinstr(_M_N_, " ", "", .) + " " // Removes all spaces from acronym, then adds one at each end

replace as_name_clean = subinstr(as_name_clean, _M_N_, _MN_, .) if _M_N_ != "" // Does the condensing. 

drop _M_N_ _MN_  // No longer needed.


  **********************
* Remove Corporate Terms *
  **********************

* THE (Prefix) *

replace as_name_clean = substr(as_name_clean, 5, .) if substr(as_name_clean, 1, 4) == "THE "


* INC (Suffix, Incorporated) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " INC"


* CORP (Suffix, Corporation) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " CORP"


* LTD (Suffix, Limited) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " LTD"


* CO (Suffix, Company/Corporation) * // Note that this actually leaves a fair few "AND CO" companies with "AND" as a suffix unless we drop that too.

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 7) if substr(as_name_clean, -7, 7) == " AND CO"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " CO"


* A (Suffix, Unclear) *

// Two forms of this appear - "CL A" and "SER A". I remove both.

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " CL A"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 6) if substr(as_name_clean, -6, 6) == " SER A"


* LP (Suffix, Limited Partnership) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " LP"


* CP (Suffix, Corporation) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " CP"


* PLC (Suffix, Public Limited Company) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " PLC"


* TRUST (Suffix, Trust) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 6) if substr(as_name_clean, -6, 6) == " TRUST"


* ADR, ADS (Suffixes, American Depositary Receipts/Shares) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " ADR"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " ADS"


* TR (Suffix, Trust) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " TR"


* BANCORP, BANCORPORATION (Suffix, Banking Corporation) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 8) if substr(as_name_clean, -8, 8) == " BANCORP"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 15) if substr(as_name_clean, -15, 15) == " BANCORPORATION"


* SA (Sociedad Anónima/Societé Anonyme) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " SA"


* LLC (Limited Liability Company) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " LLC"


* CL ? (Suffixes, Unknown) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " CL B"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 6) if substr(as_name_clean, -6, 6) == " CL B2"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " CL C"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " CL D"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " CL I"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " CL Y"


* HOLDINGS, HOLDING, HLDGS (Suffix, Holding Company) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 9) if substr(as_name_clean, -9, 9) == " HOLDINGS"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 8) if substr(as_name_clean, -8, 8) == " HOLDING"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 6) if substr(as_name_clean, -6, 6) == " HLDGS"


* II (Suffix, Second Listing) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " II"


* State Suffixes (Including DC, Puerto Rico) * // Note that Colorado also doubles up as "CO", i.e. Company, Corporation.

local states "AL KY OH AK LA OK AZ ME OR AR MD PA AS MA PR CA MI RI CO MN SC CT MS SD DE MO TN DC MT TX FL NE GA NV UT NH VT HI NJ VA ID NM IL NY WA IN NC WV IA ND WI KS WY" // A string containing all two letter state codes

gen lw = word(as_name_clean, -1) // Variable containing last word in string

gen lwl = length(lw) // Variable containing length of last word in string

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if (strpos("`states'", lw) > 0) & (lwl == 2) & (substr(as_name_clean, -7, 7) != " AND CO") // Removes two-letter state code from end of string.

drop lw lwl


* COS (Suffix, Companies) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " COS"


* HLDG (Suffix, Holding) * // Note that this can come as part of "HOLDING CO", with " CO" removed above.

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " HLDG"


* AG (Suffix, Aktiengesellschaft) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " AG"


* III (Suffix, Third Listing) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " III"


* AB (Suffix, Aktiebolag) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " AB"


* NEW (Suffix, New Version of Compustat Listing) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " NEW"


* SA DE CV/SAB DE CV (Suffix, Sociedad Anónima de Capital Variable/Sociedad Anónima Bursátil de Capital Variable) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 10) if substr(as_name_clean, -9, 9) == " SA DE CV"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 10) if substr(as_name_clean, -10, 10) == " SAB DE CV"


* I (Suffix, First Listing) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 2) if substr(as_name_clean, -2, 2) == " I"


* SE (Suffix, Societas Europaea) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " SE"


* SPN (Suffix, Unknown) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " SPN"


* THE (Suffix, Basically where "The Dog Company" appears as "Dog Company, The" *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " THE"s


* COM (Suffix, Company) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " COM"


* FSB (Suffix, Federal Savings Bank) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " FSB"


* SPA (Suffix, Società per Azioni) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " SPA"


* IV (Suffix, Fourth Listing) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " IV"


* LIMITED (Suffix) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 8) if substr(as_name_clean, -8, 8) == " LIMITED"


* CORPORATION (Suffix) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 12) if substr(as_name_clean, -12, 12) == " CORPORATION"


* COMPANY (Suffix) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 8) if substr(as_name_clean, -8, 8) == " COMPANY"


* DEL (Suffix, Delaware) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " DEL"


* CIE (Compagnie) *

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " CIE"


* Removing Again - Round 2 *

// Note that "DOGS CO LTD" will now still be "DOGS CO", whereas we want it to just be "DOGS". We run through until there are no more suffixes to remove

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " INC"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " CORP"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " LTD"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 7) if substr(as_name_clean, -7, 7) == " AND CO"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 7) if substr(as_name_clean, -7, 7) == " CO"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " CL A"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 6) if substr(as_name_clean, -6, 6) == " SER A"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " LP"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " CP"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " PLC"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 6) if substr(as_name_clean, -6, 6) == " TRUST"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " ADR"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " ADS"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " TR"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 8) if substr(as_name_clean, -8, 8) == " BANCORP"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " SA"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " LLC"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " CL B"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 6) if substr(as_name_clean, -6, 6) == " CL B2"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " CL C"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " CL D"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " CL I"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " CL Y"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 9) if substr(as_name_clean, -9, 9) == " HOLDINGS"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 8) if substr(as_name_clean, -8, 8) == " HOLDING"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 6) if substr(as_name_clean, -6, 6) == " HLDGS"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " II"
local states "AL KY OH AK LA OK AZ ME OR AR MD PA AS MA PR CA MI RI CO MN SC CT MS SD DE MO TN DC MT TX FL NE GA NV UT NH VT HI NJ VA ID NM IL NY WA IN NC WV IA ND WI KS WY"
gen lw = word(as_name_clean, -1)
gen lwl = length(lw)
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if (strpos("`states'", lw) > 0) & (lwl == 2) & (substr(as_name_clean, -7, 7) != " AND CO")
drop lw lwl
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " COS"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " HLDG"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " AG"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " III"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " AB"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " NEW"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 10) if substr(as_name_clean, -9, 9) == " SA DE CV"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 10) if substr(as_name_clean, -10, 10) == " SAB DE CV"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 2) if substr(as_name_clean, -2, 2) == " I"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " SE"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " SPN"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " THE"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " COM"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " FSB"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " SPA"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " IV"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 8) if substr(as_name_clean, -8, 8) == " LIMITED"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 12) if substr(as_name_clean, -12, 12) == " CORPORATION"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 8) if substr(as_name_clean, -8, 8) == " COMPANY"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " CIE"


* Removing Again - Round 3 *

// We only need 3 rounds of this

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " INC"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " CORP"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " LTD"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 7) if substr(as_name_clean, -7, 7) == " AND CO"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 7) if substr(as_name_clean, -7, 7) == " CO"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " CL A"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 6) if substr(as_name_clean, -6, 6) == " SER A"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " LP"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " CP"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " PLC"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 6) if substr(as_name_clean, -6, 6) == " TRUST"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " ADR"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " ADS"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " TR"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 8) if substr(as_name_clean, -8, 8) == " BANCORP"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " SA"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " LLC"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " CL B"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 6) if substr(as_name_clean, -6, 6) == " CL B2"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " CL C"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " CL D"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " CL I"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " CL Y"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 9) if substr(as_name_clean, -9, 9) == " HOLDINGS"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 8) if substr(as_name_clean, -8, 8) == " HOLDING"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 6) if substr(as_name_clean, -6, 6) == " HLDGS"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " II"
local states "AL KY OH AK LA OK AZ ME OR AR MD PA AS MA PR CA MI RI CO MN SC CT MS SD DE MO TN DC MT TX FL NE GA NV UT NH VT HI NJ VA ID NM IL NY WA IN NC WV IA ND WI KS WY"
gen lw = word(as_name_clean, -1)
gen lwl = length(lw)
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if (strpos("`states'", lw) > 0) & (lwl == 2) & (substr(as_name_clean, -7, 7) != " AND CO")
drop lw lwl
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " COS"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 5) if substr(as_name_clean, -5, 5) == " HLDG"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " AG"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " III"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " AB"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " NEW"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 10) if substr(as_name_clean, -9, 9) == " SA DE CV"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 10) if substr(as_name_clean, -10, 10) == " SAB DE CV"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 2) if substr(as_name_clean, -2, 2) == " I"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " SE"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " SPN"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " THE"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " COM"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " FSB"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " SPA"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 3) if substr(as_name_clean, -3, 3) == " IV"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 8) if substr(as_name_clean, -8, 8) == " LIMITED"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 12) if substr(as_name_clean, -12, 12) == " CORPORATION"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 8) if substr(as_name_clean, -8, 8) == " COMPANY"
replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - 4) if substr(as_name_clean, -4, 4) == " CIE"


* Removing Words from Middle of String *

// We now remove the above from the middle of the string. This is because we might wish to retain the "CANADA" in "DOGS CO CANADA", but would like to remove "CO". Exceptions here are "DE" which appears frequently but is "de" as in "of" in French/Spanish, and "I", "II", "III" & "IV", which are Compustat suffixes and therefore only need be removed at the end of the string. Terms that do not make any changes are omitted from the code.


* INC (Incorporated) *

replace as_name_clean = subinstr(as_name_clean, " INC "," ", .)


* CORP (Corporation) *

replace as_name_clean = subinstr(as_name_clean, " CORP "," ", .)


* LTD (Limited) *

replace as_name_clean = subinstr(as_name_clean, " LTD "," ", .)


* AND CO (and Company) *

replace as_name_clean = subinstr(as_name_clean, " AND CO "," ", .)


* CO (Company) *

replace as_name_clean = subinstr(as_name_clean, " CO " ," ", .)


* CL A (Unknown) *

replace as_name_clean = subinstr(as_name_clean, " CL A "," ", .)


* CP (Corporation) *

replace as_name_clean = subinstr(as_name_clean, " CP "," ", .)


* PLC (Public Limited Company) *

replace as_name_clean = subinstr(as_name_clean, " PLC " ," ", .)


* BANCORP (Banking Corporation) *

replace as_name_clean = subinstr(as_name_clean, " BANCORP "," ", .)


* HOLDINGS *

replace as_name_clean = subinstr(as_name_clean, " HOLDINGS "," ", .)


* HLDGS (Holdings) *

replace as_name_clean = subinstr(as_name_clean, " HLDGS "," ", .)


* HLDG (Holding) *

replace as_name_clean = subinstr(as_name_clean, " HLDG "," ", .)


* THE *

replace as_name_clean = subinstr(as_name_clean, " THE "," ", .)


  ************************************
* Abbreviations - Variable Initiations *
  ************************************

* Get first- and last- word variables *

split as_name_clean, gen(word_) // Splits into 7 words

gen lw = "" // Initiate last word variable

forvalues i = 1/7{ // Iteratively replace last word variable until no more non-missing values.
	
	replace lw = word_`i' if word_`i' != ""
	
	if(`i' > 1){
		
		drop word_`i'
		
	}
	
}

rename word_1 fw // Clarify first word variable

label var fw "first word in name" 

label var lw "last word in name"


* Get Indicator Variable for One-word Names *

gen wc = wordcount(as_name_clean)

gen oneword = 0 // Initiate indicator

replace oneword = 1 if wc == 1 // Flag one-word names

drop wc // No longer necessary


  *********************************************
* Abbreviations - One-word to One-word Mappings *
  *********************************************
   
* Map International *

local subin "INT"

local _subin_ = " " + "`subin'" +  " "

local subout "INTERNATIONAL"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "INTERN"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'" 

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0) 

local subout "INTL"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)
replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Services *

local subin "SVCS"

local _subin_ = " " + "`subin'" +  " "

local subout "SERVICES"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Group *

local subin "GP"

local _subin_ = " " + "`subin'" +  " "

local subout "GROUP"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "GRP"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)
local subout "GR"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Power *

local subin "PWR"

local _subin_ = " " + "`subin'" +  " "

local subout "POWER"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Manufacturing *

local subin "MFG"

local _subin_ = " " + "`subin'" +  " "

local subout "MANUFACTURING"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Systems *

local subin "SYS"

local _subin_ = " " + "`subin'" +  " "

local subout "SYSTEMS"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "SYSTEM"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "SYST"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Resources *

local subin "RES"

local _subin_ = " " + "`subin'" +  " "

local subout "RESOURCES"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Associated *

local subin "ASSD"

local _subin_ = " " + "`subin'" +  " "

local subout "ASSOCIATED"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Development *

local subin "DEV"

local _subin_ = " " + "`subin'" +  " "

local subout "DEVELOPMENT"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Investments *


local subin "IVT"

local _subin_ = " " + "`subin'" +  " "

local subout "INVESTMENT"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .) 

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'" 

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0) 

local subout "INVESTMENTS"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .) 

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'" 

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0) 

local subout "INVT"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .) 

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'" 

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "INVS"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Management *

local subin "MGMT"

local _subin_ = " " + "`subin'" +  " "

local subout "MANAGEMENT"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .) 

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Products *

local subin "PROD"

local _subin_ = " " + "`subin'" +  " "

local subout "PRODUCTS"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "PRODS"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Canada *

local subin "CAN"

local _subin_ = " " + "`subin'" +  " "

local subout "CANADA"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "CDA"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map USA *

local subin "US"

local _subin_ = " " + "`subin'" +  " "

local subout "USA"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "AM"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "AMERICA"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "AMER"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Properties *

local subin "PPTYS"

local _subin_ = " " + "`subin'" +  " "

local subout "PROPERTIES"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Association *

local subin "ASS"

local _subin_ = " " + "`subin'" +  " "

local subout "ASSOCIATION"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "ASSOC"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "ASSN"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Service * 

local subin "SVC"

local _subin_ = " " + "`subin'" +  " "

local subout "SERVICE"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Communication *

local subin "COMM"

local _subin_ = " " + "`subin'" +  " "

local subout "COMMUNICATIONS"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "COMMUNICATION"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

replace as_name_clean = subinstr(as_name_clean, "COMMUN", "COMM", .) if as_name_clean == "COMPUTER AND COMMUN TECHNOLOGY" | as_name_clean == "COMMUN AND CABLE"


* Map Entertainment *

local subin "ENTMT"

local _subin_ = " " + "`subin'" +  " "

local subout "ENTERTAINMENT"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Telecommunications *

local subin "TELECOM"

local _subin_ = " " + "`subin'" +  " "

local subout "TELECOMMUNICATIONS"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "TELECOMM"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Partners *

local subin "PRTNRS"

local _subin_ = " " + "`subin'" +  " "

local subout "PARTNERS"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Explorations *

local subin "EXPL"

local _subin_ = " " + "`subin'" +  " "

local subout "EXPLORATION"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "EXPLORATIONS"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Insurance *

local subin "INS"

local _subin_ = " " + "`subin'" +  " "

local subout "INSURANCE"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map American *

local subin "AMERN"

local _subin_ = " " + "`subin'" +  " "

local subout "AMERICAN"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map National *

local subin "NATL"

local _subin_ = " " + "`subin'" +  " "

local subout "NATIONAL"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Communities, Community *

local subin "CMNTY"

local _subin_ = " " + "`subin'" +  " "

local subout "COMMUNITIES"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "COMMUN"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "COMMUNITY"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Bank *

local subin "BK"

local _subin_ = " " + "`subin'" +  " "

local subout "BANK"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "BANC"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Savings *

local subin "SVGS"

local _subin_ = " " + "`subin'" +  " "

local subout "SAVINGS"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Chemicals, Chemical *

local subin "CHEM"

local _subin_ = " " + "`subin'" +  " "

local subout "CHEMICALS"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "CHEMICAL"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Realty *

local subin "REALTY"

local _subin_ = " " + "`subin'" +  " "

local subout "RLTY"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Solutions *

local subin "SOLTNS"

local _subin_ = " " + "`subin'" +  " "

local subout "SOLUTIONS"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Transport *

local subin "TRANS"

local _subin_ = " " + "`subin'" +  " "

local subout "TRANSPORT"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "TRANSPRT"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "TRNSPRT"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Finance, Financial *

local subin "FIN"

local _subin_ = " " + "`subin'" +  " "

local subout "FINANCE"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "FINANCIAL"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "FINL"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map First *

local subin "1ST"

local _subin_ = " " + "`subin'" +  " "

local subout "FIRST"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Second *

local subin "2ND"

local _subin_ = " " + "`subin'" +  " "

local subout "SECOND"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Third *

local subin "3RD"

local _subin_ = " " + "`subin'" +  " "

local subout "THIRD"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Fourth *

local subin "4TH"

local _subin_ = " " + "`subin'" +  " "

local subout "FOURTH"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Fifth *

local subin "5TH"

local _subin_ = " " + "`subin'" +  " "

local subout "FIFTH"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Sixth *

local subin "6TH"

local _subin_ = " " + "`subin'" +  " "

local subout "SIXTH"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Drugs *

local subin "DRUG"

local _subin_ = " " + "`subin'" +  " "

local subout "DRUGS"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Technology, Technologies *

local subin "TECH"

local _subin_ = " " + "`subin'" +  " "

local subout "TECHNOLOGY"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "TECHNOLOGIES"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Laboratories, Laboratory *

local subin "LAB"

local _subin_ = " " + "`subin'" +  " "

local subout "LABORATORIES"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "LABORATORY"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "LABS"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "LABO"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Brothers *

local subin "BROS"

local _subin_ = " " + "`subin'" +  " "

local subout "BROTHERS"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Electrical *

local subin "ELEC"

local _subin_ = " " + "`subin'" +  " "

local subout "ELECTRICAL"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "ELECTRIC"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .) 

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'" 

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Commercial *

local subin "COMML"

local _subin_ = " " + "`subin'" +  " "

local subout "COMMERCIAL"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Consolidated *

local subin "CONS"

local _subin_ = " " + "`subin'" +  " "

local subout "CONSOLIDATED"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Industries, Industrial *

local subin "IND"

local _subin_ = " " + "`subin'" +  " "

local subout "INDUSTRIES"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "INDUSTRIAL"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "INDS"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0) 

// 0 duplicates created


* Map Instruments *

local subin "INSTR"

local _subin_ = " " + "`subin'" +  " "

local subout "INSTRUMENT"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "INSTRUMENTS"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0) 


* Map Society *

local subin "SOC"

local _subin_ = " " + "`subin'" +  " "

local subout "SOCIETY"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .) 

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'" 

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0) 

local subout "SOCIEDAD"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .) 

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'" 

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0) 

local subout "SOCIETE"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .) 

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0) 

local subout "STE"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map General *

local subin "GEN"

local _subin_ = " " + "`subin'" +  " "

local subout "GENERAL"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Enterprise *

local subin "ENTPR"

local _subin_ = " " + "`subin'" +  " "

local subout "ENTERPRISE"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "ENTERPRISES"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Engineering *

local subin "ENG"

local _subin_ = " " + "`subin'" +  " "

local subout "ENGINEERING"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


  **********************************************
* Abbreviations - Many-word to One-word Mappings *
  **********************************************

* Map Health Care *

local subin "HEALTHCARE"

local _subin_ = " " + "`subin'" +  " "

local subout "HEALTH CARE"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if strpos(as_name_clean, "`subout'") == 1

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if strpos(as_name_clean, "`subout'") == length(as_name_clean) - length("`sub_out'") + 1


* Map North America *

local subin "N AM"

local _subin_ = " " + "`subin'" +  " "

local subout "NORTH US" // NORTH AMERICA will have been changed to NORTH US above.

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .) 

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if strpos(as_name_clean, "`subout'") == 1 

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if strpos(as_name_clean, "`subout'") == length(as_name_clean) - length("`sub_out'") + 1 

local subout "N US" // N AMERICA will have been changed to NORTH US above.

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .) 

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if strpos(as_name_clean, "`subout'") == 1 

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if strpos(as_name_clean, "`subout'") == length(as_name_clean) - length("`sub_out'") + 1 


* Map United States of America *

local subin "US"

local _subin_ = " " + "`subin'" +  " "

local subout "UNITED STATES"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .) 

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if strpos(as_name_clean, "`subout'") == 1

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if strpos(as_name_clean, "`subout'") == length(as_name_clean) - length("`sub_out'") + 1 

local subout "US OF US" // Previous edits will have transformed UNITED STATES OF AMERICA into UNITED STATES OF US. We rectify that here

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if strpos(as_name_clean, "`subout'") == 1 

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if strpos(as_name_clean, "`subout'") == length(as_name_clean) - length("`sub_out'") + 1

local subout "OF US" // A company of the form DOG CAT OF AMERICA will have become DOG CAT OF US. We change that to DOG CAT US here

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if strpos(as_name_clean, "`subout'") == 1

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if strpos(as_name_clean, "`subout'") == length(as_name_clean) - length("`sub_out'") + 1


* Map Real Estate *

local subin "RE"

local _subin_ = " " + "`subin'" +  " "

local subout "REAL ESTATE"

local _subout_ = " " + "`subout'" + " "

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .)

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if strpos(as_name_clean, "`subout'") == 1

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if strpos(as_name_clean, "`subout'") == length(as_name_clean) - length("`sub_out'") + 1


  ***********************************
* Drop Dangling Terms and Empty Names *
  ***********************************
  
// Here we drop " AND" and " OF" from the end of company names 

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("AND")) if (lw == "AND") & (oneword == 0)

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("OF")) if (lw == "OF") & (oneword == 0)


* Strip of Superfluous Whitespace Again *

replace as_name_clean = stritrim(as_name_clean) // Note the difference between functions stritrim and strtrim.


* Get Rid of Leading, Trailing Whitespace *

replace as_name_clean = strtrim(as_name_clean) // Note the difference between functions stritrim and strtrim.

  ******
* Export *
  ******
  
* Drop Extraneous Variables *

keep as_name as_name_clean gvkey conm as_date_1 as_date_n as_source 

order as_name as_name_clean gvkey conm as_date_1 as_date_n as_source 


* Export *
  
compress

save "./outputs/003a_database_a_clean_names_messy_times.dta", replace


  *******************
* Clean Time Mappings *
  *******************

* Import *

use "./outputs/003a_database_a_clean_names_messy_times.dta", clear

  
* Establish as_name_clean-gvkey Mappings that are One-to-Many *

bysort as_name_clean: gen nr_mappings_as_name_clean = _N

bysort as_name_clean gvkey: gen nr_mappings_as_name_clean_gvkey = _N

gen as_name_clean_one_to_many = (nr_mappings_as_name_clean != nr_mappings_as_name_clean_gvkey)

label var as_name_clean_one_to_many "as_name_clean maps to multiple gvkeys."

drop nr_mappings_as_name_clean nr_mappings_as_name_clean_gvkey // No longer necessary


* Where as_name_clean-gvkey Mapping One-to-One, Extend to Entire Period *

// If the name has a one-to-one mapping, extending it to the furthest period implied all such mappings (from both CRSP and Compustat) is fairly benign.

bysort as_name_clean: egen min_as_date_1 = min(as_date_1) if as_name_clean_one_to_many == 0 // Gets first day of first mapping

bysort as_name_clean: egen max_as_date_n = max(as_date_n) if as_name_clean_one_to_many == 0 // Gets last day of last mapping

replace as_date_1 = min_as_date_1 if !missing(min_as_date_1) // Will only replace for one-to-one mappings

replace as_date_n = max_as_date_n if !missing(max_as_date_n) // Will only replace for one-to-one mappings

drop min_as_date_1 max_as_date_n // No longer needed. Duplicates observations among one-to-one mapping names.

bysort as_name_clean (as_source): drop if _n > 1 & as_name_clean_one_to_many == 0 // Drops now-duplicated listings (except for source), favouring mappings sourced from Compustat.


* Where as_name_clean*time-gvkey Mapping One-to-One, but as_name_clean-gvkey Mapping One-to-Many, Extend Times to Entire Period *

bysort as_name_clean gvkey: egen min_asgvkey_date_1 = min(as_date_1) if as_name_clean_one_to_many == 1 // Executes only for one-to-many mappings that may not be so on any given date.

bysort as_name_clean gvkey: egen max_asgvkey_date_n = max(as_date_n) if as_name_clean_one_to_many == 1

bysort as_name_clean (min_asgvkey_date_1): gen gvkey_clash_raw = (max_asgvkey_date_n >= min_asgvkey_date_1[_n+1] & gvkey != gvkey[_n+1]) if as_name_clean_one_to_many == 1 // Highlights gvkey clash for an arbitrary observation under one gvkey

bysort as_name_clean (min_asgvkey_date_1): replace gvkey_clash_raw = 1 if gvkey_clash_raw[_n-1] == 1 // Highlights gvkey clash for an arbitrary observation under another gvkey

bysort as_name_clean gvkey: egen gvkey_clash = max(gvkey_clash_raw) // Highlights all observations under all gvkeys that clash.

drop gvkey_clash_raw // No longer informative

bysort as_name_clean gvkey: replace as_date_1 = min_asgvkey_date_1 if as_name_clean_one_to_many == 1 & gvkey_clash == 0 // Change time constraints for one-to-one as_name_clean*time-gvkey mappings 

bysort as_name_clean gvkey: replace as_date_n = max_asgvkey_date_n if as_name_clean_one_to_many == 1 & gvkey_clash == 0

bysort as_name_clean gvkey (as_source): drop if _n > 1 & as_name_clean_one_to_many == 1 & gvkey_clash == 0 // Drops now-duplicated listings (except for source), favouring mappings sourced from Compustat.

drop as_name_clean_one_to_many min_asgvkey_date_1 max_asgvkey_date_n gvkey_clash

  
* Check Again for Overlap *

bysort as_name_clean (as_date_1 gvkey): gen overlap = ((_n == 1 & as_date_n >= as_date_1[_n+1] & !missing(as_date_1[_n+1])) | (_n > 1 & _n < _N & (as_date_1 <= as_date_n[_n-1] | as_date_n >= as_date_1[_n+1])) | (_n == _N & as_date_1 <= as_date_n[_n-1] & !missing(as_date_n[_n-1])))

encode as_name_clean if overlap == 1, gen(n_enc)

gen n = n_enc // This is just to keep my sanity whilst I make manual aterations.

drop n_enc overlap // Overlap isn't actually needed now - all we need is a non-missing n to indicate an overlap.


* Remove Overlaps *

// Empty clean names - we can't functionally use these

drop if as_name_clean == ""


// 1-10 (VERIFIED FUNCTIONAL)

drop if as_name_clean == "1ST VIRTUAL" & gvkey == "110100" // Transient listing

replace as_date_1 = date("30apr2016","DMY") if as_name_clean == "ADT" & gvkey == "032930" // Should change 2. Change for re-list
replace as_date_n = date("29apr2016", "DMY") if as_name_clean == "ADT" & gvkey == "014438" & as_source == 1
drop if as_name_clean == "ADT" & gvkey == "014438" & as_source == 2 // Duplicate
drop if as_name_clean == "ADT" & gvkey == "032930" & as_source == 2 

replace as_date_1 = date("01aug1985", "DMY") if as_name_clean == "ADVANCED TELECOM" & gvkey == "001171" & as_source == 1 // Clarify mapping
replace as_date_n = date("04dec1992", "DMY") if as_name_clean == "ADVANCED TELECOM" & gvkey == "001171" & as_source == 1 // Clarify mapping 
drop if as_name_clean == "ADVANCED TELECOM" & gvkey == "001171" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("12aug1989", "DMY") if as_name_clean == "ADVANTAGE" & gvkey == "003227" // Clarify mapping

replace as_date_1 = date("16aug2007", "DMY") if as_name_clean == "AEROFLEX" & gvkey == "184639" // Clarify mapping

drop if as_name_clean == "AFFINION GP" & gvkey == "165164" // Non-holdings company is actually unlisted

replace as_date_1 = date("31aug1995", "DMY") if as_name_clean == "AIRTRAN" & gvkey == "030399" // Clarify mapping

replace as_date_1 = date("01nov2016", "DMY") if as_name_clean == "ALCOA" & gvkey == "027638" // Clarify mapping

replace as_date_1 = date("28dec2004", "DMY") if as_name_clean == "AMC ENTMT" & gvkey == "164271" & as_source == 1 // Clarify mapping
replace as_date_1 = date("01jan2016", "DMY") if as_name_clean == "AMC ENTMT" & gvkey == "177637" & as_source == 1 // Clarify mapping
drop if as_name_clean == "AMC ENTMT" & gvkey == "177637" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("31jan1984", "DMY") if as_name_clean == "AMERN CAPITAL" & gvkey == "010934" & as_source == 1 // Clarify mapping
drop if as_name_clean == "AMERN CAPITAL" & gvkey == "010934" & as_source == 2 // Drop new duplicate


// 11-20 (VERIFIED FUNCTIONAL)

replace as_date_1 = date("30may2020", "DMY") if as_name_clean == "AMERN OUTDOOR BRANDS" & gvkey == "036826" & as_source == 1 // Clarify mapping
drop if as_name_clean == "AMERN OUTDOOR BRANDS" & gvkey == "036826" & as_source == 2 // Drop new duplicate

drop if as_name_clean == "AMERN STANDARD" & gvkey == "115016" // Superfluous listing

drop if as_name_clean == "AMOCO" & gvkey == "015257" // Transient listing

replace as_name_clean = conm if as_name_clean == "APL" // 4 changes. Added to list to check on patent side.
drop if as_name_clean == "APL CORP" & gvkey == "001058" & as_source == 2 // Drop new duplicate
replace as_date_n = date("13nov1997", "DMY") if as_name_clean == "APL LTD" & gvkey == "001543" & as_source == 1 // Clarify mapping
drop if as_name_clean == "APL LTD" & gvkey == "001543" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("01jan2002", "DMY") if as_name_clean == "ARAMARK" & gvkey == "144519" & as_source == 1 // Clarify mapping
replace as_date_1 = date("01jul2013", "DMY") if as_name_clean == "ARAMARK" & gvkey == "186858" & as_source == 1 // Clarify mapping
drop if as_name_clean == "ARAMARK" & gvkey == "186858" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("01apr2020", "DMY") if as_name_clean == "ARCONIC" & gvkey == "035978" & as_source == 1 // Clarify mapping

replace as_date_1 = date("01sep1984", "DMY") if as_name_clean == "ARRAYS" & gvkey == "001771" & as_source == 1 // Clarify mapping
replace as_date_n = date("08feb1988", "DMY") if as_name_clean == "ARRAYS" & gvkey == "001771" & as_source == 1 // Clarify mapping
drop if as_name_clean == "ARRAYS" & gvkey == "001771" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("01feb1985", "DMY") if as_name_clean == "ASTRO MEDICAL" & gvkey == "001820" // Clarify mapping

replace as_date_1 = date("22nov2005", "DMY") if as_name_clean == "AT AND T" & gvkey == "009899" // Clarify mapping

replace as_date_n = date("21nov2005", "DMY") if as_name_clean == "ATANDT" & gvkey == "001581" // Clarify mapping
replace as_date_1 = date("22nov2005", "DMY") if as_name_clean == "ATANDT" & gvkey == "009899" // Clarify mapping


// 21-30 (VERIFIED FUNCTIONAL)

replace as_date_1 = date("31jul1996", "DMY") if as_name_clean == "ATARI" & gvkey == "061718" // Clarify mapping

drop if as_name_clean == "ATI" & gvkey == "001067" & as_source == 2 // Drop new duplicate
replace as_date_n = date("30jan1984", "DMY") if as_name_clean == "ATI" & gvkey == "001067" // Clarify mapping

drop if gvkey == "119174" // Drops 2. Short-lived dotcom listing

replace as_date_1 = date("01jul2017", "DMY") if as_name_clean == "AVAYA" & gvkey == "032855" & as_source == 1 // Clarify mapping
drop if as_name_clean == "AVAYA" & gvkey == "032855" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("04jul2017", "DMY") if as_name_clean == "BAKER HUGHES" & gvkey == "032106" & as_source == 1 // Clarify mapping
drop if as_name_clean == "BAKER HUGHES" & gvkey == "032106" & as_source == 2 // Drop new duplicate

replace as_date_n = date("31mar2021", "DMY") if as_name_clean == "BLUEGREEN VACATIONS" & gvkey == "011877" & as_source == 2 // Clarify mapping
replace as_date_1 = date("01apr2021", "DMY") if as_name_clean == "BLUEGREEN VACATIONS" & gvkey == "039571" & as_source == 2 // Clarify mapping
replace as_date_n = date("31dec2021", "DMY") if as_name_clean == "BLUEGREEN VACATIONS" & gvkey == "039571" & as_source == 2 // Clarify mapping

replace as_date_1 = date("10oct1997", "DMY") if as_name_clean == "BLYTH" & gvkey == "030219" // Clarify mapping

replace as_date_1 = date("01oct2012", "DMY") if as_name_clean == "BOISE CASCADE" & gvkey == "016486" // Clarify mapping

replace as_date_n = date("31mar1995", "DMY") if as_name_clean == "BPO MGMT SVCS" & gvkey == "019557" & as_source == 1 // Delaware has more assets than Pennsylvania, so we map to the former.
drop if as_name_clean == "BPO MGMT SVCS" & gvkey == "019557" & as_source == 2 // Drop new duplicate
drop if as_name_clean == "BPO MGMT SVCS" & gvkey == "063384" & as_source == 2 // Drop new duplicate

drop if as_name_clean == "BROADCAST INT" & gvkey == "014843" // Remove mapping to Vermont subsidiary


// 31-40 (VERIFIED FUNCTIONAL)

replace as_date_1 = date("30jan2016", "DMY") if as_name_clean == "BROADCOM" & gvkey == "180711" & as_source == 1 // Clarify mapping
drop if as_name_clean == "BROADCOM" & gvkey == "180711" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("24may2003", "DMY") if as_name_clean == "BROADWING" & gvkey == "135865" // Clarify mapping

replace as_date_n = date("12jun2007", "DMY") if as_name_clean == "BWAY" & gvkey == "060898" & as_source == 1 // Clarify mapping
drop if as_name_clean == "BWAY" & gvkey == "060898" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("15jun2005", "DMY") if as_name_clean == "CAESARS ENTMT" & gvkey == "020423" & as_source == 1 // Clarify mapping
replace as_date_n = date("20jul2020", "DMY") if as_name_clean == "CAESARS ENTMT" & gvkey == "020423" & as_source == 1 // Clarify mapping
replace as_date_1 = date("21jul2020", "DMY") if as_name_clean == "CAESARS ENTMT" & gvkey == "021808" & as_source == 1 // Clarify mapping
drop if as_name_clean == "CAESARS ENTMT" & gvkey == "021808" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("23nov1988", "DMY") if as_name_clean == "CALLON PETROLEUM" & gvkey == "015060" & as_source == 1 // Clarify mapping
drop if as_name_clean == "CALLON PETROLEUM" & gvkey == "015060" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("01sep2005", "DMY") if as_name_clean == "CARDIAC SCIENCE" & gvkey == "147451" // Clarify mapping

drop if as_name_clean == "CENTRAL TELEPHONE" & (gvkey == "002868" | gvkey == "002869" | gvkey == "002867") // Drops 3. Remove regional subsidiary listings

replace as_date_1 = date("23feb1996", "DMY") if as_name_clean == "CHAMPPS ENTMT" & gvkey == "065088" & as_source == 1 // Clarify mapping
replace as_date_n = date("23oct2007", "DMY") if as_name_clean == "CHAMPPS ENTMT" & gvkey == "065088" & as_source == 1 // Clarify mapping
drop if as_name_clean == "CHAMPPS ENTMT" & gvkey == "065088" & as_source == 2 // Drop new duplicate

drop if as_name_clean == "CHANCELLOR" & gvkey == "062068" & as_source == 2 // Drop transitory mapping

replace as_date_1 = date("01oct2002", "DMY") if as_name_clean == "CHEROKEE INT" & gvkey == "157494" & as_source == 1 // Clarify mapping
replace as_date_n = date("21nov2008", "DMY") if as_name_clean == "CHEROKEE INT" & gvkey == "157494" & as_source == 1 // Clarify mapping
drop if as_name_clean == "CHEROKEE INT" & gvkey == "157494" & as_source == 2 // Drop new duplicate


// 41-50 (VERIFIED FUNCTIONAL)

replace as_date_1 = date("01apr2001", "DMY") if as_name_clean == "CITADEL BROADCASTING" & gvkey == "149089" // Clarify mapping

drop if as_name_clean == "COLLINS FOODS INT" & gvkey == "003177" // Collins Foods never really trades as Collins Foods

replace as_date_1 = date("14jan2011", "DMY") if as_name_clean == "COMMSCOPE" & gvkey == "018036" // Clarify mapping

replace as_date_1 = date("29apr1997", "DMY") if as_name_clean == "CONS FREIGHTWAYS" & gvkey == "063975" & as_source == 1 // Clarify mapping
replace as_date_n = date("03oct2002", "DMY") if as_name_clean == "CONS FREIGHTWAYS" & gvkey == "063975" & as_source == 1 // Clarify mapping
drop if as_name_clean == "CONS FREIGHTWAYS" & gvkey == "063975" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("28apr1976", "DMY") if as_name_clean == "CONTINENTAL CAN" & gvkey == "011155" & as_source == 1 // Clarify mapping
replace as_date_n = date("29may1998", "DMY") if as_name_clean == "CONTINENTAL CAN" & gvkey == "011155" & as_source == 1 // Clarify mapping
drop if as_name_clean == "CONTINENTAL CAN" & gvkey == "011155" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("02mar2000", "DMY") if as_name_clean == "CONVERSE" & gvkey == "151948" // Clarify mapping

replace as_date_1 = date("05jan1989", "DMY") if as_name_clean == "CONVEST ENERGY" & gvkey == "012039" & as_source == 1 // Clarify mapping
replace as_date_n = date("23oct1997", "DMY") if as_name_clean == "CONVEST ENERGY" & gvkey == "012039" & as_source == 1 // Clarify mapping
drop if as_name_clean == "CONVEST ENERGY" & gvkey == "012039" & as_source == 2 // Drop new duplicate

drop if as_name_clean == "CROWN" & gvkey == "003621" // Short-lived listing

replace as_date_1 = date("01oct2000", "DMY") if as_name_clean == "DADE BEHRING" & gvkey == "151016" // Clarify mapping

replace as_date_1 = date("25dec2001", "DMY") if as_name_clean == "DEAN FOODS" & gvkey == "062655" & as_source == 2 // Clarify mapping
replace as_date_n = date("31dec2019", "DMY") if as_name_clean == "DEAN FOODS" & gvkey == "062655" & as_source == 2 // Clarify mapping
drop if as_name_clean == "DEAN FOODS" & gvkey == "062655" & as_source == 1 // Drop new duplicate


// 51-60 (VERIFIED FUNCTIONAL)

replace as_date_1 = date("01may1987", "DMY") if as_name_clean == "DIAMOND SHAMROCK" & gvkey == "013587" // Clarify mapping

replace as_date_1 = date("31oct1986", "DMY") if as_name_clean == "DIGITAL TRANSERVICE" & gvkey == "013893" & as_source == 1 // Clarify mapping
replace as_date_n = date("06aug1987", "DMY") if as_name_clean == "DIGITAL TRANSERVICE" & gvkey == "013893" & as_source == 1 // Clarify mapping
drop if as_name_clean == "DIGITAL TRANSERVICE" & gvkey == "013893" & as_source == 2 // Drop new duplicate

drop if as_name_clean == "DIRECTV" & gvkey == "264765" // We drop the holding company mapping here.

replace as_date_1 = date("01jan1988", "DMY") if as_name_clean == "DYNAMIC SCIENCES INT" & gvkey == "014442" & as_source == 1 // Clarify mapping
drop if as_name_clean == "DYNAMIC SCIENCES INT" & gvkey == "014442" & as_source == 2 // Drops 2 duplicates.

drop if as_name_clean == "DYNCORP INT" & gvkey == "187846" // Transitory listing

replace as_date_1 = date("31jan1984", "DMY") if as_name_clean == "ECONO THERM ENERGY SYS" & gvkey == "012427" & as_source == 1 // Clarify mapping
drop if as_name_clean == "ECONO THERM ENERGY SYS" & gvkey == "012427" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("19may2007", "DMY") if as_name_clean == "EMDEON" & gvkey == "175903" // Clarify mapping

replace as_date_n = date("31mar1981", "DMY") if as_name_clean == "ENERGY RES" & gvkey == "004363" & as_source == 1 // Clarify mapping

drop if as_name_clean == "ENVISION HEALTHCARE" & gvkey == "018432" // Drops 2. We drop the holding company mapping here.

replace as_date_1 = date("29sep1989", "DMY") if as_name_clean == "EVERGREEN RES" & gvkey == "020064" & as_source == 1 // Clarify mapping
replace as_date_n = date("28sep2004", "DMY") if as_name_clean == "EVERGREEN RES" & gvkey == "020064" & as_source == 1 // Clarify mapping
drop if as_name_clean == "EVERGREEN RES" & gvkey == "020064" & as_source == 2 // Drop new duplicate


// 61-70

drop if as_name_clean == "EXPL" & gvkey == "013567" // Remove transitory listing

replace as_date_1 = date("04nov2015", "DMY") if as_name_clean == "EXTERRAN" & gvkey == "023864" // Clarify mapping

replace as_date_1 = date("23dec1997", "DMY") if as_name_clean == "FREEPORT MCMORAN" & gvkey == "014590" & as_source == 1 // Clarify mapping
drop if as_name_clean == "FREEPORT MCMORAN" & gvkey == "014590" & as_source == 2 // Drop new duplicate

replace as_name_clean = "FRONTIER CORP" if as_name_clean == "FRONTIER" & gvkey == "009195" // Added to list to check on patent side.
replace as_name_clean = "FRONTIER HLDGS" if as_name_clean == "FRONTIER" & gvkey == "004914"

replace as_name_clean = "FTD INC" if as_name_clean == "FTD" & gvkey == "149299" & as_source == 1 // Added to list to check on patent side.
replace as_name_clean = "FTD.COM" if as_name_clean == "FTD" & gvkey == "122656"
drop if as_name_clean == "FTD" & gvkey == "149299" & as_source == 2 // Drop new duplicate

drop if as_name_clean == "GAIA" & gvkey == "026175" // Drop mapping to regional listing

replace as_date_1 = date("21nov2019", "DMY") if as_name_clean == "GANNETT" & gvkey == "019574" // Clarify mapping

replace as_date_1 = date("10mar2018", "DMY") if as_name_clean == "GCI LIBERTY" & gvkey == "013664" & as_source == 1 // Clarify mapping
replace as_date_n = date("21dec2020", "DMY") if as_name_clean == "GCI LIBERTY" & gvkey == "013664" & as_source == 1 // Clarify mapping
drop if as_name_clean == "GCI LIBERTY" & gvkey == "013664" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("01may1994", "DMY") if as_name_clean == "GEN NUTRITION" & gvkey == "026905" & as_source == 1 // Clarify mapping
replace as_date_n = date("11aug1999", "DMY") if as_name_clean == "GEN NUTRITION" & gvkey == "026905" & as_source == 1 // Clarify mapping
drop if as_name_clean == "GEN NUTRITION" & gvkey == "026905" & as_source == 2 // Drop new duplicate

drop if as_name_clean == "GEN TELEPHONE" & as_name != "GENERAL TELEPHONE CO OF OH" // Drops 5. Ohio has the most assets, so we re-map to that one.


// 71-80 (VERIFIED FUNCTIONAL)

replace as_name_clean = "GLOBAL INDUSTRIES" if as_name_clean == "GLOBAL IND" & gvkey == "027816" // Added to list to check on patent side.
replace as_name_clean = "GLOBAL INDUSTRIAL" if as_name_clean == "GLOBAL IND" & gvkey == "060931"

replace as_date_1 = date("02nov2001", "DMY") if as_name_clean == "GLOBALNET" & gvkey == "106159" // Clarify mapping

replace as_date_1 = date("01jul2004", "DMY") if as_name_clean == "GOLD KIST" & gvkey == "161075" & as_source == 1 // Clarify mapping
replace as_date_n = date("10jan2007", "DMY") if as_name_clean == "GOLD KIST" & gvkey == "161075" & as_source == 1 // Clarify mapping
drop if as_name_clean == "GOLD KIST" & gvkey == "161075" & as_source == 2 // Drop 2 new duplicates.

replace as_date_1 = date("16sep1989", "DMY") if as_name_clean == "GOLDEN OIL" & gvkey == "008590" & as_source == 1 // Clarify mapping
drop if as_name_clean == "GOLDEN OIL" & gvkey == "008590" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("29sep1998", "DMY") if as_name_clean == "GP 1 SOFTWARE" & gvkey == "003277" & as_source == 2 // Clarify mapping
drop if as_name_clean == "GP 1 SOFTWARE" & gvkey == "003277" & as_source == 1 // Drop new duplicate

replace as_name_clean = "GRAHAM HLDGS" if as_name_clean == "GRAHAM" & gvkey == "011300" // Added to checklist for patents
replace as_name_clean = "GRAHAM CORP" if as_name_clean == "GRAHAM" & gvkey == "005254"

replace as_date_1 = date("01apr1995", "DMY") if as_name_clean == "GRAND UNION" & gvkey == "061094" // Clarify mapping

replace as_date_1 = date("01apr1985", "DMY") if as_name_clean == "GREATE BAY CASINO" & gvkey == "012118" // Clarify mapping

replace as_date_1 = date("01mar1994", "DMY") if as_name_clean == "GTECH" & gvkey == "025807" // Clarify mapping

replace as_date_1 = date("01aug1996", "DMY") if as_name_clean == "HALLWOOD ENERGY" & gvkey == "012044" & as_source == 1 // Clarify mapping
drop if as_name_clean == "HALLWOOD ENERGY" & gvkey == "012044" & as_source == 2 // Drop new duplicate


// 81-90 (VERIFIED FUNCTIONAL)

replace as_date_1 = date("01oct2005", "DMY") if as_name_clean == "HANDE EQUIPMENT SVCS" & gvkey == "165856" // Clarify mapping

replace as_date_1 = date("08apr1998", "DMY") if as_name_clean == "HANDY AND HARMAN" & gvkey == "011462" // Clarify mapping

replace as_date_1 = date("24mar1981", "DMY") if as_name_clean == "HEI" & gvkey == "005404" & as_source == 1 // Clarify mapping
replace as_date_n = date("23jul1990", "DMY") if as_name_clean == "HEI" & gvkey == "005403" & as_source == 1 // Clarify mapping
drop if as_name_clean == "HEI" & as_source == 2 // Drops 2. Duplicates
replace as_name_clean = "HEI INC" if as_name_clean == "HEI" & gvkey == "005404" // Added to patents checklist
replace as_name_clean = "HEI CORP" if as_name_clean == "HEI" & gvkey == "005403"

drop if as_name_clean == "HOLLY" & gvkey == "029458" // Holly Holdings is transient, inactive listing

drop if as_name_clean == "HUNTSMAN INT" & gvkey == "148255" // Drop holdings company

drop if as_name_clean == "IAC INTERACTIVECORP" & gvkey == "036691" // Drops 2 duplicates

replace as_date_1 = date("12nov1994", "DMY") if as_name_clean == "ICN PHARMACEUTICALS" & gvkey == "009340" // Clarify mapping

drop if as_name_clean == "IGO" & gvkey == "124975" // Drop transient listing 

replace as_date_1 = date("18oct2001", "DMY") if as_name_clean == "INSIGHT HEALTH SVCS" & gvkey == "149297" // Clarify mapping

replace as_date_1 = date("25mar2020", "DMY") if as_name_clean == "INSTRUCTURE" & gvkey == "039312" // Clarify mapping


// 91-100 (VERIFIED FUNCTIONAL)

replace as_date_1 = date("03jun1998", "DMY") if as_name_clean == "INTERSTATE HOTELS" & gvkey == "121474" // Clarify mapping

drop if as_name_clean == "ITT" & gvkey == "061738" // Secondary listing
drop if as_name_clean == "ITT" & gvkey == "005860" & as_source == 2 // Drops 2 duplicates

drop if as_name_clean == "JONES INTERCABLE" & gvkey == "013573" // Main listing seems to be Comcast Joint Holdings

replace as_date_1 = date("01apr2007", "DMY") if as_name_clean == "K AND F IND" & gvkey == "164533" // Clarify mapping

replace as_date_1 = date("02may1987", "DMY") if as_name_clean == "KAISER ALUMINUM AND CHEM" & gvkey == "014531" // Clarify mapping

replace as_date_1 = date("30jun2001", "DMY") if as_name_clean == "KANEB SVCS" & gvkey == "144076" & as_source == 2 // Clarify mapping
drop if as_name_clean == "KANEB SVCS" & gvkey == "144076" & as_source == 1 // Drop new duplicate

drop if as_name_clean == "KNOLL INT" & gvkey == "014358" // Drop duplicate
drop if as_name_clean == "KNOLL INT" & gvkey == "006478" & as_source == 2 // Drop duplicate

replace as_date_1 = date("01jul2009", "DMY") if as_name_clean == "KOPPERS" & gvkey == "163113" // Clarify mapping

drop if as_name_clean == "LA QUINTA MOTOR INNS" & gvkey == "013564" // Drop secondary listing

replace as_date_1 = date("12aug1999", "DMY") if as_name_clean == "LABONE" & gvkey == "024184" & as_source == 2 // Clarify mapping
drop if as_name_clean == "LABONE" & gvkey == "024184" & as_source == 1 // Drop new duplicate


// 101-110 (VERIFIED FUNCTIONAL)

replace as_date_1 = date("01oct2004", "DMY") if as_name_clean == "LAS VEGAS SANDS" & gvkey == "161844" // Clarify mapping

drop if as_name_clean == "LEAR" & gvkey == "016477" // Drop holding company

replace as_date_1 = date("28dec1995", "DMY") if as_name_clean == "LEARNING" & gvkey == "007345" & as_source == 1 // Clarify mapping
replace as_date_n = date("14may1999", "DMY") if as_name_clean == "LEARNING" & gvkey == "007345" & as_source == 1 // Clarify mapping
drop if as_name_clean == "LEARNING" & gvkey == "007345" & as_source == 2 // Drop new duplicate
replace as_date_n = date("27dec1995", "DMY") if as_name_clean == "LEARNING" & gvkey == "025208" & as_source == 1 // Clarify mapping
drop if as_name_clean == "LEARNING" & gvkey == "025208" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("01jul2000", "DMY") if as_name_clean == "LIFE TECH" & gvkey == "118577" // Clarify mapping

replace as_date_1 = date("28apr2007", "DMY") if as_name_clean == "LIGHTBRIDGE" & gvkey == "140982" // Clarify mapping

drop if as_name_clean == "MCAFEE" & gvkey == "126773" // Drop mapping to transient listing

drop if as_name_clean == "MEDEX REDH" & gvkey == "161057" // Drop mapping to transient listing

replace as_date_1 = date("27jul1999", "DMY") if as_name_clean == "MEDICAL MANAGER" & gvkey == "016469" & as_source == 2 // Clarify mapping
drop if as_name_clean == "MEDICAL MANAGER" & gvkey == "016469" & as_source == 1 // Drop new duplicate

replace as_date_n = date("03feb2011", "DMY") if as_name_clean == "MEDQUIST" & gvkey == "025216" // Clarify mapping

replace as_date_1 = date("01dec2005", "DMY") if as_name_clean == "METALS US" & gvkey == "175087" // Clarify mapping
replace as_date_n = date("30nov2005", "DMY") if as_name_clean == "METALS US" & gvkey == "065074" & as_source == 1 // Clarify mapping
drop if as_name_clean == "METALS US" & gvkey == "065074" & as_source == 2 // Drop new duplicate


// 111-120 (VERIFIED FUNCTIONAL)

replace as_date_1 = date("04sep1996", "DMY") if as_name_clean == "MICROTEK MEDICAL" & gvkey == "030843" & as_source == 1 // Clarify mapping
replace as_date_n = date("12nov2007", "DMY") if as_name_clean == "MICROTEK MEDICAL" & gvkey == "030843" & as_source == 1 // Clarify mapping
drop if as_name_clean == "MICROTEK MEDICAL" & gvkey == "030843" & as_source == 2 // Drop new duplicate

replace as_date_n = date("30jan1985", "DMY") if as_name_clean == "MINDEN OIL AND GAS" & gvkey == "007419" & as_source == 1
drop if as_name_clean == "MINDEN OIL AND GAS" & gvkey == "007419" & as_source == 2 // Nested wider listing

replace as_date_1 = date("02aug1991", "DMY") if as_name_clean == "MOMENTUM" & gvkey == "021092" // Clarify mapping

replace as_date_1 = date("01jul2019", "DMY") if as_name_clean == "NATL CINEMEDIA" & gvkey == "176523" // Clarify mapping

replace as_date_n = date("31dec2006", "DMY") if as_name_clean == "NEWPAGE" & gvkey == "174315" // Redirect mapping away from holding corp

drop if as_name_clean == "NORTHWEST AIRLINES" & gvkey == "015309" // Drop transient listing 
drop if as_name_clean == "NORTHWEST AIRLINES" & gvkey == "007672" & as_source == 2 // Drop duplicate

replace as_date_1 = date("17sep2005", "DMY") if as_name_clean == "NUANCE COMM" & gvkey == "061685" // Clarify mapping

replace as_date_n = date("30jun2013", "DMY") if as_name_clean == "OFFICIAL PAYMENTS" & gvkey == "066059" & as_source == 1 // Clarify mapping
drop if as_name_clean == "OFFICIAL PAYMENTS" & gvkey == "066059" & as_source == 2 // Drop new duplicate
drop if as_name_clean == "OFFICIAL PAYMENTS" & gvkey == "126717" // Drop transient listing 

replace as_date_1 = date("19aug2004", "DMY") if as_name_clean == "PANAMSAT" & gvkey == "162556" // Clarify mapping
replace as_date_n = date("18aug2004", "DMY") if as_name_clean == "PANAMSAT" & gvkey == "061340" & as_source == 1 // Clarify mapping
drop if as_name_clean == "PANAMSAT" & gvkey == "061340" & as_source == 2 // Drop new duplicate

replace as_name_clean = "PARADISE INC" if as_name_clean == "PARADISE" & gvkey == "008336" // Added to check list for patent data
replace as_name_clean = "PARADISE HLDGS" if as_name_clean == "PARADISE" & gvkey == "030179"


// 121-130 (VERIFIED FUNCTIONAL)

replace as_date_1 = date("01feb2000", "DMY") if as_name_clean == "PERFUMANIA" & gvkey == "124360" // Clarify mapping

replace as_name_clean = "PETRO USA" if as_name_clean == "PETRO US" & gvkey == "001272" // Added to check list for patent data
replace as_name_clean = "PETRO AMERICA" if as_name_clean == "PETRO US" & gvkey == "145207"

replace as_date_1 = date("31jan1986", "DMY") if as_name_clean == "PETROMARK RES" & gvkey == "013280" & as_source == 1 // Clarify mapping
drop if as_name_clean == "PETROMARK RES" & gvkey == "013280" & as_source == 2 // Drop new duplicate

drop if as_name_clean == "PHIBRO ANIMAL HEALTH" & gvkey == "148293" // Map to active listing

drop if as_name_clean == "PHILIP MORRIS" & gvkey == "013302" // We keep Phillip Morris under Altria

replace as_date_1 = date("16aug1988", "DMY") if as_name_clean == "PHOTRONICS" & gvkey == "013200" // Clarify mapping

replace as_date_1 = date("01oct1989", "DMY") if as_name_clean == "PITTWAY" & gvkey == "010006" & as_source == 1 // Clarify mapping
replace as_date_n = date("15feb2000", "DMY") if as_name_clean == "PITTWAY" & gvkey == "010006" & as_source == 1 // Clarify mapping
drop if as_name_clean == "PITTWAY" & gvkey == "010006" & as_source == 2 // Drop new duplicate

drop if as_name_clean == "PLM EQUIPMENT GROWTH FUND" // Drops 3. Just a fund

replace as_date_1 = date("01jul1991", "DMY") if as_name_clean == "PRECISION OPTICS" & gvkey == "024842" // Clarify mapping

replace as_date_1 = date("01aug1992", "DMY") if as_name_clean == "PRIME MOTOR INNS" & gvkey == "013578" // Clarify mapping


// 131-140 (VERIFIED FUNCTIONAL)

replace as_date_1 = date("28mar2002", "DMY") if as_name_clean == "PROXIM" & gvkey == "138347" // Clarify mapping

replace as_date_1 = date("01jul2000", "DMY") if as_name_clean == "QWEST COMM INT" & gvkey == "061489" & as_source == 1 // Clarify mapping
replace as_date_n = date("31mar2011", "DMY") if as_name_clean == "QWEST COMM INT" & gvkey == "061489" & as_source == 1 // Clarify mapping
drop if as_name_clean == "QWEST COMM INT" & gvkey == "061489" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("01oct1989", "DMY") if as_name_clean == "RAMADA" & gvkey == "012443" // Redirect mapping away from holding company

replace as_date_1 = date("12nov1996", "DMY") if as_name_clean == "RED LION HOTELS" & gvkey == "109079" // Clarify mapping

drop if as_name_clean == "REPUBLIC RES" & gvkey == "009062" // Drop mapping to regional listing

replace as_date_1 = date("01apr1992", "DMY") if as_name_clean == "REXNORD OLD" & gvkey == "025493" // Clarify mapping

replace as_date_1 = date("28jun1990", "DMY") if as_name_clean == "ROYAL INT OPTICAL" & gvkey == "023244" & as_source == 1 // Clarify mapping
replace as_date_n = date("09jun1995", "DMY") if as_name_clean == "ROYAL INT OPTICAL" & gvkey == "023244" & as_source == 1 // Clarify mapping
drop if as_name_clean == "ROYAL INT OPTICAL" & gvkey == "023244" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("28feb1979", "DMY") if as_name_clean == "RSI" & gvkey == "008905" & as_source == 1 // Clarify mapping
replace as_date_n = date("15nov1989", "DMY") if as_name_clean == "RSI" & gvkey == "008905" & as_source == 1 // Clarify mapping
drop if as_name_clean == "RSI" & gvkey == "008905" & as_source == 2 // Drop new duplicate
replace as_date_1 = date("16nov1989", "DMY") if as_name_clean == "RSI" & gvkey == "017108" & as_source == 1 // Clarify mapping
drop if as_name_clean == "RSI" & gvkey == "017108" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("27feb1999", "DMY") if as_name_clean == "RYERSON TULL" & gvkey == "005968" // Clarify mapping

drop if as_name_clean == "SAKS" & gvkey == "062915" // Drop mapping to holding company


// 141-150 (VERIFIED FUNCTIONAL)

replace as_date_1 = date("09feb1988", "DMY") if as_name_clean == "SHELTER COMPONENTS" & gvkey == "010560" & as_source == 1 // Clarify mapping
drop if as_name_clean == "SHELTER COMPONENTS" & gvkey == "010560" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("01apr1997", "DMY") if as_name_clean == "SILGAN" & gvkey == "064389" // Clarify mapping

replace as_date_1 = date("10nov1981", "DMY") if as_name_clean == "SIPPICAN" & gvkey == "009752" // Clarify mapping

replace as_date_1 = date("24dec1983", "DMY") if as_name_clean == "SOUTHERN PACIFIC" & gvkey == "009862" // Clarify mapping

replace as_date_1 = date("17jul2018", "DMY") if as_name_clean == "SPECTRUM BRANDS" & gvkey == "011670" & as_source == 2 // Clarify mapping
drop if as_name_clean == "SPECTRUM BRANDS" & gvkey == "065459" & as_source == 2 // Nested within wider mapping

replace as_date_1 = date("06aug2003", "DMY") if as_name_clean == "SPORTS AUTHORITY" & gvkey == "066278" & as_source == 2 // Clarify mapping
drop if as_name_clean == "SPORTS AUTHORITY" & gvkey == "066278" & as_source == 1 // Drop new duplicate

replace as_date_1 = date("07oct1998", "DMY") if as_name_clean == "SPX" & gvkey == "005087" // Clarify mapping
drop if as_name_clean == "SPX" & gvkey == "005087" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("01aug2000", "DMY") if as_name_clean == "STYLECLICK" & gvkey == "138309" & as_source == 1 // Clarify mapping
drop if as_name_clean == "STYLECLICK" & gvkey == "138309" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("01jul1990", "DMY") if as_name_clean == "SUNBEAM" & gvkey == "001278" & as_source == 1 // Clarify mapping
replace as_date_n = date("05feb2001", "DMY") if as_name_clean == "SUNBEAM" & gvkey == "001278" & as_source == 1 // Clarify mapping
drop if as_name_clean == "SUNBEAM" & gvkey == "001278" & as_source == 2 // Drop new duplicate
drop if as_name_clean == "SUNBEAM" & gvkey == "010160" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("06oct2012", "DMY") if as_name_clean == "SUNOCO" & gvkey == "012892" // Clarify mapping


// 151-160 (VERIFIED FUNCTIONAL)

replace as_date_1 = date("30jan1985", "DMY") if as_name_clean == "SUNSTATES" & gvkey == "010186" & as_source == 1 // Clarify mapping
replace as_date_n = date("23jul1996", "DMY") if as_name_clean == "SUNSTATES" & gvkey == "010186" & as_source == 1 // Clarify mapping
drop if as_name_clean == "SUNSTATES" & gvkey == "010186" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("25feb1989", "DMY") if as_name_clean == "TEKNOWLEDGE" & gvkey == "015495" // Clarify mapping

replace as_date_1 = date("22feb1990", "DMY") if as_name_clean == "TELOS" & gvkey == "002578" & as_source == 1 // Clarify mapping
replace as_date_n = date("21feb1990", "DMY") if as_name_clean == "TELOS" & gvkey == "011824" & as_source == 1 // Clarify mapping
drop if as_name_clean == "TELOS" & gvkey == "011824" & as_source == 2 // Drop new duplicate
drop if as_name_clean == "TELOS" & gvkey == "002578" & as_source == 2 // Drop new duplicate

drop if as_name_clean == "TENNECO" & gvkey == "010442" // Remove mapping to inactive listing
drop if as_name_clean == "TENNECO" & gvkey == "010443" & as_source == 2 // Drop 2 duplicates

drop if as_name_clean == "TETRA TECH" & gvkey != "010473" & as_source == 2 // Drops 3. All duplicates.
replace as_name_clean = "TETRA TECHNOLOGIES" if as_name_clean == "TETRA TECH" & gvkey == "021237" // Tetra Tech kept as that. Both Added to list for checking patent data

replace as_name_clean = "TIVO CORP" if as_name_clean == "TIVO" & gvkey == "064480" // Both Added to list for checking patent data
replace as_name_clean = "TIVO INC" if as_name_clean == "TIVO" & gvkey == "124394"

replace as_date_1 = date("15jun1989", "DMY") if as_name_clean == "TJX" & gvkey == "011672" // Clarify mapping

replace as_date_1 = date("25nov1987", "DMY") if as_name_clean == "TOWLE MFG" & gvkey == "014641" & as_source == 1 // Clarify mapping
drop if as_name_clean == "TOWLE MFG" & gvkey == "014641" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("01jul2004", "DMY") if as_name_clean == "TOWN SPORTS INT" & gvkey == "164606" & as_source == 1 // Clarify mapping
replace as_date_n = date("23sep2020", "DMY") if as_name_clean == "TOWN SPORTS INT" & gvkey == "164606" & as_source == 1 // Clarify mapping
drop if as_name_clean == "TOWN SPORTS INT" & gvkey == "164606" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("28feb1984", "DMY") if as_name_clean == "TRANE" & gvkey == "001567" // Clarify mapping
replace as_date_n = date("27feb1984", "DMY") if as_name_clean == "TRANE" & gvkey == "010649" & as_source == 1 // Clarify mapping
drop if as_name_clean == "TRANE" & gvkey == "010649" & as_source == 2 // Drop new duplicate


// 161-170 (VERIFIED FUNCTIONAL)

drop if as_name_clean == "TSC" & gvkey == "010303" // Drops 2. Drop more transient link
replace as_date_n = date("31oct1985", "DMY") if as_name_clean == "TSC" & gvkey == "010302" & as_source == 1 // Clarify mapping
drop if as_name_clean == "TSC" & gvkey == "010302" & as_source == 2 // Drop new duplicate

drop if as_name_clean == "TSI" & gvkey == "010304" & as_source == 1 // Drop duplicate
replace as_date_n = date("03oct1994", "DMY") if as_name_clean == "TSI" & gvkey == "015328" & as_source == 1 // Clarify mapping
drop if as_name_clean == "TSI" & gvkey == "015328" & as_source == 2 // Drop new duplicate
replace as_name_clean = "TSI INC" if as_name_clean == "TSI" & gvkey == "010304"
replace as_name_clean = "TSI CORP" if as_name_clean == "TSI" & gvkey == "015328"

replace as_date_n = date("04mar1993", "DMY") if as_name_clean == "TSL" & gvkey == "010330" & as_source == 1 // Clarify mapping
drop if as_name_clean == "TSL" & gvkey == "010330" & as_source == 2 // Drop new duplicate
replace as_name_clean = "TSL HLDGS" if as_name_clean == "TSL" & gvkey == "010330" // Both Added to list for checking patent data
replace as_name_clean = "TSL INC" if as_name_clean == "TSL" & gvkey == "015432"

replace as_date_1 = date("12jul1997", "DMY") if as_name_clean == "UNICO" & gvkey == "014271" // Clarify mapping

drop if as_name_clean == "UNITED AIRLINES" & gvkey == "010795" // Remove mapping to holding company 

replace as_name_clean = "UNITED INDUSTRIAL" if as_name_clean == "UNITED IND" & gvkey == "010906" // Both Added to list for checking patent data
replace as_name_clean = "UNITED INDSTRIES" if as_name_clean == "UNITED IND" & gvkey == "148354"

drop if as_name_clean == "UNIVERSAL COMPRESSION" & gvkey == "148355" // Only holding company is actually listed.
replace as_date_n = date("20aug2007", "DMY") if as_name_clean == "UNIVERSAL COMPRESSION" & gvkey == "135969" & as_source == 1 // Clarify mapping
drop if as_name_clean == "UNIVERSAL COMPRESSION" & gvkey == "135969" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("22sep2004", "DMY") if as_name_clean == "US AIRWAYS GP" & gvkey == "001382" & as_source == 1 // Clarify mapping 
replace as_date_n = date("09dec2013", "DMY") if as_name_clean == "US AIRWAYS GP" & gvkey == "001382" & as_source == 1 // Clarify mapping
drop if as_name_clean == "US AIRWAYS GP" & gvkey == "001382" & as_source == 2 // Drop new duplicate

drop if as_name_clean == "US BRIDGE" & gvkey == "061146" // Drops 3 mappings to regional subsidiary
drop if as_name_clean == "US BRIDGE" & gvkey == "030934" & as_source == 2 // Drop new duplicate

replace as_date_1 = date("01oct1996", "DMY") if as_name_clean == "US CAN" & gvkey == "027908" // Clarify mapping


// 171-180 (VERIFIED FUNCTIONAL)

replace as_date_1 = date("30apr2018", "DMY") if as_name_clean == "US COMPRESSION PRTNRS" & gvkey == "033449" & as_source == 1 // Clarify mapping
drop if as_name_clean == "US COMPRESSION PRTNRS" & gvkey == "033449" & as_source == 2 // Drop 2 new duplicates

replace as_name_clean = "AMERICA WEST" if as_name_clean == "US WEST" & gvkey == "001382" // US WEST kept as is. Both Added to list for checking patent data

replace as_date_n = date("14mar2005", "DMY") if as_name_clean == "VARCO INT" & gvkey == "020993" & as_source == 1 // Clarify mapping
drop if as_name_clean == "VARCO INT" & gvkey == "020993" & as_source == 2 // Drop new duplicate

drop if as_name_clean == "VERIZON" & gvkey != "005090"  // Drops 8. Verizon California is the largest by assets

drop if as_name_clean == "VERSO PAPER" & gvkey == "178266" // Drop mapping to holding company

replace as_date_1 = date("01apr2011", "DMY") if as_name_clean == "VISANT" & gvkey == "162488" // Clarify mapping

replace as_date_1 = date("29nov1990", "DMY") if as_name_clean == "VISX" & gvkey == "014897" & as_source == 1 // Clarify mapping
replace as_date_n = date("31may2005", "DMY") if as_name_clean == "VISX" & gvkey == "014897" & as_source == 1 // Clarify mapping
drop if as_name_clean == "VISX" & gvkey == "014897" & as_source == 2 // Drop 2 new duplicates

replace as_date_n = date("03oct2005", "DMY") if as_name_clean == "VULCAN" & gvkey == "011225" & as_source == 2 // Clarify mapping
drop if as_name_clean == "VULCAN" & gvkey == "011226" // Drop mapping to briefer listing

drop if as_name_clean == "WEST" & gvkey == "011376" // We let WEST map to WEST CORP, rather than to WEST PHARMACEUTICAL SERVICES

replace as_date_1 = date("30jul2008", "DMY") if as_name_clean == "XM SATELLITE RADIO" & gvkey == "148365"  // Clarify mapping
replace as_date_n = date("29jul2008", "DMY") if as_name_clean == "XM SATELLITE RADIO" & gvkey == "124442" & as_source == 1 // Clarify mapping
drop if as_name_clean == "XM SATELLITE RADIO" & gvkey == "124442" & as_source == 2 // Drop new duplicate


* Remove Extraneous Variables *

drop n // No longer needed


* Export *

compress

save "./outputs/003a_database_a_clean_names_clean_times.dta", replace


  ***********************************
* Clean Time Mappings - No Whitespace *
  ***********************************

* Import *

use "./outputs/003a_database_a_clean_names_clean_times.dta", clear


* Remove All Whitespace *

replace as_name_clean = subinstr(as_name_clean, " ", "", .) // Removes all whitespace

  
* Establish as_name_clean-gvkey Mappings that are One-to-Many *

bysort as_name_clean: gen nr_mappings_as_name_clean = _N

bysort as_name_clean gvkey: gen nr_mappings_as_name_clean_gvkey = _N

gen as_name_clean_one_to_many = (nr_mappings_as_name_clean != nr_mappings_as_name_clean_gvkey)

label var as_name_clean_one_to_many "as_name_clean maps to multiple gvkeys."

drop nr_mappings_as_name_clean nr_mappings_as_name_clean_gvkey // No longer necessary


* Where as_name_clean-gvkey Mapping One-to-One, Extend to Entire Period *

// If the name has a one-to-one mapping, extending it to the furthest period implied all such mappings (from both CRSP and Compustat) is fairly benign.

bysort as_name_clean: egen min_as_date_1 = min(as_date_1) if as_name_clean_one_to_many == 0 // Gets first day of first mapping

bysort as_name_clean: egen max_as_date_n = max(as_date_n) if as_name_clean_one_to_many == 0 // Gets last day of last mapping

replace as_date_1 = min_as_date_1 if !missing(min_as_date_1) // Will only replace for one-to-one mappings

replace as_date_n = max_as_date_n if !missing(max_as_date_n) // Will only replace for one-to-one mappings

drop min_as_date_1 max_as_date_n // No longer needed. Duplicates observations among one-to-one mapping names.

bysort as_name_clean (as_source): drop if _n > 1 & as_name_clean_one_to_many == 0 // Drops now-duplicated listings (except for source), favouring mappings sourced from Compustat.


* Where as_name_clean*time-gvkey Mapping One-to-One, but as_name_clean-gvkey Mapping One-to-Many, Extend Times to Entire Period *

bysort as_name_clean gvkey: egen min_asgvkey_date_1 = min(as_date_1) if as_name_clean_one_to_many == 1 // Executes only for one-to-many mappings that may not be so on any given date.

bysort as_name_clean gvkey: egen max_asgvkey_date_n = max(as_date_n) if as_name_clean_one_to_many == 1

bysort as_name_clean (min_asgvkey_date_1): gen gvkey_clash_raw = (max_asgvkey_date_n >= min_asgvkey_date_1[_n+1] & gvkey != gvkey[_n+1]) if as_name_clean_one_to_many == 1 // Highlights gvkey clash for an arbitrary observation under one gvkey

bysort as_name_clean (min_asgvkey_date_1): replace gvkey_clash_raw = 1 if gvkey_clash_raw[_n-1] == 1 // Highlights gvkey clash for an arbitrary observation under another gvkey

bysort as_name_clean gvkey: egen gvkey_clash = max(gvkey_clash_raw) // Highlights all observations under all gvkeys that clash.

drop gvkey_clash_raw // No longer informative

bysort as_name_clean gvkey: replace as_date_1 = min_asgvkey_date_1 if as_name_clean_one_to_many == 1 & gvkey_clash == 0 // Change time constraints for one-to-one as_name_clean*time-gvkey mappings 

bysort as_name_clean gvkey: replace as_date_n = max_asgvkey_date_n if as_name_clean_one_to_many == 1 & gvkey_clash == 0

bysort as_name_clean gvkey (as_source): drop if _n > 1 & as_name_clean_one_to_many == 1 & gvkey_clash == 0 // Drops now-duplicated listings (except for source), favouring mappings sourced from Compustat.

drop as_name_clean_one_to_many min_asgvkey_date_1 max_asgvkey_date_n gvkey_clash

  
* Check Again for Overlap *

bysort as_name_clean (as_date_1 gvkey): gen overlap = ((_n == 1 & as_date_n >= as_date_1[_n+1] & !missing(as_date_1[_n+1])) | (_n > 1 & _n < _N & (as_date_1 <= as_date_n[_n-1] | as_date_n >= as_date_1[_n+1])) | (_n == _N & as_date_1 <= as_date_n[_n-1] & !missing(as_date_n[_n-1])))

encode as_name_clean if overlap == 1, gen(n_enc)

gen n = n_enc // This is just to keep my sanity whilst I make manual aterations.

drop n_enc overlap // Overlap isn't actually needed now - all we need is a non-missing n to indicate an overlap.


* Remove Overlaps *

drop if as_name_clean == "BARNESANDNOBLE" & gvkey == "120773" // Remove mapping to transitory dotcom business

replace as_date_1 = date("21nov2000", "DMY") if as_name_clean == "DELIAS" & gvkey == "119474" & as_source == 1 // Clarify mapping
replace as_date_n = date("19dec2014", "DMY") if as_name_clean == "DELIAS" & gvkey == "119474" & as_source == 1 // Clarify mapping
drop if as_name_clean == "DELIAS" & gvkey == "119474" & as_source == 2 // Drop new duplicate

drop if as_name_clean == "KANDFIND" & gvkey == "164533" // Drops 2 mappings to shorter-lived holding company

replace as_date_1 = date("01oct1983", "DMY") if as_name_clean == "MCCORMICKOILANDGAS" & gvkey == "011968" // Clarify mapping

replace as_date_1 = date("01jul1989", "DMY") if as_name_clean == "MIDSOUTH" & gvkey == "014857" // Clarify mapping

drop if as_name_clean == "PARTECH" & gvkey == "014920" // Drop transitory mapping

replace as_date_1 = date("28apr1999", "DMY") if as_name_clean == "PERKINELMER" & gvkey == "004145" // Clarify mapping

replace as_date_1 = date("15aug2007", "DMY") if as_name_clean == "POINT360" & gvkey == "178089" & as_source == 1 // Clarify mapping
drop if as_name_clean == "POINT360" & gvkey == "178089" & as_source == 2 // Drop new duplicate

drop if as_name_clean == "WAVETECHINT" & gvkey == "013172" // Drop mapping to transitory listing


* Drop Extraneous Variables *

drop n


* Label as_name_clean *

label var as_name_clean "Clean Company Name" // Now it is finally indeed clean


* Get Wide Mapping Times: Get Variables 5 and 10 Years Either Side * // For each as_date, we either (1) expand by 5 years either side if there are no listings 10 years away that side or (2) expand to the midpoint between mappings

gen tenyb_y = yofd(as_date_1) - 10 // Year: 10 years before
gen tenyb_m = mod(mofd(as_date_1), 12) + 1 // Month (1-12): 10 years before
gen tenyb_d = as_date_1 - dofm(mofd(as_date_1)) + 1 // Day of Month (1-31): 10 years before

gen fiveyb_y = yofd(as_date_1) - 5 // Year: 5 years before
gen fiveyb_m = mod(mofd(as_date_1), 12) + 1 // Month (1-12): 5 years before
gen fiveyb_d = as_date_1 - dofm(mofd(as_date_1)) + 1 // Day of Month (1-31): 5 years before

gen fiveya_y = yofd(as_date_n) + 5 // Year: 5 years after
gen fiveya_m = mod(mofd(as_date_n), 12) + 1 // Month (1-12): 5 years after
gen fiveya_d = as_date_n - dofm(mofd(as_date_n)) + 1 // Day of Month (1-31): 5 years after

gen tenya_y = yofd(as_date_n) + 10 // Year: 10 years after
gen tenya_m = mod(mofd(as_date_n), 12) + 1 // Month (1-12): 10 years after
gen tenya_d = as_date_n - dofm(mofd(as_date_n)) + 1 // Day of Month (1-31): 10 years after

local prefixes `" "tenyb" "fiveyb" "fiveya" "tenya" "'

foreach prefix in `prefixes'{
	
	replace `prefix'_d = 28 if `prefix'_m == 2 & `prefix'_d == 29 & mod(`prefix'_y, 4) != 0
	
}

tostring tenyb_y tenyb_m tenyb_d fiveyb_y fiveyb_m fiveyb_d fiveya_y fiveya_m fiveya_d tenya_y tenya_m tenya_d, replace // Get to string to concatenate run through date()

gen tenyb_s = tenyb_y + "-" + tenyb_m + "-" + tenyb_d // Concatenate to format date() understands

gen fiveyb_s = fiveyb_y + "-" + fiveyb_m + "-" + fiveyb_d

gen fiveya_s = fiveya_y + "-" + fiveya_m + "-" + fiveya_d

gen tenya_s = tenya_y + "-" + tenya_m + "-" + tenya_d

gen tenyb = date(tenyb_s, "YMD")

label var tenyb "Ten years before as_date_1"

gen fiveyb = date(fiveyb_s, "YMD")

label var fiveyb "Five years before as_date_1"

gen fiveya = date(fiveya_s, "YMD")

label var fiveya "Five years after as_date_n"

gen tenya = date(tenya_s, "YMD")

label var tenya "Ten years after as_date_n"

format tenyb fiveyb fiveya tenya %td

drop tenyb_y tenyb_m tenyb_d fiveyb_y fiveyb_m fiveyb_d fiveya_y fiveya_m fiveya_d tenya_y tenya_m tenya_d tenyb_s fiveyb_s fiveya_s tenya_s // No longer needed


* Get Wide Mapping Times: Expand 5 Years Either Side where Appropriate *

bysort as_name_clean (as_date_1): gen as_date_1_wide = fiveyb if _n == 1 | (_n > 1 & as_date_n[_n-1] <= tenyb)

bysort as_name_clean (as_date_n): gen as_date_n_wide = fiveya if _n == _N | (_n < _N & as_date_1[_n+1] >= tenya)


* Get Wide Mapping Times: Expand to Midpoint *

bysort as_name_clean (as_date_1): replace as_date_1_wide = as_date_1 - floor((as_date_1 - as_date_n[_n-1])/2) if missing(as_date_1_wide) // Maps to the proper midpoint, favours listing after for mid-day

label var as_date_1_wide "Extended day of start of name-gvkey link"

bysort as_name_clean (as_date_n): replace as_date_n_wide = as_date_n + floor((as_date_1[_n+1] - as_date_n - 1)/2) if missing(as_date_n_wide) // Maps to the proper midpoint, favours listing after for mid-day

label var as_date_n_wide "Extended day of end of name-gvkey link"


* Drop Extraneous Variables and Re-order *

drop tenyb fiveyb fiveya tenya

order as_name as_name_clean gvkey conm as_date_1 as_date_1_wide as_date_n as_date_n_wide as_source


* Export *

compress

save "./outputs/003a_database_a.dta", replace
  

*************
* POSTAMBLE *
*************

log close

exit


/* Code for identifying non-alphanumeric characters
  
preserve

gen nonalphanumeric = regexm(as_name_clean, "[^a-zA-z0-9 ]") // Indicator variable for the presence of non-alphanumeric characters

gen what_character = regexs(0) if regexm(as_name_clean, "[^a-zA-z0-9 ]") // Returns matched character

drop if nonalphanumeric == 0 // Drops observations without non-alphanumeric characters

tabulate what_character

count // Count of remaining observations with non-alphanumeric characters

restore

*/


/* Basic code structure for mapping one-word to one-word

local subin "ABBREVIATION" // Abbreviated word to substitute in

local _subin_ = " " + "`subin'" +  " " // The abbreviated word, but with spaces either side

local subout "ORGINAL WORD" // Lengthier word to substitute out

local _subout_ = " " + "`subout'" + " " // The lengthier word, but with spaces either side

replace as_name_clean = subinstr(as_name_clean, "`_subout_'", "`_subin_'", .) // Substitutes out middle words

replace as_name_clean = "`subin'" + substr(as_name_clean, length("`subout'") + 1, .) if fw == "`subout'" // Substitutes first word

replace as_name_clean = substr(as_name_clean, 1, length(as_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0) // Substitutes last word (if word count is greater than one).

*/

/*

List of patent-side companies to check...
APL (APL CORP, APL LTD)
FRONTIER (FRONTIER CORP, FRONTIER HLDGS)
FTD (FTD INC, FTD.COM)
GLOBAL IND (GLOBAL INDUSTRIES, GLOBAL INDUSTRIAL)
GRAHAM (GRAHAM CORP, GRAHAM HLDGS)
HEI (HEI INC, HEI CORP)
PARADISE (PARADISE INC, PARADISE HOLDINGS)
PETRO US (PETRO USA, PETRO AMERICA)
TETRA TECH (TETRA TECH, TETRA TECHNOLOGIES)
TIVO (TIVO INC, TIVO CORP)
TSI (TSI INC, TSI CORP)
TSL (TSL INC, TSL HLDGS)
UNITED IND (UNITED INDUSTRIES, UNITED INDUSTRIAL)
US WEST (US WEST, AMERICA WEST)

*/

/* Templates for alterations

drop if as_name_clean == "" & gvkey == ""

drop if as_name_clean == "" & gvkey == "" & as_source ==  // Drop new duplicate

drop if as_name_clean == "" & gvkey == "" & as_date_1 == date("", "DMY") // Drop new duplicate

replace as_date_1 = date("", "DMY") if as_name_clean == "" & gvkey == "" // Clarify mapping

replace as_date_1 = date("", "DMY") if as_name_clean == "" & gvkey == "" & as_source ==  // Clarify mapping
drop if as_name_clean == "" & gvkey == "" & as_source ==  // Drop new duplicate

replace as_date_n = date("", "DMY") if as_name_clean == "" & gvkey == "" // Clarify mapping

replace as_date_n = date("", "DMY") if as_name_clean == "" & gvkey == "" & as_source ==  // Clarify mapping
drop if as_name_clean == "" & gvkey == "" & as_source ==  // Drop new duplicate

replace as_date_1 = date("", "DMY") if as_name_clean == "" & gvkey == "" & as_source ==  // Clarify mapping
replace as_date_n = date("", "DMY") if as_name_clean == "" & gvkey == "" & as_source ==  // Clarify mapping
drop if as_name_clean == "" & gvkey == "" & as_source ==  // Drop new duplicate

replace as_name_clean = conm if as_name_clean == "" // Added to list to check on patent side.

replace as_name_clean = "" if as_name_clean == "" & gvkey == ""
replace as_name_clean = "" if as_name_clean == "" & gvkey == ""

*/