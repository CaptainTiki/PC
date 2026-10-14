# generator for levels/deck03.txt — Habitation Ring (three stacked chains)
# floors: 0 = F0 maintenance under the commons, 1 = F1 hab, 2 = F2 (maintenance west / gallery + Corridor D east)
W, H = 74, 36
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
def line(f, pts, s):
    for (x, y) in pts: put(f, x, y, s)

rooms = []   # [rooms] lines
# =============================================================== F1 hab
room(1, 2, 20, 27, 21)                       # Corridor A
put(1, 3, 20, '@')
for x in (6, 12, 18, 24): put(1, x, 20, '*')
put(1, 5, 19, 'L'); put(1, 16, 19, 'L')
put(1, 8, 22, 'V'); put(1, 21, 22, 'V')
room(1, 7, 15, 11, 18)                       # command room A
for x in (7, 8, 9): put(1, x, 19, 'g')
put(1, 10, 19, 'D')
put(1, 9, 15, 'r'); put(1, 8, 15, 'j'); put(1, 10, 15, 'j'); put(1, 9, 17, 'j')   # wall desks flank the panel, one free desk mid-room
put(1, 9, 16, '*'); put(1, 8, 16, 's'); put(1, 10, 16, 's'); put(1, 8, 18, 's'); put(1, 10, 18, 's')
put(1, 9, 14, 'K')
rooms += ["room cabin 4 19 s 1", "room cabin 14 19 s 1", "room cabin 20 19 s 1",
          "room cabin 5 22 n 1", "room cabin 11 22 n 1"]
room(1, 15, 23, 19, 26, ',')                 # storeroom A: ledge along south + east walls
put(1, 17, 22, 'D')
for x in range(16, 20): put(1, x, 26, 'w')
for y in (23, 24, 25): put(1, 19, y, 'w')
put(1, 15, 26, 'z'); put(1, 16, 23, 'X'); put(1, 15, 24, 'x'); put(1, 17, 24, '*'); put(1, 18, 23, 'a')
for x in (21, 22): put(1, x, 23, 'i')        # high duct east (row 23: comes out beside the ladder, not onto it)
room(1, 24, 23, 24, 24, ',')                 # riser (hidden ladder up)
put(1, 24, 24, 'l'); put(1, 24, 23, 'h')
put(1, 28, 20, 'D'); put(1, 28, 21, 'D')     # pressure seal
room(1, 29, 20, 32, 21)                      # junction
put(1, 33, 20, '.'); put(1, 33, 21, '.')     # into the commons
put(1, 30, 20, '*')
# Corridor C stem north + keycard door
room(1, 30, 10, 31, 18, ',')
put(1, 30, 19, 'D'); put(1, 31, 19, 'D')
for y in (12, 16): put(1, 30, y, '*')
put(1, 31, 14, 'e')
rooms += ["room cabin 29 12 e 1", "room cabin 29 16 e 1"]
room(1, 33, 11, 37, 13)                      # crew lounge
put(1, 32, 12, 'D'); put(1, 35, 12, '*'); put(1, 34, 11, 'n'); put(1, 35, 11, 'n'); put(1, 36, 13, 'b'); put(1, 37, 13, 'b'); put(1, 34, 13, 's')
# Corridor C east-west, collapse, rooms beyond
room(1, 30, 8, 60, 9, ',')
for x in (31, 36, 42, 48, 54, 59): put(1, x, 8, '*')
for x in (33, 34):
    put(1, x, 8, 'X'); put(1, x, 9, 'X')     # collapse (stand-in)
put(1, 35, 8, 's'); put(1, 36, 9, 'e'); put(1, 45, 9, 's'); put(1, 50, 8, 'e'); put(1, 57, 9, 's'); put(1, 58, 8, 's')
rooms += ["room cabin 40 7 s 1", "room cabin 52 7 s 1", "room cabin 56 10 n 1"]
room(1, 44, 3, 48, 6)                        # library (secret 3)
put(1, 46, 7, 'D'); put(1, 44, 3, 'h'); put(1, 48, 3, 'a'); put(1, 46, 5, '*'); put(1, 46, 2, 'K')
room(1, 61, 6, 64, 11)                       # transit lobby
put(1, 60, 8, ','); put(1, 60, 9, ',')
put(1, 63, 9, 'E'); put(1, 62, 7, '*'); put(1, 63, 11, 'a'); put(1, 65, 8, 'L'); put(1, 61, 10, 's'); put(1, 64, 6, 'e')
# Commons (two storey, dark until the breaker)
room(1, 34, 18, 47, 27)
for x in (36, 40, 44): put(1, x, 28, 'R')
for x in (38, 42): put(1, x, 17, 'R')
put(1, 48, 24, 'R'); put(1, 33, 23, 'R')
for p in [(37, 20), (41, 20), (37, 25), (41, 25)]: put(1, *p, '*')
for p in [(38, 22), (39, 22), (40, 22), (41, 22)]: put(1, *p, 'n')
for p in [(36, 19), (44, 20), (39, 26), (43, 24), (35, 26)]: put(1, *p, 's')
for p in [(40, 19), (45, 26)]: put(1, *p, 'e')
put(1, 36, 23, 'X'); put(1, 43, 19, 'x'); put(1, 44, 27, 'b'); put(1, 35, 20, 'h')
# stairwell inside the commons (lockdown shutter at its foot)
for y in range(22, 27):
    put(1, 45, y, '#'); put(1, 47, y, '#')
put(1, 46, 22, '#')
for y in (23, 24, 25): put(1, 46, y, '/')
put(1, 46, 26, 'D')
# security post on the commons north wall
room(1, 44, 14, 47, 16)
for x in (44, 45, 46): put(1, x, 17, 'g')
put(1, 47, 17, 'D')
put(1, 45, 15, 'q'); put(1, 46, 16, 'y'); put(1, 44, 15, 'j'); put(1, 47, 15, 'j'); put(1, 44, 14, 's'); put(1, 47, 14, 's'); put(1, 45, 14, '*')
put(1, 45, 13, 'K')
# quiet room (secret 2) on the commons north wall
room(1, 35, 15, 37, 16)
put(1, 36, 17, 'D'); put(1, 36, 15, 'h'); put(1, 35, 16, 'a')
# gym + locker room south, with the hatch down
room(1, 36, 29, 40, 32)
put(1, 38, 28, 'D'); put(1, 37, 30, 'o'); put(1, 39, 30, 'o'); put(1, 38, 31, '*'); put(1, 36, 32, 'h'); put(1, 40, 29, 's'); put(1, 36, 29, 's')
room(1, 42, 29, 44, 31)
put(1, 41, 30, 'D'); put(1, 43, 31, '^'); put(1, 42, 29, 'x'); put(1, 43, 29, '*')
# rec room west
room(1, 28, 23, 32, 27)
put(1, 33, 25, 'D'); put(1, 30, 24, '*'); put(1, 28, 23, 'X'); put(1, 29, 27, 'a'); put(1, 31, 26, 'n'); put(1, 30, 26, 'n'); put(1, 29, 25, 's')
# Corridor B east, cabins, storeroom B with the ladder up
room(1, 49, 20, 66, 21)
put(1, 48, 20, '.'); put(1, 48, 21, '.')
for x in (51, 57, 63): put(1, x, 20, '*')
put(1, 54, 19, 'R'); put(1, 60, 22, 'R')
for p in [(50, 21), (55, 20), (60, 21), (64, 20)]: put(1, *p, 's')
put(1, 58, 20, 'e'); put(1, 53, 21, 'b')
rooms += ["room cabin 51 19 s 1", "room cabin 56 19 s 1", "room cabin 61 19 s 1",
          "room cabin 53 22 n 1", "room cabin 58 22 n 1", "room cabin 63 22 n 1"]
room(1, 68, 19, 70, 22, ',')
put(1, 67, 20, 'D'); put(1, 70, 22, 'l'); put(1, 68, 19, 'X'); put(1, 69, 20, '*'); put(1, 68, 22, 'a'); put(1, 70, 19, 's')
# =============================================================== F2
# west: maintenance over Corridor A
room(2, 24, 22, 26, 25, ',')                 # landing over the riser
put(2, 24, 24, '^'); put(2, 26, 23, '*'); put(2, 25, 25, 'a'); put(2, 26, 25, 's')
for x in range(18, 23): put(2, x, 23, 'm')   # shaft west
room(2, 14, 21, 16, 24, ',')                 # pump closet
put(2, 15, 22, '*'); put(2, 14, 24, 'b'); put(2, 16, 24, 'b'); put(2, 14, 21, 'e'); put(2, 16, 22, 'p')
put(2, 15, 20, 'D')
room(2, 12, 15, 17, 19, ',')                 # fan room
put(2, 14, 17, 'o'); put(2, 15, 17, 'o'); put(2, 13, 15, '*'); put(2, 17, 19, '*'); put(2, 12, 18, 's'); put(2, 16, 16, 's'); put(2, 13, 19, 's'); put(2, 17, 16, 'e')
put(2, 18, 17, 'P'); put(2, 11, 15, 'W')
put(2, 11, 17, 'D')
room(2, 7, 15, 10, 18, ',')                  # over the command room
put(2, 9, 16, 'G'); put(2, 8, 18, '*'); put(2, 7, 15, 'x'); put(2, 10, 18, 'a')
put(2, 14, 14, 'D')
room(2, 13, 11, 15, 13, ',')                 # spares store (secret 1)
put(2, 14, 12, 'h'); put(2, 13, 11, 'a'); put(2, 15, 13, '*')
# east: gallery over the commons
room(2, 34, 18, 47, 27, 'c')
rect(2, 36, 20, 45, 25, '^')
for p in [(38, 21), (43, 21), (38, 24), (43, 24), (40, 23)]: put(2, *p, 'v')
put(2, 46, 23, '^'); put(2, 46, 24, '^')     # stairwell
for p in [(35, 19), (46, 19), (35, 26), (40, 27), (44, 18)]: put(2, *p, 'e')
put(2, 47, 26, 'a'); put(2, 34, 27, 'h')
for x in (36, 40, 44): put(2, x, 28, '!')
put(2, 33, 22, '!'); put(2, 48, 22, '!'); put(2, 40, 17, '!')
# Corridor D north from the gallery, ending in the collapse over Corridor C
room(2, 36, 8, 37, 16, ',')
put(2, 36, 17, ','); put(2, 37, 17, ',')
for x in (36, 37):
    put(2, x, 8, '~'); put(2, x, 9, '~')     # broken floor: drops into Corridor C
put(2, 36, 13, '*'); put(2, 37, 15, 's'); put(2, 36, 12, 's')
rooms += ["room cabin 38 11 w 2", "room cabin 38 15 w 2"]
room(2, 31, 12, 34, 14, ',')                 # family quarters
put(2, 35, 13, 'D'); put(2, 32, 12, 'x'); put(2, 33, 14, 'h'); put(2, 31, 13, '*'); put(2, 32, 14, 's')
room(2, 32, 9, 34, 10, ',')                  # observation nook
put(2, 35, 10, 'D'); put(2, 31, 9, 'O'); put(2, 31, 10, 'O'); put(2, 33, 9, 'a'); put(2, 32, 10, 'e')
# room over the security post, fed by the crawl from storeroom B
room(2, 44, 13, 50, 15, ',')
put(2, 45, 15, 'G'); put(2, 44, 13, '*'); put(2, 48, 13, 'h'); put(2, 49, 14, 's'); put(2, 47, 14, 's'); put(2, 46, 13, 's')
for y in range(17, 21): put(2, 50, y, 'm')
put(2, 50, 21, 'm')
for x in range(51, 67): put(2, x, 21, 'm')
room(2, 68, 19, 70, 23, ',')                 # landing over storeroom B
put(2, 70, 22, '^'); put(2, 69, 19, '*'); put(2, 68, 23, 'a'); put(2, 69, 21, 's')
# =============================================================== F0 maintenance under the commons
room(0, 42, 24, 43, 32, ',')
put(0, 43, 31, 'l'); put(0, 42, 26, '*'); put(0, 42, 30, '*'); put(0, 44, 28, 'R'); put(0, 41, 25, 'R')
put(0, 42, 27, 's'); put(0, 43, 25, 's')
room(0, 35, 26, 40, 31, ',')                 # pump room
put(0, 41, 28, ','); put(0, 41, 29, ',')
for p in [(36, 27), (36, 30), (39, 27), (39, 30)]: put(0, *p, 'o')
put(0, 37, 28, '*'); put(0, 38, 31, 'b'); put(0, 35, 31, 'b'); put(0, 40, 26, 'h'); put(0, 35, 26, 'p'); put(0, 40, 31, 'p')
for p in [(37, 30), (38, 27), (36, 29), (39, 29)]: put(0, *p, 's')
put(0, 38, 26, 'e'); put(0, 34, 28, 'P'); put(0, 37, 32, 'V')
room(0, 45, 24, 48, 27, ',')                 # power room
put(0, 44, 25, ','); put(0, 44, 26, ',')
put(0, 48, 26, 'k'); put(0, 46, 25, '*'); put(0, 45, 27, 'a'); put(0, 47, 24, 'e'); put(0, 46, 27, 'e'); put(0, 49, 25, 'R')

def dump(f):
    rows = [''.join(r).rstrip() for r in F[f]]
    while rows and rows[-1] == '': rows.pop()
    return '\n'.join(rows)

out = dump(0) + '\n[floor 1]\n' + dump(1) + '\n[floor 2]\n' + dump(2) + '\n'
out += '[rooms]\n' + '\n'.join(rooms) + '\n'
out += '''[locks]
lock 10 19 1 oneway n
lock 28 20 1 seal
lock 30 19 1 keycard crew
lock 47 17 1 oneway n
lock 46 26 1 lockdown
[links]
link 9 15 1 to 28 20 1
link 46 16 1 to 46 26 1
[power]
zone 34 12 49 27
zone 48 18 71 23
[stairs]
stair 46 25 n 1
[shots]
shot a_start 3 21 -90 0 1
shot b_command_glass 8 20 0 6 1
shot c_seal 26 21 -90 2 1
shot d_storeroom 17 23 180 4 1
shot e_fanroom 12 17 -90 -4 2
shot f_drop 8 16 -90 -45 2
shot g_junction 30 21 0 2 1
shot h_commons 34 20 -90 -2 1
shot i_security 46 19 0 4 1
shot j_power 45 25 -90 0 0
shot k_corridor_b 50 21 -90 0 1
shot l_gallery 35 19 -135 -10 2
shot m_corridor_d 36 16 0 -2 2
shot n_hole 36 11 0 -40 2
shot o_transit 56 9 -90 0 1
'''
import os; open(os.path.join(os.path.dirname(os.path.abspath(__file__)), '..', 'levels', 'deck03.txt'), 'w').write(out)
print(out)
