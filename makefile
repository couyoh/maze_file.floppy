BUILDDIR := build
SRCDIR := src
BOCHS := bochs
RESOURCES := resources
OUTPUT := $(BUILDDIR)/floppy.img

all: $(OUTPUT)

$(BUILDDIR)/stage2.bin: $(SRCDIR)/stage2.asm $(SRCDIR)/layout.inc $(SRCDIR)/file_selector.inc $(SRCDIR)/maze_common.inc $(SRCDIR)/common.inc | $(BUILDDIR)
	nasm $< -o $@

$(BUILDDIR)/maze.com: $(SRCDIR)/maze.asm $(SRCDIR)/layout.inc $(SRCDIR)/maze_common.inc $(SRCDIR)/common.inc | $(BUILDDIR)
	nasm $< -o $@

$(BUILDDIR)/hasami_shogi.com: $(SRCDIR)/hasami_shogi.asm $(SRCDIR)/layout.inc $(SRCDIR)/common.inc | $(BUILDDIR)
	nasm $< -o $@

$(BUILDDIR)/floppy.img: $(SRCDIR)/floppy.asm $(SRCDIR)/mbr.asm $(SRCDIR)/layout.inc $(SRCDIR)/common.inc \
                        $(BUILDDIR)/stage2.bin $(BUILDDIR)/maze.com $(BUILDDIR)/hasami_shogi.com \
                        $(RESOURCES)/readme.txt | $(BUILDDIR)
	nasm $< -o $@

qemu: $(OUTPUT)
	qemu-system-x86_64 -fda $<

debug: $(OUTPUT)
	$(BOCHS) -dbg -qf ./.bochsrc

clean:
	rm -f $(BUILDDIR)/*.bin $(BUILDDIR)/*.com $(BUILDDIR)/*.img

$(BUILDDIR):
	mkdir -p $(BUILDDIR)

.PHONY: all qemu debug clean
