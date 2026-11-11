extends RefCounted
static func options() -> Dictionary:
	return {
		"rooms":{"shack":"res://examples/last_signal/rooms/shack/", "roof":"res://examples/last_signal/rooms/roof/"},
		"crew":{"rae":{"name":"RAE","color":Color("e4c458"),"sheet":"res://examples/last_signal/art/rae.svg","portrait":"res://examples/last_signal/art/portrait.svg","height":40,"start":{"room":"shack","pos":Vector2(160,132)},"abilities":[],"poke":"HELLO.","quips":["THAT WILL NOT FIX THE SIGNAL."]}},
		"roster":["rae"], "items":{"fuse":{"name":"FUSE","icon":"res://examples/last_signal/art/fuse.svg","hint":"A SPARE FUSE. THE RADIO MAY NEED IT."}},
		"npcs":{}, "world":[], "common_strings":"",
		"presentation":{"title":["THE LAST SIGNAL"],"demo_end":["SIGNAL RESTORED", "THANKS FOR PLAYING"]},
		"localization":{"languages":[["en","ENGLISH"]],"debug_locales":[]},
		"sounds":{"blip":"", "pickup":"", "door":"", "switch":""}}
