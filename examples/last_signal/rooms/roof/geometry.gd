extends RefCounted
const DATA={"id":"roof","name":"ROOF","location_name":"ROOF","width":320,"music":"","bg":"res://examples/last_signal/rooms/roof/bg.svg",
	"walk_boxes":[Rect2i(10,116,300,30)], "props":[], "anchors":{}, "distinct":[],
	"hotspots":[
		{"id":"stairs","name":"RADIO SHACK","rect":Rect2(25,65,45,51),"walk":Vector2(48,130),"face":"back","prop":""},
		{"id":"beacon","name":"BEACON","rect":Rect2(220,30,40,80),"walk":Vector2(240,130),"face":"back","prop":""}],
	"entries":{"stairs":{"pos":Vector2(48,130),"room":"shack","entry":"door","hotspot":"stairs"}}}
