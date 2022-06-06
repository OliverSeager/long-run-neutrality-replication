/*

Oliver Seager
o.j.seager@lse.ac.uk
SE 17

The idea of this script is to match patents to gvkeys from Compustat. The end output is a gvkey-ecq level dataset with quarterly fractional, citation-weighted patent counts for the given quarter and summations over horizons of up to 19 quarters ahead.

Created: 17/05/2022
Last Modified: 24/05/2022

Infiles:
- assignee.dta (Patentsview data on all patent assignees, with assignee_id.)
- patent_assignee.dta (Patentsview's one-to-many mapping of patent_id to assignee_id.)
- application.dta (Patentsview data on applications for granted patents.)
- patent.dta (Patentsview comprehensive patent-level data.)
- 003a_database_a.dta (Concatenated Compustat (conm) and CRSP (comnam) names, cleaned, to Compustat gvkey, with time overlaps removed and wide timings added)
- cpc_classification.dta (PatentsView's data on the CPC classification of Patents)
- 001a_patent_forward_citations.dta (Observations at the patent level, with number of forward citations by patent.)
- 001c_cstat_jan1961_jan2022_ow_controls.dta (S&P Compustat Quarterly Fundamentals data, with all Ottonello and Winberry (2020) control variables)

Out&Infiles:

Outfiles:
- 003b_patent_dates.dta (Patent-level data, with application date and granting date for each patent.)
- 003b_database_b1.dta (A mapping of Compustat gvkeys to PatentsView assignee IDs, with names used for match, in addition to dates of link validity.)
- 003b_database_b2.dta (Patent-level data (with assignee_id) on fractional, citation-weighted patent data.)
- 003b_database_b3.dta (A gvkey-ecq level dataset of summative patent counts for the current ecq through 19 ecqs ahead.)

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

log using "./code/003b_patent_database_b.log", replace


*********************************************************
* DATABASE B1 - MAPPING OF gvkey TO ps_name-assignee_id *
*********************************************************

* Import Assignee Data *

use "./data/assignee.dta", clear


* Drop Misparsed Rows *

bysort assignee_id: gen misparsed = (length(assignee_id) != 36) // Stata won't read *everything* properly. Thankfully the three that it's read improperly seem to not be firms anyway.

drop if misparsed == 1

drop misparsed


* Drop Individuals and Governmental Organisations *

drop if assignee_type == 4 | assignee_type == 5 | assignee_type == 6 | assignee_type == 7 | assignee_type == 8 | assignee_type == 9 | assignee_type == 14 | assignee_type == 15 | assignee_type == 17


* Drop Extraneous Variables *

keep assignee_id assignee_name

rename assignee_name ps_name // Align with Database A phrasing


* Initiate Clean Name Variable *

gen ps_name_clean = ps_name // We start with ps_name

label var ps_name_clean "Cleaned patenting organisation name"


* Drop Organisations without Names *

drop if ps_name_clean == ""


* Change Names to Upper Case *

replace ps_name = upper(ps_name)

replace ps_name_clean = upper(ps_name_clean)


* Merge to Assignee-Patent Mapping *

merge 1:m assignee_id using "./data/patent_assignee.dta", keepusing(patent_id)

drop if _merge != 3 // We can't use firms that don't patent.

drop _merge


* Merge to Application Date Data *

merge m:1 patent_id using "./data/application.dta", keepusing(application_date)

drop if _merge == 2 // We don't want patents on which we have no good assignee data

drop _merge


* Merge to Granting Data Data *

merge m:1 patent_id using "./data/patent.dta", keepusing(granting_date)

drop if _merge == 2 // We don't want patents on which we have no good assignee data

drop _merge


* Drop Patents for which we have no Date *

drop if missing(application_date) & missing(granting_date) // These aren't particularly useful to us.


* Populate Missing Application Date Values *

// Where we have no application date, we assume that application was 840 days (or whatever the median length of time is) before granting.

gen waiting_period = granting_date - application_date // Length of time between application and granting

quietly summarize waiting_period, detail // Gets median into `=r(p50)'

replace application_date = granting_date - `r(p50)' if missing(application_date)


* Export Application and Granting Dates at the Patent Level *

// We do this to aid in the construction of Database B2 (Patent Value)

preserve

keep patent_id application_date granting_date // We want to reduce from the assignee-patent level to the patent level here

duplicates drop

save "./outputs/003b_patent_dates.dta", replace

restore


* Drop Extraneous Variables *

drop waiting_period granting_date // No longer needed


* Get Patenting Period for ps_name-assignee_id Pair *

bysort ps_name assignee_id: egen ps_date_1 = min(application_date)

label var ps_date_1 "Day of start of name-assignee_id link"

bysort ps_name assignee_id: egen ps_date_n = max(application_date)

label var ps_date_n "Day of end of name-assignee_id link"


* Reduce to ps_name-assignee_id level *

drop patent_id application_date

duplicates drop // Note that, at this point, ps_name and ps_name_clean are identical


  ********************
* Deal with Whitespace *
  ********************

* Replace non-Space Whitespace with Space Whitespace * // An example of non-space whitespace would be tab or newline

replace ps_name_clean = regexr(ps_name_clean, "[\s]", " ") // \s is all whitespace characters, the space is the space whitespace character.


* Trim Consecutive Whitespace Characters to Single Character *

replace ps_name_clean = stritrim(ps_name_clean) // Note the difference between functions stritrim and strtrim.


* Get Rid of Leading, Trailing Whitespace *

replace ps_name_clean = strtrim(ps_name_clean) // Note the difference between functions stritrim and strtrim.


  **********************************
* Remove non-Alphanumeric Characters *
  **********************************

* & *

replace ps_name_clean = subinstr(ps_name_clean, "&AMP", "AND", .)

replace ps_name_clean = subinstr(ps_name_clean, "&", "AND", .)


* () *

replace ps_name_clean = subinstr(ps_name_clean, "(", "", .)

replace ps_name_clean = subinstr(ps_name_clean, ")", "", .)


* - *

// Here we replace a hyphen with a space, and then use the standard whitespace procedure.

replace ps_name_clean = subinstr(ps_name_clean, "-", " ", .)

replace ps_name_clean = stritrim(ps_name_clean)

replace ps_name_clean = strtrim(ps_name_clean)


* . *

replace ps_name_clean = subinstr(ps_name_clean, ".", "", .)


* ' *

replace ps_name_clean = subinstr(ps_name_clean, "'", "", .)


* / *

// Like with hyphens, here we replace a forward slash with a space, and then use the standard whitespace procedure

replace ps_name_clean = subinstr(ps_name_clean, "/", " ", .)

replace ps_name_clean = stritrim(ps_name_clean)

replace ps_name_clean = strtrim(ps_name_clean)


* , *

replace ps_name_clean = subinstr(ps_name_clean, ",", "", .)


* " *

// This is where we have to start getting careful about creating erroneous duplicates.

replace ps_name_clean = subinstr(ps_name_clean, `"""', "", .)


* @ *

replace ps_name_clean = subinstr(ps_name_clean, "@", "AT", .)


* ; *

replace ps_name_clean = subinstr(ps_name_clean, ";", "", .)


* + *

// This requires some care, but can mostly be replaced with " AND "

replace ps_name_clean = subinstr(ps_name_clean, "+", " AND ", .) 

replace ps_name_clean = stritrim(ps_name_clean)

replace ps_name_clean = strtrim(ps_name_clean)


* : *

// First replace with a space, then strip whitespace.

replace ps_name_clean = subinstr(ps_name_clean, ":", " ", .)

replace ps_name_clean = stritrim(ps_name_clean)

replace ps_name_clean = strtrim(ps_name_clean)


* ! *

replace ps_name_clean = subinstr(ps_name_clean, "!", "", .)


* # *

replace ps_name_clean = subinstr(ps_name_clean, "#", "", .)


* % *

// First replace with " PERCENT", then strip of whitespace.

replace ps_name_clean = subinstr(ps_name_clean, "%", " PERCENT", .)

replace ps_name_clean = stritrim(ps_name_clean)

duplicates drop


* $ *

// These appear to all be mis-parsed "S" characters

replace ps_name_clean = subinstr(ps_name_clean, "$", "S", .)


* * *

replace ps_name_clean = subinstr(ps_name_clean, "*", " ", .)

replace ps_name_clean = stritrim(ps_name_clean)

replace ps_name_clean = strtrim(ps_name_clean)


* < *

// This are all just part of mis-parsed gibberish.

replace ps_name_clean = subinstr(ps_name_clean, "<", "", .)


* = *

// Only one valid company name, in which = is properly replaced with nothing

replace ps_name_clean = subinstr(ps_name_clean, "=", "", .)


* > *

// Again, mis-parsed gibberish

replace ps_name_clean = subinstr(ps_name_clean, ">" , "", .)


* ? *

// Comes at the end of a lot of company names.

replace ps_name_clean = subinstr(ps_name_clean, "?", "", .) 


* {} *

// These all indicate nonstandard latin characters, i.e. {HACEK OVER N}, {DOT OVER O}. Since nonstandard latin characters do not appear in compustat, these are replaced with the latin characters that are amended, which can be parsed as the character before }...

replace ps_name_clean = subinstr(ps_name_clean, "{", "", .) if ps_name_clean == "{PERSONALIZED MEDIA COMMUNICATIONS LLC" // ...except for this one, which creates...

duplicates drop // ...a benign duplicate.

// Since regular expressions works one matched substring at a time (and we need to use regular expressions here), we loop through this process until it's complete.

count if regexm(ps_name_clean, "{[^}]*}") // This counts the number of observations in which "{some phrase}" is matched

local loop_switch = r(N) // Initiates loop switch

while (`loop_switch' > 0){
	
	gen nonstandard_char = regexs(0) if regexm(ps_name_clean, "{[^}]*}") // Gets matched "{some phrase}" substring
	
	gen standard_char = substr(nonstandard_char, -2, 1) // Extracts standard latin character that is amended
	
	replace ps_name_clean = subinstr(ps_name_clean, nonstandard_char, standard_char, .) // Replaces "{some phrase}" with standard character the curly brackets signify an amendment to
	
	count if regexm(ps_name_clean, "{[^}]*}") // Counts observations with changes still needed
	
	local loop_switch = r(N) // Updates loop switch
	
	drop nonstandard_char standard_char
	
}


* | *

replace ps_name_clean = subinstr(ps_name_clean, "|", " ", .)


* [] *

// We deal with these the same way we dealt with ()

replace ps_name_clean = subinstr(ps_name_clean, "[", "", .)

replace ps_name_clean = subinstr(ps_name_clean, "]", "", .)


* _ *

// This is generally used instead of a space

replace ps_name_clean = subinstr(ps_name_clean, "_", " ", .)

replace ps_name_clean = stritrim(ps_name_clean) 

replace ps_name_clean = strtrim(ps_name_clean)


* ` *

// Since this works largely in the same way as an apostrophe, we just drop the character

replace ps_name_clean = subinstr(ps_name_clean, "`", "", .)


* Deal with Observations with Phantom Whitespace Character *

// There are 446 observations in the Fleming data which end in a series of 0s and 1s, with some strange whitespace character between them that is not picked up by regular expressions. We use regular expressions here to shave this portion of ps_name_clean from the end.

gen alphanumeric_ps_name_clean = regexs(0) if regexm(ps_name_clean, "[A-Z0-9 ]*") // Gets the starting alphanumeric string for *all* observations. Using list if alphanumeric_ps_name_clean != ps_name_clean is also a good way of identifying nonalphanumeric characters present

replace ps_name_clean = alphanumeric_ps_name_clean // Replaces ps_name_clean with the first string of alphanumeric characters.

drop alphanumeric_ps_name_clean


  *****************
* Condense Acronyms *
  *****************
  
* Leading Acronyms * // Here we clean acronyms that appear at the start of a string, i.e. "D O G   CAT   C O W   FOX   R A T" becomes "DOG   CAT   C O W   FOX   R A T"

gen A_B_ = regexs(0) if regexm(ps_name_clean, "^(. (. )+)") // The gappy acronym

gen AB_ = subinstr(A_B_, " ", "", .) + " " // Removes all spaces from acronym, then adds one at the end.

replace ps_name_clean = subinstr(ps_name_clean, A_B_, AB_, .) if A_B_ != "" // Does the condensing.

drop A_B_ AB_ // No longer needed


* Trailing Acronyms * // Here we clean acronyms that appear at the end of a string, i.e. "D O G   CAT   C O W   FOX   R A T" becomes "D O G   CAT   C O W   FOX   RAT"

gen _Y_Z = regexs(0) if regexm(ps_name_clean, "(( .)+ .)$") // The gappy acronym

gen _YZ = " " + subinstr(_Y_Z, " ", "", .) // Removes all spaces from acronym, then adds one at the start.

replace ps_name_clean = subinstr(ps_name_clean, _Y_Z, _YZ, .) if _Y_Z != "" // Does the condensing. 

drop _Y_Z _YZ  // No longer needed. 


* Mid-string Acronyms * // Here we clean acronyms that appear in the middle of a string, i.e. "D O G   CAT   C O W   FOX   R A T" becomes "D OG   CAT   COW   FOX   RA T". This is why we do leading and trailing acronyms first.

gen _M_N_ = regexs(0) if regexm(ps_name_clean, " . (. )+") // The gappy acronym

gen _MN_ = " " + subinstr(_M_N_, " ", "", .) + " " // Removes all spaces from acronym, then adds one at each end

replace ps_name_clean = subinstr(ps_name_clean, _M_N_, _MN_, .) if _M_N_ != "" // Does the condensing. 

drop _M_N_ _MN_  // No longer needed.


  **********************
* Remove Corporate Terms *
  **********************

* THE (Prefix) *

replace ps_name_clean = substr(ps_name_clean, 5, .) if substr(ps_name_clean, 1, 4) == "THE "


* INC (Suffix, Incorporated) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " INC"


* CORP (Suffix, Corporation) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CORP"


* LTD (Suffix, Limited) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " LTD"


* CO (Suffix, Company/Corporation) * // Note that this actually leaves a fair few "AND CO" companies with "AND" as a suffix unless we drop that too.

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 7) if substr(ps_name_clean, -7, 7) == " AND CO"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " CO"


* A (Suffix, Unclear) *

// Two forms of this appear - "CL A" and "SER A". I remove both.

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL A"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 6) if substr(ps_name_clean, -6, 6) == " SER A"


* LP (Suffix, Limited Partnership) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " LP"


* CP (Suffix, Corporation) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " CP"


* PLC (Suffix, Public Limited Company) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " PLC"


* TRUST (Suffix, Trust) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 6) if substr(ps_name_clean, -6, 6) == " TRUST"


* ADR, ADS (Suffixes, American Depositary Receipts/Shares) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " ADR"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " ADS"


* TR (Suffix, Trust) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " TR"


* BANCORP, BANCORPORATION (Suffix, Banking Corporation) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 8) if substr(ps_name_clean, -8, 8) == " BANCORP"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 15) if substr(ps_name_clean, -15, 15) == " BANCORPORATION"


* SA (Sociedad Anónima/Societé Anonyme) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " SA"


* LLC (Limited Liability Company) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " LLC"


* CL ? (Suffixes, Unknown) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL B"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 6) if substr(ps_name_clean, -6, 6) == " CL B2"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL C"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL D"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL I"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL Y"


* HOLDINGS, HOLDING, HLDGS (Suffix, Holding Company) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 9) if substr(ps_name_clean, -9, 9) == " HOLDINGS"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 8) if substr(ps_name_clean, -8, 8) == " HOLDING"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 6) if substr(ps_name_clean, -6, 6) == " HLDGS"


* II (Suffix, Second Listing) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " II"


* State Suffixes (Including DC, Puerto Rico) * // Note that Colorado also doubles up as "CO", i.e. Company, Corporation.

local states "AL KY OH AK LA OK AZ ME OR AR MD PA AS MA PR CA MI RI CO MN SC CT MS SD DE MO TN DC MT TX FL NE GA NV UT NH VT HI NJ VA ID NM IL NY WA IN NC WV IA ND WI KS WY" // A string containing all two letter state codes

gen lw = word(ps_name_clean, -1) // Variable containing last word in string

gen lwl = length(lw) // Variable containing length of last word in string

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if (strpos("`states'", lw) > 0) & (lwl == 2) & (substr(ps_name_clean, -7, 7) != " AND CO") // Removes two-letter state code from end of string.

drop lw lwl


* COS (Suffix, Companies) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " COS"


* HLDG (Suffix, Holding) * // Note that this can come as part of "HOLDING CO", with " CO" removed above.

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " HLDG"


* AG (Suffix, Aktiengesellschaft) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " AG"


* III (Suffix, Third Listing) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " III"


* AB (Suffix, Aktiebolag) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " AB"


* NEW (Suffix, New Version of Compustat Listing) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " NEW"


* SA DE CV/SAB DE CV (Suffix, Sociedad Anónima de Capital Variable/Sociedad Anónima Bursátil de Capital Variable) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 10) if substr(ps_name_clean, -9, 9) == " SA DE CV"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 10) if substr(ps_name_clean, -10, 10) == " SAB DE CV"


* I (Suffix, First Listing) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 2) if substr(ps_name_clean, -2, 2) == " I"


* SE (Suffix, Societas Europaea) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " SE"


* SPN (Suffix, Unknown) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " SPN"


* THE (Suffix, Basically where "The Dog Company" appears as "Dog Company, The" *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " THE"s


* COM (Suffix, Company) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " COM"


* FSB (Suffix, Federal Savings Bank) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " FSB"


* SPA (Suffix, Società per Azioni) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " SPA"


* IV (Suffix, Fourth Listing) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " IV"


* LIMITED (Suffix) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 8) if substr(ps_name_clean, -8, 8) == " LIMITED"


* CORPORATION (Suffix) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 12) if substr(ps_name_clean, -12, 12) == " CORPORATION"


* COMPANY (Suffix) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 8) if substr(ps_name_clean, -8, 8) == " COMPANY"


* DEL (Suffix, Delaware) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " DEL"


* CIE (Compagnie) *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " CIE"


* Removing Again - Round 2 *

// Note that "DOGS CO LTD" will now still be "DOGS CO", whereas we want it to just be "DOGS". We run through until there are no more suffixes to remove

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " INC"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CORP"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " LTD"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 7) if substr(ps_name_clean, -7, 7) == " AND CO"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 7) if substr(ps_name_clean, -7, 7) == " CO"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL A"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 6) if substr(ps_name_clean, -6, 6) == " SER A"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " LP"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " CP"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " PLC"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 6) if substr(ps_name_clean, -6, 6) == " TRUST"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " ADR"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " ADS"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " TR"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 8) if substr(ps_name_clean, -8, 8) == " BANCORP"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " SA"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " LLC"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL B"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 6) if substr(ps_name_clean, -6, 6) == " CL B2"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL C"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL D"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL I"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL Y"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 9) if substr(ps_name_clean, -9, 9) == " HOLDINGS"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 8) if substr(ps_name_clean, -8, 8) == " HOLDING"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 6) if substr(ps_name_clean, -6, 6) == " HLDGS"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " II"
local states "AL KY OH AK LA OK AZ ME OR AR MD PA AS MA PR CA MI RI CO MN SC CT MS SD DE MO TN DC MT TX FL NE GA NV UT NH VT HI NJ VA ID NM IL NY WA IN NC WV IA ND WI KS WY"
gen lw = word(ps_name_clean, -1)
gen lwl = length(lw)
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if (strpos("`states'", lw) > 0) & (lwl == 2) & (substr(ps_name_clean, -7, 7) != " AND CO")
drop lw lwl
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " COS"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " HLDG"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " AG"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " III"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " AB"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " NEW"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 10) if substr(ps_name_clean, -9, 9) == " SA DE CV"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 10) if substr(ps_name_clean, -10, 10) == " SAB DE CV"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 2) if substr(ps_name_clean, -2, 2) == " I"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " SE"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " SPN"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " THE"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " COM"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " FSB"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " SPA"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " IV"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 8) if substr(ps_name_clean, -8, 8) == " LIMITED"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 12) if substr(ps_name_clean, -12, 12) == " CORPORATION"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 8) if substr(ps_name_clean, -8, 8) == " COMPANY"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " CIE"


* Removing Again - Round 3 *

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " INC"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CORP"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " LTD"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 7) if substr(ps_name_clean, -7, 7) == " AND CO"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 7) if substr(ps_name_clean, -7, 7) == " CO"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL A"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 6) if substr(ps_name_clean, -6, 6) == " SER A"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " LP"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " CP"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " PLC"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 6) if substr(ps_name_clean, -6, 6) == " TRUST"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " ADR"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " ADS"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " TR"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 8) if substr(ps_name_clean, -8, 8) == " BANCORP"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " SA"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " LLC"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL B"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 6) if substr(ps_name_clean, -6, 6) == " CL B2"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL C"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL D"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL I"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL Y"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 9) if substr(ps_name_clean, -9, 9) == " HOLDINGS"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 8) if substr(ps_name_clean, -8, 8) == " HOLDING"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 6) if substr(ps_name_clean, -6, 6) == " HLDGS"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " II"
local states "AL KY OH AK LA OK AZ ME OR AR MD PA AS MA PR CA MI RI CO MN SC CT MS SD DE MO TN DC MT TX FL NE GA NV UT NH VT HI NJ VA ID NM IL NY WA IN NC WV IA ND WI KS WY"
gen lw = word(ps_name_clean, -1)
gen lwl = length(lw)
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if (strpos("`states'", lw) > 0) & (lwl == 2) & (substr(ps_name_clean, -7, 7) != " AND CO")
drop lw lwl
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " COS"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " HLDG"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " AG"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " III"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " AB"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " NEW"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 10) if substr(ps_name_clean, -9, 9) == " SA DE CV"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 10) if substr(ps_name_clean, -10, 10) == " SAB DE CV"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 2) if substr(ps_name_clean, -2, 2) == " I"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " SE"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " SPN"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " THE"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " COM"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " FSB"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " SPA"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " IV"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 8) if substr(ps_name_clean, -8, 8) == " LIMITED"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 12) if substr(ps_name_clean, -12, 12) == " CORPORATION"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 8) if substr(ps_name_clean, -8, 8) == " COMPANY"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " CIE"


* Removing Again - Round 4 *

// We just need 4 rounds of this

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " INC"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CORP"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " LTD"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 7) if substr(ps_name_clean, -7, 7) == " AND CO"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 7) if substr(ps_name_clean, -7, 7) == " CO"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL A"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 6) if substr(ps_name_clean, -6, 6) == " SER A"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " LP"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " CP"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " PLC"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 6) if substr(ps_name_clean, -6, 6) == " TRUST"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " ADR"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " ADS"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " TR"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 8) if substr(ps_name_clean, -8, 8) == " BANCORP"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " SA"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " LLC"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL B"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 6) if substr(ps_name_clean, -6, 6) == " CL B2"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL C"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL D"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL I"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " CL Y"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 9) if substr(ps_name_clean, -9, 9) == " HOLDINGS"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 8) if substr(ps_name_clean, -8, 8) == " HOLDING"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 6) if substr(ps_name_clean, -6, 6) == " HLDGS"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " II"
local states "AL KY OH AK LA OK AZ ME OR AR MD PA AS MA PR CA MI RI CO MN SC CT MS SD DE MO TN DC MT TX FL NE GA NV UT NH VT HI NJ VA ID NM IL NY WA IN NC WV IA ND WI KS WY"
gen lw = word(ps_name_clean, -1)
gen lwl = length(lw)
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if (strpos("`states'", lw) > 0) & (lwl == 2) & (substr(ps_name_clean, -7, 7) != " AND CO")
drop lw lwl
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " COS"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 5) if substr(ps_name_clean, -5, 5) == " HLDG"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " AG"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " III"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " AB"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " NEW"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 10) if substr(ps_name_clean, -9, 9) == " SA DE CV"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 10) if substr(ps_name_clean, -10, 10) == " SAB DE CV"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 2) if substr(ps_name_clean, -2, 2) == " I"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " SE"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " SPN"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " THE"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " COM"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " FSB"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " SPA"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 3) if substr(ps_name_clean, -3, 3) == " IV"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 8) if substr(ps_name_clean, -8, 8) == " LIMITED"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 12) if substr(ps_name_clean, -12, 12) == " CORPORATION"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 8) if substr(ps_name_clean, -8, 8) == " COMPANY"
replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - 4) if substr(ps_name_clean, -4, 4) == " CIE"


* Removing Words from Middle of String *

// We now remove the above from the middle of the string. This is because we might wish to retain the "CANADA" in "DOGS CO CANADA", but would like to remove "CO". Exceptions here are "DE" which appears frequently but is "de" as in "of" in French/Spanish, and "I", "II", "III" & "IV", which are Compustat suffixes and therefore only need be removed at the end of the string. Terms that do not make any changes are omitted from the code.


* INC (Incorporated) *

replace ps_name_clean = subinstr(ps_name_clean, " INC "," ", .)


* CORP (Corporation) *

replace ps_name_clean = subinstr(ps_name_clean, " CORP "," ", .)


* LTD (Limited) *

replace ps_name_clean = subinstr(ps_name_clean, " LTD "," ", .)


* AND CO (and Company) *

replace ps_name_clean = subinstr(ps_name_clean, " AND CO "," ", .)


* CO (Company) *

replace ps_name_clean = subinstr(ps_name_clean, " CO " ," ", .)


* CL A (Unknown) *

replace ps_name_clean = subinstr(ps_name_clean, " CL A "," ", .)


* CP (Corporation) *

replace ps_name_clean = subinstr(ps_name_clean, " CP "," ", .)


* PLC (Public Limited Company) *

replace ps_name_clean = subinstr(ps_name_clean, " PLC " ," ", .)


* BANCORP (Banking Corporation) *

replace ps_name_clean = subinstr(ps_name_clean, " BANCORP "," ", .)


* HOLDINGS *

replace ps_name_clean = subinstr(ps_name_clean, " HOLDINGS "," ", .)


* HLDGS (Holdings) *

replace ps_name_clean = subinstr(ps_name_clean, " HLDGS "," ", .)


* HLDG (Holding) *

replace ps_name_clean = subinstr(ps_name_clean, " HLDG "," ", .)


* THE *

replace ps_name_clean = subinstr(ps_name_clean, " THE "," ", .)
  

  ************************************
* Abbreviations - Variable Initiations *
  ************************************

* Get first- and last- word variables *

split ps_name_clean, gen(word_) // Splits into 29 words

gen lw = "" // Initiate last word variable

forvalues i = 1/29{ // Iteratively replace last word variable until no more non-missing values.
	
	replace lw = word_`i' if word_`i' != ""
	
	if(`i' > 1){
		
		drop word_`i'
		
	}
	
}

rename word_1 fw // Clarify first word variable

label var fw "first word in name" 

label var lw "last word in name"


* Get Indicator Variable for One-word Names *

gen wc = wordcount(ps_name_clean)

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

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "INTERN"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'" 

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0) 

local subout "INTL"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)
replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Services *

local subin "SVCS"

local _subin_ = " " + "`subin'" +  " "

local subout "SERVICES"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Group *

local subin "GP"

local _subin_ = " " + "`subin'" +  " "

local subout "GROUP"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "GRP"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)
local subout "GR"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Power *

local subin "PWR"

local _subin_ = " " + "`subin'" +  " "

local subout "POWER"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Manufacturing *

local subin "MFG"

local _subin_ = " " + "`subin'" +  " "

local subout "MANUFACTURING"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Systems *

local subin "SYS"

local _subin_ = " " + "`subin'" +  " "

local subout "SYSTEMS"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "SYSTEM"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "SYST"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Resources *

local subin "RES"

local _subin_ = " " + "`subin'" +  " "

local subout "RESOURCES"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Associated *

local subin "ASSD"

local _subin_ = " " + "`subin'" +  " "

local subout "ASSOCIATED"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Development *

local subin "DEV"

local _subin_ = " " + "`subin'" +  " "

local subout "DEVELOPMENT"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Investments *


local subin "IVT"

local _subin_ = " " + "`subin'" +  " "

local subout "INVESTMENT"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .) 

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'" 

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0) 

local subout "INVESTMENTS"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .) 

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'" 

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0) 

local subout "INVT"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .) 

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'" 

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "INVS"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Management *

local subin "MGMT"

local _subin_ = " " + "`subin'" +  " "

local subout "MANAGEMENT"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .) 

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Products *

local subin "PROD"

local _subin_ = " " + "`subin'" +  " "

local subout "PRODUCTS"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "PRODS"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Canada *

local subin "CAN"

local _subin_ = " " + "`subin'" +  " "

local subout "CANADA"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "CDA"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map USA *

local subin "US"

local _subin_ = " " + "`subin'" +  " "

local subout "USA"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "AM"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "AMERICA"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "AMER"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Properties *

local subin "PPTYS"

local _subin_ = " " + "`subin'" +  " "

local subout "PROPERTIES"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Association *

local subin "ASS"

local _subin_ = " " + "`subin'" +  " "

local subout "ASSOCIATION"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "ASSOC"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "ASSN"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Service * 

local subin "SVC"

local _subin_ = " " + "`subin'" +  " "

local subout "SERVICE"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Communication *

local subin "COMM"

local _subin_ = " " + "`subin'" +  " "

local subout "COMMUNICATIONS"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "COMMUNICATION"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

replace ps_name_clean = subinstr(ps_name_clean, "COMMUN", "COMM", .) if ps_name_clean == "COMPUTER AND COMMUN TECHNOLOGY" | ps_name_clean == "COMMUN AND CABLE"


* Map Entertainment *

local subin "ENTMT"

local _subin_ = " " + "`subin'" +  " "

local subout "ENTERTAINMENT"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Telecommunications *

local subin "TELECOM"

local _subin_ = " " + "`subin'" +  " "

local subout "TELECOMMUNICATIONS"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "TELECOMM"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Partners *

local subin "PRTNRS"

local _subin_ = " " + "`subin'" +  " "

local subout "PARTNERS"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Explorations *

local subin "EXPL"

local _subin_ = " " + "`subin'" +  " "

local subout "EXPLORATION"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "EXPLORATIONS"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Insurance *

local subin "INS"

local _subin_ = " " + "`subin'" +  " "

local subout "INSURANCE"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map American *

local subin "AMERN"

local _subin_ = " " + "`subin'" +  " "

local subout "AMERICAN"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map National *

local subin "NATL"

local _subin_ = " " + "`subin'" +  " "

local subout "NATIONAL"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Communities, Community *

local subin "CMNTY"

local _subin_ = " " + "`subin'" +  " "

local subout "COMMUNITIES"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "COMMUN"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "COMMUNITY"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Bank *

local subin "BK"

local _subin_ = " " + "`subin'" +  " "

local subout "BANK"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "BANC"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Savings *

local subin "SVGS"

local _subin_ = " " + "`subin'" +  " "

local subout "SAVINGS"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Chemicals, Chemical *

local subin "CHEM"

local _subin_ = " " + "`subin'" +  " "

local subout "CHEMICALS"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "CHEMICAL"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Realty *

local subin "REALTY"

local _subin_ = " " + "`subin'" +  " "

local subout "RLTY"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Solutions *

local subin "SOLTNS"

local _subin_ = " " + "`subin'" +  " "

local subout "SOLUTIONS"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Transport *

local subin "TRANS"

local _subin_ = " " + "`subin'" +  " "

local subout "TRANSPORT"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "TRANSPRT"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "TRNSPRT"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Finance, Financial *

local subin "FIN"

local _subin_ = " " + "`subin'" +  " "

local subout "FINANCE"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "FINANCIAL"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "FINL"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map First *

local subin "1ST"

local _subin_ = " " + "`subin'" +  " "

local subout "FIRST"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Second *

local subin "2ND"

local _subin_ = " " + "`subin'" +  " "

local subout "SECOND"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Third *

local subin "3RD"

local _subin_ = " " + "`subin'" +  " "

local subout "THIRD"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Fourth *

local subin "4TH"

local _subin_ = " " + "`subin'" +  " "

local subout "FOURTH"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Fifth *

local subin "5TH"

local _subin_ = " " + "`subin'" +  " "

local subout "FIFTH"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Sixth *

local subin "6TH"

local _subin_ = " " + "`subin'" +  " "

local subout "SIXTH"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Drugs *

local subin "DRUG"

local _subin_ = " " + "`subin'" +  " "

local subout "DRUGS"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Technology, Technologies *

local subin "TECH"

local _subin_ = " " + "`subin'" +  " "

local subout "TECHNOLOGY"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "TECHNOLOGIES"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Laboratories, Laboratory *

local subin "LAB"

local _subin_ = " " + "`subin'" +  " "

local subout "LABORATORIES"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "LABORATORY"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "LABS"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "LABO"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Brothers *

local subin "BROS"

local _subin_ = " " + "`subin'" +  " "

local subout "BROTHERS"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Electrical *

local subin "ELEC"

local _subin_ = " " + "`subin'" +  " "

local subout "ELECTRICAL"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "ELECTRIC"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .) 

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'" 

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Commercial *

local subin "COMML"

local _subin_ = " " + "`subin'" +  " "

local subout "COMMERCIAL"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Consolidated *

local subin "CONS"

local _subin_ = " " + "`subin'" +  " "

local subout "CONSOLIDATED"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Industries, Industrial *

local subin "IND"

local _subin_ = " " + "`subin'" +  " "

local subout "INDUSTRIES"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "INDUSTRIAL"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "INDS"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0) 

// 0 duplicates created


* Map Instruments *

local subin "INSTR"

local _subin_ = " " + "`subin'" +  " "

local subout "INSTRUMENT"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "INSTRUMENTS"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0) 


* Map Society *

local subin "SOC"

local _subin_ = " " + "`subin'" +  " "

local subout "SOCIETY"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .) 

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'" 

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0) 

local subout "SOCIEDAD"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .) 

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'" 

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0) 

local subout "SOCIETE"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .) 

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0) 

local subout "STE"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map General *

local subin "GEN"

local _subin_ = " " + "`subin'" +  " "

local subout "GENERAL"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Enterprise *

local subin "ENTPR"

local _subin_ = " " + "`subin'" +  " "

local subout "ENTERPRISE"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)

local subout "ENTERPRISES"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


* Map Engineering *

local subin "ENG"

local _subin_ = " " + "`subin'" +  " "

local subout "ENGINEERING"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if fw == "`subout'"

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if (lw == "`subout'") & (oneword == 0)


  **********************************************
* Abbreviations - Many-word to One-word Mappings *
  **********************************************

* Map Health Care *

local subin "HEALTHCARE"

local _subin_ = " " + "`subin'" +  " "

local subout "HEALTH CARE"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if strpos(ps_name_clean, "`subout'") == 1

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if strpos(ps_name_clean, "`subout'") == length(ps_name_clean) - length("`sub_out'") + 1


* Map North America *

local subin "N AM"

local _subin_ = " " + "`subin'" +  " "

local subout "NORTH US" // NORTH AMERICA will have been changed to NORTH US above.

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .) 

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if strpos(ps_name_clean, "`subout'") == 1 

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if strpos(ps_name_clean, "`subout'") == length(ps_name_clean) - length("`sub_out'") + 1 

local subout "N US" // N AMERICA will have been changed to NORTH US above.

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .) 

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if strpos(ps_name_clean, "`subout'") == 1 

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if strpos(ps_name_clean, "`subout'") == length(ps_name_clean) - length("`sub_out'") + 1 


* Map United States of America *

local subin "US"

local _subin_ = " " + "`subin'" +  " "

local subout "UNITED STATES"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .) 

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if strpos(ps_name_clean, "`subout'") == 1

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if strpos(ps_name_clean, "`subout'") == length(ps_name_clean) - length("`sub_out'") + 1 

local subout "US OF US" // Previous edits will have transformed UNITED STATES OF AMERICA into UNITED STATES OF US. We rectify that here

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if strpos(ps_name_clean, "`subout'") == 1 

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if strpos(ps_name_clean, "`subout'") == length(ps_name_clean) - length("`sub_out'") + 1

local subout "OF US" // A company of the form DOG CAT OF AMERICA will have become DOG CAT OF US. We change that to DOG CAT US here

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if strpos(ps_name_clean, "`subout'") == 1

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if strpos(ps_name_clean, "`subout'") == length(ps_name_clean) - length("`sub_out'") + 1


* Map Real Estate *

local subin "RE"

local _subin_ = " " + "`subin'" +  " "

local subout "REAL ESTATE"

local _subout_ = " " + "`subout'" + " "

replace ps_name_clean = subinstr(ps_name_clean, "`_subout_'", "`_subin_'", .)

replace ps_name_clean = "`subin'" + substr(ps_name_clean, length("`subout'") + 1, .) if strpos(ps_name_clean, "`subout'") == 1

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("`subout'")) + "`subin'" if strpos(ps_name_clean, "`subout'") == length(ps_name_clean) - length("`sub_out'") + 1


  ***********************************
* Drop Dangling Terms and Empty Names *
  ***********************************
  
// Here we drop " AND" and " OF" from the end of company names 

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("AND")) if (lw == "AND") & (oneword == 0)

replace ps_name_clean = substr(ps_name_clean, 1, length(ps_name_clean) - length("OF")) if (lw == "OF") & (oneword == 0)


* Strip of Superfluous Whitespace Again *

replace ps_name_clean = stritrim(ps_name_clean) // Note the difference between functions stritrim and strtrim.


* Get Rid of Leading, Trailing Whitespace *

replace ps_name_clean = strtrim(ps_name_clean) // Note the difference between functions stritrim and strtrim.


  *******************************************
* Merge to Database A, Keep Only Merged Names *
  *******************************************
  
* Drop Extraneous Variables *

drop fw lw oneword


* Adjust Disambiguated Clean Names *

replace ps_name_clean = "HEIINC" if ps_name_clean == "HEI" // Disambiguated as "HEI" mapped to "HEI LTD" and "HEI CORP"

replace ps_name_clean = "TIVOCORP" if ps_name_clean == "TIVO" // Disambiguated as "TIVO" mapped to "TIVO CORP" and "TIVO INC"


* Merge to Database A *

rename ps_name_clean as_name_clean // For merge

joinby as_name_clean using "./outputs/003a_database_a.dta" // By default this only keeps merged observations

rename as_name_clean name_clean


* Drop Temporally Erroneous Observations *
  
drop if ps_date_1 > as_date_n_wide | ps_date_n < as_date_1_wide
  

* Export *

save "./outputs/003b_database_b1.dta", replace


******************************************
* DATABASE 2: PATENT-LEVEL CITATION DATA *
******************************************

* Import Patent Assignee Data *

use "./data/patent_assignee.dta", clear


* Drop Extraneous Variables *

drop location_id // We're not interested in location here.


* Get Fractional Share of Patent per Assignee *

bysort patent_id: gen fractional_share = 1/_N // For patents with multiple assignees, this gets the share of the patent belonging to each assignee.

label var fractional_share "Fractional share of patent attributable to assignee."


* Reduce to Patent Level *

// Since we want to weight forward citations of patents relative to their cohort (by year and NBER patent category), we need one observation per patent

drop assignee_id // Only variable varying at the patent level

duplicates drop


* Merge to Patent Date Data *

merge 1:1 patent_id using "./outputs/003b_patent_dates.dta"

drop if _merge != 3 // We can't use patents for which we have no dates.

drop _merge


* Merge to CPC Classification Data *

merge 1:m patent_id using "./data/cpc_classification.dta", keepusing(subsection_id sequence)

drop if _merge == 2 // We don't want classifications on patents for which we have no assignee data or dates.

drop if sequence != 0 // We only want the lead classification for each patent

gen cpc_1character = substr(subsection_id, 1, 1)

gen cpc_2character = substr(subsection_id, 1, 2)

label var cpc_1character "CPC classification, first character"

label var cpc_2character "CPC classification, first two characters"

drop _merge sequence subsection_id


* Merge to Citation Data *

merge 1:1 patent_id using "./outputs/001a_patent_forward_citations.dta"

drop if _merge == 2 // We don't want patents with citation numbers but no assignee or no dates

drop _merge


* Label Patents Not Merging to Citation Data as Having 0 Citations *

// Patents with 0 Citations do not exist in the Citation Data.

replace nr_forward_citations = 0 if missing(nr_forward_citations)


* Drop Get Year of Application *

gen year = yofd(application_date)


* Get Mean Number of Citations by Year * // Note that we do this by granting year - this is the year at which patent citations start to accumulate.

bysort year: egen year_mean_citations = mean(nr_forward_citations)


* Get Mean Number of Citations by Category *

bysort year cpc_1character: egen year_cat_mean_citations = mean(nr_forward_citations) if _N >= 50 & cpc_1character != "Y" // We only do this for year-categories with more than 50 patents. Y is a kind of 'miscellaneous' categorisation.


* Get Mean Number of Citations by Subcategory *

bysort year cpc_2character: egen year_cat_subcat_mean_citations = mean(nr_forward_citations) if _N >= 50 & cpc_1character != "Y"


* Get Weighted Number of Forward Citations *

gen weighted_forward_citations = nr_forward_citations/year_cat_subcat_mean_citations if !missing(year_cat_subcat_mean_citations) // Weighting for patents in year x CPC-2character with 50 or more patents.

replace weighted_forward_citations = nr_forward_citations/year_cat_mean_citations if !missing(year_cat_mean_citations) & missing(year_cat_subcat_mean_citations) // Backup weighting for patents in year x CPC-1characterwith 50 or more patents, but a year x NBER subcategory with less than 50 patents.

replace weighted_forward_citations = nr_forward_citations/year_mean_citations if missing(year_cat_mean_citations) & missing(year_cat_subcat_mean_citations) // Backup to backup weighting for patents in year x CPC-1character with less than 50 patents.

label var weighted_forward_citations "Nr. of forward citations divided by mean of most granular cohort w/ >=50 patents"

drop year year_mean_citations year_cat_mean_citations year_cat_subcat_mean_citations


* Get Fractional Weighted Number of Forward Citations *

gen frac_weighted_forward_citations = weighted_forward_citations*fractional_share

label var frac_weighted_forward_citations "Weighted number of forward citations divided by number of patent assignees"


* Merge Back to Patent-Assignee Mapping *

merge 1:m patent_id using "./data/patent_assignee.dta", keepusing(assignee_id)

drop if _merge != 3 // We can't use any patents which have either (1) no assignee data or (2) no citation data or (3) no date data.

drop _merge


* Drop Extraneous Variables, Reorder *

drop fractional_share granting_date cpc_1character cpc_2character

order assignee_id patent_id application_date nr_forward_citations weighted_forward_citations frac_weighted_forward_citations


* Export *

compress assignee_id patent_id nr_forward_citations weighted_forward_citations frac_weighted_forward_citations

save "./outputs/003b_database_b2.dta", replace


*************************
* CONSTRUCT DATABASE B3 *
*************************

* Import B1 *

use "./outputs/003b_database_b1.dta", clear


* Joinby with B2 *

joinby assignee_id using "./outputs/003b_database_b2.dta", unmatched(both)

tabulate _merge

keep if _merge == 3 // We only want patents we can map to gvkeys, and vice versa

drop _merge


* Drop Temporally Erroneous Patents *

drop if application_date < as_date_1_wide | application_date > as_date_n_wide // If the patent is assigned to the assignee ID at a time when the assignee_id does not map to the gvkey, we need to drop this.


* Drop Extraneous Variables *

keep gvkey patent_id application_date frac_weighted_forward_citations // All we need for B3 is an ecq count of fractional weighted patent citations.


* Collapse to the Monthly Level *

gen ecq_start_month = mofd(application_date) // We use the start month of the exact calendar quarter as our time variable

format ecq_start_month %tm

label var ecq_start_month "Starting month of exact calendar quarter"

collapse (sum) frac_weighted_forward_citations, by(gvkey ecq_start_month)


* Set Panel *

encode gvkey, gen(gvkey_enc) // We need a numeric for setting the panel

xtset gvkey_enc ecq_start_month


* Fill Panel *

// We do this to calculate sums for each gvkey

tsfill, full // Fill in gaps, creating a strongly balanced panel


* Populate Empty Panel Observations *

bysort gvkey_enc (gvkey): replace gvkey = gvkey[_N] // Here we populate the gvkey for the new observations; for string variables, missing values go to the *start* of an ordering

drop gvkey_enc // No longer needed

replace frac_weighted_forward_citations = 0 if missing(frac_weighted_forward_citations)


* Get *Quarterly* Value of Patent Counts *

bysort gvkey (ecq_start_month): gen ecq_patent_count = frac_weighted_forward_citations + frac_weighted_forward_citations[_n+1] + frac_weighted_forward_citations[_n+2]

drop if missing(ecq_patent_count) // We don't need these last two months - we don't have full data on the last two quarters that they are the starting month of


* Get Winsorised Quarterly Value of Patent Counts, Based on "Active Patenting Period" for Firms *

/* For winsorisation, we... 
(1) ...only count normal calendar quarters (Jan-Mar, Apr-Jun, etc.) as to not triple-count firm patenting
(2) ...only count quarters when the firm is "actively patenting" - the period from the firm's first patenting to last patenting
*/

bysort gvkey (ecq_start_month): egen first_patenting_ecqStartMonth = min((frac_weighted_forward_citations > 0)*ecq_start_month) // First ecq_start month for which firm patents (essentially two months before first patenting month)

bysort gvkey (ecq_start_month): egen last_patenting_ecqStartMonth = max((frac_weighted_forward_citations > 0)*ecq_start_month) // Last ecq_start month for which firm patents (essentially last patenting month)

gen active_patenting_ecq = (ecq_start_month >= first_patenting_ecqStartMonth & ecq_start_month <= last_patenting_ecqStartMonth) // Marks quarters as "active patenting" or not (note citationless patents don't count here). 

drop first_patenting_ecqStartMonth last_patenting_ecqStartMonth // No longer needed

_pctile ecq_patent_count if mod(ecq_start_month, 3) == 0 & active_patenting_ecq == 1, percentiles(1 99) // The mod Boolean checks the ecq corresponds to a standard quarter. Stores 1st percentile in `r(r1)' and 99th percentile in `r(r2)'

gen wins_ecq_patent_count = `r(r1)'*(ecq_patent_count < `r(r1)') + ecq_patent_count*(ecq_patent_count >= `r(r1)' & ecq_patent_count <= `r(r2)') + `r(r2)'*(ecq_patent_count > `r(r2)')  // Gets winsorised value

drop active_patenting_ecq frac_weighted_forward_citations // No longer needed


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

save "./outputs/003b_database_b3.dta", replace


*************
* POSTAMBLE *
*************

log close

exit