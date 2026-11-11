extends RefCounted
const DATA={"id":"shack","name":"RADIO SHACK","location_name":"RADIO SHACK","width":320,"music":"","bg":"res://examples/last_signal/rooms/shack/bg.svg",
	"walk_boxes":[Rect2i(10,116,300,30)], "props":[], "anchors":{}, "distinct":[],
	"hotspots":[
		{"id":"drawer","name":"DRAWER","rect":Rect2(28,75,55,36),"walk":Vector2(55,130),"face":"back","prop":""},
		{"id":"radio","name":"RADIO","rect":Rect2(112,65,65,45),"walk":Vector2(145,130),"face":"back","prop":""},
		{"id":"door","name":"ROOF STAIRS","rect":Rect2(250,40,45,76),"walk":Vector2(272,130),"face":"back","prop":""}],
	"entries":{"door":{"pos":Vector2(272,130),"room":"roof","entry":"stairs","hotspot":"door"}}}
