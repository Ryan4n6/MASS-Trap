# Assignment #3+4 — Variables Resubmission
# Student: Ben Massfeller, Grade 5
# Teacher: Ms. Sofferin
# Original grade: 0/20 — "Variables incomplete. Missing Dependent Variable."

---

## VARIABLES

### Independent Variable (What I Changed)
The amount of weight added to the car. I tested four conditions:
- **0 grams** added (base weight only)
- **+3.5 grams** of tungsten
- **+7 grams** of tungsten
- **+14 grams** of tungsten

### Dependent Variable (What I Measured)
**Speed** measured in meters per second (m/s) and **time** measured in seconds (s).

The M.A.S.S. Trap system uses infrared sensors to automatically measure how long it takes the car to travel the track (time), and then calculates speed by dividing the track length by the time (speed = distance ÷ time).

The system also calculates:
- **Momentum** in kg·m/s (momentum = mass × velocity)
- **Kinetic Energy** in Joules (KE = ½ × mass × velocity²)

### Controlled Variables (What I Kept the Same)
- **Track**: Same Hot Wheels track, 5.85 meters long, same ramp angle
- **Start position**: Car placed at the exact same spot at the top of the ramp every time
- **Release method**: Released by hand from the same position (not pushed)
- **Car model**: Ford F-150 Hot Wheels truck for all runs
- **NFC tracking sticker**: Each car has an identification sticker weighing 0.025g
- **Number of trials**: 3 trials per condition per car
- **Measurement tool**: Same M.A.S.S. Trap sensor system for all runs

---

## MATERIALS LIST

1. M.A.S.S. Trap measurement system (ESP32-S3 computer with infrared sensors, built by me and my dad)
2. Hot Wheels track — 5.85 meters (19.2 feet)
3. 2 Hot Wheels Ford F-150 trucks
4. Tungsten weights: 3.5 gram, 7 gram, and 14 gram pieces
5. Precision digital scale (measures to 0.001 grams)
6. NFC identification stickers (2, one per car)
7. Laptop computer for viewing the dashboard

---

## PROCEDURE (Step by Step)

1. Weigh each car on the scale. Write down the weight.
2. Stick an NFC tag on each car. Weigh again. Write down the new weight.
3. Set up the track with sensors at the start and finish.
4. Turn on the M.A.S.S. Trap system and connect to the dashboard.
5. **No weight condition:** Put the car at the top of the ramp. Let go. The sensors measure the time and speed automatically. Do this 3 times for each car.
6. **+3.5g condition:** Tape 3.5 grams of tungsten to the car. Run 3 trials per car.
7. **+7g condition:** Tape 7 grams of tungsten to the car. Run 3 trials per car.
8. **+14g condition:** Tape 14 grams of tungsten to the car. Run 3 trials per car.
9. If any run looks wrong (like the car hit the wall), run an extra trial.
10. Export all data from the system and calculate the averages.
