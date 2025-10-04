# FPGA Quick Start - Key Generator

## 🚀 In 3 Steps

### 1️⃣ Create Project

```tcl
cd "/Users/samir/Projects/FPGA/Simple Implementation/multiple_keys"
source create_fpga_project.tcl
```

### 2️⃣ Build

```tcl
build_all
```

### 3️⃣ Program

- Hardware Manager → Auto Connect → Program Device

---

## 🎮 Board Controls

| Control       | Function          |
| ------------- | ----------------- |
| **BTNC**      | Generate key      |
| **BTNU/D**    | Change order ±1   |
| **SW[9:0]**   | Set seed (0-1000) |
| **SW[15:10]** | Set order (1-63)  |

## 💡 LED Display

| LED           | Meaning               |
| ------------- | --------------------- |
| **LED[0]**    | Blinking = Processing |
| **LED[1]**    | Solid = Key Ready     |
| **LED[7:2]**  | Current order         |
| **LED[15:8]** | Hash bits [7:0]       |

## 📟 7-Segment Display

Shows **genseed1** value in decimal (0-1000)

---

## ⚡ Example: Generate K1

1. Set SW[9:0] = `0000000100` (decimal 100)
2. Set order = 1 (SW[15:10] = `000001`)
3. Press **BTNC**
4. Wait for **LED[1]** ON
5. Read hash from **LED[15:8]**

---

## 🔧 Supported Boards

✅ **Basys3** (default - uncommented in .xdc)
✅ **Nexys A7-50T / 100T** (commented out)
✅ **Arty A7-35T / 100T** (add constraints)

To change board:

1. Edit `create_fpga_project.tcl` (line 30)
2. Edit `fpga_constraints.xdc` (comment/uncomment sections)

---

## 📊 Performance

- **Clock**: 100 MHz
- **Time/Key**: ~690 ns (69 cycles)
- **Throughput**: ~1.45M keys/sec

---

## 🐛 Troubleshooting

**No activity?**
→ Check reset button released, press BTNC

**Timing fails?**
→ Reduce clock freq or check critical paths

**Wrong board?**
→ Verify constraints match your hardware

---

## 📂 Files

- `fpga_top.vhd` - Top wrapper
- `fpga_constraints.xdc` - Pin assignments
- `create_fpga_project.tcl` - Build script
- `generate_key.vhd` - Core logic

---

## 🎯 Formula

```
Kn = H(Tn(genseed1))

K1 = H(T1(100))
K2 = H(T2(100))
...
K100 = H(T100(100))
```

---

For detailed guide, see: **FPGA_USAGE_GUIDE.md**
