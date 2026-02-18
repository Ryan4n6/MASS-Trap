# Ben's Science Fair Submission — Assignment #5/6/7
# Due: Friday, February 20, 2026
# Student: Ben Massfeller, Grade 5
# Teacher: Ms. Sofferin

---

## TITLE

**Does Adding Weight to a Hot Wheels Car Make It Go Faster or Slower?**

---

## ABSTRACT

This experiment tested whether adding mass to Hot Wheels cars changes how fast they roll down a ramp. Two identical Ford F-150 Hot Wheels trucks were tested on a 5.85-meter track at four different weight levels: no added weight, +3.5 grams, +7 grams, and +14 grams of tungsten. Each condition was tested 3 times. The speed of each car was measured using infrared sensors connected to an ESP32 microcontroller. I found that adding a small amount of weight (3.5g or 7g) made both cars slightly faster, but adding a lot of weight (14g) made the heavier car slower while the lighter car kept getting faster. This means that mass does affect speed, but the effect depends on how heavy the car already is. The heavier car may have more friction when it gets too heavy, which slows it down.

---

## TESTABLE QUESTION

Does adding mass to a Hot Wheels car change how fast it travels down a 5.85-meter ramp?

---

## HYPOTHESIS

If I add more mass to a Hot Wheels car, then it will go faster down the ramp, because heavier objects have more gravitational potential energy at the top of the ramp, which converts to more kinetic energy at the bottom.

---

## VARIABLES

- **Independent Variable (what I changed):** The amount of added weight — 0 grams, 3.5 grams, 7 grams, and 14 grams of tungsten weights placed on the car
- **Dependent Variable (what I measured):** Speed in meters per second (m/s) and time in seconds (s)
- **Controlled Variables (what I kept the same):** Track length (5.85 meters), start height, release method (released from the same spot every time), car model (Ford F-150 Hot Wheels truck), NFC tracking sticker mass (0.025 grams each)

---

## MATERIALS

1. M.A.S.S. Trap speed measurement system (ESP32-S3 microcontroller with infrared sensors)
2. Hot Wheels track — 5.85 meters (19.2 feet) long
3. 2× Hot Wheels Ford F-150 trucks (identical model)
   - "F-150 Control" — 38.025 grams (the heavier twin)
   - "F-150 Test" — 31.546 grams (the lighter twin)
4. Tungsten weights — 3.5g, 7g, and 14g pieces
5. Digital precision scale (0.001g accuracy)
6. 2× NFC stickers for car identification (0.025g each)
7. Laptop for viewing the M.A.S.S. Trap dashboard

---

## PROCEDURE

1. Weigh each car on the precision scale and record the base weight.
2. Attach an NFC identification sticker to each car and record the new weight (car + sticker).
3. Set up the M.A.S.S. Trap track with infrared sensors at the start and finish.
4. Connect to the M.A.S.S. Trap dashboard on my laptop.
5. **Condition 1 (No added weight):** Place each car at the top of the ramp. Release. The sensors automatically record the time and calculate speed. Do 3 trials per car, alternating between cars (Control, Test, Control, Test, Control, Test).
6. **Condition 2 (+3.5g tungsten):** Attach 3.5g of tungsten weight to each car. Repeat 3 trials per car.
7. **Condition 3 (+7g tungsten):** Attach 7g of tungsten weight to each car. Repeat 3 trials per car.
8. **Condition 4 (+14g tungsten):** Attach 14g of tungsten weight to each car. Repeat 3 trials per car.
9. The M.A.S.S. Trap automatically saves all data including time, speed, momentum, and kinetic energy.
10. Export data and calculate averages for each condition.

---

## DATA

### F-150 Control (Base weight: 38.025g)

| Condition | Total Weight (g) | Trial 1 Time (s) | Trial 2 Time (s) | Trial 3 Time (s) | Avg Time (s) | Avg Speed (m/s) |
|-----------|-----------------|-------------------|-------------------|-------------------|---------------|-----------------|
| No added weight | 38.025 | 1.5612 | 1.5072 | 1.4895 | 1.519 | 3.853 |
| +3.5g tungsten | 41.525 | 1.4813 | 1.4806 | 1.5152 | 1.492 | 3.922 |
| +7g tungsten | 45.025 | 1.5035 | 1.4779 | 1.4987 | 1.493 | 3.919 |
| +14g tungsten | 52.025 | 1.5148 | 1.5083 | 1.4833 | 1.502 | 3.896 |

> **Note:** For the +14g condition, I ran 4 trials. Trial 2 (1.687s) was much slower than all other runs — the car may have bumped the wall. I removed this outlier and used the other 3 trials for the average.

### F-150 Test (Base weight: 31.546g)

| Condition | Total Weight (g) | Trial 1 Time (s) | Trial 2 Time (s) | Trial 3 Time (s) | Avg Time (s) | Avg Speed (m/s) |
|-----------|-----------------|-------------------|-------------------|-------------------|---------------|-----------------|
| No added weight | 31.546 | 1.5443 | 1.5099 | 1.4773 | 1.510 | 3.876 |
| +3.5g tungsten | 35.046 | 1.4742 | 1.4801 | 1.5180 | 1.491 | 3.926 |
| +7g tungsten | 38.546 | 1.5123 | 1.4696 | 1.5147 | 1.499 | 3.905 |
| +14g tungsten | 45.546 | 1.4676 | 1.4805 | 1.4734 | 1.474 | 3.971 |

### Physics Calculations (Averages)

| Condition | Car | Mass (kg) | Speed (m/s) | Momentum (kg·m/s) | Kinetic Energy (J) |
|-----------|-----|-----------|-------------|--------------------|--------------------|
| No weight | Control | 0.038 | 3.853 | 0.147 | 0.282 |
| No weight | Test | 0.032 | 3.876 | 0.122 | 0.237 |
| +3.5g | Control | 0.042 | 3.922 | 0.163 | 0.319 |
| +3.5g | Test | 0.035 | 3.926 | 0.138 | 0.270 |
| +7g | Control | 0.045 | 3.919 | 0.176 | 0.346 |
| +7g | Test | 0.039 | 3.905 | 0.151 | 0.294 |
| +14g | Control | 0.052 | 3.896 | 0.197 | 0.374 |
| +14g | Test | 0.046 | 3.971 | 0.181 | 0.359 |

---

## RESULTS

### What the Data Shows

**Both cars got faster when I added a small amount of weight.**
- The Control car went from 3.853 m/s (no weight) to 3.922 m/s (+3.5g) — that's 1.8% faster.
- The Test car went from 3.876 m/s (no weight) to 3.926 m/s (+3.5g) — that's 1.3% faster.

**The two cars acted differently when I added a lot of weight (+14g).**
- The **Control car** (heavier twin, 38g base) got **slower** — it dropped from 3.922 m/s back down to 3.896 m/s. Adding 14 grams of tungsten to the already-heavy car was too much.
- The **Test car** (lighter twin, 31.5g base) kept getting **faster** — it reached 3.971 m/s, the fastest speed of any car in any condition. Adding 14 grams to the lighter car still helped.

**Momentum always increased with more mass.**
- This makes sense because momentum = mass × velocity. Even when speed stayed about the same, the heavier car always had more momentum (more "pushing force").

**Kinetic energy always increased with more mass.**
- KE = ½ × mass × velocity². Since mass went up and speed barely changed, kinetic energy went up for every condition.

### Trends and Patterns

1. **The "Sweet Spot"**: Adding 3.5g of tungsten was the sweet spot for both cars — it made them faster without slowing them down.
2. **Diminishing Returns**: For the Control car, going from +3.5g to +7g didn't help much (3.922 → 3.919 m/s), and +14g actually made it slower (3.896 m/s).
3. **Lighter Cars Benefit More**: The lighter Test car kept getting faster all the way up to +14g, while the heavier Control car hit its limit earlier.
4. **Manufacturing Surprise**: Even though both cars are the same model from the same package, the Control car weighs 38.025g and the Test car weighs 31.546g — a difference of 6.479g (20.5%). They are NOT identical.

---

## ANALYSIS

The data shows that adding mass to a Hot Wheels car does **not** simply make it faster or slower — it depends on how much weight you add and how heavy the car already is.

**Why adding weight helps (at first):** When a car sits at the top of the ramp, it has gravitational potential energy (PE = mass × gravity × height). A heavier car has more PE. As it rolls down, that PE converts to kinetic energy (KE = ½mv²). More mass means more energy to start with, which can overcome friction and air resistance better.

**Why too much weight hurts:** At some point, the extra mass increases friction between the wheels and the axles, and between the wheels and the track. The wheels on Hot Wheels cars are very small, so even a little extra friction makes a big difference. The Control car (which was already 6.5 grams heavier) hit this friction limit sooner.

**The manufacturing variance matters:** I expected two "identical" cars to weigh the same, but they were 20.5% different. This is important because it means you can't assume two cars from the same package will perform the same. In real science, you have to weigh and measure everything — you can't just trust the label.

**Outlier (Run 21):** During one trial with the Control car at +14g, the time was 1.687 seconds — much slower than the other runs (1.47–1.51s). The car probably hit the side of the track or a wheel got stuck. I ran an extra trial to replace it. Real scientists deal with outliers by running extra trials and documenting what happened.

---

## CONCLUSION

My hypothesis was **partially supported**. I predicted that adding mass would make the cars faster because of more gravitational potential energy. This was true for small amounts of weight (+3.5g and +7g) and for the lighter car at all weights. However, the heavier car actually got slower when I added +14g of tungsten, which means my hypothesis was not completely right.

The real answer is more interesting than my hypothesis: **there is an optimal weight for maximum speed.** Adding mass helps up to a point by increasing the energy available, but eventually the extra friction from the added weight overcomes the energy advantage. The lighter car had more "room" before hitting its friction limit, which is why it kept getting faster.

**If I could do this experiment again, I would:**
1. Test more weight levels (0g, 1g, 2g, 3g... up to 20g) to find exactly where the speed peaks
2. Test 3 or more cars to see if the pattern holds across different models
3. Measure the friction of each car's wheels before and after adding weight
4. Try different types of weight placement (front, back, on top) to see if where you put the weight matters

---

## APPLICATION (Real-World Connection)

This experiment connects to real-world physics and engineering in several ways:

1. **Race Car Design:** Professional racing teams (NASCAR, F1) spend millions trying to find the perfect weight for their cars. Too light and they lose grip. Too heavy and they're slow. My experiment showed this same tradeoff at 1:64 scale.

2. **Roller Coasters:** Roller coaster designers use the same PE → KE conversion that makes Hot Wheels work. They have to account for different rider weights — a car full of adults converts more potential energy than a car full of kids.

3. **Manufacturing Quality:** I discovered that two "identical" Hot Wheels trucks differ by 20.5% in mass. This is a real quality control issue — in industries like aerospace or medicine, parts that are supposed to be identical MUST be identical, or things fail.

4. **Scientific Method:** I learned that you can't just guess — you have to measure. I thought heavier = faster, and I was only partially right. Without actual data collection and measurement, I would have had the wrong answer.

---

*Data collected using the M.A.S.S. Trap (Motion Analysis & Speed System) — an ESP32-based physics laboratory built by Ben Massfeller and his dad.*
*Track length: 5.8522 meters (19.2 feet) | Scale: 1:64 | Sensor: Infrared break-beam | Precision: ±0.001 seconds*
*25 total race runs collected on February 17, 2026*
