class_name DayRules
extends RefCounted
## Data-driven difficulty curve. Each day turns on more checks; the generator
## and the desk UI both read from here, so adding a rule = adding a flag.

const LAST_DAY := 7
const DAY_LENGTH_SECONDS := 240.0   # real seconds from 08:00 to 18:00
const START_ORDINAL := 69           # day-of-year; day 1 is "11 MAR"
const MONTHS := ["JAN", "FEB", "MAR", "APR", "MAY", "JUN", "JUL", "AUG", "SEP", "OCT", "NOV", "DEC"]
const MONTH_LEN := [31, 28, 31, 30, 31, 30, 31, 31, 30, 31, 30, 31]

static func for_day(day: int, bonus_guests: int = 0) -> Dictionary:
	var r := {
		"day": day,
		"guests": 5 + maxi(bonus_guests, 0), # guests in line per day (+ Word of Mouth bonus)
		"wolf_chance": 0.15 + day * 0.03,  # chance a guest is a wolf in disguise
		"sloppy_chance": 0.12,             # chance an honest sheep has bad papers anyway
		"check_booking": true,             # ID vs today's database
		"check_region": true,
		"check_species": true,
		"check_health": day >= 2,          # health certificate + vaccines
		"scanner": day >= 3,               # paid instant wolf scanner
		"scanner_cost": 100,
		"scanner_cost_step": 75,
		"check_id_expiry": day >= 4,
		"check_voucher": day >= 5,         # booking voucher: room + nights
		"check_face": day >= 6,            # ID photo vs the guest's face
		"quota": 0,                         # set below from expected valid guests
		"required_vaccines": ["Rabies"],
		"news": "",
	}
	match day:
		1: r.news = "Welcome! Match each ID with today's bookings on the computer.
Find Rulebook bottom right for help."
		
		2:
			r.required_vaccines = ["Rabies", "Scrapie"]
			r.news = "Health inspectors are in town. Guests need a Health Certificate.
Find Rulebook bottom right for help."
		3:
			r.required_vaccines = ["Rabies", "Scrapie", "Anthrax"]
			r.news = "New gadget: the Wolf Scanner. It costs money per scan.
Find Rulebook bottom right for help."
		4:
			r.required_vaccines = ["Rabies", "Anthrax"]
			r.news = "Expired ID cards are no longer accepted.
Find Rulebook bottom right for help."
		5:
			r.required_vaccines = ["Rabies", "Scrapie", "Anthrax"]
			r.news = "Guests must bring a Booking Voucher matching the reservation.
Find Rulebook bottom right for help."
		6:
			r.required_vaccines = ["Rabies", "Scrapie", "Anthrax", "Bluetongue"]
			r.news = "Wolves are forging ID photos. Guest's face must match on ID.
Find Rulebook bottom right for help."
		7:
			r.required_vaccines = ["Rabies", "Scrapie", "Anthrax", "Bluetongue"]
			r.wolf_chance = 0.45
			r.news = "Full moon tonight. Trust no one."
	# Boss wants ~75% of the honest guests he can reasonably expect.
	r.quota = int(r.guests * (1.0 - r.wolf_chance) * (1.0 - r.sloppy_chance) * 0.75)
	return r

## Dates are day-of-year ints so "is it expired?" is a plain comparison.
static func today(day: int) -> int:
	return START_ORDINAL + day

static func format_date(ordinal: int) -> String:
	var d := clampi(ordinal, 1, 365)
	var m := 0
	while d > MONTH_LEN[m]:
		d -= MONTH_LEN[m]
		m += 1
	return "%02d %s" % [d, MONTHS[m]]
