# generator for levels/hub.txt — Habitation hub: one commons you cross four times,
# four wings off it, the transit lift visible and locked from the first minute.
#   F1 = main deck, F2 = maintenance over the hab wing (the only way into engineering)
# Loop: arrive S -> hub (lift lockdown, hab keycard, NW/NE doors dark) -> E med bay
# (crew keycard at the far end) -> hub -> W hab (quarters, storeroom climb) -> F2
# maintenance -> grate drop into engineering control -> breaker (power: NW + NE doors)
# -> out the NW door into the hub -> NE gym -> security office lockdown console -> hub
# -> lift.
import os
W, H = 96, 60
F = [[[' '] * W for _ in range(H)] for _ in range(3)]

def put(f, x, y, s): F[f][y][x] = s
def rect(f, x0, y0, x1, y1, s):
    for y in range(y0, y1 + 1):
        for x in range(x0, x1 + 1): F[f][y][x] = s
def room(f, x0, y0, x1, y1, fl='.', wall='#'):
    for y in range(y0 - 1, y1 + 2):
        for x in range(x0 - 1, x1 + 2):
            if x0 <= x <= x1 and y0 <= y <= y1: F[f][y][x] = fl
            elif F[f][y][x] == ' ': F[f][y][x] = wall
def hwall(f, x0, x1, y, s='#'):
    for x in range(x0, x1 + 1): put(f, x, y, s)
def vwall(f, x, y0, y1, s='#'):
    for y in range(y0, y1 + 1): put(f, x, y, s)

rooms, locks, links, zones, shots = [], [], [], [], []

# ================================================================ F1 hub
room(1, 40, 26, 55, 37, ',')                      # commons: a ring round the lift core
hwall(1, 40, 55, 25, '!'); hwall(1, 40, 55, 38, '!')
# lift core in the exact centre: glass on every side, shutter on lockdown facing the dock
room(1, 46, 30, 49, 33)
for x in (46, 47, 48, 49): put(1, x, 29, 'g')
for x in (46, 49): put(1, x, 34, 'g')
for y in (30, 31, 32, 33): put(1, 45, y, 'g'); put(1, 50, y, 'g')
put(1, 47, 34, 'D'); put(1, 48, 34, 'D')
locks += ["lock 47 34 1 lockdown", "lock 48 34 1 lockdown"]
put(1, 47, 31, 'E'); put(1, 46, 30, '*'); put(1, 49, 33, '*')
# ring: pillars and benches break the sightlines, loot tucked behind them
for x, y in ((42, 28), (53, 28), (42, 35), (53, 35)): put(1, x, y, 'o')
for y in (31, 32): put(1, 42, y, 'n'); put(1, 53, y, 'n')
for x in (44, 51): put(1, x, 27, 'n'); put(1, x, 36, 'n')
put(1, 41, 27, 'h'); put(1, 54, 36, 'a'); put(1, 41, 36, '*'); put(1, 54, 27, '*'); put(1, 47, 27, '*'); put(1, 48, 36, '*')
put(1, 44, 29, 's'); put(1, 51, 34, 's'); put(1, 47, 27, 'e'); put(1, 41, 32, 's'); put(1, 54, 31, 's')
# arrival from the south
room(1, 46, 39, 49, 52, ',')
put(1, 47, 38, 'D'); put(1, 48, 38, 'D')
room(1, 43, 54, 52, 57)                            # airlock / dock
put(1, 47, 53, 'D'); put(1, 48, 53, 'D')
put(1, 47, 56, '@'); put(1, 44, 54, 'x'); put(1, 51, 54, 'X'); put(1, 44, 57, '*'); put(1, 51, 57, '*')
put(1, 47, 46, '*'); put(1, 48, 43, 's'); put(1, 46, 50, 'h')
put(1, 45, 44, 'V'); put(1, 50, 48, 'V')

# ================================================================ E wing: med bay (open; keycard at the far end)
put(1, 56, 31, 'D'); put(1, 56, 32, 'D')
room(1, 57, 31, 60, 32, ',')                      # link
room(1, 61, 27, 70, 36)                            # reception (west) | triage (east)
vwall(1, 66, 27, 29); vwall(1, 66, 34, 36)         # partition with a gap in the middle
put(1, 63, 28, 'j'); put(1, 63, 29, 'n'); put(1, 62, 35, 'n'); put(1, 63, 35, 'n'); put(1, 62, 28, '*'); put(1, 64, 34, 'h')
for y in (28, 32, 35): put(1, 69, y, 'n')          # triage beds
put(1, 68, 30, 's'); put(1, 68, 34, 's'); put(1, 62, 31, 'e'); put(1, 69, 36, '*'); put(1, 67, 27, 'a')
hwall(1, 61, 70, 26, '!'); put(1, 65, 37, 'K')
room(1, 72, 23, 84, 29)                            # ward A: four bays off a south aisle
put(1, 71, 28, 'D')
for x in (75, 78, 81): vwall(1, x, 23, 26)
for x in (73, 77, 80, 83): put(1, x, 24, 'n'); put(1, x, 25, 'n')
put(1, 73, 26, 'h'); put(1, 83, 26, 'h'); put(1, 76, 26, 's'); put(1, 82, 24, 's'); put(1, 79, 28, 'e'); put(1, 84, 29, '*'); put(1, 72, 29, '*'); put(1, 80, 26, 'a')
room(1, 72, 33, 84, 39)                            # ward B: trashed, bays off a north aisle
put(1, 71, 34, 'D')
for x in (75, 78, 81): vwall(1, x, 36, 39)
for x in (73, 77, 80, 83): put(1, x, 38, 'n')
put(1, 73, 37, 'X'); put(1, 80, 37, 'x'); put(1, 77, 37, 'b'); put(1, 83, 37, 'h'); put(1, 74, 34, 's'); put(1, 82, 35, 's'); put(1, 79, 34, 'e'); put(1, 72, 33, '*'); put(1, 84, 35, '*')
room(1, 86, 24, 91, 29)                            # surgery
put(1, 85, 26, 'D'); put(1, 88, 26, 'j'); put(1, 88, 28, 'j'); put(1, 87, 25, 'h'); put(1, 90, 28, 's'); put(1, 90, 25, 'e')
room(1, 86, 33, 91, 38)                            # pharmacy: counter, the crew keycard behind the shelving
put(1, 85, 35, 'D'); put(1, 90, 37, 'q'); put(1, 87, 34, 'x'); put(1, 90, 34, 'X'); vwall(1, 89, 36, 38); put(1, 88, 36, 'n'); put(1, 88, 35, 'n'); put(1, 87, 38, 's'); put(1, 89, 33, 's'); put(1, 86, 36, 'a')
put(1, 88, 39, 'R')

# ================================================================ W wing: hab (keycard)
put(1, 39, 31, 'D'); put(1, 39, 32, 'D')
locks += ["lock 39 31 1 keycard crew", "lock 39 32 1 keycard crew"]
room(1, 14, 31, 38, 32, ',')                      # hab spine
for x in (17, 23, 29, 35): put(1, x, 31, '*')
put(1, 20, 32, 's'); put(1, 26, 31, 's'); put(1, 32, 32, 'e'); put(1, 37, 31, 'h')
room(1, 14, 20, 15, 42, ',')                      # hab cross corridor (north and south)
put(1, 14, 24, '*'); put(1, 15, 38, '*'); put(1, 14, 28, 's'); put(1, 15, 36, 's'); put(1, 14, 41, 'a')
rooms += ["room quarters 19 30 s 1", "room quarters 26 30 s 1", "room quarters 33 30 s 1",
          "room quarters 19 33 n 1", "room quarters 26 33 n 1", "room quarters 33 33 n 1",
          "room quarters 13 24 e 1", "room quarters 13 38 e 1"]
# storeroom at the north end: crate -> ledge -> high vent -> hidden riser ladder
room(1, 17, 20, 21, 24, ',')
put(1, 16, 22, 'D')
for x in range(18, 22): put(1, x, 20, 'w')
for y in (21, 22, 23): put(1, 21, y, 'w')
put(1, 17, 20, 'z'); put(1, 18, 23, 'X'); put(1, 19, 23, 'x'); put(1, 20, 24, '*'); put(1, 19, 21, 'a'); put(1, 20, 22, 's')
for x in (23, 24): put(1, x, 21, 'i')             # high duct east
room(1, 26, 21, 26, 22, ',')                      # riser
put(1, 26, 22, 'l'); put(1, 26, 21, 'h')
# laundry at the south end: dead end with loot
room(1, 17, 40, 22, 43)
put(1, 16, 41, 'D'); put(1, 18, 41, 'n'); put(1, 19, 41, 'n'); put(1, 21, 43, 'x'); put(1, 22, 40, 'h'); put(1, 20, 42, 's'); put(1, 18, 43, 's'); put(1, 22, 42, 'b')

# ================================================================ NW wing: engineering (dark until the breaker)
put(1, 41, 25, 'D'); put(1, 42, 25, 'D')
room(1, 41, 17, 42, 24, ',')                      # stem north
room(1, 20, 16, 42, 17, ',')                      # engineering corridor
for x in (24, 30, 36): put(1, x, 16, '*')
put(1, 27, 17, 's'); put(1, 33, 16, 's'); put(1, 39, 17, 'e'); put(1, 21, 16, 'h')
room(1, 14, 4, 30, 14, ',')                        # pump halls: west | pipe gallery wall | east
vwall(1, 22, 4, 14); put(1, 22, 5, ','); put(1, 22, 13, ',')   # gallery wall, gaps at both ends
put(1, 17, 15, 'D'); put(1, 18, 15, 'D')          # corridor door into the west hall
for x, y in ((17, 7), (17, 11), (26, 7), (26, 11)): put(1, x, y, 'o')
for x in (19, 20): put(1, x, 9, 'n')
for x in (24, 25, 27, 28): put(1, x, 9, 'n')
for y in (5, 6, 12, 13): put(1, 15, y, 'p'); put(1, 29, y, 'p')
for y in (7, 8, 10, 11): put(1, 21, y, 'p'); put(1, 23, y, 'p')
put(1, 20, 5, 'X'); put(1, 25, 13, 'X'); put(1, 16, 9, 'x'); put(1, 28, 5, 'x'); put(1, 20, 13, 'b'); put(1, 24, 5, 'b')
put(1, 18, 5, 's'); put(1, 26, 5, 's'); put(1, 18, 13, 's'); put(1, 26, 13, 's'); put(1, 19, 9, 'e'); put(1, 25, 11, 'e'); put(1, 15, 9, 'h'); put(1, 29, 11, 'a'); put(1, 18, 4, '*'); put(1, 26, 14, '*')
hwall(1, 14, 30, 3, 'P'); put(1, 14, 3, '#'); put(1, 30, 3, '#')
put(1, 31, 9, 'D')                                 # east hall <-> control room
room(1, 32, 6, 38, 11)                             # control room: breaker, grate above
put(1, 35, 12, 'D'); put(1, 33, 7, 'j'); put(1, 37, 7, 'j'); put(1, 38, 9, 'k'); put(1, 35, 8, '*'); put(1, 33, 10, 's'); put(1, 37, 10, 's'); put(1, 35, 10, 'h')
room(1, 32, 13, 38, 14, ',')                      # link control -> corridor
put(1, 35, 15, '.')
room(1, 32, 3, 38, 4, '_')                        # cable gallery behind control (loot)
put(1, 35, 5, 'D'); put(1, 33, 3, 'a'); put(1, 37, 4, 'h'); put(1, 35, 3, 's')

# ================================================================ NE wing: gym + security (dark until the breaker)
put(1, 53, 25, 'D'); put(1, 54, 25, 'D')
room(1, 53, 17, 54, 24, ',')
room(1, 53, 16, 76, 17, ',')                      # rec corridor
for x in (58, 64, 70): put(1, x, 16, '*')
put(1, 60, 17, 's'); put(1, 67, 16, 's'); put(1, 73, 17, 'e')
room(1, 58, 4, 75, 14)                             # gym: changing room | hall / weights room
vwall(1, 63, 4, 14); put(1, 63, 9, 'D')           # changing room door
hwall(1, 64, 75, 10); put(1, 69, 10, '.'); put(1, 70, 10, '.')   # hall | weights, open gap
put(1, 64, 15, 'D'); put(1, 65, 15, 'D')          # corridor door into the weights room
for y in (5, 7, 11, 13): put(1, 59, y, 'n'); put(1, 61, y, 'n')  # changing room lockers
put(1, 60, 9, 'h'); put(1, 62, 6, 's'); put(1, 60, 12, 's'); put(1, 58, 14, 'a')
for x in (66, 69, 72): put(1, x, 6, 'n'); put(1, x, 8, 'n')      # hall: gear rows
put(1, 65, 4, '*'); put(1, 74, 9, 'x'); put(1, 67, 5, 's'); put(1, 73, 7, 's'); put(1, 70, 7, 'e')
for x in (66, 70, 73): put(1, x, 12, 'n')                        # weights benches
put(1, 68, 13, 'X'); put(1, 64, 11, 'h'); put(1, 75, 14, '*'); put(1, 66, 11, 's'); put(1, 72, 13, 's'); put(1, 69, 12, 'e')
hwall(1, 58, 75, 3, 'L'); put(1, 58, 3, '#'); put(1, 75, 3, '#')
room(1, 77, 6, 82, 10)                             # security office: lockdown console behind glass
put(1, 76, 7, 'g'); put(1, 76, 9, 'g'); put(1, 76, 8, 'D')
put(1, 79, 6, 'y'); put(1, 78, 7, 'j'); put(1, 81, 8, 'j'); put(1, 81, 10, 'h'); put(1, 78, 9, 's'); put(1, 81, 7, 'e'); put(1, 79, 8, '*')
links += ["link 79 6 1 to 47 34 1", "link 79 6 1 to 48 34 1"]
room(1, 77, 12, 82, 14, ',')                      # showers behind security
put(1, 79, 11, 'D'); put(1, 78, 13, 'x'); put(1, 81, 13, 'a'); put(1, 80, 12, 's')

# ================================================================ F2 maintenance: riser -> over hab -> over engineering control
room(2, 25, 19, 27, 23, ',')                      # landing over the riser
put(2, 26, 22, '^'); put(2, 26, 19, 'a'); put(2, 25, 23, 'h')
for y in range(12, 18): put(2, 26, y, 'm')        # shaft north (mouth in the landing's wall)
for x in range(27, 33): put(2, x, 12, 'm')        # shaft east... to the fan room
room(2, 34, 10, 38, 13, ',')                      # fan room
put(2, 35, 10, 'o'); put(2, 37, 10, 'o'); put(2, 36, 12, 'p'); put(2, 34, 13, 'x'); put(2, 38, 13, 'a'); put(2, 36, 11, 's'); put(2, 38, 11, 's')
room(2, 32, 5, 38, 8, ',')                        # room over the control room: grate drop
put(2, 35, 9, '.'); put(2, 35, 7, 'G'); put(2, 33, 6, 'X'); put(2, 37, 5, 'h'); put(2, 33, 8, 's'); put(2, 37, 7, 'e')
hwall(2, 32, 38, 4, 'R'); put(2, 32, 4, '#'); put(2, 38, 4, '#')

# ---- lit chamfers in the powered wings (med bay, hab); NW/NE stay dark until the breaker
for y0, y1 in ((23, 29), (33, 39)):
    for y in range(y0, y1 + 1):
        if F[1][y][85] == '#': put(1, 85, y, '!')
hwall(1, 73, 83, 22, '!'); hwall(1, 73, 83, 40, '!')
hwall(1, 62, 69, 26, '!'); hwall(1, 62, 69, 37, '!')
for y in range(21, 42):
    if F[1][y][13] == '#': put(1, 13, y, '!')
    if F[1][y][16] == '#': put(1, 16, y, '!')
for x in range(17, 38):
    if F[1][30][x] == '#': put(1, x, 30, '!')
    if F[1][33][x] == '#': put(1, x, 33, '!')
# ================================================================ power + shots
zones += ["zone 12 1 44 25", "zone 52 1 85 25"]
shots += ["shot a_arrival 47 50 0 0 1", "shot b_hub_lift 47 37 0 4 1", "shot c_hub_ring 41 27 -135 0 1",
          "shot d_medbay 62 31 -90 0 1", "shot e_ward 73 26 -90 0 1", "shot f_pharmacy 86 35 -90 0 1",
          "shot g_hab_spine 37 31 90 0 1", "shot h_quarters 19 30 0 0 1", "shot i_storeroom 18 23 180 6 1",
          "shot j_landing 26 20 0 0 2", "shot k_grate 35 5 180 -45 2", "shot l_control 35 11 0 0 1",
          "shot m_pumphall 22 14 0 0 1", "shot n_gym 66 14 0 0 1", "shot o_security 76 8 -90 0 1",
          "shot p_hub_return 42 26 135 4 1"]

def dump(f):
    rows = [''.join(r).rstrip() for r in F[f]]
    while rows and rows[-1] == '': rows.pop()
    return '\n'.join(rows)
out = '[floor 1]\n' + dump(1) + '\n[floor 2]\n' + dump(2) + '\n'
out += '[rooms]\n' + '\n'.join(rooms) + '\n'
out += '[locks]\n' + '\n'.join(locks) + '\n'
out += '[links]\n' + '\n'.join(links) + '\n'
out += '[power]\n' + '\n'.join(zones) + '\n'
out += '[shots]\n' + '\n'.join(shots) + '\n'
open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'levels', 'hub.txt'), 'w').write(out)
print(out)
