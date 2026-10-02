# Conical Involute Gears (Beveloid Gears) for Backlash Reduction

A parametric Lua modeling script designed for **[IceSL](https://icesl.loria.fr/)** that constructs and simulates straight conical involute gear pairs (beveloid gears). This tool allows you to explore how profile shift variations along the face width can be adjusted axially to control and minimize gear backlash.

The mathematical formulation for the gear geometry follows the analytical rack-generation method presented by **Jesper Brauer (2002)**.

---

## 📌 Features

- **Parametric Beveloid Gear Generator**: Constructs 3D gear solids using profile shift variations across the face width ($x_{\text{bottom}}$ to $x_{\text{top}}$).
- **Interactive IceSL Controls**: Dynamic UI sliders to adjust module, pressure angle, tooth count, face width, shim thickness, and clearance.
- **Backlash Inspection & Probing**: Visual intersection tool to detect gear contact conditions:
  - **No Intersection**: Positive backlash (clearance between flanks).
  - **Slight Line Contact**: Zero backlash (optimal engagement).
  - **Overlapping Volume**: Negative backlash (interference / binding).
- **Adjustable Sampling Resolution**: A unified resolution slider to balance real-time interactive performance with geometry smoothness for high-quality export/printing.
- **Full Assembly Modeling**: Includes configurable gear shafts, mounting blocks, fastening screws, shim spacers, and baseplate options.

---

## 🛠️ Prerequisites & Installation

1. Download and install **[IceSL Studio](https://icesl.loria.fr/)** (procedural modeling and slicing software).
2. Clone this repository or download the files:
   ```bash
   git clone https://github.com/your-username/beveloid-gear-icesl.git
   ```
3. Open `beveloid_gear.lua` inside IceSL Studio.

---

## 🚀 Usage Guide

1. **Open Script**: Launch `beveloid_gear.lua` in IceSL Studio.
2. **Parameter Adjustment**:
   - **Resolution**: Lower values give faster preview renders; higher values produce smooth surfaces suitable for 3D printing.
   - **Profile Shift Coefficients**: Modify $x_{\text{bottom}}$ and $x_{\text{top}}$ for both gears to control gear taper and conical geometry.
   - **Driving Gear Rotation**: Rotate the drive train to observe live dynamic meshing.
   - **Driven Gear Angular Offset**: Fine-tune the driven gear angle to evaluate backlash play.
   - **Shim Thickness**: Adjust the spacer thickness to observe how axial movement eliminates gear play.
3. **Collision & Interference Check**:
   - Enable `Show Intersection Body` in the UI panel to isolate and highlight interpenetrating volumes between gear teeth.

---

## 📐 Mathematical Model

Conical involute gears (beveloid gears) utilize a continuously varying profile shift along their axial width. The resulting cone angle $\delta$ is given by:

$$\tan(\delta) = \frac{m \cdot (x_{\text{top}} - x_{\text{bottom}})}{b}$$

Where:
- $m$ = Normal Module
- $x_{\text{bottom}}, x_{\text{top}}$ = Profile shift coefficients at the bottom and top slice planes
- $b$ = Axial face width

Tooth profiles across each slice layer are evaluated analytically using rack-generated involute curves and root fillet arcs.

---

## 📖 Citation & References

If you use or build upon this project in your research or application, please reference:

- **Brauer, Jesper. (2002)**. *Analytical geometry of straight conical involute gears*. **Mechanism and Machine Theory**, 37(2), 127–141.  
  DOI: [10.1016/S0094-114X(01)00062-3](https://doi.org/10.1016/S0094-114X(01)00062-3)

---

## 👥 Authors & Team

- **Development**: Team 37
- Created for research and design of precision gear drives with adjustable backlash reduction using **IceSL**.
