AS = nasm
LD = ld

ASFLAGS = -f elf64 -w+all -w+error -w-unknown-warning -w-reloc-rel
LDFLAGS = -pie -I /lib64/ld-linux-x86-64.so.2 --fatal-warnings

TARGET = discrete_fractal
SRC = discrete_fractal.asm
OBJ = discrete_fractal.o

.PHONY: all debug clean

# Default target (Release build)
all: $(TARGET)

# Debug target: Appends debug flags and forces a clean rebuild
debug: ASFLAGS += -g -F dwarf
debug: clean $(TARGET)

$(TARGET): $(OBJ)
	$(LD) $(LDFLAGS) -o $(TARGET) $(OBJ)

$(OBJ): $(SRC)
	$(AS) $(ASFLAGS) -o $(OBJ) $(SRC)

clean:
	rm -f $(TARGET) $(OBJ)