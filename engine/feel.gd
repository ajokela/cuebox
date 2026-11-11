extends RefCounted

# Every number that gives the game its awkward 8-bit feel. Constants only.

# walking
const STEP_TIME := 0.125
const STEP_X := 6
const STEP_Y := 3

# camera lurch
const CAM_STEP := 8
const CAM_TICK := 1.0 / 12.0
const CAM_EDGE_LO := 0.3
const CAM_EDGE_HI := 0.7

# speech
const WRAP_CHARS := 26
const SPEECH_BASE := 0.9
const SPEECH_PER_CHAR := 0.055
const SPEECH_GAP := 0.08
const MOUTH_MIN := 0.07
const MOUTH_MAX := 0.18

# actions and room changes
const USE_PAUSE := 0.15
const DOOR_BLACKOUT := 0.3
const DOOR_SETTLE := 0.15
const SWITCH_BLACKOUT := 0.2
const MUSIC_SILENCE := 0.45
const HATCH_OPEN_WAIT := 0.3
const JIGGLE := [2, -2, 2, -1, 0]
const JIGGLE_STEP := 0.05
const GIVE_SIDE := 18

# sound
const MUSIC_DB := -6.0
const SFX_DB := -4.0

# layout
const ROOM_H := 152
const HUD_H := 28
const VIEW_H := 180
const BASE_W := 320

# lamp flicker
const LAMP_ON_MIN := 0.2
const LAMP_ON_MAX := 2.5
const LAMP_OFF_MIN := 0.04
const LAMP_OFF_MAX := 0.25
