# =============================================================================
# Genome Annotation Pipeline – Ficus aurea
# Steps: BUSCO → RepeatModeler → RepeatMasker → BUSCO (masked) → BRAKER3
#
# BRAKER3 mode is selected automatically based on what evidence is provided
# in config.mk:
#
#   PROTEIN_DB only              → EP  mode  (proteins only)
#   RNA_R1 / RNA_BAM only        → ET  mode  (RNA-seq only)
#   PROTEIN_DB + RNA_R1/RNA_BAM  → ETP mode  (proteins + RNA-seq)
#
# Conda environments (set names in config.mk):
#   CONDA_ANNOTATION – BUSCO, RepeatModeler, RepeatMasker
#   CONDA_APPTAINER  – Apptainer (runs BRAKER3 .sif) + AGAT
#   CONDA_RNASEQ     – STAR, samtools (only used when RNA-seq is provided)
#
# Usage:
#   make build_sif      – build BRAKER3 Apptainer image (run once)
#   make all            – run full pipeline
#   make busco          – BUSCO on raw assembly
#   make repeat_modeler – build de novo repeat/TE library
#   make repeat_masker  – soft-mask genome
#   make busco_masked   – BUSCO on masked assembly
#   make star_index     – STAR genome index (RNA-seq only)
#   make star_align     – align RNA-seq reads (RNA-seq only)
#   make braker         – BRAKER3 gene annotation
#   make clean          – remove all output directories
#   make help           – show this message
# =============================================================================

include config.mk

# ── Conda run wrappers ────────────────────────────────────────────────────────
# `conda run` executes a command inside an environment without needing
# `conda activate`, which does not work in non-interactive shells like make.
RUN_ANNOTATION := conda run --no-capture-output -n $(CONDA_ANNOTATION)
RUN_APPTAINER  := conda run --no-capture-output -n $(CONDA_APPTAINER)
RUN_RNASEQ     := conda run --no-capture-output -n $(CONDA_RNASEQ)

# if using micromamba
#RUN_ANNOTATION := micromamba run -n $(CONDA_ANNOTATION)
#RUN_APPTAINER  := micromamba run -n $(CONDA_APPTAINER)
#RUN_RNASEQ     := micromamba run -n $(CONDA_RNASEQ)

# ── Auto-detect BRAKER3 mode from config.mk ───────────────────────────────────
# Logic:
#   HAS_PROTEIN is set if PROTEIN_DB is defined and non-empty
#   HAS_RNA     is set if RNA_BAM, RNA_R1, or RNA_R2 is defined and non-empty
#
# These drive:
#   BRAKER_MODE_FLAG – the --epmode / --etpmode flag passed to braker.pl
#   STAR_NEEDED      – whether STAR index/align steps run
#   FINAL_BAM        – path to the BAM file passed to braker.pl
HAS_PROTEIN := $(if $(strip $(PROTEIN_DB)),yes,)
HAS_RNA     := $(if $(or $(strip $(RNA_BAM)),$(strip $(RNA_R1))),yes,)

ifeq ($(HAS_PROTEIN),yes)
  ifeq ($(HAS_RNA),yes)
    BRAKER_MODE      := ETP
    BRAKER_MODE_FLAG :=           # ETP is the default when both are provided
  else
    BRAKER_MODE      := EP
    BRAKER_MODE_FLAG := --epmode
  endif
else
  ifeq ($(HAS_RNA),yes)
    BRAKER_MODE      := ET
    BRAKER_MODE_FLAG :=           # ET is default when only RNA is provided
  else
    $(error Neither PROTEIN_DB nor RNA evidence is set in config.mk)
  endif
endif

# ── BAM path resolution ───────────────────────────────────────────────────────
# If a pre-aligned BAM is given use it directly; otherwise expect STAR output.
ifdef RNA_BAM
  FINAL_BAM    := $(abspath $(RNA_BAM))
  STAR_NEEDED  :=
else ifdef RNA_R1
  FINAL_BAM    := $(abspath $(STAR_DIR)/Aligned.sortedByCoord.out.bam)
  STAR_NEEDED  := yes
else
  FINAL_BAM    :=
  STAR_NEEDED  :=
endif

# ── Derived paths ─────────────────────────────────────────────────────────────
SOFTMASKED_GENOME := $(REPEAT_MASKER_DIR)/$(notdir $(GENOME)).softmasked
STAR_INDEX_DIR    := $(STAR_DIR)/genome_index

# ── Absolute paths for Apptainer bind-mounts ──────────────────────────────────
ABS_GENOME      := $(abspath $(SOFTMASKED_GENOME))
ABS_GENOME_DIR  := $(abspath $(REPEAT_MASKER_DIR))
ABS_BRAKER_DIR  := $(abspath $(BRAKER_DIR))
ABS_PROTEIN_DB  := $(if $(PROTEIN_DB),$(abspath $(PROTEIN_DB)),)
ABS_PROTEIN_DIR := $(if $(PROTEIN_DB),$(abspath $(dir $(PROTEIN_DB))),)
ABS_BAM_DIR     := $(if $(FINAL_BAM),$(abspath $(dir $(FINAL_BAM))),)
ABS_SIF         := $(abspath $(BRAKER3_SIF))

# ── Stamp files ───────────────────────────────────────────────────────────────
STAMP_DIR     := .stamps
STAMP_BUSCO   := $(STAMP_DIR)/busco.done
STAMP_REPMOD  := $(STAMP_DIR)/repeat_modeler.done
STAMP_REPMSK  := $(STAMP_DIR)/repeat_masker.done
STAMP_BUSCO2  := $(STAMP_DIR)/busco_masked.done
STAMP_STARIDX := $(STAMP_DIR)/star_index.done
STAMP_STARALN := $(STAMP_DIR)/star_align.done
STAMP_BRAKER  := $(STAMP_DIR)/braker.done

# ── Conditional step list for `all` ───────────────────────────────────────────
# STAR steps are added to the dependency chain only when RNA-seq is provided.
ifdef STAR_NEEDED
  ALL_STEPS := $(STAMP_BUSCO) $(STAMP_REPMOD) $(STAMP_REPMSK) $(STAMP_BUSCO2) \
               $(STAMP_STARIDX) $(STAMP_STARALN) $(STAMP_BRAKER)
else ifdef RNA_BAM
  # pre-supplied BAM: no STAR needed but RNA is present
  ALL_STEPS := $(STAMP_BUSCO) $(STAMP_REPMOD) $(STAMP_REPMSK) $(STAMP_BUSCO2) \
               $(STAMP_BRAKER)
else
  ALL_STEPS := $(STAMP_BUSCO) $(STAMP_REPMOD) $(STAMP_REPMSK) $(STAMP_BUSCO2) \
               $(STAMP_BRAKER)
endif

.PHONY: all build_sif busco repeat_modeler repeat_masker busco_masked \
        star_index star_align braker clean clean_all help

# ── Default target ─────────────────────────────────────────────────────────────
all: $(ALL_STEPS)
	@echo ""
	@echo "============================================"
	@echo " Pipeline complete! (BRAKER3 mode: $(BRAKER_MODE))"
	@echo " Key outputs:"
	@echo "   BUSCO (raw)    : $(BUSCO_RAW_DIR)/"
	@echo "   Repeat library : $(REPEAT_MODELER_DIR)/$(GENOME_NAME)-families.fa"
	@echo "   Masked genome  : $(SOFTMASKED_GENOME)"
	@echo "   BUSCO (masked) : $(BUSCO_MASKED_DIR)/"
	$(if $(FINAL_BAM),@echo "   RNA-seq BAM    : $(FINAL_BAM)",)
	@echo "   Gene models    : $(BRAKER_DIR)/braker.gtf"
	@echo "   Gene models    : $(BRAKER_DIR)/braker.gff3"
	@echo "============================================"

$(STAMP_DIR):
	mkdir -p $(STAMP_DIR)

# =============================================================================
# Build Apptainer image (run once before the pipeline)
# =============================================================================
build_sif: $(ABS_SIF)

$(ABS_SIF):
	@echo "[Apptainer] Building BRAKER3 image – this may take 10-20 minutes..."
	$(RUN_APPTAINER) apptainer build $(ABS_SIF) docker://teambraker/braker3:latest
	@echo "[Apptainer] Image built: $(ABS_SIF)"

# =============================================================================
# STEP 1 – BUSCO on raw assembly
#   conda env: CONDA_ANNOTATION
# =============================================================================
busco: $(STAMP_BUSCO)

$(STAMP_BUSCO): $(GENOME) | $(STAMP_DIR)
	@echo "[BUSCO] Assessing raw assembly completeness..."
	@echo "  conda env: $(CONDA_ANNOTATION)"
	mkdir -p $(BUSCO_RAW_DIR)
	$(RUN_ANNOTATION) busco \
		--in $(abspath $(GENOME)) \
		--out $(GENOME_NAME)_raw \
		--out_path $(abspath $(BUSCO_RAW_DIR)) \
		--lineage_dataset $(BUSCO_LINEAGE) \
		--mode genome \
		--cpu $(THREADS) \
		--download_path $(abspath $(BUSCO_DOWNLOADS)) \
		$(BUSCO_EXTRA_ARGS)
	touch $@

# =============================================================================
# STEP 2 – RepeatModeler: build de novo repeat/TE library
#   conda env: CONDA_ANNOTATION
# =============================================================================
repeat_modeler: $(STAMP_REPMOD)

$(STAMP_REPMOD): $(GENOME) | $(STAMP_DIR)
	@echo "[RepeatModeler] Building de novo repeat/TE library..."
	@echo "  conda env: $(CONDA_ANNOTATION)"
	mkdir -p $(REPEAT_MODELER_DIR)
	cd $(REPEAT_MODELER_DIR) && \
		$(RUN_ANNOTATION) BuildDatabase \
			-name $(GENOME_NAME) \
			-engine $(REPEAT_ENGINE) \
			$(abspath $(GENOME))
	cd $(REPEAT_MODELER_DIR) && \
		$(RUN_ANNOTATION) RepeatModeler \
			-database $(GENOME_NAME) \
			-engine $(REPEAT_ENGINE) \
			-pa $(THREADS) \
			-LTRStruct \
			2>&1 | tee RepeatModeler.log
	touch $@

# =============================================================================
# STEP 3 – RepeatMasker: soft-mask genome
#   conda env: CONDA_ANNOTATION
#   -xsmall produces lowercase soft-masking (required by BRAKER3 --softmasking)
# =============================================================================
repeat_masker: $(STAMP_REPMSK)

$(STAMP_REPMSK): $(STAMP_REPMOD) | $(STAMP_DIR)
	@echo "[RepeatMasker] Soft-masking genome..."
	@echo "  conda env: $(CONDA_ANNOTATION)"
	mkdir -p $(REPEAT_MASKER_DIR)
	@if [ -n "$(REPEAT_EXTRA_LIB)" ] && [ -f "$(REPEAT_EXTRA_LIB)" ]; then \
		echo "  Merging de novo library with $(REPEAT_EXTRA_LIB)..."; \
		cat $(REPEAT_MODELER_DIR)/$(GENOME_NAME)-families.fa $(REPEAT_EXTRA_LIB) \
			> $(REPEAT_MASKER_DIR)/combined_repeat_library.fa; \
	else \
		cp $(REPEAT_MODELER_DIR)/$(GENOME_NAME)-families.fa \
		   $(REPEAT_MASKER_DIR)/combined_repeat_library.fa; \
	fi
	$(RUN_ANNOTATION) RepeatMasker \
		-lib $(REPEAT_MASKER_DIR)/combined_repeat_library.fa \
		-pa $(THREADS) \
		-xsmall \
		-gff \
		-dir $(REPEAT_MASKER_DIR) \
		$(abspath $(GENOME)) \
		2>&1 | tee $(REPEAT_MASKER_DIR)/RepeatMasker.log
	cp $(REPEAT_MASKER_DIR)/$(notdir $(GENOME)).masked $(SOFTMASKED_GENOME)
	@echo "[RepeatMasker] Softmasked genome: $(SOFTMASKED_GENOME)"
	touch $@

# =============================================================================
# STEP 4 – BUSCO on masked assembly (sanity check for over-masking)
#   conda env: CONDA_ANNOTATION
# =============================================================================
busco_masked: $(STAMP_BUSCO2)

$(STAMP_BUSCO2): $(STAMP_REPMSK) | $(STAMP_DIR)
	@echo "[BUSCO] Assessing masked assembly completeness..."
	@echo "  conda env: $(CONDA_ANNOTATION)"
	mkdir -p $(BUSCO_MASKED_DIR)
	$(RUN_ANNOTATION) busco \
		--in $(ABS_GENOME) \
		--out $(GENOME_NAME)_masked \
		--out_path $(abspath $(BUSCO_MASKED_DIR)) \
		--lineage_dataset $(BUSCO_LINEAGE) \
		--mode genome \
		--cpu $(THREADS) \
		--download_path $(abspath $(BUSCO_DOWNLOADS)) \
		$(BUSCO_EXTRA_ARGS)
	touch $@

# =============================================================================
# STEP 5 – STAR genome index (only runs when RNA-seq evidence is provided)
#   conda env: CONDA_RNASEQ
#   Built from the soft-masked genome so STAR splice junction detection is
#   not confused by hard-masked (N) regions.
# =============================================================================
star_index: $(STAMP_STARIDX)

$(STAMP_STARIDX): $(STAMP_REPMSK) | $(STAMP_DIR)
ifdef STAR_NEEDED
	@echo "[STAR] Building genome index from soft-masked assembly..."
	@echo "  conda env: $(CONDA_RNASEQ)"
	mkdir -p $(STAR_INDEX_DIR)
	$(RUN_RNASEQ) STAR \
		--runMode genomeGenerate \
		--genomeDir $(STAR_INDEX_DIR) \
		--genomeFastaFiles $(ABS_GENOME) \
		--genomeSAindexNbases 13 \
		--runThreadN $(THREADS) \
		2>&1 | tee $(STAR_INDEX_DIR)/STAR_index.log
else
	@echo "[STAR index] Skipping – no FASTQ reads provided"
endif
	touch $@

# =============================================================================
# STEP 6 – STAR alignment (only runs when RNA-seq FASTQs are provided)
#   conda env: CONDA_RNASEQ
#   Key flags for BRAKER3 compatibility:
#     --outSAMstrandField intronMotif   → adds XS tag required by BRAKER3
#     --outFilterIntronMotifs RemoveNoncanonical → cleaner junctions
#     --twopassMode Basic               → better junction discovery
#     --alignSoftClipAtReferenceEnds No → BRAKER3 recommendation
# =============================================================================
star_align: $(STAMP_STARALN)

$(STAMP_STARALN): $(STAMP_STARIDX) | $(STAMP_DIR)
ifdef STAR_NEEDED
	@echo "[STAR] Aligning RNA-seq reads to masked genome..."
	@echo "  conda env: $(CONDA_RNASEQ)"
	mkdir -p $(STAR_DIR)
	$(RUN_RNASEQ) STAR \
		--runMode alignReads \
		--genomeDir $(STAR_INDEX_DIR) \
		--readFilesIn $(abspath $(RNA_R1)) $(if $(RNA_R2),$(abspath $(RNA_R2)),) \
		$(if $(filter %.gz,$(RNA_R1)),--readFilesCommand zcat,) \
		--outSAMstrandField intronMotif \
		--outFilterIntronMotifs RemoveNoncanonical \
		--outSAMtype BAM SortedByCoordinate \
		--outSAMattrIHstart 0 \
		--alignSoftClipAtReferenceEnds No \
		--twopassMode Basic \
		--outFileNamePrefix $(abspath $(STAR_DIR))/ \
		--runThreadN $(THREADS) \
		2>&1 | tee $(STAR_DIR)/STAR_align.log
	@echo "[STAR] Indexing BAM..."
	$(RUN_RNASEQ) samtools index -@ $(THREADS) $(FINAL_BAM)
	@echo "[STAR] Mapping summary:"
	@grep -E "Uniquely mapped|mapped to multiple|unmapped" \
		$(STAR_DIR)/Log.final.out || true
else
	@echo "[STAR align] Skipping – no FASTQ reads provided"
endif
	touch $@

# =============================================================================
# STEP 7 – BRAKER3 via Apptainer
#   conda env: CONDA_APPTAINER
#
#   Mode is set automatically (see top of Makefile):
#     EP  mode → proteins only   (set PROTEIN_DB, leave RNA unset)
#     ET  mode → RNA-seq only    (set RNA_R1/RNA_BAM, leave PROTEIN_DB unset)
#     ETP mode → proteins + RNA  (set both)
#
#   The teambraker/braker3 image bundles AUGUSTUS, GeneMark-ETP, DIAMOND,
#   ProtHint, TSEBRA, AGAT – no external license key needed.
# =============================================================================
braker: $(STAMP_BRAKER)

# Dependency: braker waits for STAR alignment stamp if RNA FASTQs are given,
# otherwise depends only on repeat masking being complete.
$(STAMP_BRAKER): $(STAMP_REPMSK) \
                 $(if $(STAR_NEEDED),$(STAMP_STARALN),) \
                 $(ABS_SIF) | $(STAMP_DIR)
	@echo "[BRAKER3] Running in $(BRAKER_MODE) mode via Apptainer..."
	@echo "  conda env: $(CONDA_APPTAINER)"
	@# ── Pre-flight checks ────────────────────────────────────────────────────
	@if [ ! -f "$(ABS_SIF)" ]; then \
		echo "ERROR: Apptainer image not found at $(ABS_SIF)"; \
		echo "  Run: make build_sif"; \
		exit 1; \
	fi
	@if [ "$(BRAKER_MODE)" != "EP" ] && [ ! -f "$(FINAL_BAM)" ]; then \
		echo "ERROR: BAM not found at $(FINAL_BAM)"; \
		echo "  Run: make star_align  (or set RNA_BAM in config.mk)"; \
		exit 1; \
	fi
	mkdir -p $(ABS_BRAKER_DIR)
	@# ── Run BRAKER3 ──────────────────────────────────────────────────────────
	$(RUN_APPTAINER) apptainer exec \
		--no-home \
		--bind $(ABS_GENOME_DIR):$(ABS_GENOME_DIR) \
		--bind $(ABS_BRAKER_DIR):$(ABS_BRAKER_DIR) \
		$(if $(ABS_PROTEIN_DIR),--bind $(ABS_PROTEIN_DIR):$(ABS_PROTEIN_DIR),) \
		$(if $(ABS_BAM_DIR),--bind $(ABS_BAM_DIR):$(ABS_BAM_DIR),) \
		$(ABS_SIF) \
		braker.pl \
			--genome=$(ABS_GENOME) \
			$(if $(ABS_PROTEIN_DB),--prot_seq=$(ABS_PROTEIN_DB),) \
			$(if $(FINAL_BAM),--bam=$(FINAL_BAM),) \
			$(BRAKER_MODE_FLAG) \
			--species=$(SPECIES_NAME) \
			--workingdir=$(ABS_BRAKER_DIR) \
			--threads=$(THREADS) \
			--softmasking \
			$(BRAKER_EXTRA_ARGS) \
		2>&1 | tee $(ABS_BRAKER_DIR)/braker.log
	@# ── GTF → GFF3 using AGAT (bundled in the BRAKER3 container) ─────────────
	@if [ -f "$(ABS_BRAKER_DIR)/braker.gtf" ]; then \
		echo "[BRAKER3] Converting braker.gtf → braker.gff3 with AGAT..."; \
		$(RUN_APPTAINER) apptainer exec \
			--no-home \
			--bind $(ABS_BRAKER_DIR):$(ABS_BRAKER_DIR) \
			$(ABS_SIF) \
			agat_convert_sp_gxf2gxf.pl \
				--gxf $(ABS_BRAKER_DIR)/braker.gtf \
				-o   $(ABS_BRAKER_DIR)/braker.gff3 \
			2>&1 | tee -a $(ABS_BRAKER_DIR)/braker.log; \
	else \
		echo "WARNING: braker.gtf not found – check $(ABS_BRAKER_DIR)/braker.log"; \
	fi
	touch $@

# =============================================================================
# Utilities
# =============================================================================
clean:
	@echo "Removing pipeline outputs (Apptainer image kept)..."
	rm -rf $(STAMP_DIR) \
	       $(BUSCO_RAW_DIR) \
	       $(BUSCO_MASKED_DIR) \
	       $(REPEAT_MODELER_DIR) \
	       $(REPEAT_MASKER_DIR) \
	       $(STAR_DIR) \
	       $(BRAKER_DIR)

clean_all: clean
	@echo "Also removing Apptainer image $(ABS_SIF)..."
	rm -f $(ABS_SIF)

help:
	@echo ""
	@echo "  Genome Annotation Pipeline – $(GENOME_NAME)"
	@echo "  =========================================="
	@echo "  BRAKER3 mode (auto-detected from config.mk):"
	@echo "    EP  mode → set PROTEIN_DB only"
	@echo "    ET  mode → set RNA_R1 or RNA_BAM only"
	@echo "    ETP mode → set PROTEIN_DB + RNA_R1 or RNA_BAM"
	@echo "  Current mode: $(BRAKER_MODE)"
	@echo ""
	@echo "  Conda environments:"
	@echo "    $(CONDA_ANNOTATION)  → BUSCO, RepeatModeler, RepeatMasker"
	@echo "    $(CONDA_APPTAINER)   → Apptainer, AGAT"
	@echo "    $(CONDA_RNASEQ)      → STAR, samtools (RNA-seq only)"
	@echo ""
	@echo "  Targets:"
	@echo "    build_sif      Build BRAKER3 Apptainer image (run once)"
	@echo "    all            Run complete pipeline"
	@echo "    busco          BUSCO on raw assembly"
	@echo "    repeat_modeler RepeatModeler de novo TE/repeat library"
	@echo "    repeat_masker  RepeatMasker soft-masking"
	@echo "    busco_masked   BUSCO on masked assembly"
	@echo "    star_index     STAR genome index    (RNA-seq only)"
	@echo "    star_align     Align RNA-seq reads  (RNA-seq only)"
	@echo "    braker         BRAKER3 gene annotation"
	@echo "    clean          Remove outputs (keeps Apptainer image)"
	@echo "    clean_all      Remove outputs + Apptainer image"
	@echo ""
	@echo "  Configuration: edit config.mk"
	@echo ""
