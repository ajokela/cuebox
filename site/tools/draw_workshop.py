#!/usr/bin/env python3
"""Original, deterministic, code-drawn website illustration (MIT)."""
from pathlib import Path
import random

parts = ['<svg xmlns="http://www.w3.org/2000/svg" width="480" height="300" viewBox="0 0 240 150" shape-rendering="crispEdges">']
def rect(x, y, w, h, color):
    parts.append(f'<rect x="{x}" y="{y}" width="{w}" height="{h}" fill="{color}"/>')
def path(d, color):
    parts.append(f'<path d="{d}" fill="{color}"/>')

# A cutaway workshop: chunky geometry, deliberate highlights, no external art.
rect(0,0,240,150,'#152a39')
rect(0,10,240,108,'#284a51')
rect(0,10,240,3,'#427076')
rect(7,15,226,97,'#2c5057')
for y in range(21,111,13):
    for x in range(9 + (10 if y % 2 else 0),230,27):
        rect(x,y,19,1,'#31565c')
        rect(x+18,y-5,1,5,'#31565c')
rect(0,112,240,38,'#35434b')
rect(0,113,240,3,'#1c323c')
for y in range(124,150,12):
    rect(0,y,240,1,'#52605c')
    for x in range((y % 3)*18,240,40): rect(x,y+1,1,10,'#283a45')
# Night through a tall double window.
rect(117,21,75,58,'#182c3b');rect(120,24,69,52,'#6d8b82');rect(123,27,63,46,'#112739')
path('M123 58L136 46L147 54L163 41L186 60V73H123Z','#264453')
path('M123 65L143 56L161 66L178 53L186 60V73H123Z','#3d5b60')
rect(168,33,8,8,'#dbe4bd');rect(166,35,12,4,'#dbe4bd');rect(174,31,5,8,'#112739')
for x,y in [(128,34),(142,40),(156,30),(181,43),(135,50),(150,32)]:rect(x,y,1,1,'#a6bdbc')
rect(153,25,3,50,'#6d8b82');rect(121,53,66,2,'#6d8b82');rect(116,77,77,3,'#1b313e');rect(115,76,79,2,'#9eac8f')
# Projected light, floor and a well-used rug.
path('M123 79H186L221 133H100Z','#3b5456')
rect(70,125,110,17,'#805d52');rect(72,127,106,13,'#ad8063');rect(76,129,98,9,'#587d76')
for x in range(76,174,8):rect(x,132,4,2,'#9da581')
# Shelves and mismatched books.
rect(14,27,77,4,'#1e3540');rect(14,26,77,2,'#a78a68');rect(20,31,3,5,'#937356');rect(83,31,3,5,'#937356')
for x,h,c in [(21,12,'#bf7054'),(26,15,'#afad83'),(32,11,'#70958b'),(37,14,'#d6b676'),(44,14,'#6e8790'),(50,10,'#b0715c')]:
    rect(x,26-h,4,h,c);rect(x,27-h,4,1,'#d6c199')
rect(69,17,13,8,'#7e9085');rect(71,14,9,3,'#b5b894');rect(73,19,5,4,'#416967')
# Pin board, taped-up hints and a clock that probably needs fixing.
rect(18,41,47,30,'#182f3c');rect(20,43,43,26,'#85624d');rect(23,46,15,16,'#ded0a0');rect(40,49,18,13,'#b8c3a4')
for y in [50,53,56]:rect(25,y,10,1,'#9b9575')
rect(44,52,10,2,'#657a6d');rect(46,56,6,2,'#657a6d');rect(27,44,5,3,'#c19969');rect(48,47,5,3,'#d0aa73')
rect(83,42,14,14,'#182e39');rect(85,40,10,18,'#aab39b');rect(81,44,18,10,'#aab39b');rect(85,44,10,10,'#263f49');rect(89,45,1,5,'#e2c78c');rect(89,49,4,1,'#e2c78c')
# Left cabinet with brass pulls and a mug.
rect(17,88,52,32,'#20333b');rect(18,90,48,28,'#91644d');rect(21,92,42,10,'#ad7a57');rect(21,105,42,10,'#9b7052')
rect(18,87,50,3,'#d0a172');rect(37,96,10,2,'#e4c877');rect(37,109,10,2,'#d8bc70');rect(21,118,4,6,'#594e42');rect(60,118,4,6,'#594e42')
rect(26,80,7,7,'#b9c4aa');rect(33,81,3,4,'#b9c4aa');rect(33,82,2,2,'#2c5057');rect(27,79,5,1,'#1b313b')
rect(46,82,16,5,'#435f63');rect(48,80,12,2,'#a7b59a')
# Radio table: green phosphor, stacked equipment, dangling cable.
rect(94,102,86,4,'#c09b70');rect(97,106,4,20,'#7f6853');rect(173,106,4,20,'#7f6853');rect(99,121,75,3,'#7f6853')
rect(101,77,58,25,'#172e37');rect(103,76,54,24,'#658a81');rect(106,80,36,14,'#163a3c');rect(108,82,32,10,'#224b45')
path('M109 88H113V86H116V90H118V85H120V89H122V86H126V88H130V84H132V90H135V87H139V88H109Z','#c4e68f')
for y in [81,84,87,90]:rect(146,y,7,1,'#284a51')
rect(107,96,34,1,'#9eaf91');rect(145,95,6,4,'#d8bd79');rect(161,89,13,13,'#45676a');rect(164,92,7,5,'#203b43');rect(166,99,3,1,'#c6d99c')
path('M153 102H155V116H167V118H152Z','#172e37')
# Ceiling lamp: warm pool and a short chain.
rect(62,0,2,44,'#172e39');path('M58 43H68L75 51H51Z','#d6955f');rect(51,51,24,3,'#efc27b');rect(57,54,12,2,'#f1dda2')
path('M57 57H70L79 77H47Z','#385a5b')
# Plant, positively withholding information.
rect(200,105,19,14,'#bc7854');rect(198,103,23,4,'#d39765');rect(202,119,15,3,'#775444');rect(208,74,2,29,'#88a87a')
path('M208 89H198V84H193V78H202V82H208Z','#789976')
path('M210 81H215V73H222V80H217V86H210Z','#a2b67f')
path('M208 75H201V66H205V70H210V75Z','#7ea183')
path('M210 96H216V89H224V85H227V94H220V99H210Z','#819f71')
path('M207 97H200V91H191V86H199V89H206Z','#a2b67f')
# A small, original adventurer with a mustard coat.
rect(84,112,11,4,'#263b43');rect(86,133,4,9,'#1a303a');rect(93,133,4,9,'#1a303a');rect(84,141,7,3,'#102b36');rect(93,141,7,3,'#102b36')
rect(84,119,14,15,'#c99d5a');rect(86,117,9,3,'#e8bf74');rect(84,122,3,8,'#e7bd74');rect(97,121,3,10,'#a97d4d');rect(98,131,3,3,'#c89f79');rect(85,133,12,2,'#7e6653')
rect(86,106,10,11,'#c7a37d');rect(84,103,11,6,'#26343b');rect(87,102,9,3,'#26343b');rect(94,109,4,5,'#d3b08a');rect(95,109,1,2,'#20333b');rect(85,108,3,5,'#3d423e')
# Small specks make an old room feel inhabited, without visual noise.
for x,y in [(10,136),(225,124),(36,143),(181,140),(6,61),(231,101)]:rect(x,y,2,1,'#718071')
parts.append('</svg>')
Path(__file__).resolve().parents[1].joinpath('assets/workshop.svg').write_text(''.join(parts)+'\n')
