GLOBAL_DATUM_INIT(thralls, /datum/antagonist/thrall, new)

/datum/antagonist/thrall
	id = MODE_THRALL
	role_text = "Thrall"
	role_text_plural = "Thralls"
	feedback_tag = "thrall_objective"
	blacklisted_jobs = list(/datum/job/ai, /datum/job/cyborg, /datum/job/chaplain)
	welcome_text = "You are a vampire's thrall: a pawn to be commanded by them at will."
	antaghud_indicator = "hudthrall"

/datum/antagonist/thrall/Initialize()
	. = ..()
	if(config.game.thrall_min_age)
		min_player_age = config.game.thrall_min_age

/datum/antagonist/thrall/update_antag_mob(datum/mind/player)
	..()
	player.current.make_vampire_thrall()
