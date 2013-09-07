var/list/zones = list()
var/list/DoorDirections = list(NORTH,WEST) //Which directions doors turfs can connect to zones
var/list/CounterDoorDirections = list(SOUTH,EAST) //Which directions doors turfs can connect to zones

/zone
	var/dbg_output = 0 //Enables debug output.
	var/rebuild = 0 //If 1, zone will be rebuilt on next process. Not sure if used.
	var/datum/gas_mixture/air //The air contents of the zone.
	var/list/contents //All the tiles that are contained in this zone.
	var/list/unsimulated_tiles // Any space tiles in this list will cause air to flow out.

	var/list/connections //connection objects which refer to connections with other zones, e.g. through a door.
	var/list/direct_connections //connections which directly connect two zones.

	var/list/connected_zones //Parallels connections, but lists zones to which this one is connected and the number
							 //of points they're connected at.
	var/list/closed_connection_zones //Same as connected_zones, but for zones where the door or whatever is closed.

	var/last_update = 0
	var/progress = "nothing"


//CREATION AND DELETION
/zone/New(turf/start)
	. = ..()
	//Get the turfs that are part of the zone using a floodfill method
	if(istype(start,/list))
		contents = start
	else
		contents = FloodFill(start)

	//Change all the zone vars of the turfs, check for space to be added to unsimulated_tiles.
	for(var/turf/T in contents)
		if(T.zone && T.zone != src)
			T.zone.RemoveTurf(T)
		T.zone = src
		if(!istype(T,/turf/simulated))
			AddTurf(T)

	//Generate the gas_mixture for use in txhis zone by using the average of the gases
	//defined at startup.
	air = new
	air.group_multiplier = contents.len
	for(var/turf/simulated/T in contents)
		air.oxygen += T.oxygen / air.group_multiplier
		air.nitrogen += T.nitrogen / air.group_multiplier
		air.carbon_dioxide += T.carbon_dioxide / air.group_multiplier
		air.toxins += T.toxins / air.group_multiplier
		air.temperature += T.temperature / air.group_multiplier
	air.update_values()

	//Add this zone to the global list.
	zones.Add(src)


//DO NOT USE.  Use the SoftDelete proc.
/zone/Del()
	//Ensuring the zone list doesn't get clogged with null values.
	for(var/turf/simulated/T in contents)
		RemoveTurf(T)
		air_master.ReconsiderTileZone(T)
	for(var/zone/Z in connected_zones)
		if(src in Z.connected_zones)
			Z.connected_zones.Remove(src)
	air_master.AddConnectionToCheck(connections)
	zones.Remove(src)
	air = null
	. = ..()


//Handles deletion via garbage collection.
/zone/proc/SoftDelete()
	zones.Remove(src)
	air = null

	//Ensuring the zone list doesn't get clogged with null values.
	for(var/turf/simulated/T in contents)
		RemoveTurf(T)
		air_master.ReconsiderTileZone(T)

	//Removing zone connections and scheduling connection cleanup
	for(var/zone/Z in connected_zones)
		if(src in Z.connected_zones)
			Z.connected_zones.Remove(src)
	connected_zones = null

	air_master.AddConnectionToCheck(connections)
	connections = null

	return 1


//ZONE MANAGEMENT FUNCTIONS
/zone/proc/AddTurf(turf/T)
	//Adds the turf to contents, increases the size of the zone, and sets the zone var.
	if(istype(T, /turf/simulated))
		if(T in contents)
			return
		if(T.zone)
			T.zone.RemoveTurf(T)
		contents += T
		if(air)
			air.group_multiplier++

		T.zone = src

	else
		if(!unsimulated_tiles)
			unsimulated_tiles = list()
		else if(T in unsimulated_tiles)
			return
		unsimulated_tiles += T
		contents -= T

/zone/proc/RemoveTurf(turf/T)
	//Same, but in reverse.
	if(istype(T, /turf/simulated))
		if(!(T in contents))
			return
		contents -= T
		if(air)
			air.group_multiplier--

		if(T.zone == src)
			T.zone = null

		if(!contents.len)
			SoftDelete()

	else if(unsimulated_tiles)
		unsimulated_tiles -= T
		if(!unsimulated_tiles.len)
			unsimulated_tiles = null

  //////////////
 //PROCESSING//
//////////////

#define QUANTIZE(variable)		(round(variable,0.0001))

/zone/proc/process()
	. = 1

	progress = "problem with: SoftDelete()"

	//Deletes zone if empty.
	if(!contents.len)
		return SoftDelete()

	progress = "problem with: Rebuild()"

	//Does rebuilding stuff.
	if(rebuild)
		rebuild = 0
		Rebuild() //Shoving this into a proc.

	if(!contents.len) //If we got soft deleted.
		return

	progress = "problem with: air regeneration"

	//Sometimes explosions will cause the air to be deleted for some reason.
	if(!air)
		air = new()
		air.oxygen = MOLES_O2STANDARD
		air.nitrogen = MOLES_N2STANDARD
		air.temperature = T0C
		air.total_moles()
		world.log << "Air object lost in zone. Regenerating."


	progress = "problem with: ShareSpace()"

	if(unsimulated_tiles)
		if(locate(/turf/simulated) in unsimulated_tiles)
			for(var/turf/simulated/T in unsimulated_tiles)
				unsimulated_tiles -= T

		if(unsimulated_tiles.len)
			var/moved_air = ShareSpace(air,unsimulated_tiles)

			if(moved_air > vsc.airflow_lightest_pressure)
				AirflowSpace(src)
		else
			unsimulated_tiles = null

	//Check the graphic.
	progress = "problem with: modifying turf graphics"

	air.graphic = 0
	if(air.toxins > MOLES_PLASMA_VISIBLE)
		air.graphic = 1
	else if(air.trace_gases.len)
		var/datum/gas/sleeping_agent = locate(/datum/gas/sleeping_agent) in air.trace_gases
		if(sleeping_agent && (sleeping_agent.moles > 1))
			air.graphic = 2

	progress = "problem with an inbuilt byond function: some conditional checks"

	//Only run through the individual turfs if there's reason to.
	if(air.graphic != air.graphic_archived || air.temperature > PLASMA_FLASHPOINT)

		progress = "problem with: turf/simulated/update_visuals()"

		for(var/turf/simulated/S in contents)
			//Update overlays.
			if(air.graphic != air.graphic_archived)
				if(S.HasDoor(1))
					S.update_visuals()
				else
					S.update_visuals(air)

			progress = "problem with: item or turf temperature_expose()"

			//Expose stuff to extreme heat.
			if(air.temperature > PLASMA_FLASHPOINT)
				for(var/atom/movable/item in S)
					item.temperature_expose(air, air.temperature, CELL_VOLUME)
				S.hotspot_expose(air.temperature, CELL_VOLUME)

	progress = "problem with: calculating air graphic"

	//Archive graphic so we can know if it's different.
	air.graphic_archived = air.graphic

	progress = "problem with: calculating air temp"

	//Ensure temperature does not reach absolute zero.
	air.temperature = max(TCMB,air.temperature)

	progress = "problem with an inbuilt byond function: length(connections)"

	//Handle connections to other zones.
	if(length(connections))

		progress = "problem with: ZMerge(), a couple of misc procs"

		if(length(direct_connections))
			for(var/connection/C in connections)

				//Do merging if conditions are met. Specifically, if there's a non-door connection
				//to somewhere with space, the zones are merged regardless of equilibrium, to speed
				//up spacing in areas with double-plated windows.
				if(C.A.zone && C.B.zone)
					if(C.A.zone.air.compare(C.B.zone.air) || unsimulated_tiles)
						ZMerge(C.A.zone,C.B.zone)

		progress = "problem with: ShareRatio(), Airflow(), a couple of misc procs"

		//Share some
		for(var/zone/Z in connected_zones)
			//If that zone has already processed, skip it.
			if(Z.last_update > last_update)
				continue

			if(air && Z.air)
				//Ensure we're not doing pointless calculations on equilibrium zones.
				var/moles_delta = abs(air.total_moles() - Z.air.total_moles())
				if(moles_delta > 0.1 || abs(air.temperature - Z.air.temperature) > 0.1)
					if(abs(Z.air.return_pressure() - air.return_pressure()) > vsc.airflow_lightest_pressure)
						Airflow(src,Z)
					var/unsimulated_boost = 0
					if(unsimulated_tiles)
						unsimulated_boost += unsimulated_tiles.len
					if(Z.unsimulated_tiles)
						unsimulated_boost += Z.unsimulated_tiles.len
					unsimulated_boost = max(0, min(3, unsimulated_boost))
					ShareRatio( air , Z.air , connected_zones[Z] + unsimulated_boost)

		for(var/zone/Z in closed_connection_zones)
			//If that zone has already processed, skip it.
			if(Z.last_update > last_update)
				continue

			if(air && Z.air)
				if( abs(air.temperature - Z.air.temperature) > vsc.connection_temperature_delta )
					ShareHeat(air, Z.air, closed_connection_zones[Z])

	progress = "all components completed successfully, the problem is not here"

  ////////////////
 //Air Movement//
////////////////

var/list/sharing_lookup_table = list(0.30, 0.40, 0.48, 0.54, 0.60, 0.66)

proc/ShareRatio(datum/gas_mixture/A, datum/gas_mixture/B, connecting_tiles)
	//Shares a specific ratio of gas between mixtures using simple weighted averages.
	var
		//WOOT WOOT TOUCH THIS AND YOU ARE A RETARD
		ratio = sharing_lookup_table[6]
		//WOOT WOOT TOUCH THIS AND YOU ARE A RETARD

		size = max(1,A.group_multiplier)
		share_size = max(1,B.group_multiplier)

		full_oxy = A.oxygen * size
		full_nitro = A.nitrogen * size
		full_co2 = A.carbon_dioxide * size
		full_plasma = A.toxins * size

		full_heat_capacity = A.heat_capacity() * size

		s_full_oxy = B.oxygen * share_size
		s_full_nitro = B.nitrogen * share_size
		s_full_co2 = B.carbon_dioxide * share_size
		s_full_plasma = B.toxins * share_size

		s_full_heat_capacity = B.heat_capacity() * share_size

		oxy_avg = (full_oxy + s_full_oxy) / (size + share_size)
		nit_avg = (full_nitro + s_full_nitro) / (size + share_size)
		co2_avg = (full_co2 + s_full_co2) / (size + share_size)
		plasma_avg = (full_plasma + s_full_plasma) / (size + share_size)

		temp_avg = (A.temperature * full_heat_capacity + B.temperature * s_full_heat_capacity) / (full_heat_capacity + s_full_heat_capacity)

	//WOOT WOOT TOUCH THIS AND YOU ARE A RETARD
	if(sharing_lookup_table.len >= connecting_tiles) //6 or more interconnecting tiles will max at 42% of air moved per tick.
		ratio = sharing_lookup_table[connecting_tiles]
	//WOOT WOOT TOUCH THIS AND YOU ARE A RETARD

	A.oxygen = max(0, (A.oxygen - oxy_avg) * (1-ratio) + oxy_avg )
	A.nitrogen = max(0, (A.nitrogen - nit_avg) * (1-ratio) + nit_avg )
	A.carbon_dioxide = max(0, (A.carbon_dioxide - co2_avg) * (1-ratio) + co2_avg )
	A.toxins = max(0, (A.toxins - plasma_avg) * (1-ratio) + plasma_avg )

	A.temperature = max(0, (A.temperature - temp_avg) * (1-ratio) + temp_avg )

	B.oxygen = max(0, (B.oxygen - oxy_avg) * (1-ratio) + oxy_avg )
	B.nitrogen = max(0, (B.nitrogen - nit_avg) * (1-ratio) + nit_avg )
	B.carbon_dioxide = max(0, (B.carbon_dioxide - co2_avg) * (1-ratio) + co2_avg )
	B.toxins = max(0, (B.toxins - plasma_avg) * (1-ratio) + plasma_avg )

	B.temperature = max(0, (B.temperature - temp_avg) * (1-ratio) + temp_avg )

	for(var/datum/gas/G in A.trace_gases)
		var/datum/gas/H = locate(G.type) in B.trace_gases
		if(H)
			var/G_avg = (G.moles*size + H.moles*share_size) / (size+share_size)
			G.moles = (G.moles - G_avg) * (1-ratio) + G_avg
			H.moles = (H.moles - G_avg) * (1-ratio) + G_avg
		else
			H = new G.type
			B.trace_gases += H
			var/G_avg = (G.moles*size) / (size+share_size)
			G.moles = (G.moles - G_avg) * (1-ratio) + G_avg
			H.moles = (H.moles - G_avg) * (1-ratio) + G_avg

	A.update_values()
	B.update_values()

	if(A.compare(B)) return 1
	else return 0

proc/ShareSpace(datum/gas_mixture/A, list/unsimulated_tiles, dbg_output)
	//A modified version of ShareRatio for spacing gas at the same rate as if it were going into a large airless room.
	if(!unsimulated_tiles || !unsimulated_tiles.len)
		return 0

	var
		unsim_oxygen = 0
		unsim_nitrogen = 0
		unsim_co2 = 0
		unsim_plasma = 0
		unsim_heat_capacity = 0
		unsim_temperature = 0

		size = max(1,A.group_multiplier)

		// We use the same size for the potentially single space tile
		// as we use for the entire room. Why is this?
		// Short answer: We do not want larger rooms to depressurize more
		// slowly than small rooms, preserving our good old "hollywood-style"
		// oh-shit effect when large rooms get breached, but still having small
		// rooms remain pressurized for long enough to make escape possible.
		share_size = max(1, max(size + 3, 1) + unsimulated_tiles.len)
		correction_ratio = share_size / unsimulated_tiles.len

	for(var/turf/T in unsimulated_tiles)
		unsim_oxygen += T.oxygen
		unsim_co2 += T.carbon_dioxide
		unsim_nitrogen += T.nitrogen
		unsim_plasma += T.toxins
		unsim_temperature += T.temperature/unsimulated_tiles.len

	//These values require adjustment in order to properly represent a room of the specified size.
	unsim_oxygen *= correction_ratio
	unsim_co2 *= correction_ratio
	unsim_nitrogen *= correction_ratio
	unsim_plasma *= correction_ratio
	unsim_heat_capacity = HEAT_CAPACITY_CALCULATION(unsim_oxygen, unsim_co2, unsim_nitrogen, unsim_plasma)

	var
		ratio = sharing_lookup_table[6]

		old_pressure = A.return_pressure()

		full_oxy = A.oxygen * size
		full_nitro = A.nitrogen * size
		full_co2 = A.carbon_dioxide * size
		full_plasma = A.toxins * size

		full_heat_capacity = A.heat_capacity() * size

		oxy_avg = (full_oxy + unsim_oxygen) / (size + share_size)
		nit_avg = (full_nitro + unsim_nitrogen) / (size + share_size)
		co2_avg = (full_co2 + unsim_co2) / (size + share_size)
		plasma_avg = (full_plasma + unsim_plasma) / (size + share_size)

		temp_avg = 0

	if((full_heat_capacity + unsim_heat_capacity) > 0)
		temp_avg = (A.temperature * full_heat_capacity + unsim_temperature * unsim_heat_capacity) / (full_heat_capacity + unsim_heat_capacity)

	if(sharing_lookup_table.len >= unsimulated_tiles.len) //6 or more interconnecting tiles will max at 42% of air moved per tick.
		ratio = sharing_lookup_table[unsimulated_tiles.len]

	A.oxygen = max(0, (A.oxygen - oxy_avg) * (1 - ratio) + oxy_avg )
	A.nitrogen = max(0, (A.nitrogen - nit_avg) * (1 - ratio) + nit_avg )
	A.carbon_dioxide = max(0, (A.carbon_dioxide - co2_avg) * (1 - ratio) + co2_avg )
	A.toxins = max(0, (A.toxins - plasma_avg) * (1 - ratio) + plasma_avg )

	A.temperature = max(TCMB, (A.temperature - temp_avg) * (1 - ratio) + temp_avg )

	for(var/datum/gas/G in A.trace_gases)
		var/G_avg = (G.moles * size) / (size + share_size)
		G.moles = (G.moles - G_avg) * (1 - ratio) + G_avg

	A.update_values()

	return abs(old_pressure - A.return_pressure())


proc/ShareHeat(datum/gas_mixture/A, datum/gas_mixture/B, connecting_tiles)
	//Shares a specific ratio of gas between mixtures using simple weighted averages.
	var
		//WOOT WOOT TOUCH THIS AND YOU ARE A RETARD
		ratio = sharing_lookup_table[6]
		//WOOT WOOT TOUCH THIS AND YOU ARE A RETARD

		full_heat_capacity = A.heat_capacity()

		s_full_heat_capacity = B.heat_capacity()

		temp_avg = (A.temperature * full_heat_capacity + B.temperature * s_full_heat_capacity) / (full_heat_capacity + s_full_heat_capacity)

	//WOOT WOOT TOUCH THIS AND YOU ARE A RETARD
	if(sharing_lookup_table.len >= connecting_tiles) //6 or more interconnecting tiles will max at 42% of air moved per tick.
		ratio = sharing_lookup_table[connecting_tiles]
	//WOOT WOOT TOUCH THIS AND YOU ARE A RETARD

	//We need to adjust it to account for the insulation settings.
	ratio *= 1 - vsc.connection_insulation

	A.temperature = max(0, (A.temperature - temp_avg) * (1- (ratio / max(1,A.group_multiplier)) ) + temp_avg )
	B.temperature = max(0, (B.temperature - temp_avg) * (1- (ratio / max(1,B.group_multiplier)) ) + temp_avg )


  ///////////////////
 //Zone Rebuilding//
///////////////////
//Used for updating zone geometry when a zone is cut into two parts.

zone/proc/Rebuild()
	var/list/new_zone_contents = IsolateContents()
	if(new_zone_contents.len == 1)
		return

	var/list/current_contents
	var/list/new_zones = list()

	contents = new_zone_contents[1]
	air.group_multiplier = contents.len

	for(var/identifier in 2 to new_zone_contents.len)
		current_contents = new_zone_contents[identifier]
		var/zone/new_zone = new (current_contents)
		new_zone.air.copy_from(air)
		new_zones += new_zone

	for(var/connection/connection in connections)
		connection.Cleanup()

	var/turf/simulated/adjacent

	for(var/turf/unsimulated in unsimulated_tiles)
		for(var/direction in cardinal)
			adjacent = get_step(unsimulated, direction)

			if(istype(adjacent) && adjacent.CanPass(null, unsimulated, 0, 0))
				for(var/zone/zone in new_zones)
					if(adjacent in zone)
						zone.AddTurf(unsimulated)


//Implements a two-pass connected component labeling algorithm to determine if the zone is, in fact, split.

/zone/proc/IsolateContents()
	var/turf/simulated/current
	var/turf/simulated/adjacent
	var/list/current_adjacents = list()
	var/adjacent_id
	var/lowest_id

	var/list/identical_ids = list()
	var/turfs = contents.Copy()
	var/current_identifier = 1

	for(current in turfs)
		lowest_id = null
		current_adjacents = list()

		for(var/direction in current.air_check_directions)
			adjacent = get_step(current, direction)
			if(adjacent in turfs)
				current_adjacents += adjacent
				adjacent_id = turfs[adjacent]

				if(adjacent_id && (!lowest_id || adjacent_id < lowest_id))
					lowest_id = adjacent_id

		if(!lowest_id)
			lowest_id = current_identifier++

		for(adjacent in current_adjacents)
			adjacent_id = turfs[adjacent]
			if(adjacent_id)
				if(identical_ids.len < adjacent_id)
					identical_ids.len = adjacent_id

				identical_ids[adjacent_id] = lowest_id

			turfs[adjacent] = lowest_id
		turfs[current] = lowest_id

	var/list/final_arrangement = list()

	for(current in turfs)
		current_identifier = identical_ids[turfs[current]]

		if( current_identifier > final_arrangement.len )
			final_arrangement.len = current_identifier
			final_arrangement[current_identifier] = list(current)

		else
			final_arrangement[current_identifier] += current

	//lazy but fast
	final_arrangement.Remove(null)

	return final_arrangement


/*
	if(!RequiresRebuild())
		return

	//Choose a random turf and regenerate the zone from it.
	var/list/new_contents
	var/list/new_unsimulated

	var/list/turfs_needing_zones = list()

	var/list/zones_to_check_connections = list(src)

	if(!locate(/turf/simulated/floor) in contents)
		for(var/turf/simulated/turf in contents)
			air_master.ReconsiderTileZone(turf)
		return SoftDelete()

	var/turfs_to_ignore = list()
	if(direct_connections)
		for(var/connection/connection in direct_connections)
			if(connection.A.zone != src)
				turfs_to_ignore += A
			else if(connection.B.zone != src)
				turfs_to_ignore += B

	new_unsimulated = ( unsimulated_tiles ? unsimulated_tiles : list() )

	//Now, we have allocated the new turfs into proper lists, and we can start actually rebuilding.

	//If something isn't carried over, it will need a new zone.
	for(var/turf/T in contents)
		if(!(T in new_contents))
			RemoveTurf(T)
			turfs_needing_zones += T

	//Handle addition of new turfs
	for(var/turf/S in new_contents)
		if(!istype(S, /turf/simulated))
			new_unsimulated |= S
			new_contents.Remove(S)

		//If something new is added, we need to deal with it seperately.
		else if(!(S in contents) && istype(S, /turf/simulated))
			if(!(S.zone in zones_to_check_connections))
				zones_to_check_connections += S.zone

			S.zone.RemoveTurf(S)
			AddTurf(S)

	//Handle the addition of new unsimulated tiles.
	unsimulated_tiles = null

	if(new_unsimulated.len)
		for(var/turf/S in new_unsimulated)
			if(istype(S, /turf/simulated))
				continue
			for(var/direction in cardinal)
				var/turf/simulated/T = get_step(S,direction)
				if(istype(T) && T.zone && S.CanPass(null, T, 0, 0))
					T.zone.AddTurf(S)

	//Finally, handle the orphaned turfs

	for(var/turf/simulated/T in turfs_needing_zones)
		if(!T.zone)
			zones_to_check_connections += new /zone(T)

	for(var/zone/zone in zones_to_check_connections)
		for(var/connection/C in zone.connections)
			C.Cleanup()*/

