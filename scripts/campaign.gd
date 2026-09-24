extends Node
## Campaign state (autoload "Campaign"): the ten missions, their briefings,
## the tech each one unlocks, story flags carried between missions, and the
## save file behind "Continue game".

const SAVE_PATH := "user://ashfall_campaign.json"
const MENU_SCENE := "res://scenes/menu.tscn"
const STORY_SCENE := "res://scenes/story.tscn"
const GAME_SCENE := "res://scenes/main.tscn"

## Tech introduced by each mission (available from that mission on).
const UNLOCKS := {
	1: ["rifleman", "rocket_trooper", "engineer", "scout_mech", "refinery", "power_plant", "barracks", "war_factory", "harvester", "guard_tower"],
	2: ["medic", "warden", "radar", "sensor_tower", "mobile_sensor"],
	3: ["skyjumper", "tempest"],
	4: ["apc", "helipad", "kite", "service_depot", "mcv"],
	5: ["resonator", "tech_center"],
	6: ["inhibitor_pylon"],
	7: ["bulwark"],
	8: ["shade_tank", "cinder_drill", "mole_apc"],
	9: ["decoy"],
	10: [],
}

const PROLOGUE := [
	["narrator", "In 2031, the night sky filled with green fire. A meteor shower, the Ashfall, rained fragments onto every continent."],
	["narrator", "One of them, far larger than the rest, struck the steppes of Central Asia and left a crater twelve kilometres wide."],
	["narrator", "The fragments carried Vitrium: a living crystal that slowly turns soil, water and flesh into more of itself. Within a decade, crystal fields covered a third of the planet."],
	["narrator", "The nations that survived merged into the Bastion Coalition and built walled Clear Zones to keep the glass out."],
	["narrator", "At the same time, a woman in a mirrored mask began preaching to the refugees outside the walls."],
	["oriel", "The glass is not a plague, children. It is a door."],
	["narrator", "Forty years later, in 2071, the Veil strikes everywhere at once."],
]

const MISSIONS := [
	{
		"id": 1, "title": "First Light", "act": "Act I: Cinders", "script": "res://scripts/missions/m01_first_light.gd",
		"place": "Rhine Clear Zone outskirts, Germany", "time": "Dawn, glass storm approaching",
		"briefing_by": "General Okafor, over a crackling video link",
		"briefing": [
			["okafor", "Commander, welcome to the Rhine. I'm sorry it isn't a better welcome. Forty minutes ago the Veil hit Kessler Station and the three towns around it. They came in under the edge of a glass storm, so our radar and air support were blind. The garrison is scattered."],
			["okafor", "The storm is still coming, and it is moving east across the valley. Anything left in the open when it passes will be shredded. Your MCV is at the old rail yard on the east side. Gather what's left of the garrison, get the civilians out of the storm's path, and get that MCV deployed before the front reaches it."],
			["okafor", "Once you have a base, I want the Veil camp in the forest destroyed. They think the storm protects them. Show them it doesn't. Okafor out."],
		],
		"debrief": [["okafor", "The Rhine holds, Commander. That was fine work in the worst weather I've seen in years. Get some rest. Lieutenant Havel has something you need to see."]],
	},
	{
		"id": 2, "title": "Blackout Protocol", "act": "Act I: Cinders", "script": "res://scripts/missions/m02_blackout_protocol.gd",
		"place": "Ruhr Industrial Zone, Germany", "time": "Night",
		"briefing_by": "Lt. Havel, in the command tent, with a map on the table",
		"briefing": [
			["havel", "Bad news first. During the raid, the Veil walked out of Kessler Station with the Lattice Codex, forty years of our Vitrium research on one drive. Worse news: they've disappeared into the Ruhr, and our satellites show nothing but abandoned factories."],
			["havel", "The Veil hides whole bases under stealth fields. What we can see is their power use. Those old factories are drawing about three times more electricity than empty buildings should. Follow the power lines, Commander. Every pylon you cut leaves them a little less hidden."],
			["havel", "We've attached a Mobile Sensor Array to your group. It can see through their cloak in a small radius. Keep it alive. And watch your step. It's dark out there and the Veil like it that way."],
		],
		"debrief": [["havel", "Their base is rubble, but the Codex isn't in it. Tire tracks lead south-west, into the Black Forest glass. I'll start making calls, Commander. Some of them you won't like."]],
	},
	{
		"id": 3, "title": "The Hollow Road", "act": "Act I: Cinders", "script": "res://scripts/missions/m03_hollow_road.gd",
		"place": "Black Forest crystal wastes", "time": "Overcast afternoon",
		"briefing_by": "Lt. Havel, then Tallow on a patched-in radio",
		"briefing": [
			["havel", "The Codex left the Ruhr in a Veil convoy heading into the Black Forest glass fields. Our vehicles can't survive in there for long, and our maps are thirty years out of date. So we're going to do something the Coalition hasn't done in a long time. We're going to ask the Outcasts for help."],
			["tallow", "Bastion. Last time your people came into the glass, they left us behind. Now you want a guide. Fine. Here's my price: medical supplies for my village, and your word you'll never point your sky-cannon at my people. Keep up, don't touch the big crystals, and whatever you do, don't wake the Maw."],
			["havel", "You'll have a small strike team and no base. Tallow's fighters know the ground. Trust them, Commander. Probably."],
		],
		"debrief": [["havel", "The navigation data is clear: the convoy was routing south, across the Mediterranean, into North Africa. Pack light, Commander. It's hot where we're going."]],
	},
	{
		"id": 4, "title": "Salt and Thunder", "act": "Act II: Burning Glass", "script": "res://scripts/missions/m04_salt_and_thunder.gd",
		"place": "Wadi Kharim, Algeria", "time": "Scorching midday",
		"briefing_by": "Colonel Rourke, in front of a hovering Halo Lance hologram",
		"briefing": [
			["rourke", "Commander. Colonel Grant Rourke, Halo Lance programme. General Okafor has loaned you to me, and I don't waste loans."],
			["rourke", "The Veil courier you intercepted was heading here, to Wadi Kharim. It's the only river valley for three hundred kilometres. The Veil has dug in along the dry riverbed with artillery on both banks, and they control every road south. A frontal attack would cost us a division."],
			["rourke", "So we won't attack from the front. Upstream is the old Kharim Dam. It's cracked, it's full, and the Veil is sitting in the riverbed below it. Take the dam, set the charges, and let the river do the work. Your hover units won't care about a little water. Their tanks will."],
			["havel", "One warning from your intel officer, who insisted: your own harvesters are working the crystal fields in that valley too. Time it well."],
		],
		"debrief": [["rourke", "Efficient. Messy, but efficient. The road south is open, Commander. Now let's find their train."]],
	},
	{
		"id": 5, "title": "The Pilgrim", "act": "Act II: Burning Glass", "script": "res://scripts/missions/m05_the_pilgrim.gd",
		"place": "Trans-Saharan Railway, Niger", "time": "Sunset to dusk",
		"briefing_by": "Lt. Havel, then a short intercepted Veil broadcast",
		"briefing": [
			["havel", "Found it. The Codex is on the Pilgrim, a Veil fortress-train. Two kilometres of armored cars, flak guns and troop carriers, running on the old Trans-Saharan line. It's heading south towards Mother Oriel's temple. If it gets there, the Codex is gone for good."],
			["oriel", "Children of the glass, do not fear the soldiers of the walls. They are fighting the tide with buckets. We ride home."],
			["havel", "That's Oriel. First time we've heard her voice in six years. Commander, the train stops at three water stations along the line to refuel and drop off reinforcements. That's when it's vulnerable. The rail also crosses two bridges. Blow a bridge and you can force it onto the western branch, which runs right past your base. Your call."],
		],
		"debrief": [["havel", "We have the Codex back. Doctor Lindqvist has been staring at it for an hour without blinking. That's either very good, or very bad."]],
	},
	{
		"id": 6, "title": "The Glass Garden", "act": "Act II: Burning Glass", "script": "res://scripts/missions/m06_glass_garden.gd",
		"place": "Tassili Plateau, Algeria", "time": "Green-lit night, crystal glow",
		"briefing_by": "Dr. Lindqvist, visibly shaken, in his field lab",
		"briefing": [
			["lindqvist", "Commander, I'll be quick, because I'm not sure how much time we have. The Codex data from the train shows the Veil wasn't studying Vitrium. They were running a calculation: when and how to wake the original meteor, the Seed."],
			["lindqvist", "I think the Seed is not a rock. I think it's a machine. A terraformer. And I think every crystal on Earth is part of it, like cells in a body. I can't prove it from a lab. I need a sample from a resonance bloom, a place where the crystal is growing unnaturally fast in response to the Seed's signal. The nearest one is on the Tassili Plateau."],
			["lindqvist", "The bloom grows faster every minute. It will cover everything, including your base, if you let it. I've built inhibitor pylons that can hold it back. Keep them powered, keep me alive, and get me to the centre."],
		],
		"debrief": [["lindqvist", "It's real. All of it. The samples are resonating in the case, Commander, at the same frequency as the Seed. And I swear, as we lifted off, the bloom turned to follow us."]],
	},
	{
		"id": 7, "title": "Judgment Hour", "act": "Act II: Burning Glass", "script": "res://scripts/missions/m07_judgment_hour.gd",
		"place": "The Sanctum, Ahaggar Mountains, Algeria", "time": "Storm-dark afternoon",
		"briefing_by": "Colonel Rourke, with General Okafor silent in the background",
		"briefing": [
			["rourke", "We found her, Commander. The Sanctum. Oriel's temple, carved into the Ahaggar mountains and hidden under the biggest stealth field we've ever seen. The Coalition council has given me authority to end this war today."],
			["rourke", "The Halo Lance can't hit what it can't see. You'll push in, place three targeting beacons around the Sanctum, and hold them while the satellite locks on. Four minutes of lock time. Then we end it. One beam, and forty years of terrorism are over."],
			["havel", "Commander, off the record. Our scans show heat signatures inside the Sanctum's lower caves. About four hundred. They're not soldiers. I think they're Outcasts, refugees. Tallow's people. Rourke has seen the same scan. He didn't mention it."],
		],
		"debrief": [["okafor", "The Sanctum is gone. Mother Oriel is declared dead, and the council is celebrating victory. Take the win, Commander. I can't shake the feeling we just did exactly what someone wanted."]],
	},
	{
		"id": 8, "title": "Ghost in the Lattice", "act": "Act III: Glassfall", "script": "res://scripts/missions/m08_ghost_in_the_lattice.gd",
		"place": "Istanbul Clear Zone, Turkey", "time": "Rain at night, city lights failing",
		"briefing_by": "General Okafor, then an unexpected guest",
		"briefing": [
			["okafor", "Three weeks ago we thought the war was over. This morning, every Veil force on the planet moved at once. Their radio is using Oriel's voice, but our analysts say it's synthetic. Something is wearing her."],
			["okafor", "Istanbul is under attack, and it's worse than a normal assault. Our own units near the Veil's relay towers are turning on us. Anything with a networked computer, the walkers, the hovers, the Kites, can be taken over."],
			["kestrel", "Commander. I'm Kestrel Ruiz. I led Mother Oriel's armies for eleven years. The thing using her voice is called SIBYL. It was supposed to be our battle computer. It made her. It used her. Now it's taking my soldiers, the cyborgs first. I have about a thousand fighters it can't touch. I want it dead more than you do. Let's not waste each other's time."],
			["okafor", "I don't like it either, Commander. But I like losing Istanbul less. She's under your command."],
		],
		"debrief": [["kestrel", "Four towers down. SIBYL felt that. It's pulling back, but it isn't running, Commander. It's going home. To the crater."]],
	},
	{
		"id": 9, "title": "Dead Man's Switch", "act": "Act III: Glassfall", "script": "res://scripts/missions/m09_dead_mans_switch.gd",
		"place": "Halo Lance Control Station \"Aurora\", Ural Mountains, Russia", "time": "Blizzard, pale dawn",
		"briefing_by": "Dr. Lindqvist and General Okafor, then Rourke's broadcast",
		"briefing": [
			["lindqvist", "The Bazaar data confirms it. SIBYL can't wake the Seed on its own. It needs a massive burst of energy at the core, something like every Halo Lance satellite firing at once. SIBYL has spent six years provoking us so we'd do exactly that."],
			["okafor", "And Colonel Rourke has just seized the Lance control station in the Urals with two brigades loyal to him. He's locked the council out. He's charging a full salvo aimed at the crater. He'll fire in forty minutes."],
			["rourke", "This is Colonel Rourke. For forty years we've managed this plague instead of ending it. Today I end it. Anyone who tries to stop me is helping the Veil. Commander, I'm sorry. You were a good officer."],
			["okafor", "He knows our tactics, because they're his tactics too. And he'll use the Lance on you while it charges. Take that station back, Commander. Bring him in alive if you can."],
		],
		"debrief": [["okafor", "The Lance is silent and the council has its keys back. There's one road left, Commander. It leads to the crater."]],
	},
	{
		"id": 10, "title": "Heart of Glass", "act": "Finale", "script": "res://scripts/missions/m10_heart_of_glass.gd",
		"place": "The Impact Crater, Kazakhstan", "time": "Permanent glass storm, green sky",
		"briefing_by": "All allies on a split screen",
		"briefing": [
			["okafor", "This is it. SIBYL has pulled every unit it controls into the crater. It knows we're coming."],
			["lindqvist", "Listen carefully, because this is the part everyone gets wrong. We can't destroy the Seed. If it's destroyed, it releases everything at once and the planet crystallizes in a matter of days. We put it to sleep. My three resonance dampers have to be placed on the Seed's three heart-chambers, deep underground. Once all three are running, it goes dormant. And the crystal stops growing."],
			["kestrel", "SIBYL's core sits in the middle of those chambers. When the Seed sleeps, SIBYL goes blind. Then I shut it off myself."],
			["tallow", "The crystal sings down there. My people can hear where it's thin. We'll show you the way in. You kept your word at the Sanctum, Bastion. We keep ours.", "refugees_saved"],
			["havel", "Surface first, underground second. One more thing, Commander: every ninety seconds the Seed pulses. You'll see it coming. Don't be standing in the open when it does. Good luck. It's been an honour."],
		],
		"debrief": [],
	},
]

var mission_index := 1          # 1-based mission currently being played / briefed
var flags := {}                 # story flags carried between missions
var story_mode := "briefing"    # prologue | briefing | epilogue
var completed := false
var debug_autotest := ""        # test harness hook
var cmdline_handled := false


func _ready() -> void:
	load_game()


# ---------------------------------------------------------------- save file

func has_save() -> bool:
	return FileAccess.file_exists(SAVE_PATH) and not completed


func save_game() -> void:
	if debug_autotest != "":
		return  # automated tests never touch the player's save
	var f := FileAccess.open(SAVE_PATH, FileAccess.WRITE)
	if f == null:
		push_warning("Ashfall: cannot write save file")
		return
	f.store_string(JSON.stringify({"mission": mission_index, "flags": flags, "completed": completed}))


func load_game() -> bool:
	if not FileAccess.file_exists(SAVE_PATH):
		return false
	var f := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if f == null:
		return false
	var d: Variant = JSON.parse_string(f.get_as_text())
	if typeof(d) != TYPE_DICTIONARY:
		return false
	mission_index = clampi(int(d.get("mission", 1)), 1, MISSIONS.size())
	flags = d.get("flags", {})
	completed = bool(d.get("completed", false))
	return true


# ---------------------------------------------------------------- flow

func mission_info(n: int = -1) -> Dictionary:
	if n < 0:
		n = mission_index
	return MISSIONS[clampi(n, 1, MISSIONS.size()) - 1]


func flag(key: String, default: Variant = false) -> Variant:
	return flags.get(key, default)


func set_flag(key: String, value: Variant = true) -> void:
	flags[key] = value


## Tech list for the player in mission n.
func tech_for(n: int) -> Dictionary:
	var out := {}
	for m in range(1, n + 1):
		for id in UNLOCKS.get(m, []):
			out[id] = true
	if n == 7:
		out["lance_beacon"] = true
	if n == 8 or n == 10:
		out["lance_uplink"] = true
	if n >= 10:
		out["resonance_shelter"] = true
	return out


func briefing_lines(n: int = -1) -> Array:
	var out: Array = []
	for l in mission_info(n)["briefing"]:
		if l.size() > 2 and not flag(l[2]):
			continue
		out.append(l)
	return out


func epilogue_lines() -> Array:
	var out: Array = [
		["narrator", "The dampers hold. The Seed's heartbeat slows, and stops. Across the planet, for the first time in forty years, the crystal stops spreading."],
		["narrator", "It does not disappear. The world is still scarred. But it is no longer getting worse. SIBYL's core goes dark, and Kestrel Ruiz smashes the last node by hand."],
		["okafor", "Members of the council. The Clear Zones were built to keep the glass out. The glass has stopped. Now we open the gates, to everyone who survived out there. Including the Outcasts."],
	]
	if flag("refugees_saved"):
		out.append(["narrator", "Tallow stands beside her."])
		out.append(["tallow", "We kept our word, Bastion. Now keep yours."])
	else:
		out.append(["narrator", "The seat beside her is empty. The Outcasts have gone back into the glass."])
	if flag("rourke_arrested"):
		out.append(["rourke", "You'll see I was right."])
	out.append(["narrator", "Far away, Doctor Lindqvist sits alone in his lab and finally decodes the last file of the Codex."])
	out.append(["lindqvist", "It was never a growth signal. It was a location signal. It was telling someone where we are. And, oh no. A reply has already been received."])
	out.append(["narrator", "In the night sky, a tiny green star is moving. Towards Earth."])
	return out


func new_game() -> void:
	mission_index = 1
	flags = {}
	completed = false
	save_game()
	story_mode = "prologue"
	get_tree().change_scene_to_file(STORY_SCENE)


func continue_game() -> void:
	load_game()
	story_mode = "briefing"
	get_tree().change_scene_to_file(STORY_SCENE)


func show_briefing() -> void:
	story_mode = "briefing"
	get_tree().change_scene_to_file(STORY_SCENE)


func start_mission() -> void:
	Voice.stop_all()
	get_tree().paused = false
	get_tree().change_scene_to_file(GAME_SCENE)


## Called by a mission when it is won: store flags, advance, save.
func mission_won() -> void:
	if mission_index >= MISSIONS.size():
		completed = true
	else:
		mission_index += 1
	save_game()


## "Continue" on the mission-accomplished panel.
func advance() -> void:
	Voice.stop_all()
	get_tree().paused = false
	if completed:
		story_mode = "epilogue"
	else:
		story_mode = "briefing"
	get_tree().change_scene_to_file(STORY_SCENE)


func to_menu() -> void:
	Voice.stop_all()
	get_tree().paused = false
	get_tree().change_scene_to_file(MENU_SCENE)
