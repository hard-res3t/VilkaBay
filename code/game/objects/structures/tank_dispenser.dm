/obj/structure/dispenser
	name = "tank storage unit"
	desc = "A simple yet bulky storage device for gas tanks. Has room for up to ten oxygen tanks, and ten plasma tanks."
	icon = 'icons/obj/objects.dmi'
	icon_state = "dispenser"
	density = 1
	anchored = 1.0
	w_class = ITEM_SIZE_NO_CONTAINER
	var/oxygentanks = 10
	var/plasmatanks = 10
	var/list/oxytanks = list()	//sorry for the similar var names
	var/list/platanks = list()

	var/static/radial_oxygen = image(icon = 'icons/hud/radial.dmi', icon_state = "oxygen")
	var/static/radial_plasma = image(icon = 'icons/hud/radial.dmi', icon_state = "plasma")

	// we show the button even if the proc will not work
	var/static/list/radial_options = list("dispence oxygen" = radial_oxygen, "dispence plasma" = radial_plasma)
	var/static/list/ai_radial_options = list("dispence oxygen" = radial_oxygen, "dispence plasma" = radial_plasma)

/obj/structure/dispenser/oxygen
	plasmatanks = 0

/obj/structure/dispenser/plasma
	oxygentanks = 0

/obj/structure/dispenser/Initialize()
	. = ..()
	update_icon()

/obj/structure/dispenser/on_update_icon()
	ClearOverlays()
	switch(oxygentanks)
		if(1 to 3)	AddOverlays("oxygen-[oxygentanks]")
		if(4 to INFINITY) AddOverlays("oxygen-4")
	switch(plasmatanks)
		if(1 to 4)	AddOverlays("plasma-[plasmatanks]")
		if(5 to INFINITY) AddOverlays("plasma-5")

/obj/structure/dispenser/attack_ai(mob/user)
	if(user.Adjacent(src))
		return attack_hand(user)
	..()

/obj/structure/dispenser/attack_hand(mob/user)
	user.set_machine(src)
	add_fingerprint(user)
	interact(user)

/obj/structure/dispenser/interact(mob/user)
	if(user.stat || user.restrained())
		return

	var/list/complete_options = radial_options.Copy()
	var/list/ai_complete_options = ai_radial_options.Copy()

	if(!plasmatanks)
		complete_options.Remove("dispence plasma")
		ai_complete_options.Remove("dispence plasma")

	if(!oxygentanks)
		complete_options.Remove("dispence oxygen")
		ai_complete_options.Remove("dispence oxygen")

	var/choice = show_radial_menu(user, src, isAI(user) ? ai_complete_options : complete_options, require_near = !issilicon(user))

	switch(choice)
		if("dispence oxygen")
			dispence_oxygen(user)
		if("dispence plasma")
			dispence_plasma(user)

/obj/structure/dispenser/attackby(obj/item/I, mob/user)
	if(istype(I, /obj/item/tank/oxygen) || istype(I, /obj/item/tank/air) || istype(I, /obj/item/tank/anesthetic))
		if(oxygentanks < 10)
			if(!user.drop(I, src))
				return
			oxytanks.Add(I)
			oxygentanks++
			to_chat(user, "<span class='notice'>You put [I] in [src].</span>")
			if(oxygentanks < 5)
				update_icon()
		else
			to_chat(user, "<span class='notice'>[src] is full.</span>")
		return
	if(istype(I, /obj/item/tank/plasma))
		if(plasmatanks < 10)
			if(!user.drop(I, src))
				return
			platanks.Add(I)
			plasmatanks++
			to_chat(user, "<span class='notice'>You put [I] in [src].</span>")
			if(oxygentanks < 6)
				update_icon()
		else
			to_chat(user, "<span class='notice'>[src] is full.</span>")
		return
	if(isWrench(I))
		if(anchored)
			to_chat(user, "<span class='notice'>You lean down and unwrench [src].</span>")
			anchored = 0
		else
			to_chat(user, "<span class='notice'>You wrench [src] into place.</span>")
			anchored = 1
		return

/obj/structure/dispenser/proc/dispence_oxygen(mob/user)
	if(oxygentanks)
		var/obj/item/tank/oxygen/O
		if(oxytanks.len == oxygentanks)
			O = oxytanks[1]
			oxytanks.Remove(O)
		else
			O = new /obj/item/tank/oxygen(loc)
		O.dropInto(loc)
		to_chat(user, "<span class='notice'>You take [O] out of [src].</span>")
		oxygentanks--
		update_icon()

/obj/structure/dispenser/proc/dispence_plasma(mob/user)
	if(plasmatanks)
		var/obj/item/tank/plasma/P
		if(platanks.len == plasmatanks)
			P = platanks[1]
			platanks.Remove(P)
		else
			P = new /obj/item/tank/plasma(loc)
		P.dropInto(loc)
		to_chat(user, "<span class='notice'>You take [P] out of [src].</span>")
		plasmatanks--
		update_icon()
